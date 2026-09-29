# Board constraints shared by every QMTech Wukong revision.
#
# From the Sun-2 project.  The handful of pins that differ between revisions
# live in wukong_v1.xdc and wukong_v3.xdc; syn/build.tcl reads the revision file first and then this one.
# That order matters: a clock has to exist before anything names it.  Everything here is common because the two boards genuinely agree:
# DDR3, Ethernet, the serial console and the PMOD are on identical balls,
# verified against QMTech's own DDR3.ucf and GMII reference design for each.
#
# Board pins only.  The DDR3 pins are NOT here: MIG emits them from
# syn/mig/sun3_mig.prj, and hand-copying them is how two sources drift apart.
# The old LiteX XDC shows exactly that failure -- it constrains ddram_cs_n to
# E22, a pin the V1 schematic shows is connected to nothing.

set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Loading from the SPI configuration flash.  Every revision has a Micron part
# there -- N25Q064A on the V3, MT25QL128 on the V1 -- and both take the Quad
# Output Fast Read (6Bh) that a x4 bus width issues, with no quad-enable bit to
# set first.  Without these the FPGA reads a 3.8 MB bitstream one bit at a time
# at its ~3 MHz default CCLK, which is about ten seconds from power to a
# running machine; x4 at 33 MHz plus compression makes it a small fraction of
# one.  33 MHz is well inside both parts' read ratings.  Compression also makes
# JTAG programming quicker, and changes nothing about the design.
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4  [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE   33 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS    TRUE [current_design]

# ---------------------------------------------------------------------------
# Clocks
# ---------------------------------------------------------------------------
# The oscillator is 50 MHz on every revision; only the ball it lands on differs,
# and that is in the revision file, which is read first.
create_clock -name clk50 -period 20.000 [get_ports clk50]

# ---------------------------------------------------------------------------
# Serial console (ttya)
# ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports serial_tx]
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS33} [get_ports serial_rx]

# ---------------------------------------------------------------------------
# LEDs
# ---------------------------------------------------------------------------
# The on-board LEDs and the buttons are in the revision file.
#
# The Sun-3 diagnostic register, on PMOD J10 (as the old LiteX build and the
# Sun-2 have it).  Identical on V1 and V3.
set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[0]}]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[1]}]
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[2]}]
set_property -dict {PACKAGE_PIN G5 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[3]}]
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[4]}]
set_property -dict {PACKAGE_PIN G7 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[5]}]
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[6]}]
set_property -dict {PACKAGE_PIN G8 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[7]}]

# The second LED header, carrying sun3_fpga.v's todebug (a count of PROM
# accesses).  Pins from Old/qmtech_wukong_V1_0.xdc (extra_leds0).
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVCMOS33} [get_ports {extra_leds0[0]}]
set_property -dict {PACKAGE_PIN H4 IOSTANDARD LVCMOS33} [get_ports {extra_leds0[1]}]
set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS33} [get_ports {extra_leds0[2]}]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports {extra_leds0[3]}]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports {extra_leds0[4]}]
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {extra_leds0[5]}]
set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS33} [get_ports {extra_leds0[6]}]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {extra_leds0[7]}]

# ---------------------------------------------------------------------------
# Clock domains
# ---------------------------------------------------------------------------
# Everything derives from clk50, so Vivado would otherwise time paths between
# the CPU, serial and DRAM user-interface domains as if they were related.
# They are not: the crossings that exist are wb_to_mig_ui's handshake, the
# SCCs' own synchronisers and reset_sync.
#
# NOTE (from the Sun-2 project): set_clock_groups outranks set_max_delay, so the
# bounds in wukong_wbcdc.xdc are reported as overridden and constrain nothing.
# build.tcl writes exceptions_ignored.rpt so this stays visible.
set cpu_clk    [get_clocks -of_objects [get_pins clkgen/mmcm_a/CLKOUT1]]
set serial_clk [get_clocks -of_objects [get_pins clkgen/mmcm_b/CLKOUT0]]
set mig_clk    [get_clocks -of_objects [get_pins clkgen/mmcm_a/CLKOUT0]]

# clk50 is in here too: the reset assembly and the hold counter run on it.
set_clock_groups -asynchronous \
    -group [get_clocks clk50] \
    -group $cpu_clk \
    -group $serial_clk \
    -group [get_clocks -include_generated_clocks $mig_clk]

# The PHY's MII clocks, and the Ethernet pins, are in wukong_eth.xdc, which
# build.tcl reads only with ETH=1: an XDC cannot say `if', and constraints on
# ports that do not exist are dropped with a warning.
