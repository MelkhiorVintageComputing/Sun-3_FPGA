# The bw2 on HDMI (VIDEO=1).  Read by syn/build.tcl only with the knob: the
# tmds_* ports and the pixel clocks exist only then, and constraints on
# objects that do not exist are dropped with a warning.  From the Sun-2
# project's wukong_hdmi.xdc and the HDMI pins of its wukong_common.xdc.
#
# Pins from QMTech's HDMI reference design (Test06_HDMI_OUT), bank 35, the
# same four pairs on V1 and V3.
set_property -dict {PACKAGE_PIN D4 IOSTANDARD TMDS_33} [get_ports tmds_clk_p]
set_property -dict {PACKAGE_PIN C4 IOSTANDARD TMDS_33} [get_ports tmds_clk_n]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD TMDS_33} [get_ports {tmds_p[0]}]
set_property -dict {PACKAGE_PIN D1 IOSTANDARD TMDS_33} [get_ports {tmds_n[0]}]
set_property -dict {PACKAGE_PIN F2 IOSTANDARD TMDS_33} [get_ports {tmds_p[1]}]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD TMDS_33} [get_ports {tmds_n[1]}]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD TMDS_33} [get_ports {tmds_p[2]}]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD TMDS_33} [get_ports {tmds_n[2]}]

# The pixel clock and its 5x partner are related to each other and to nothing
# else.  fb_scanout's line buffer is written on MIG's ui_clk and read on the
# pixel clock, and its two toggles cross the same way, through two-flop
# synchronisers (the vertical blanking to V_INT too, synchronised in
# sun3_fpga).
set_clock_groups -asynchronous -group [get_clocks {mmcm_pixel mmcm_x5}]
