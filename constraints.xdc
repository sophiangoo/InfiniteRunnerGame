# XDC Constraints File for Infinite Runner Game

# Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# Reset 
set_property -dict { PACKAGE_PIN W19   IOSTANDARD LVCMOS33 } [get_ports reset]

# Game Control Buttons
# Left Button 
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports btn_left]

# Right Button 
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports btn_right]

# Center Button - Start game
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports btn_center]

# 7-Segment Display Segments 
set_property -dict { PACKAGE_PIN W7   IOSTANDARD LVCMOS33 } [get_ports {segments[0]}]
set_property -dict { PACKAGE_PIN W6   IOSTANDARD LVCMOS33 } [get_ports {segments[1]}]
set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS33 } [get_ports {segments[2]}]
set_property -dict { PACKAGE_PIN V8   IOSTANDARD LVCMOS33 } [get_ports {segments[3]}]
set_property -dict { PACKAGE_PIN U5   IOSTANDARD LVCMOS33 } [get_ports {segments[4]}]
set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports {segments[5]}]
set_property -dict { PACKAGE_PIN U7   IOSTANDARD LVCMOS33 } [get_ports {segments[6]}]

# 7-Segment Display Digit Enables 
set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports {digit_enable[0]}]
set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports {digit_enable[1]}]
set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports {digit_enable[2]}]
set_property -dict { PACKAGE_PIN W4   IOSTANDARD LVCMOS33 } [get_ports {digit_enable[3]}]

# Configuration options
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

