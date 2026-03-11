/*
 *  RX (Receive)
 *
 *  Including Frame-Sync Detector, CRC-5, CRC-16, Command Buffer
 *
 *  FPGA Mode: The data path uses decoded_bit from the digital PIE decoder
 *  instead of raw pie_code. fs_detector still uses raw pie_code for preamble
 *  detection. clk_dpie is now the reconstructed clock from pie_decoder.
 */


`timescale 1us / 1ns


module rx
(
output [7:0]cmd,
output [51:0]param,
output package_complete,
output crc_check_pass,
output [15:0]crc_16,
output en_crc5,
output en_crc16,
output wire [2:0] brain_state,       // fs_detector state monitor
output wire        ila_fs,            // frame-sync flag for ILA
output wire [15:0] dbg_pulse_width,   // pulse width measurement
output wire [15:0] tari_width,        // measured Tari period for PIE decoder
input pie_code,
input decoded_bit,
input clk_dpie,
input clk_crc5,
input clk_crc16,
input clk,                            // 5 MHz system clock for fs_detector
input rst_n,
input rst_for_new_package,
input rst_crc16,
input reply_data,
input en_crc16_for_rpy
);


// Internal sync wire from fs_detector
(* mark_debug = "true" *) wire sync;  // Frame-sync valid (= ila_fs at top level)

// ila_fs mirrors the sync output for ILA probing
assign ila_fs = sync;


fs_detector fs_detector_1
(
.sync(sync),
.brain_state(brain_state),
.dbg_pulse_width(dbg_pulse_width),
.tari_width(tari_width),              // measured Tari period → pie_decoder
.rfid_in(pie_code),                   // pie_code is the inverted RF signal
.clk(clk),                            // 5 MHz system clock
.rst_n(rst_n),
.package_complete(package_complete)
);


crc5 crc5_1
(
.crc5_check_pass(crc5_check_pass),
.clk_crc5(clk_crc5),
.rst_for_new_package(rst_for_new_package),
.data(decoded_bit),
.sync(sync),
.package_complete(package_complete)
);


crc16 crc16_1
(
.crc16_check_pass_reg(crc16_check_pass_reg),
.crc_16(crc_16),
.clk_crc16(clk_crc16),
.rst_crc16(rst_crc16),
.data(decoded_bit),
.reply_data(reply_data),
.sync(sync),
.package_complete(package_complete),
.en_crc16_for_rpy(en_crc16_for_rpy)
);


cmd_buf cmd_buf_1
(
.cmd(cmd),
.param(param),
.package_complete(package_complete),
.en_crc5(en_crc5),
.en_crc16(en_crc16),
.clk_cmd(clk_dpie),
.rst_for_new_package(rst_for_new_package),
.bits_in(decoded_bit),
.sync(sync)
);


assign crc_check_pass = crc5_check_pass | crc16_check_pass_reg;


endmodule
