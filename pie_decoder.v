/*
 *  PIE Decoder — Synchronous Symbol-Level Decoder
 *
 *  Replaces the ASIC's analog clk_dpie delay-line approach with a fully
 *  digital PIE decoder running on the 5 MHz system clock.
 *
 *  After fs_detector asserts `sync` (frame-sync valid), this module:
 *    1. Detects falling edges on `rfid_in` (start of each PIE symbol)
 *    2. Measures the full symbol period (falling-edge → falling-edge)
 *    3. Compares period against 1.5 × tari_width (the pivot):
 *         period ≤ pivot → data-0
 *         period >  pivot → data-1
 *    4. On each falling edge (= end of previous symbol), sets `bit_val`
 *       and then toggles `dec_clk` one cycle later so downstream logic
 *       (cmd_buf, CRC) sees stable data on the posedge of dec_clk.
 *
 *  Timing diagram for downstream consumers:
 *    falling_edge →  bit_val updated (same cycle)
 *    +1 cycle     →  dec_clk toggles (posedge → cmd_buf shifts bits_in)
 *                    bit_val is stable with >1 cycle of setup time.
 *
 *  Dynamic Clock Recovery:
 *    pivot = tari_width + (tari_width >> 1)   [i.e., 1.5 × tari_width]
 *    This adapts automatically to the reader's actual Tari timing.
 */

`timescale 1us / 1ns

module pie_decoder
(
    output reg         bit_val,        // Decoded data bit (0 or 1)
    output reg         bit_strobe,     // Single-cycle pulse when bit_val is valid
    output reg         dec_clk,        // Reconstructed clock (toggles 1 cycle after bit_val)

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
    // Pivot computation (registered for timing closure)
    //   fs_detector's tari_width = half-Tari (delimiter-rise to first
    //   data-0 falling edge). pie_decoder measures FULL symbol periods
    //   (falling→falling), so full_tari = 2 × tari_width.
    //   pivot = 1.5 × full_tari = 3 × tari_width
    // ---------------------------------------------------------------
    reg [15:0] pivot;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            pivot <= 16'd0;
        end else begin
            pivot <= tari_width + {tari_width[14:0], 1'b0};  // 3 × tari_width
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
    reg       toggle_pending; // Fire dec_clk toggle one cycle after bit_val set

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state          <= D_IDLE;
            sym_counter    <= 16'd0;
            bit_val        <= 1'b0;
            bit_strobe     <= 1'b0;
            dec_clk        <= 1'b0;
            toggle_pending <= 1'b0;
        end else begin
            // Default: clear single-cycle signals
            bit_strobe <= 1'b0;

            // ----- Delayed dec_clk toggle -----
            // One cycle after bit_val was set (toggle_pending), toggle
            // dec_clk. This guarantees bit_val has >= 1 clock cycle of
            // setup time before cmd_buf samples it on posedge dec_clk.
            if (toggle_pending) begin
                dec_clk        <= ~dec_clk;
                bit_strobe     <= 1'b1;
                toggle_pending <= 1'b0;
            end

            case (state)
                // -------------------------------------------------
                // D_IDLE: Wait for fs_detector to assert sync
                // -------------------------------------------------
                D_IDLE: begin
                    sym_counter    <= 16'd0;
                    dec_clk        <= 1'b0;
                    toggle_pending <= 1'b0;
                    if (sync) begin
                        state <= D_WAIT_FE;
                    end
                end

                // -------------------------------------------------
                // D_WAIT_FE: Wait for the first falling edge after
                //   RTcal completes. This is the boundary between
                //   RTcal and the first data symbol.
                //   We start counting from this edge.
                // -------------------------------------------------
                D_WAIT_FE: begin
                    if (package_complete || !sync) begin
                        state <= D_IDLE;
                    end else if (falling_edge) begin
                        sym_counter <= 16'd1;
                        state       <= D_MEASURE;
                    end
                end

                // -------------------------------------------------
                // D_MEASURE: Count ticks of each symbol period.
                //   On falling edge → the previous symbol is complete.
                //   Decode its period vs pivot, set bit_val immediately,
                //   schedule dec_clk toggle for next cycle.
                // -------------------------------------------------
                D_MEASURE: begin
                    if (package_complete || !sync) begin
                        state <= D_IDLE;
                    end else if (falling_edge) begin
                        // --- End of the current symbol ---
                        // Decode the just-completed symbol
                        bit_val        <= (sym_counter > pivot) ? 1'b1 : 1'b0;
                        toggle_pending <= 1'b1;  // dec_clk toggles next cycle
                        sym_counter    <= 16'd1; // reset for the new symbol
                    end else begin
                        sym_counter <= sym_counter + 16'd1;
                    end
                end

                default: state <= D_IDLE;
            endcase
        end
    end

endmodule
