/*
 * Testbench: led_rgb_tb
 *
 * Purpose: Verify the LD0 RGB Brain LED logic from fpga_top.v
 *
 * Tests each brain_state value and confirms:
 *   S_IDLE  (0): Solid Blue  — led0_b=0(ON), led0_r=1(OFF), led0_g=1(OFF)
 *   S_DELIM (1): Blink Blue  — led0_b toggles with blink
 *   S_TARI  (2): Blink Blue  — led0_b toggles with blink
 *   S_RTCAL (3): Blink Red   — led0_r toggles with blink
 *   S_DONE  (4): Blink Green — led0_g toggles with blink
 *
 * Active-LOW convention: 0 = LED ON, 1 = LED OFF
 */

`timescale 1us / 1ns

module led_rgb_tb;

    // ---------------------------------------------------------------
    // Inputs (stimulus)
    // ---------------------------------------------------------------
    reg [2:0]  brain_state;
    reg        blink;

    // ---------------------------------------------------------------
    // Outputs (DUT — combinational RGB logic from fpga_top)
    // ---------------------------------------------------------------
    wire led0_r;
    wire led0_g;
    wire led0_b;

    // ---------------------------------------------------------------
    // DUT: replicate the exact combinational logic from fpga_top.v
    // ---------------------------------------------------------------
    assign led0_r = ~((brain_state == 3'd3) & blink);
    assign led0_g = ~((brain_state == 3'd4) & blink);
    assign led0_b = ~((brain_state == 3'd0)
                    | ((brain_state == 3'd1 || brain_state == 3'd2) & blink));

    // ---------------------------------------------------------------
    // Test counters
    // ---------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    // ---------------------------------------------------------------
    // Assertion task
    // ---------------------------------------------------------------
    task check_rgb;
        input [2:0]  state;
        input        blink_val;
        input        exp_r, exp_g, exp_b;
        input [63:0] label; // 8-char label
        begin
            brain_state = state;
            blink       = blink_val;
            #1; // let combinational logic settle

            if (led0_r === exp_r && led0_g === exp_g && led0_b === exp_b) begin
                $display("PASS | state=%0d blink=%0b | R=%b G=%b B=%b | %0s",
                         state, blink_val, led0_r, led0_g, led0_b, label);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | state=%0d blink=%0b | R=%b G=%b B=%b (exp %b %b %b) | %0s",
                         state, blink_val, led0_r, led0_g, led0_b, exp_r, exp_g, exp_b, label);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("led_rgb_tb.vcd");
        $dumpvars(0, led_rgb_tb);

        $display("=== LED RGB Brain Testbench ===");
        $display("Active-LOW: 0=ON, 1=OFF");
        $display("");

        // --- S_IDLE (0): Solid Blue regardless of blink ---
        //     R=OFF(1), G=OFF(1), B=ON(0)
        check_rgb(3'd0, 1'b0,  1'b1, 1'b1, 1'b0,  "IDLE_b0 ");
        check_rgb(3'd0, 1'b1,  1'b1, 1'b1, 1'b0,  "IDLE_b1 ");

        // --- S_DELIM (1): Blink Blue ---
        //     blink=0: R=OFF(1), G=OFF(1), B=OFF(1) [blink off]
        //     blink=1: R=OFF(1), G=OFF(1), B=ON(0)  [blink on]
        check_rgb(3'd1, 1'b0,  1'b1, 1'b1, 1'b1,  "DELIM_b0");
        check_rgb(3'd1, 1'b1,  1'b1, 1'b1, 1'b0,  "DELIM_b1");

        // --- S_TARI (2): Blink Blue ---
        check_rgb(3'd2, 1'b0,  1'b1, 1'b1, 1'b1,  "TARI_b0 ");
        check_rgb(3'd2, 1'b1,  1'b1, 1'b1, 1'b0,  "TARI_b1 ");

        // --- S_RTCAL (3): Blink Red ---
        //     blink=0: all OFF (1,1,1)
        //     blink=1: R=ON(0), G=OFF(1), B=OFF(1)
        check_rgb(3'd3, 1'b0,  1'b1, 1'b1, 1'b1,  "RTCAL_b0");
        check_rgb(3'd3, 1'b1,  1'b0, 1'b1, 1'b1,  "RTCAL_b1");

        // --- S_DONE (4): Blink Green ---
        //     blink=0: all OFF (1,1,1)
        //     blink=1: R=OFF(1), G=ON(0), B=OFF(1)
        check_rgb(3'd4, 1'b0,  1'b1, 1'b1, 1'b1,  "DONE_b0 ");
        check_rgb(3'd4, 1'b1,  1'b1, 1'b0, 1'b1,  "DONE_b1 ");

        // --- S_ERROR (5): All OFF (no LED lit) ---
        check_rgb(3'd5, 1'b0,  1'b1, 1'b1, 1'b1,  "ERR_b0  ");
        check_rgb(3'd5, 1'b1,  1'b1, 1'b1, 1'b1,  "ERR_b1  ");

        $display("");
        $display("=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule
