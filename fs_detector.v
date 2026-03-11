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
 *    - Delimiter: detect a LOW dip in the range [50..80] ticks
 *    - Tari: measure the full falling-to-falling edge period of data-0
 *    - RTcal: measure the full falling-to-falling edge period of RTcal
 *    - Validate RTcal > 2 * Tari using the pivot
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
                     S_RTCAL = 3'd3,   // Measuring RTcal symbol period
                     S_DONE  = 3'd4,   // Frame-sync valid
                     S_ERROR = 3'd5;   // Invalid timing

    // ---------------------------------------------------------------
    // Timing thresholds (5 MHz clock, 200 ns/tick)
    // ---------------------------------------------------------------
    // Delimiter LOW dip: 12.5 us nominal → 62.5 ticks, accept 50–80
    localparam [15:0] DELIM_MIN = 16'd50;
    localparam [15:0] DELIM_MAX = 16'd80;

    // Tari full period (falling→falling): 6.25 us = 31.25 ticks, accept 10–50
    localparam [15:0] TARI_MIN = 16'd10;
    localparam [15:0] TARI_MAX = 16'd50;

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
                    end
                end

                // -------------------------------------------------
                // S_TARI: Measure Tari as falling→falling period
                //   Counter was reset to 1 at the Delimiter's rising edge.
                //   On next falling edge: that's one full Tari period.
                // -------------------------------------------------
                S_TARI: begin
                    if (falling_edge) begin
                        // Sample-then-reset: capture Tari period
                        pulse_width   <= pulse_counter;
                        tari_count    <= pulse_counter;
                        pulse_counter <= 16'd1;
                        // Validate Tari
                        if (pulse_counter >= TARI_MIN &&
                            pulse_counter <= TARI_MAX) begin
                            state <= S_RTCAL;
                        end else begin
                            state <= S_ERROR;
                        end
                    end else begin
                        pulse_counter <= pulse_counter + 16'd1;
                    end
                end

                // -------------------------------------------------
                // S_RTCAL: Measure RTcal as falling→falling period
                //   On next falling edge: that's the full RTcal period.
                //   Validate: RTcal > 2 * Tari
                // -------------------------------------------------
                S_RTCAL: begin
                    if (falling_edge) begin
                        // Sample-then-reset
                        pulse_width   <= pulse_counter;
                        pulse_counter <= 16'd1;
                        // Validate RTcal > 2 * Tari
                        if (pulse_counter > {tari_count[14:0], 1'b0}) begin
                            sync  <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            state <= S_ERROR;
                        end
                    end else begin
                        pulse_counter <= pulse_counter + 16'd1;
                    end
                end

                // -------------------------------------------------
                // S_DONE: Frame-sync valid, wait for package_complete
                // -------------------------------------------------
                S_DONE: begin
                    if (package_complete) begin
                        sync  <= 1'b0;
                        state <= S_IDLE;
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
