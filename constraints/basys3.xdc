##==============================================================================
## basys3.xdc
## Constraints file for the OV7670 + VGA video pipeline on the Basys 3 board.
##
## Camera Pmod pins match the table in the project handout:
##   P17 D0     N17 D1     M19 D2     M18 D3
##   L17 D4     K17 D5     C16 D6     B16 D7
##   A17 HREF   A16 PCLK   R18 PWDN   P18 RST
##   A14 SCL    A15 SDA    B15 VSYNC  C15 XCLK
##
## The VGA, clock, switches, pushbuttons, and LEDs use the official Digilent
## Basys 3 XDC pin assignments.
##==============================================================================

## ----------------------------------------------------------------------------
## Master clock (100 MHz)
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN W5 [get_ports clk_100m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100m]
create_clock -period 10.000 -name sys_clk [get_ports clk_100m]

## OV7670 PCLK is an INPUT clock to the FPGA.
## In QVGA mode with the scaling settings we use it runs ~12 MHz.
## Give the tool a conservative 40 ns period (25 MHz) so timing closes.
create_clock -period 40.000 -name ov_pclk [get_ports ov_pclk]
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks ov_pclk]

## ----------------------------------------------------------------------------
## Centre pushbutton (reset)
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN U18 [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]

## ----------------------------------------------------------------------------
## Slide switches sw[15:0]
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
set_property PACKAGE_PIN V16 [get_ports {sw[1]}]
set_property PACKAGE_PIN W16 [get_ports {sw[2]}]
set_property PACKAGE_PIN W17 [get_ports {sw[3]}]
set_property PACKAGE_PIN W15 [get_ports {sw[4]}]
set_property PACKAGE_PIN V15 [get_ports {sw[5]}]
set_property PACKAGE_PIN W14 [get_ports {sw[6]}]
set_property PACKAGE_PIN W13 [get_ports {sw[7]}]
set_property PACKAGE_PIN V2  [get_ports {sw[8]}]
set_property PACKAGE_PIN T3  [get_ports {sw[9]}]
set_property PACKAGE_PIN T2  [get_ports {sw[10]}]
set_property PACKAGE_PIN R3  [get_ports {sw[11]}]
set_property PACKAGE_PIN W2  [get_ports {sw[12]}]
set_property PACKAGE_PIN U1  [get_ports {sw[13]}]
set_property PACKAGE_PIN T1  [get_ports {sw[14]}]
set_property PACKAGE_PIN R2  [get_ports {sw[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

## ----------------------------------------------------------------------------
## LEDs led[15:0]
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property PACKAGE_PIN W18 [get_ports {led[4]}]
set_property PACKAGE_PIN U15 [get_ports {led[5]}]
set_property PACKAGE_PIN U14 [get_ports {led[6]}]
set_property PACKAGE_PIN V14 [get_ports {led[7]}]
set_property PACKAGE_PIN V13 [get_ports {led[8]}]
set_property PACKAGE_PIN V3  [get_ports {led[9]}]
set_property PACKAGE_PIN W3  [get_ports {led[10]}]
set_property PACKAGE_PIN U3  [get_ports {led[11]}]
set_property PACKAGE_PIN P3  [get_ports {led[12]}]
set_property PACKAGE_PIN N3  [get_ports {led[13]}]
set_property PACKAGE_PIN P1  [get_ports {led[14]}]
set_property PACKAGE_PIN L1  [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## ----------------------------------------------------------------------------
## VGA connector (4-4-4)
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN G19 [get_ports {vga_r[0]}]
set_property PACKAGE_PIN H19 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN J19 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN N19 [get_ports {vga_r[3]}]
set_property PACKAGE_PIN J17 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN H17 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN G17 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D17 [get_ports {vga_g[3]}]
set_property PACKAGE_PIN N18 [get_ports {vga_b[0]}]
set_property PACKAGE_PIN L18 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN K18 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN J18 [get_ports {vga_b[3]}]
set_property PACKAGE_PIN P19 [get_ports vga_hsync]
set_property PACKAGE_PIN R19 [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*] vga_g[*] vga_b[*] vga_hsync vga_vsync}]

## ----------------------------------------------------------------------------
## OV7670 camera pins (from project handout)
## Wire these to Pmod JA / JB / JC / JXADC according to how you break out the
## camera module. Pin NAMES below are the FPGA package pins specified in the
## rubric and so are board-pin agnostic - as long as your ribbon lands those
## FPGA balls, routing will be correct.
## ----------------------------------------------------------------------------
set_property PACKAGE_PIN P17 [get_ports {ov_data[0]}]
set_property PACKAGE_PIN N17 [get_ports {ov_data[1]}]
set_property PACKAGE_PIN M19 [get_ports {ov_data[2]}]
set_property PACKAGE_PIN M18 [get_ports {ov_data[3]}]
set_property PACKAGE_PIN L17 [get_ports {ov_data[4]}]
set_property PACKAGE_PIN K17 [get_ports {ov_data[5]}]
set_property PACKAGE_PIN C16 [get_ports {ov_data[6]}]
set_property PACKAGE_PIN B16 [get_ports {ov_data[7]}]
set_property PACKAGE_PIN A17 [get_ports ov_href]
set_property PACKAGE_PIN A16 [get_ports ov_pclk]
set_property PACKAGE_PIN R18 [get_ports ov_pwdn]
set_property PACKAGE_PIN P18 [get_ports ov_reset_n]
set_property PACKAGE_PIN A14 [get_ports ov_sioc]
set_property PACKAGE_PIN A15 [get_ports ov_siod]
set_property PACKAGE_PIN B15 [get_ports ov_vsync]
set_property PACKAGE_PIN C15 [get_ports ov_xclk]
set_property IOSTANDARD LVCMOS33 [get_ports {ov_data[*] ov_href ov_pclk ov_pwdn ov_reset_n ov_sioc ov_siod ov_vsync ov_xclk}]

## The SCCB lines are used as open-drain. Enable the internal pull-ups so the
## bus idles high even if external 4.7 k resistors are not fitted. For long
## cables external resistors are still recommended.
set_property PULLUP true [get_ports ov_sioc]
set_property PULLUP true [get_ports ov_siod]

## Improve camera-data-bus integrity: use fast slew on outputs, moderate
## drive on all camera IOs.
set_property DRIVE 12   [get_ports {ov_xclk ov_reset_n ov_pwdn}]
set_property SLEW FAST  [get_ports {ov_xclk}]

## ----------------------------------------------------------------------------
## Configuration bank voltage (Basys 3 default)
## ----------------------------------------------------------------------------
set_property CFGBVS VCCO       [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
