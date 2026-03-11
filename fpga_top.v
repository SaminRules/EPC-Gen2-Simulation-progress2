/*
 * Module: fpga_top
 *
 * Purpose:
 * --------
 * Top-level FPGA module for EPC Gen2 RFID Tag on Xilinx Spartan-7 (Arty S7).
 *
 * *** PHYSICAL HARDWARE MODE ***
 * The virtual reader (fpga_reader) has been removed. The rfid_in pin
 * on PMOD JA Pin 1 (L17) is the sole source of PIE-encoded commands.
 *
 * Architecture (Redesigned):
 * --------
 * Physical Antenna (PMOD JA Pin 1)
 *     └──→ rfid_in → glitch_filter → rfid_filtered → bb_proc
 *                                                     ├──→ rx → fs_detector → brain_state + tari_width
 *                                                     ├──→ pie_decoder (uses tari_width for clock recovery)
 *                                                     │       └──→ decoded_bit + dec_clk
 *                                                     ├──→ cmd_buf (clocked by dec_clk, data = decoded_bit)
 *                                                     └──→ cmd_proc → cmd_state
 *
 * System Clock (100 MHz)  ──→ clk_in_IBUF_BUFG ──→ dbg_hub/clk (JTAG)
 *     │
 * Clocking Wizard (PLL) → 5 MHz clock
 *     │
 *     ├──→ glitch_filter (4-cycle digital integrator on rfid_in)
 *     ├──→ fs_detector (pulse-width @ 200ns resolution)
 *     ├──→ pie_decoder (symbol-level PIE decoding + clock recovery)
 *     ├──→ heartbeat_cnt (unused, retained to avoid removing counter)
 *     ├──→ led_div (RGB blink generator, ~2.4 Hz)
 *     ├──→ u_ila_0/clk (ILA sampling)
 *     │
 * Clock Divider (÷25) → 200 kHz clock
 *     └──→ bb_proc (clk_200K, internal CRG state machines)
 *
 * ================================================================
 * SIGNAL CONDITIONING — GLITCH FILTER
 * ================================================================
 *
 * A 4-cycle digital integrator sits between rfid_in and all downstream
 * logic.  The filter uses a 4-bit shift register clocked at 5 MHz;
 * the output changes only when ≥3 of the last 4 samples agree.
 * This filters glitches shorter than 800 ns (4 × 200 ns), protecting
 * the CRC-5 check and PIE decoder from analog jitter.
 *
 * ================================================================
 * DIAGNOSTIC BYPASS SYSTEM
 * ================================================================
 *
 * Mode Toggle — sw_diag_mode (SW0, Pin H14):
 *   0 = Smart Mode    : LD1 Solid Blue.  LD0 (Brain) follows real cmd_state.
 *   1 = Diagnostic Mode: LD1 Solid Red.  LD0 follows manual test_state_reg.
 *
 * Manual Control — diag_btn (BTN1, Pin K16):
 *   In Diagnostic Mode, each debounced press increments test_state_reg (0–3):
 *     0 → IDLE    : LD0 Solid Blue
 *     1 → RECEIVE : LD0 Blinking Blue  (~2.4 Hz)
 *     2 → PROCESS : LD0 Solid Red      + 3.35s Pulse-Stretch
 *     3 → REPLY   : LD0 Slow-Pulse Green + 3.35s Pulse-Stretch
 *   State wraps: 3 → 0.
 *
 *   ERROR MODE: If PROCESS (4'h3) persists > ~6.7s (two 3.35s durations),
 *     the system enters Error Mode → LD0 Blinking Red (~2.4 Hz).
 *     After another ~6.7s of Error display, auto-resets to IDLE (Solid Blue).
 *
 * Debounce: 20-bit counter @ 5 MHz = ~209 ms settling window.
 *   Prevents double-stepping on a single button press.
 *
 * 3-LED Diagnostic System:
 *     led[0]: HARDCODED OFF
 *     led[1] (Ears):   ON when locked=1 and rfid_filtered=0 (PLL locked, antenna idle)
 *     led[2] (Mouth):  ON only during tag_reply (backscatter active)
 *     led[3]: HARDCODED OFF
 *     LD0 RGB (Brain) — driven by active_state (muxed from real/diag):
 *       Solid Blue     — IDLE    (4'h0)
 *       Blinking Blue  — RECEIVE (Sloting=4'h1, Arbitrate=4'h2)
 *       Solid Red      — PROCESS (Reply=4'h3, Acknowledged=4'h4) [pulse-stretched ~3.35s]
 *       Blinking Red   — ERROR   (PROCESS timeout >~6.7s) [auto-resets after ~6.7s]
 *       Slow Pulse Green — REPLY (SlotTran/Open/Secured/Killing/Killed) [pulse-stretched ~3.35s]
 *     LD1 RGB (Mode Indicator):
 *       Solid Blue  — Smart Mode      (sw_diag_mode=0)
 *       Solid Red   — Diagnostic Mode (sw_diag_mode=1)
 *
 * Debug Ports:
 *     brain_state[2:0]: fs_detector state machine monitor (still routed to ILA)
 *     cmd_state[3:0]:   cmd_proc EPC Gen2 FSM state (drives RGB LEDs in Smart Mode)
 *     tari_width[15:0]: Measured Tari period from fs_detector (5 MHz ticks)
 *     ila_fs:           Frame-sync flag
 *     dbg_pulse_width[15:0]: Last measured pulse width (in 5 MHz ticks)
 *     rfid_filtered:    Output of the glitch filter
 */

module fpga_top(
    input  wire        clk_in,            // 100 MHz System Clock (Pin R2)
    input  wire        rst_btn,           // Reset Button (Pin H13, Active-HIGH)
    (* mark_debug = "true" *) input  wire        rfid_in,           // RFID antenna input (PMOD JA Pin 1, L17)
    input  wire        diag_btn,          // Diagnostic step button (physical btn[1], Pin K16)
    (* mark_debug = "true" *) (* KEEP = "TRUE" *) input  wire  sw_diag_mode,      // Mode switch (SW0, Pin H14): 0=Smart, 1=Diagnostic
    (* mark_debug = "true" *) output wire [3:0]  led,               // 4 Green User LEDs
    (* mark_debug = "true" *) output wire        led0_r,            // RGB LED0 Red   (Pin J15)
    (* mark_debug = "true" *) output wire        led0_g,            // RGB LED0 Green (Pin G17)
    (* mark_debug = "true" *) output wire        led0_b,            // RGB LED0 Blue  (Pin F15)
    output wire        led1_r,            // RGB LED1 Red   (Pin E15) — Diagnostic indicator
    output wire        led1_g,            // RGB LED1 Green (Pin F18) — always OFF
    output wire        led1_b,            // RGB LED1 Blue  (Pin E14) — Smart indicator
    output wire        tx_debug,          // Logic Analyzer Output
    // --- Debug Ports (Brain Monitors) ---
    (* mark_debug = "true" *) output wire [2:0]  brain_state,       // fs_detector state for ILA
    output wire        ila_fs,            // Frame-sync flag for ILA
    output wire [15:0] dbg_pulse_width    // Pulse width measurement for ILA
    );

    // ---------------------------------------------------------------
    // Internal Signals
    // ---------------------------------------------------------------
    wire clk_5mhz;    // Output from Clock Wizard
    wire clk_200khz;  // Output from clk_div
    (* mark_debug = "true" *) wire locked;       // Clock wizard lock indicator

    (* mark_debug = "true" *) wire rfid_filtered; // Glitch-filtered antenna signal
    (* mark_debug = "true" *) wire tag_reply;    // Signal from Tag -> Reader
    wire tag_en;       // Enable signal from Tag

    (* mark_debug = "true" *) wire [3:0] cmd_state;  // cmd_proc EPC Gen2 FSM present state
    (* mark_debug = "true" *) wire [15:0] tari_width; // Measured Tari period from fs_detector

    // ---------------------------------------------------------------
    // 1. Heartbeat LED — visual board confirmation
    //    25-bit counter on 5 MHz → MSB toggles at ~0.15 Hz
    // ---------------------------------------------------------------
    reg [24:0] heartbeat_cnt;

    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn)
            heartbeat_cnt <= 25'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 25'd1;
    end

    // ---------------------------------------------------------------
    // 1b. LED Blink Divider — ~2.4 Hz toggle for RGB LED
    //     22-bit counter on 5 MHz → bit[20] toggles at ~2.38 Hz
    // ---------------------------------------------------------------
    reg [21:0] led_div;

    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn)
            led_div <= 22'd0;
        else
            led_div <= led_div + 22'd1;
    end

    wire blink = led_div[20]; // ~2.4 Hz toggle

    // ---------------------------------------------------------------
    // 2. Clocking (The Heart)
    //    "clk_wiz_0" is a Vivado IP black-box: 100 MHz → 5 MHz
    // ---------------------------------------------------------------
    clk_wiz_0 clock_gen (
        .clk_out1(clk_5mhz),     // 5 MHz output
        .reset(rst_btn),
        .locked(locked),
        .clk_in1(clk_in)         // 100 MHz input
    );

    // ---------------------------------------------------------------
    // 3. Clock Divider (5 MHz → 200 kHz)
    // ---------------------------------------------------------------
    clk_div divider (
        .clk_in(clk_5mhz),
        .rst(rst_btn),
        .clk_out(clk_200khz)
    );

    // ---------------------------------------------------------------
    // 4. Glitch Filter — 4-cycle digital integrator on rfid_in
    //    Shift register samples rfid_in at 5 MHz (200 ns/tick).
    //    Output changes only when ≥3 of the last 4 samples agree.
    //    Filters glitches shorter than 800 ns.
    // ---------------------------------------------------------------
    reg [3:0] gf_sr;        // 4-bit shift register
    reg       gf_out;       // filtered output

    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn) begin
            gf_sr  <= 4'b0000;
            gf_out <= 1'b0;
        end else begin
            gf_sr <= {gf_sr[2:0], rfid_in};  // shift in new sample

            // Majority vote: ≥3 of 4 HIGH → output HIGH
            // ≥3 of 4 LOW  → output LOW
            // Otherwise: hold previous value
            case (gf_sr)
                4'b1111, 4'b1110, 4'b1101, 4'b1011, 4'b0111:
                    gf_out <= 1'b1;
                4'b0000, 4'b0001, 4'b0010, 4'b0100, 4'b1000:
                    gf_out <= 1'b0;
                default:
                    gf_out <= gf_out;  // hold (2 vs 2 — hysteresis)
            endcase
        end
    end

    assign rfid_filtered = gf_out;

    // ---------------------------------------------------------------
    // 5. The RFID Tag (Your Design)
    //    rfid_filtered replaces the raw rfid_in + XOR hack.
    //    The PIE decoder inside bb_proc handles clock recovery.
    // ---------------------------------------------------------------
    bb_proc my_tag (
        .clk(clk_5mhz),           // 5 MHz for fs_detector + pie_decoder
        .clk_200K(clk_200khz),
        .rst(rst_btn),
        .pie_code(rfid_filtered),  // Glitch-filtered signal → fs_detector + pie_decoder
        .clk_dpie(rfid_filtered),  // Legacy port (pie_decoder generates the real dec_clk internally)
        .debug_switch(1'b1),
        .en_tx(tag_en),
        .bs_data(tag_reply),
        .brain_state(brain_state),
        .cmd_state(cmd_state),     // cmd_proc EPC Gen2 FSM state → RGB LED logic
        .tari_width(tari_width),   // Measured Tari for ILA
        .ila_fs(ila_fs),
        .dbg_pulse_width(dbg_pulse_width)
    );

    // ---------------------------------------------------------------
    // 6. Green LED Outputs (Physical Hardware Mode)
    //    led[0]: OFF (hardcoded)  — eliminates heartbeat distraction
    //    led[1]: Ears — PLL locked AND antenna idle
    //    led[2]: Mouth — ON only during tag backscatter reply
    //    led[3]: OFF (hardcoded)  — eliminates extra noise
    // ---------------------------------------------------------------
    assign led[0] = 1'b0;                      // Hardcoded OFF
    assign led[1] = locked & ~rfid_filtered;   // Ears: listening (locked, no cmd)
    assign led[2] = tag_reply;                 // Mouth: ON during tag reply
    assign led[3] = 1'b0;                      // Hardcoded OFF

    // ---------------------------------------------------------------
    // 7. Diagnostic Mode — diag_btn Debounce + test_state_reg
    //
    //    Debounce: two-stage synchronizer → 20-bit stability counter @ 5 MHz
    //    Stable window: 2^20 / 5,000,000 = ~209 ms → no double-step on release.
    //    db_press is a single-cycle HIGH pulse on the rising edge of db_stable.
    // ---------------------------------------------------------------
    reg [19:0] db_cnt;
    reg db_sync0, db_sync1, db_stable, db_prev;

    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn) begin
            db_sync0  <= 1'b0;
            db_sync1  <= 1'b0;
            db_cnt    <= 20'd0;
            db_stable <= 1'b0;
            db_prev   <= 1'b0;
        end else begin
            // Two-stage synchronizer (metastability)
            db_sync0 <= diag_btn;
            db_sync1 <= db_sync0;
            // Stability counter: count while input disagrees, reset when it agrees
            if (db_sync1 != db_stable) begin
                // Input disagrees with accepted level — count toward acceptance
                if (db_cnt == 20'hF_FFFF)
                    db_stable <= db_sync1;  // held stable for ~209 ms → accept
                else
                    db_cnt <= db_cnt + 20'd1;
            end else begin
                // Input matches accepted level — no debounce needed, reset counter
                db_cnt <= 20'd0;
            end
            // Edge-detect register
            db_prev <= db_stable;
        end
    end

    (* mark_debug = "true" *) wire db_press = db_stable & ~db_prev;  // single-cycle rising-edge pulse

    // ---------------------------------------------------------------
    // 7c. sw_diag_mode 2-Stage CDC Synchronizer
    //     sw_diag_mode is a slow asynchronous input (mechanical switch).
    //     Before it is used in the clocked test_state_reg logic, it is
    //     passed through two flip-flops clocked by clk_5mhz to prevent
    //     metastability.  sw_mode_sync is the stable, clock-domain-safe
    //     version used in all sequential (registered) logic.
    //     The combinational LED1 assigns use the raw port directly —
    //     that path is pure IBUF→OBUF and needs no synchronizer.
    // ---------------------------------------------------------------
    reg sw_mode_ff1, sw_mode_ff2;
    (* ASYNC_REG = "TRUE" *) reg sw_mode_sync_r;

    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn) begin
            sw_mode_ff1   <= 1'b0;
            sw_mode_ff2   <= 1'b0;
            sw_mode_sync_r <= 1'b0;
        end else begin
            sw_mode_ff1   <= sw_diag_mode;   // stage 1
            sw_mode_ff2   <= sw_mode_ff1;    // stage 2 — metastability resolved
            sw_mode_sync_r <= sw_mode_ff2;   // named alias for clarity
        end
    end

    wire sw_mode_sync = sw_mode_sync_r;  // stable synchronized signal → use in clocked logic

    // ---------------------------------------------------------------
    // 7b. test_state_reg: 2-bit counter incremented by debounced BTN1
    //     Only active in Diagnostic Mode (sw_mode_sync=1, synchronized).
    //     Wraps: 0 → 1 → 2 → 3 → 0
    //     Mapping to active_state:
    //       0 → 4'h0 (IDLE)      1 → 4'h1 (RECEIVE)
    //       2 → 4'h3 (PROCESS)   3 → 4'h5 (REPLY)
    // ---------------------------------------------------------------
    (* mark_debug = "true" *) reg [1:0] test_state_reg;

    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn)
            test_state_reg <= 2'd0;
        else if (err_autoreset_fire)
            test_state_reg <= 2'd0;            // auto-reset → back to IDLE
        else if (sw_mode_sync && db_press)   // use synchronized signal here
            test_state_reg <= test_state_reg + 2'd1;  // wraps 3→0 naturally
    end

    // Map 2-bit test_state_reg into the 4-bit cmd_state space
    wire [3:0] diag_state_mapped =
        (test_state_reg == 2'd0) ? 4'h0 :  // IDLE
        (test_state_reg == 2'd1) ? 4'h1 :  // RECEIVE (Sloting)
        (test_state_reg == 2'd2) ? 4'h3 :  // PROCESS (Reply)
                                   4'h5;   // REPLY   (SlotTran)

    // Active state: Diagnostic Mode uses test state, Smart Mode uses real FSM
    // sw_mode_sync used here (clocked path); raw sw_diag_mode used for LED1 (combinational)
    (* mark_debug = "true" *) wire [3:0] active_state = sw_mode_sync ? diag_state_mapped : cmd_state;

    // ---------------------------------------------------------------
    // 8. RGB LED0 (Brain) — active_state mux drives both modes
    //    State Groups (semantic mapping from active_state):
    //      IDLE    : Ready      (4'h0)                        → Solid Blue
    //      RECEIVE : Sloting    (4'h1), Arbitrate (4'h2)      → Blinking Blue
    //      PROCESS : Reply      (4'h3), Acknowledged (4'h4)  → Solid Red     [stretched]
    //      ERROR   : PROCESS timeout (>6.7s)                  → Blinking Red  [auto-resets]
    //      REPLY   : SlotTran   (4'h5) and above              → Slow-Pulse Green [stretched]
    //
    //    Pulse stretching: 24-bit counter @ 5 MHz → ~3.35 s hold per event
    //    Error timeout:    25-bit counter @ 5 MHz → ~6.7 s (two 3.35s durations)
    // ---------------------------------------------------------------

    // --- State decode wires (single driver each) ---
    wire is_idle    = (active_state == 4'h0);
    wire is_receive = (active_state == 4'h1) | (active_state == 4'h2);
    wire is_process = (active_state == 4'h3) | (active_state == 4'h4);
    wire is_reply   = (active_state >= 4'h5);

    // ---------------------------------------------------------------
    // 8a. Error Mode — timeout + auto-reset
    //     err_timeout_cnt:  counts while is_process is HIGH.
    //                       If it reaches ~33.5M (6.7s), sets error_active.
    //     err_autoreset_cnt: counts while error_active is HIGH.
    //                        After another ~6.7s, clears error and resets FSM.
    //     Auto-reset clears test_state_reg → 2'd0 so both Diagnostic and
    //     Smart modes return to IDLE (Solid Blue).
    // ---------------------------------------------------------------
    localparam [24:0] ERR_TIMEOUT_LIMIT = 25'd33_500_000;  // 5 MHz × 6.7 s

    reg [24:0] err_timeout_cnt;
    reg [24:0] err_autoreset_cnt;
    reg        error_active;
    reg        err_autoreset_fire;  // single-cycle pulse when auto-reset triggers

    // --- Timeout counter: counts up while in PROCESS, resets otherwise ---
    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn) begin
            err_timeout_cnt <= 25'd0;
            error_active    <= 1'b0;
        end else if (err_autoreset_fire) begin
            // Auto-reset fires: clear error, return to normal
            error_active    <= 1'b0;
            err_timeout_cnt <= 25'd0;
        end else if (error_active) begin
            // Already in error — hold counter, flag stays set until auto-reset
        end else if (is_process) begin
            if (err_timeout_cnt >= ERR_TIMEOUT_LIMIT) begin
                error_active    <= 1'b1;   // enter error mode
                err_timeout_cnt <= 25'd0;   // reset for cleanliness
            end else begin
                err_timeout_cnt <= err_timeout_cnt + 25'd1;
            end
        end else begin
            // Not in PROCESS and not in error — reset counter
            err_timeout_cnt <= 25'd0;
        end
    end

    // --- Auto-reset counter: counts while error_active, fires after ~6.7s ---
    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn) begin
            err_autoreset_cnt  <= 25'd0;
            err_autoreset_fire <= 1'b0;
        end else if (error_active) begin
            if (err_autoreset_cnt >= ERR_TIMEOUT_LIMIT) begin
                err_autoreset_fire <= 1'b1;   // pulse: triggers reset
            end else begin
                err_autoreset_cnt  <= err_autoreset_cnt + 25'd1;
                err_autoreset_fire <= 1'b0;
            end
        end else begin
            err_autoreset_cnt  <= 25'd0;
            err_autoreset_fire <= 1'b0;
        end
    end

    // --- Clear error_active and reset FSM on auto-reset fire ---
    //     (error_active is set in the timeout block above;
    //      it is cleared here via the auto-reset fire pulse,
    //      which takes priority on the next cycle.)
    //     test_state_reg reset is handled in Section 7b below (via err_autoreset_fire).

    // --- Pulse-stretch counters (24-bit @ 5 MHz = ~3.35 s) ---
    //     proc_stretch: guarded by !error_active to prevent ghost red pulses.
    //                   Force-cleared when auto-reset fires.
    reg [23:0] proc_stretch;
    reg [23:0] reply_stretch;

    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn)
            proc_stretch <= 24'd0;
        else if (err_autoreset_fire)
            proc_stretch <= 24'd0;           // ghost-pulse prevention
        else if (is_process && !error_active)
            proc_stretch <= 24'hFF_FFFF;     // only load when NOT in error
        else if (proc_stretch != 24'd0)
            proc_stretch <= proc_stretch - 24'd1;
    end

    always @(posedge clk_5mhz or posedge rst_btn) begin
        if (rst_btn)
            reply_stretch <= 24'd0;
        else if (is_reply)
            reply_stretch <= 24'hFF_FFFF;
        else if (reply_stretch != 24'd0)
            reply_stretch <= reply_stretch - 24'd1;
    end

    wire proc_stretched  = (proc_stretch  != 24'd0);
    wire reply_stretched = (reply_stretch != 24'd0);

    // --- RGB LD0 assignments (single driver per signal, confirmed) ---
    //   Normal:
    //     led0_b: ON solid (IDLE) or ON blinking (RECEIVE)
    //     led0_r: ON solid when PROCESS state was recently active
    //     led0_g: Slow pulse (inverted blink) when REPLY state was recently active
    //   Error override:
    //     led0_r: Blinking Red (~2.4 Hz)
    //     led0_b: OFF
    //     led0_g: OFF
    assign led0_b = error_active ? 1'b0 : (is_idle | (is_receive & blink));
    assign led0_r = error_active ? blink : proc_stretched;
    assign led0_g = error_active ? 1'b0 : (reply_stretched & ~blink);

    // ---------------------------------------------------------------
    // 9. RGB LED1 (Mode Indicator, LD1) — single driver per signal
    //    Smart Mode      (sw_diag_mode=0): Solid Blue
    //    Diagnostic Mode (sw_diag_mode=1): Solid Red
    // ---------------------------------------------------------------
    assign led1_r = sw_diag_mode;    // Red ON  in Diagnostic Mode
    assign led1_g = 1'b0;            // Green always OFF
    assign led1_b = ~sw_diag_mode;   // Blue ON  in Smart Mode

    // ---------------------------------------------------------------
    // 10. Logic Analyzer / Oscilloscope Outputs
    // ---------------------------------------------------------------
    assign tx_debug = tag_reply;       // Connect scope here

endmodule