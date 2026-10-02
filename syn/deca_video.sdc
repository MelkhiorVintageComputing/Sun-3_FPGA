# The bw2 on the ADV7513 (VIDEO=1), read by syn/quartus.tcl after deca.sdc
# only with the knob: its pixel PLL exists only then.  From the Sun-2
# project's deca.sdc.

# The pixel clock (deca_vidclk, 108.000 MHz) is asynchronous to everything:
# fb_scanout's line buffer and toggles, and the vertical blanking into V_INT,
# all cross through block RAM or two-flop synchronisers.
set_clock_groups -asynchronous -group [get_clocks {*vidclk*pll_v*}]

# The pixel bus is source-synchronous at 108 MHz (deca_hdmi_out registers it
# on one edge and sends the clock inverted), so it is constrained as one: the
# ADV7513's setup and hold against a clock half a period later.
set_output_delay -clock [get_clocks {*vidclk*pll_v*}] -max -7.500 \
    [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]
set_output_delay -clock [get_clocks {*vidclk*pll_v*}] -min -3.800 \
    [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]
set_false_path -to   [get_ports {HDMI_TX_CLK HDMI_I2C_SCL HDMI_I2C_SDA}]
set_false_path -from [get_ports {HDMI_I2C_SDA HDMI_TX_INT}]
