/*
 *  Frame-Sync Detector (Refactored)
 *
 *  Detects the EPC Gen2 Frame-Sync preamble by measuring pulse periods
 *  on the rfid_in signal. Calibrated for a 5 MHz system clock (200 ns/tick).
 *
 *  Key fixes from 48-hour debug session:
 *    1. "Sample-Then-Reset" — pulse_width register captures counter value
 *       on edge BEFORE the counter resets. FSM evaluates stable register.
 *    2. Phantom Edge Protection — synchronizer and edge-detection FFs
 *       initialized to idle state (0) to prevent false S_ERROR on reset.
 *    3. brain_state debug output for ILA monitoring.
 *
 *  PIE Encoding timing (measured as LOW dip durations):
 *    In this system, the testbench PIE waveform has:
 *      - Delimiter: a long LOW dip (~12.5 us = 62 ticks)
 *      - After Delimiter, all data dips (Tari, RTcal) are short (~3.125 us)
 *        with the HIGH period between dips encoding the actual timing info
 *
 *  Strategy:
 *    - Delimiter: detect a LOW dip in the range [DELIM_MIN..DELIM_MAX]
 *    - S_TARI  : wait for E3 (Data-0 falling edge); counter measures dead-time
 *                between delimiter rising edge and Data-0 dip ─ not stored
 *    - S_RTCAL : counts E3→E4 (Data-0 falling → RTcal falling) = true Tari
 *                stores result as tari_count, asserts sync
 *
 *  Frame-Sync sequence:
 *    Delimiter (long LOW dip)
 *    → data-0 (Tari period, falling→falling)
 *    → RTcal (falling→falling, must be > 2×Tari)
 *    → sync asserted
 */

`timescale 1us / 1ns

module fs_detector
(
    output reg        sync,              // Frame-sync valid
    output wire [2:0] brain_state,       // State monitor for ILA
    output wire [15:0] dbg_pulse_width,  // Last measured pulse width
    output wire [15:0] tari_width,       // Measured Tari period for PIE decoder

    input  wire       rfid_in,           // Inverted RF signal (idle = LOW)
    input  wire       clk,               // 5 MHz system clock
    input  wire       rst_n,             // Active-low reset
    input  wire       package_complete   // End of frame
);

    // ---------------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------------
    localparam [2:0] S_IDLE  = 3'd0,   // Waiting for Delimiter LOW dip
                     S_DELIM = 3'd1,   // Inside Delimiter LOW dip
                     S_TARI  = 3'd2,   // Measuring Tari symbol period
                     S_RTCAL = 3'd3,   // Measuring RTcal symbol period (stores Tari)
                     S_DONE  = 3'd4,   // Frame-sync valid
                     S_ERROR = 3'd5,   // Invalid timing
                     S_TRCAL = 3'd6;   // Consume TRcal/last-preamble symbol; fire sync at data edge

    // ---------------------------------------------------------------
    // Timing thresholds (5 MHz clock, 200 ns/tick)
    // ---------------------------------------------------------------
    // Delimiter LOW dip: 12.5 us nominal → 62.5 ticks, accept 50–80
    //localparam [15:0] DELIM_MIN = 16'd50;
    //localparam [15:0] DELIM_MAX = 16'd80;
    localparam [15:0] DELIM_MIN = 16'd70;
    localparam [15:0] DELIM_MAX = 16'd150;

    // Tari full period (falling→falling): accept 10–200
    // Widened from 50 to 200 to support TARI25US (half-Tari ≈ 62 ticks at 5 MHz)
    localparam [15:0] TARI_MIN = 16'd10;
    localparam [15:0] TARI_MAX = 16'd200;

    // ---------------------------------------------------------------
    // Input synchronizer (2-FF) — initialized to idle state (0)
    // ---------------------------------------------------------------
    (* mark_debug = "true" *) reg sync_ff1, sync_ff2;  // 2-FF synchronizer (sync_ff2 = stable value)

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            sync_ff1 <= 1'b0;   // idle = LOW
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= rfid_in;
            sync_ff2 <= sync_ff1;
        end
    end

    (* mark_debug = "true" *) wire rfid_sync = sync_ff2;  // Stable, synchronized antenna signal

    // ---------------------------------------------------------------
    // Edge detector — initialized to 0 for phantom-edge protection
    // ---------------------------------------------------------------
    reg rfid_prev;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            rfid_prev <= 1'b0;  // matches idle state
        else
            rfid_prev <= rfid_sync;
    end

    (* mark_debug = "true" *) wire falling_edge = (rfid_prev == 1'b1) && (rfid_sync == 1'b0); // start of LOW dip  ← delim/tari/rtcal trigger
    (* mark_debug = "true" *) wire rising_edge  = (rfid_prev == 1'b0) && (rfid_sync == 1'b1); // end of LOW dip    ← delim_match window

    // ---------------------------------------------------------------
    // Pulse counter — free-running, counts ALL ticks from last reset
    // Used differently per state:
    //   S_DELIM: counts during LOW dip (resets on rising_edge)
    //   S_TARI/S_RTCAL: counts full period (resets on falling_edge)
    // ---------------------------------------------------------------
    (* mark_debug = "true" *) reg [15:0] pulse_counter;  // Live tick counter (delim/tari/rtcal measurement)
    (* mark_debug = "true" *) reg [15:0] pulse_width;    // Last captured pulse width (= dbg_pulse_width)

    assign dbg_pulse_width = pulse_width;
    assign tari_width      = tari_count;

    // ---------------------------------------------------------------
    // Tari storage — used to compute RTcal pivot
    // ---------------------------------------------------------------
    (* mark_debug = "true" *) reg [15:0] tari_count;  // Stored Tari period — RTcal pivot = 2×tari_count

    // ---------------------------------------------------------------
    // State machine
    // ---------------------------------------------------------------
    (* mark_debug = "true" *) reg [2:0] state;  // FSM state: 0=IDLE,1=DELIM,2=TARI,3=RTCAL,4=DONE,5=ERROR

    assign brain_state = state;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state         <= S_IDLE;
            sync          <= 1'b0;
            tari_count    <= 16'd0;
            pulse_counter <= 16'd0;
            pulse_width   <= 16'd0;
        end else begin
            case (state)
                // -------------------------------------------------
                // S_IDLE: Wait for a falling edge to start Delimiter
                // -------------------------------------------------
                S_IDLE: begin
                    sync <= 1'b0;
                    if (falling_edge) begin
                        pulse_counter <= 16'd1;
                        state         <= S_DELIM;
                    end else begin
                        pulse_counter <= 16'd0;
                    end
                end

                // -------------------------------------------------
                // S_DELIM: Count ticks during the Delimiter LOW dip
                //   On rising_edge: capture width, validate, move on
                // -------------------------------------------------
                S_DELIM: begin
                    if (rising_edge) begin
                        // Sample-then-reset: capture counter into pulse_width
                        pulse_width   <= pulse_counter;
                        pulse_counter <= 16'd1;
                        // Validate Delimiter width
                        if (pulse_counter >= DELIM_MIN &&
                            pulse_counter <= DELIM_MAX) begin
                            state <= S_TARI;
                        end else begin
                            state <= S_ERROR;
                        end
                    end else if (rfid_sync == 1'b0) begin
                        pulse_counter <= pulse_counter + 16'd1;
                        if (pulse_counter > 16'd5000) state <= S_ERROR; // 1 ms timeout (CW detected)
                    end
                end

                // -------------------------------------------------
                // S_TARI: Wait for E3 — the Data-0 falling edge.
                //   Counter here measures the dead-time between the
                //   delimiter's rising edge and Data-0's dip start.
                //   This is NOT Tari — we do not store it.
                //   On falling_edge: reset counter, move to S_RTCAL
                //   which will measure the true F→F Tari (E3→E4).
                // -------------------------------------------------
                S_TARI: begin
                    if (falling_edge) begin
                        pulse_counter <= 16'd1;  // Start true Tari measurement (E3→E4)
                        state         <= S_RTCAL;
                    end else begin
                        pulse_counter <= pulse_counter + 16'd1;
                        if (pulse_counter > 16'd5000) state <= S_ERROR; // 1 ms timeout
                    end
                end

                // -------------------------------------------------
                // S_RTCAL: Measure true falling→falling Tari (E3→E4).
                //   E3 = Data-0 dip start  (counter reset in S_TARI)
                //   E4 = RTcal  dip start  (falling_edge here)
                //   pulse_counter at E4 = full Data-0 symbol period = Tari.
                //   Validate Tari in [TARI_MIN..TARI_MAX], then assert sync.
                // -------------------------------------------------
                S_RTCAL: begin
                    if (falling_edge) begin
                        // Store the true falling→falling Tari (E3→E4)
                        pulse_width   <= pulse_counter;
                        tari_count    <= pulse_counter;
                        pulse_counter <= 16'd1;
                        // Validate Tari range, then wait one more edge (TRcal or
                        // Frame-Sync boundary) before firing sync so the PIE
                        // decoder starts exactly at the first data symbol.
                        if (pulse_counter >= TARI_MIN &&
                            pulse_counter <= TARI_MAX) begin
                            state <= S_TRCAL;  // Do NOT assert sync yet
                        end else begin
                            state <= S_ERROR;
                        end
                    end else begin
                        pulse_counter <= pulse_counter + 16'd1;
                        if (pulse_counter > 16'd5000) state <= S_ERROR;
                    end
                end

                // -------------------------------------------------
                // S_TRCAL: Skip the TRcal symbol (or the equivalent
                //   dead period in a Frame-Sync frame). Assert sync
                //   on the FIRST falling edge after RTcal, which is
                //   exactly the start of the first data symbol.
                //   The PIE decoder's D_WAIT_FE then measures from
                //   this edge to the next = true first data bit.
                // -------------------------------------------------
                S_TRCAL: begin
                    if (falling_edge) begin
                        sync  <= 1'b1;   // Fire sync at first data falling edge
                        state <= S_DONE;
                        pulse_counter <= 16'd1;
                    end else begin
                        pulse_counter <= pulse_counter + 16'd1;
                        if (pulse_counter > 16'd5000) state <= S_ERROR;
                    end
                end

                // -------------------------------------------------
                // S_DONE: Frame-sync valid, wait for package_complete
                // -------------------------------------------------
                S_DONE: begin
                    if (package_complete) begin
                        sync  <= 1'b0;
                        state <= S_IDLE;
                    end else if (falling_edge) begin
                        pulse_counter <= 16'd1;     // reset timeout on new symbols within the packet
                    end else begin
                        pulse_counter <= pulse_counter + 16'd1;
                        if (pulse_counter > 16'd5000) begin // 1 ms without falling edges (CW detected) -> deadlock release
                            sync  <= 1'b0;
                            state <= S_ERROR;
                        end
                    end
                end

                // -------------------------------------------------
                // S_ERROR: Invalid timing, wait for idle then retry
                // -------------------------------------------------
                S_ERROR: begin
                    sync          <= 1'b0;
                    pulse_counter <= 16'd0;
                    // Wait for stable HIGH (idle) before retrying
                    if (rfid_sync == 1'b1 && rfid_prev == 1'b1) begin
                        state <= S_IDLE;
                    end
                end

                // -------------------------------------------------
                default: begin
                    state <= S_IDLE;
                    sync  <= 1'b0;
                end
            endcase
        end
    end

endmodule
