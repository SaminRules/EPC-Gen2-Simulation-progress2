/*
 * PIE Decoder — Synchronous Symbol-Level Decoder
 *
 * Replaces the ASIC's analog clk_dpie delay-line approach with a fully
 * digital PIE decoder running on the 5 MHz system clock.
 */

`timescale 1us / 1ns

module pie_decoder
#(
    parameter USE_PRECISION_CLOCK = 0,       // 1 = use crystal-derived Tari (bypass preamble measurement)
    parameter NOMINAL_TARI_TICKS  = 31       // 6.2 us @ 5 MHz quartz — set to match reader's Tari
)
(
    output reg         bit_val,        // Decoded data bit (0 or 1)
    output reg         bit_strobe,     // Single-cycle pulse when bit_val is valid
    output reg         dec_clk,        // Reconstructed clock (1-cycle pulse after bit_val)

    input  wire        clk,            // 5 MHz system clock
    input  wire        rst_n,          // Active-low reset
    input  wire        rfid_in,        // Filtered PIE signal (idle = LOW in EPC Gen2)
    input  wire        sync,           // Frame-sync valid from fs_detector
    input  wire [15:0] tari_width,     // Measured Tari period (5 MHz ticks)
    input  wire        package_complete // End-of-packet flag
);

    // ---------------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------------
    localparam [1:0] D_IDLE    = 2'd0,  // Waiting for sync
                     D_WAIT_FE = 2'd1,  // Waiting for first falling edge after sync
                     D_MEASURE = 2'd2;  // Measuring symbol period

    // ---------------------------------------------------------------
    // Input synchroniser (2-FF) — prevent metastability
    // ---------------------------------------------------------------
    reg sync_ff1, sync_ff2;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= rfid_in;
            sync_ff2 <= sync_ff1;
        end
    end

    wire rfid_sync = sync_ff2;

    // ---------------------------------------------------------------
    // Edge detector
    // ---------------------------------------------------------------
    reg rfid_prev;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            rfid_prev <= 1'b0;
        else
            rfid_prev <= rfid_sync;
    end

    wire falling_edge = (rfid_prev == 1'b1) && (rfid_sync == 1'b0);

    // ---------------------------------------------------------------
    // Precision Clock Mode
    //  When USE_PRECISION_CLOCK=1, bypass the fs_detector's preamble
    //  measurement (which can be distorted by the analog front-end)
    //  and use a crystal-derived constant instead.
    //  The mux is optimized away at synthesis — zero LUTs.
    // ---------------------------------------------------------------
    wire [15:0] active_tari = (USE_PRECISION_CLOCK)
                              ? NOMINAL_TARI_TICKS[15:0]
                              : tari_width;

    // ---------------------------------------------------------------
    // Pivot computation
    //  pivot = 1.5 × active_tari to distinguish Data-0 from Data-1.
    // ---------------------------------------------------------------
    reg [15:0] pivot;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            pivot <= 16'd0;
        end else begin
            pivot <= active_tari + (active_tari >> 2);  // 1.25 × active_tari (12-tick margin at Tari=47)
        end
    end

    // ---------------------------------------------------------------
    // Symbol period counter
    // ---------------------------------------------------------------
    reg [15:0] sym_counter;   // Ticks since last falling edge

    // ---------------------------------------------------------------
    // State machine
    // ---------------------------------------------------------------
    reg [1:0] state;
    reg       toggle_pending; // Fire dec_clk pulse one cycle after bit_val set
    reg [7:0] measure_guard;  // Minimum-active counter: ignore sync drops for first N cycles

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state          <= D_IDLE;
            sym_counter    <= 16'd0;
            bit_val        <= 1'b0;
            bit_strobe     <= 1'b0;
            dec_clk        <= 1'b0;
            toggle_pending <= 1'b0;
            measure_guard  <= 8'd0;
        end else begin
            // Default: clear single-cycle signals
            bit_strobe <= 1'b0;
            dec_clk    <= 1'b0; // Default to 0, creating a clean 1-cycle pulse when triggered

            // ----- Delayed dec_clk pulse -----
            // One cycle after bit_val was set, pulse dec_clk HIGH. 
            // This guarantees bit_val has 1 full clock cycle of setup time 
            // before cmd_buf samples it.
            if (toggle_pending) begin
                dec_clk        <= 1'b1;
                bit_strobe     <= 1'b1;
                toggle_pending <= 1'b0;
            end

            case (state)
                D_IDLE: begin
                    toggle_pending <= 1'b0;
                    if (sync) begin
                        sym_counter <= 16'd1; // Start counting from sync assertion
                        state       <= D_WAIT_FE;
                    end else begin
                        sym_counter <= 16'd0;
                    end
                end

                D_WAIT_FE: begin
                    // Wait for the first falling edge after sync.
                    // Do NOT decode a bit here — the sync→first-edge interval
                    // is a preamble artifact (TRcal/frame-sync boundary), not
                    // a real data symbol.  Just transition to D_MEASURE so the
                    // first REAL data bit is decoded on the next falling edge.
                    if (package_complete || !sync) begin
                        state <= D_IDLE;
                    end else if (falling_edge) begin
                        sym_counter    <= 16'd1;
                        state          <= D_MEASURE;
                        measure_guard  <= 8'd0;  // Start guard timer
                    end else begin
                        sym_counter <= sym_counter + 16'd1;
                    end
                end

                D_MEASURE: begin
                    // Guard: don't check sync/package_complete for the first
                    // 200 cycles (~40us at 5MHz) after entering D_MEASURE.
                    // This prevents CRG feedback glitches from killing the
                    // decoder before any real data is captured.
                    if (measure_guard < 8'd200)
                        measure_guard <= measure_guard + 8'd1;

                    if ((measure_guard >= 8'd200) && (package_complete || !sync)) begin
                        state <= D_IDLE;
                        measure_guard <= 8'd0;
                    end else if (falling_edge) begin
                        // --- End of the current symbol ---
                        bit_val        <= (sym_counter > pivot) ? 1'b1 : 1'b0;
                        toggle_pending <= 1'b1;  // Trigger clock pulse for next cycle
                        sym_counter    <= 16'd1; // Reset for the new symbol
                    end else begin
                        sym_counter <= sym_counter + 16'd1;
                    end
                end

                default: state <= D_IDLE;
            endcase
        end
    end

endmodule