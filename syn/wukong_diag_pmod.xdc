# The Sun-3 diagnostic register on PMOD J10, for a Wukong without the
# Wukong-Sun expansion board (EXP=0; with it, the board's own LEDs take the
# register: syn/wukong_exp_v1.xdc, _v3.xdc).  Moved out of wukong_common.xdc,
# which every build reads, for that reason.
#
# As the old LiteX build and the Sun-2 have it.  Identical on V1 and V3.
set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[0]}]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[1]}]
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[2]}]
set_property -dict {PACKAGE_PIN G5 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[3]}]
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[4]}]
set_property -dict {PACKAGE_PIN G7 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[5]}]
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[6]}]
set_property -dict {PACKAGE_PIN G8 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[7]}]

