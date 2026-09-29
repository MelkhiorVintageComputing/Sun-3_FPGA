# The Ethernet: an RTL8211EG run as 10/100 MII for the Wish7990.  Read by
# syn/build.tcl only with ETH=1, after wukong_common.xdc.  From the Sun-2
# project's wukong_common.xdc.

# The PHY-sourced MII clocks.  Both land on clock-capable balls (M2 and P4 are
# SRCC).  400 ns is 2.5 MHz, the MII rate at 10 Mb/s -- the PHY is brought up
# advertising 10BASE-T only (phy_rtl8211_init).
create_clock -name phy_tx_clk -period 400.000 [get_ports phy_mii_tx_clk]
create_clock -name phy_rx_clk -period 400.000 [get_ports phy_mii_rx_clk]

# Asynchronous to everything else.  A single -group means "to all other
# clocks", so this does not have to name the ones wukong_common.xdc grouped.
set_clock_groups -asynchronous -group [get_clocks phy_tx_clk]
set_clock_groups -asynchronous -group [get_clocks phy_rx_clk]

# ---------------------------------------------------------------------------
# Ethernet -- RTL8211EG, bank 34.  Identical on V1 and V3.
# ---------------------------------------------------------------------------
# Bank 34 carries nothing but Ethernet and is fixed at 3.3 V.  Pins are from
# QMTech's own GMII reference design (Software/Test08_GMII_Ethernet.zip), which
# is the authoritative pinout for this board, cross-checked against the
# schematic and the LiteX platform file.  The V3's own GMII reference design
# gives the same eighteen pins, so this section serves both.
#
# Only the low four data bits are used: the PHY presents a 4-bit MII at 10 and
# 100 Mb/s and sources both clocks itself.  TXD7:4 (K1 K2 L2 M1) are left
# unconstrained and undriven.
#
# CAUTION.  Seven of these balls are PHY configuration straps, latched when the
# PHY's reset releases: L3 (PHY_AD2), U5 (AN1), R3 (SELRGV), T3 (TXDLY),
# T4 (RXDLY), T5 (AN0) and U4 (Mode).  They are inputs and must stay inputs,
# with no PULLUP/PULLDOWN/KEEPER property -- the board already pulls each to the
# level it wants.  Driving L3 or U4 changes the PHY's address, or puts the part
# into RGMII mode where nothing works in a way that resembles a MAC fault.
set_property -dict {PACKAGE_PIN M2 IOSTANDARD LVCMOS33} [get_ports phy_mii_tx_clk]
set_property -dict {PACKAGE_PIN P4 IOSTANDARD LVCMOS33} [get_ports phy_mii_rx_clk]

set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {phy_mii_txd[0]}]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports {phy_mii_txd[1]}]
set_property -dict {PACKAGE_PIN N2 IOSTANDARD LVCMOS33} [get_ports {phy_mii_txd[2]}]
set_property -dict {PACKAGE_PIN N1 IOSTANDARD LVCMOS33} [get_ports {phy_mii_txd[3]}]
set_property -dict {PACKAGE_PIN T2 IOSTANDARD LVCMOS33} [get_ports phy_mii_tx_en]
set_property -dict {PACKAGE_PIN J1 IOSTANDARD LVCMOS33} [get_ports phy_mii_tx_er]

set_property -dict {PACKAGE_PIN M4 IOSTANDARD LVCMOS33} [get_ports {phy_mii_rxd[0]}]
set_property -dict {PACKAGE_PIN N3 IOSTANDARD LVCMOS33} [get_ports {phy_mii_rxd[1]}]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD LVCMOS33} [get_ports {phy_mii_rxd[2]}]
set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports {phy_mii_rxd[3]}]
set_property -dict {PACKAGE_PIN L3 IOSTANDARD LVCMOS33} [get_ports phy_mii_rx_dv]
set_property -dict {PACKAGE_PIN U5 IOSTANDARD LVCMOS33} [get_ports phy_mii_rx_er]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33} [get_ports phy_mii_crs]
set_property -dict {PACKAGE_PIN U4 IOSTANDARD LVCMOS33} [get_ports phy_mii_col]

set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33} [get_ports phy_gtx_clk]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports phy_reset_n]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports phy_mdc]
set_property -dict {PACKAGE_PIN H1 IOSTANDARD LVCMOS33} [get_ports phy_mdio]

# The two PHY clocks are created near the top, with clk50 -- see the note there.

# MII clause 22.3.2 setup/hold, with vast margin at 2.5 MHz.
set_input_delay  -clock phy_rx_clk -max 10.000 [get_ports {phy_mii_rxd[*] phy_mii_rx_dv phy_mii_rx_er}]
set_input_delay  -clock phy_rx_clk -min  0.000 [get_ports {phy_mii_rxd[*] phy_mii_rx_dv phy_mii_rx_er}]
set_output_delay -clock phy_tx_clk -max 25.000 [get_ports {phy_mii_txd[*] phy_mii_tx_en phy_mii_tx_er}]
set_output_delay -clock phy_tx_clk -min  0.000 [get_ports {phy_mii_txd[*] phy_mii_tx_en phy_mii_tx_er}]

# CRS and COL are asynchronous to both MII clocks by the standard (clause
# 22.2.2.11/12); the MAC synchronises them into the transmit domain, so
# the pins themselves carry no timing requirement.
set_false_path -from [get_ports {phy_mii_crs phy_mii_col}]

# The PHY reset and the tied-off gigabit clock are static.
set_false_path -to [get_ports {phy_reset_n phy_gtx_clk}]

# Management runs at 125 kHz against a 2.5 MHz ceiling, from the CPU clock, so
# there is nothing to time here that the CPU domain does not already cover.
set_false_path -to   [get_ports {phy_mdc phy_mdio}]
set_false_path -from [get_ports phy_mdio]
