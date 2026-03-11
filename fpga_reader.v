/*
 * Module: fpga_reader
 * 
 * Purpose:
 * --------
 * This module simulates a virtual RFID reader that generates EPC Gen2 protocol
 * commands to test the RFID tag (bb_proc) in real hardware on the FPGA.
 * 
 * Instead of requiring an actual RF reader, this module creates the command
 * signals (pie_code) that would normally come from a real RFID reader transmitter.
 * This allows for complete system-level testing and validation of the tag
 * implementation without external RFID reader hardware.
 * 
 * Functionality:
 * --------
 * - Periodically generates command signals to stimulate the tag
 * - Creates a simplified "Query" command by sending a wake-up pulse (100µs low pulse)
 * - Runs on the 200kHz clock that drives the tag baseband processor
 * - Provides debug trigger signal for oscilloscope/logic analyzer synchronization
 * - Operates in a cyclic pattern: IDLE → SEND_CMD → WAIT → repeat
 * 
 * Command Timing:
 * --------
 * At 200kHz clock:
 * - IDLE state: Waits ~0.5 seconds (60,000 clock cycles) before next command
 * - SEND_CMD state: Sends active-low pulse for 100µs (20 clock cycles at 200kHz)
 * - WAIT state: Waits 5ms after command before returning to IDLE
 * - Cycle Time: ~0.5 seconds between commands (reader sends Query periodically)
 * 
 * Signals:
 * --------
 * Input:  clk (200 kHz clock synchronized with tag)
 * Input:  rst (asynchronous reset)
 * Output: pie_code (Protocol/PIE encoded command to tag - active low pulse)
 * Output: debug_trig (Logic analyzer trigger - pulses high when command sent)
 * 
 * Integration:
 * --------
 * This module is instantiated in fpga_top.v and connects directly to bb_proc.
 * The pie_code output feeds the tag's input, simulating reader transmission.
 * The debug_trig helps correlate timing on test equipment.
 * 
 * Testing Strategy:
 * --------
 * With both fpga_reader and bb_proc running on the same 200kHz clock:
 * 1. Reader sends periodic Query commands
 * 2. Tag receives pie_code and processes command
 * 3. Tag generates response on bs_data
 * 4. Full RFID communication loop can be verified with oscilloscope/logic analyzer
 * 5. LEDs indicate activity (reader_cmd, tag_reply, clock status)
 */

module fpga_reader (
    input  wire clk,        // 200kHz clock
    input  wire rst,
    output reg  pie_code,   // The command signal sent to Tag
    output reg  debug_trig  // Goes high when we send a command
);

    // Simple State Machine to send a "Query" command periodically
    reg [15:0] counter;
    reg [3:0]  state;
    
    localparam IDLE      = 0;
    localparam SEND_CMD  = 1;
    localparam WAIT      = 2;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 0;
            state <= IDLE;
            pie_code <= 1; // Idle line is usually high in RFID
            debug_trig <= 0;
        end else begin
            case (state)
                IDLE: begin
                    pie_code <= 1;
                    // Wait for ~0.5 seconds (at 200kHz) before trying again
                    if (counter == 60000) begin
                        counter <= 0;
                        state <= SEND_CMD;
                        debug_trig <= 1; // Trigger scope
                    end else begin
                        counter <= counter + 1;
                        debug_trig <= 0;
                    end
                end

                SEND_CMD: begin
                    // Send a simple "dip" to simulate a start-of-frame or Query
                    // This is a simplified "Wake Up" pulse for the Tag
                    if (counter < 20) begin
                        pie_code <= 0; // Active Low pulse
                        counter <= counter + 1;
                    end else begin
                        pie_code <= 1;
                        counter <= 0;
                        state <= WAIT;
                    end
                end

                WAIT: begin
                    // Wait before looping back
                    if (counter > 1000) begin
                        state <= IDLE;
                        counter <= 0;
                    end else begin
                        counter <= counter + 1;
                    end
                end
            endcase
        end
    end
endmodule