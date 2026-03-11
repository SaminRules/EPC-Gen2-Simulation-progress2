/*
 *  Simulation Stub for Xilinx Clocking Wizard IP (clk_wiz_0)
 *
 *  Purpose:
 *  --------
 *  Satisfies module elaboration in Icarus Verilog without requiring
 *  Xilinx simulation netlists. For use ONLY in simulation.
 *
 *  Behavior:
 *  ---------
 *  - clk_out1: passed through directly from clk_in1
 *    (the testbench already generates the desired 5 MHz clock)
 *  - locked: hardcoded to 1'b1 (always locked)
 *  - reset: accepted but ignored
 */

`timescale 1us / 1ns

module clk_wiz_0 (
    output wire clk_out1,
    input  wire clk_in1,
    input  wire reset,
    output wire locked
);

    // Pass clock straight through — testbench provides 5 MHz directly
    assign clk_out1 = clk_in1;

    // Always report locked so downstream logic doesn't stall
    assign locked = 1'b1;

endmodule
