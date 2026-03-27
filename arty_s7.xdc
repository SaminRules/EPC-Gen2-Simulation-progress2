## ============================================================================
## Arty S7-50 Master Constraints File (.xdc)
## Target Device: xc7s50csga324-1
## Project: EPC Gen2 RFID Tag - Refactored fpga_top.v
## ============================================================================
##
## IMPORTANT NOTES:
##   1. Reset polarity: Arty S7 buttons are Active-HIGH (pressed = 1).
##      fpga_top.v passes rst_btn directly to clk_wiz_0 (active-high reset)
##      and to bb_proc, where crg.v generates rst_n = ~rst internally.
##      No external inversion is needed.
##
##   2. rfid_in: Connected to PMOD JA Pin 1 with PULLDOWN to suppress
##      floating noise when no antenna is connected.
##
##   3. All I/O standards are LVCMOS33 (3.3V) per Arty S7 bank voltages.
##
##   4. ILA Clocking: dbg_hub uses 100 MHz (clk_in_IBUF_BUFG) for JTAG
##      stability. u_ila_0 uses clk_5mhz for sampling the 5 MHz domain.
## ============================================================================


## ----------------------------------------------------------------------------
## 100 MHz System Clock - Pin R2
## ----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports clk_in]


## ----------------------------------------------------------------------------
## Reset Button - btn[3], Pin H13 (Active-HIGH)
## Moved from G15 to H13 to free G15 for btn2 (XOR state injection).
## ----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports rst_btn]


## ----------------------------------------------------------------------------
## XOR State Injection Button - btn2, Pin G15 (BTN2, Active-HIGH)
## Press to XOR with rfid_in → manually trigger state transitions in Smart Mode.
## (Currently not used in fpga_top.v wrapper)
## ----------------------------------------------------------------------------
# set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports btn2]


## ----------------------------------------------------------------------------
## Diagnostic Step Button - diag_btn mapped to physical btn[1], Pin K16
## In Diagnostic Mode (SW0=1): increments test_state_reg (0-3) to cycle LD0.
## Button is debounced in RTL (~209 ms @ 5 MHz) to prevent double-stepping.
## Note: rx_debug removed from K16 - reader_cmd is observable via ILA instead.
## ----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports diag_btn]


## ----------------------------------------------------------------------------
## Mode Toggle Switch - SW0, Pin H14 (0=Smart Mode, 1=Diagnostic Mode)
## Digilent Arty-S7-50-Master.xdc: sw[0] = H14 (IO_L20N_T3_A19_15, LVCMOS33)
## ----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports sw_diag_mode]


## ----------------------------------------------------------------------------
## RFID Input - PMOD JA Pin 1, Pin L17
## PULLDOWN suppresses floating noise when antenna is disconnected.
## ----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS33} [get_ports rfid_in]
set_property PULLTYPE PULLDOWN [get_ports rfid_in]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets rfid_in_IBUF]

# Pmod Header JA - Pin 2 (Mapped to the RFID Transmit signal)
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports tx_debug]


## ============================================================================
## Green User LEDs (3-LED Diagnostic System)
## ============================================================================

## LED[0] - Hardcoded OFF - Pin E18
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {led[0]}]

## LED[1] - Ears (locked & ~reader_cmd = PLL locked, antenna idle) - Pin F13
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33} [get_ports {led[1]}]

## LED[2] - Mouth (ON during tag_reply / backscatter) - Pin E13
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports {led[2]}]

## LED[3] - Hardcoded OFF - Pin H15
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {led[3]}]


## ============================================================================
## RGB LED0 - Brain (state-dependent color from fs_detector)
##   Solid Blue:     S_IDLE
##   Blinking Blue:  S_DELIM / S_TARI (receiving)
##   Blinking Red:   S_RTCAL (processing)
##   Blinking Green: S_DONE  (success)
## ============================================================================

## RGB LED0 Red - Pin J15
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports led0_r]

## RGB LED0 Green - Pin G17
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports led0_g]

## RGB LED0 Blue - Pin F15
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports led0_b]


## ============================================================================
## RGB LED1 - Mode Indicator (LD1)
##   Smart Mode      (SW0=0): Solid Blue  - PLL + RTL health confirmed
##   Diagnostic Mode (SW0=1): Solid Red   - Manual test active
## ============================================================================

## RGB LED1 Red - Pin E15
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports led1_r]

## RGB LED1 Green - Pin F18 (always OFF)
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports led1_g]

## RGB LED1 Blue - Pin E14
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports led1_b]


## ============================================================================
## PMOD JB - Debug Outputs (Oscilloscope / Logic Analyzer)
## ============================================================================

## ila_fs (Frame Sync flag) - PMOD JB Pin 1, Pin N15
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports ila_fs]

## tx_debug (Tag backscatter data) - PMOD JA Pin 2, Pin L18
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports tx_debug]

## rx_debug removed from K16 - K16 is now used by diag_btn (physical BTN1).
## reader_cmd is visible via ILA (mark_debug) - no external pin needed.


## ============================================================================
## PMOD JB - brain_state[2:0] (fs_detector state monitor)
## ============================================================================

## brain_state[0] - PMOD JB Pin 4, Pin M16
set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS33} [get_ports {brain_state[0]}]

## brain_state[1] - PMOD JB Pin 7, Pin L15
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {brain_state[1]}]

## brain_state[2] - PMOD JB Pin 8, Pin L16
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {brain_state[2]}]


## ============================================================================
## PMOD JC - dbg_pulse_width[15:0] (pulse width measurement)
## Route to PMOD JC and JD for full 16-bit observation via ILA
## ============================================================================

## PMOD JC - dbg_pulse_width[7:0]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[0]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[1]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[2]}]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[3]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[4]}]
set_property -dict {PACKAGE_PIN P13 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[5]}]
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[6]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[7]}]

## PMOD JD - dbg_pulse_width[15:8]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[8]}]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[9]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[10]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[11]}]
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[12]}]
set_property -dict {PACKAGE_PIN T13 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[13]}]
set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[14]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {dbg_pulse_width[15]}]


## ============================================================================
## ILA Debug Hub Clock Constraints
## ---------------------------------
## dbg_hub MUST use 100 MHz (clk_in_IBUF_BUFG) for JTAG/programming stability.
## Using the 5 MHz PLL output causes the 98% programming hang.
## u_ila_0 uses 5 MHz to sample the core logic domain.
## ============================================================================
set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores -quiet dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false     [get_debug_cores -quiet dbg_hub]



## ============================================================================
## Bitstream Configuration
## ============================================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]







create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clock_gen/inst/clk_out1]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 4 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {cmd_state[0]} {cmd_state[1]} {cmd_state[2]} {cmd_state[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 16 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {dbg_pulse_width_OBUF[0]} {dbg_pulse_width_OBUF[1]} {dbg_pulse_width_OBUF[2]} {dbg_pulse_width_OBUF[3]} {dbg_pulse_width_OBUF[4]} {dbg_pulse_width_OBUF[5]} {dbg_pulse_width_OBUF[6]} {dbg_pulse_width_OBUF[7]} {dbg_pulse_width_OBUF[8]} {dbg_pulse_width_OBUF[9]} {dbg_pulse_width_OBUF[10]} {dbg_pulse_width_OBUF[11]} {dbg_pulse_width_OBUF[12]} {dbg_pulse_width_OBUF[13]} {dbg_pulse_width_OBUF[14]} {dbg_pulse_width_OBUF[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 4 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {active_state[0]} {active_state[1]} {active_state[2]} {active_state[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 16 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {tari_width[0]} {tari_width[1]} {tari_width[2]} {tari_width[3]} {tari_width[4]} {tari_width[5]} {tari_width[6]} {tari_width[7]} {tari_width[8]} {tari_width[9]} {tari_width[10]} {tari_width[11]} {tari_width[12]} {tari_width[13]} {tari_width[14]} {tari_width[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 3 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {brain_state_OBUF[0]} {brain_state_OBUF[1]} {brain_state_OBUF[2]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list ila_fs_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 1 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list locked]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 1 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list my_tag/pie_dec_clk]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 1 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list my_tag/pie_decoded_bit]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list rfid_filtered]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list my_tag/rx_1/fs_detector_1/rfid_in]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list tag_reply]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_5mhz]
