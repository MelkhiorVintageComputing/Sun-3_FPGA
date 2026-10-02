# Timing constraints for the Arrow DECA.  Copied from the Sun-2 project, less
# its display and SD card.
#
# Order matters: a set_clock_groups naming a clock that does not exist yet
# matches nothing and is dropped silently, so derive_pll_clocks comes first.

# ------------------------------------------------------------------ sources
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]

# The MII clocks come from the DP83620.  10 Mb/s (2.5 MHz) once configured,
# but it may autonegotiate 100 before that: constrain the tighter case.
create_clock -name net_tx_clk -period 40.000 [get_ports NET_TX_CLK]
create_clock -name net_rx_clk -period 40.000 [get_ports NET_RX_CLK]

# ------------------------------------------------------------------ derived
derive_pll_clocks -create_base_clocks

# Quartus adds no clock uncertainty unless asked (Vivado does by default).
derive_clock_uncertainty

# -------------------------------------------------------------- clock groups
# The two clkgen PLLs, the DDR3 controller's PLL, the oscillator and the PHY
# clocks are mutually unrelated: every crossing between them is a synchroniser
# or the adapter's toggle handshake.  clk50 is a group of its own (it clocks
# the console and the JTAG UART).
set_clock_groups -asynchronous \
    -group [get_clocks clk50] \
    -group [get_clocks net_tx_clk] \
    -group [get_clocks net_rx_clk] \
    -group [get_clocks {*clkgen*pll_a*}] \
    -group [get_clocks {*clkgen*pll_b*}] \
    -group [get_clocks {*ddr3*DDR3_PLL*}]

# ------------------------------------------------------------- false paths
# CRS and COL are asynchronous to both MII clocks (clause 22).
set_false_path -from [get_ports {NET_CRS NET_COL}]

# Buttons and switches: human-operated and synchronised in logic.
set_false_path -from [get_ports {KEY[*] SW[*]}]

# Outputs nothing samples on a clock: LEDs, headers, the PHY's reset and
# management pins.
set_false_path -to   [get_ports {LED[*] GPIO0_D[*] GPIO1_D[*]}]
# The HDMI pins sit idle without VIDEO=1; with it, deca_video.sdc constrains
# them instead (later constraints win).
set_false_path -to   [get_ports {HDMI_TX_D[*] HDMI_TX_CLK HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS HDMI_I2C_SCL HDMI_I2C_SDA}]
set_false_path -from [get_ports {HDMI_TX_INT HDMI_I2C_SCL HDMI_I2C_SDA}]
set_false_path -to   [get_ports {NET_RESET_n NET_PCF_EN NET_MDC}]
set_false_path -from [get_ports NET_MDIO]
set_false_path -to   [get_ports NET_MDIO]

# The micro-SD, in SPI mode: SD_CLK is a divided output of cpu_clk inside
# sd_spi, not a clock net, and MISO's only timing relation to us is the one
# blk_sd enforces in logic.
set_false_path -from [get_ports SD_MISO]
set_false_path -to   [get_ports {SD_CLK SD_CMD SD_CS_N SD_DAT1 SD_DAT2 SD_SEL \
                                 SD_CMD_DIR SD_D0_DIR SD_D123_DIR}]
