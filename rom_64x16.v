// rom_64x16.v
// 64x16 ROM with SDF-friendly port names used in bb_proc.v
// Q  = data out [15:0]
// CLK = clock
// CEN = chip enable (active low in many macros; we’ll treat 0 = enable)
// A  = address [5:0]
module rom_64x16 (
  output reg [15:0] Q,
  input  wire       CLK,
  input  wire       CEN,
  input  wire [5:0] A
);
  (* ram_style = "block" *) reg [15:0] mem [0:63];
  
  // Initialize ROM with hardcoded values from rom_code.txt
  // For Xilinx synthesis, memory is initialized via synthesis attributes
  // Add (* ram_style = "block" *) pragma to infer BRAM
  initial begin
    // Default initialization - replace with actual ROM contents
    // Row 1: 11010011 00000000 = 0xD300
    mem[0]  = 16'b1101001100000000;
    mem[1]  = 16'b0000000000000000;
    mem[2]  = 16'b0000000000000000;
    mem[3]  = 16'b0000000000000000;
    mem[4]  = 16'b0000000000000000;
    // Row 6: 01100000 00000000 = 0x6000
    mem[5]  = 16'b0110000000000000;
    // Fill remaining locations with zeros
    mem[6]  = 16'b0000000000000000;
    mem[7]  = 16'b0000000000000000;
    mem[8]  = 16'b0000000000000000;
    mem[9]  = 16'b0000000000000000;
    mem[10] = 16'b0000000000000000;
    mem[11] = 16'b0000000000000000;
    mem[12] = 16'b0000000000000000;
    mem[13] = 16'b0000000000000000;
    mem[14] = 16'b0000000000000000;
    mem[15] = 16'b0000000000000000;
    mem[16] = 16'b0000000000000000;
    mem[17] = 16'b0000000000000000;
    mem[18] = 16'b0000000000000000;
    mem[19] = 16'b0000000000000000;
    mem[20] = 16'b0000000000000000;
    mem[21] = 16'b0000000000000000;
    mem[22] = 16'b0000000000000000;
    mem[23] = 16'b0000000000000000;
    mem[24] = 16'b0000000000000000;
    mem[25] = 16'b0000000000000000;
    mem[26] = 16'b0000000000000000;
    mem[27] = 16'b0000000000000000;
    mem[28] = 16'b0000000000000000;
    mem[29] = 16'b0000000000000000;
    mem[30] = 16'b0000000000000000;
    mem[31] = 16'b0000000000000000;
    mem[32] = 16'b0000000000000000;
    mem[33] = 16'b0000000000000000;
    mem[34] = 16'b0000000000000000;
    mem[35] = 16'b0000000000000000;
    mem[36] = 16'b0000000000000000;
    mem[37] = 16'b0000000000000000;
    mem[38] = 16'b0000000000000000;
    mem[39] = 16'b0000000000000000;
    mem[40] = 16'b0000000000000000;
    mem[41] = 16'b0000000000000000;
    mem[42] = 16'b0000000000000000;
    mem[43] = 16'b0000000000000000;
    mem[44] = 16'b0000000000000000;
    mem[45] = 16'b0000000000000000;
    mem[46] = 16'b0000000000000000;
    mem[47] = 16'b0000000000000000;
    mem[48] = 16'b0000000000000000;
    mem[49] = 16'b0000000000000000;
    mem[50] = 16'b0000000000000000;
    mem[51] = 16'b0000000000000000;
    mem[52] = 16'b0000000000000000;
    mem[53] = 16'b0000000000000000;
    mem[54] = 16'b0000000000000000;
    mem[55] = 16'b0000000000000000;
    mem[56] = 16'b0000000000000000;
    mem[57] = 16'b0000000000000000;
    mem[58] = 16'b0000000000000000;
    mem[59] = 16'b0000000000000000;
    mem[60] = 16'b0000000000000000;
    mem[61] = 16'b0000000000000000;
    mem[62] = 16'b0000000000000000;
    mem[63] = 16'b0000000000000000;
  end

  always @(posedge CLK) begin
    if (CEN == 1'b0) begin
      Q <= mem[A];
    end
    // else hold last value
  end
endmodule
