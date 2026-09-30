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
set_false_path -to   [get_ports {NET_RESET_n NET_PCF_EN NET_MDC}]
set_false_path -from [get_ports NET_MDIO]
set_false_path -to   [get_ports NET_MDIO]
