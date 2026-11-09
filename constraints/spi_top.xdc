## 12 MHz clock
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports { i_Clk }];
create_clock -add -name sys_clk -period 83.333 -waveform {0 41.667} [get_ports { i_Clk }];

## Button BTN0 (reset)
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports { i_Btn0 }];

## LEDs LD2 to LD5
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports { o_Led[0] }];
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports { o_Led[1] }];
set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 } [get_ports { o_Led[2] }];
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { o_Led[3] }];

## SPI on Pmod JA, top row
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports { o_SPI_CS_n }];
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports { o_SPI_MOSI }];
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { i_SPI_MISO }];
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { o_SPI_Clk }];

## Logic analyzer test points on Pmod JA, bottom row
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports { o_Dbg_MISO }];
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { o_Dbg_MOSI }];