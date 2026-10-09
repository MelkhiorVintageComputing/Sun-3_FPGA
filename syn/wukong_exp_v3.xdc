# The Wukong-Sun expansion board (boards/Wukong/Wukong-Sun) on a QMTech
# Wukong V3's 40-pin header J12.  Read only with EXP=1 (SUN3_EXPBOARD);
# without it the diag register goes to PMOD J10 (syn/wukong_diag_pmod.xdc).
#
# The V3 brings a different set of bank-13 balls to the same header pins
# (V3 schematic and hardware manual, J12: pin 1 GND, 2 VIN, 3 U14, 4 V14,
# ... 35 U25, 36 U26; 37-38 GND, 39-40 VCCO_13), so the expansion board's
# labels, which name V1 balls, do not apply here: each line gives the header
# pin and the board's net instead.  Bank 13 is 3.3 V.
#
# The board's SN74LV1T125 buffers (keyboard and mouse) do not invert, so
# wukong_top inverts those four lines itself, as a 3/60's 74ALS04 does: the
# ports carry the connector's polarity.  The LEDs are lit by a high level
# (anode to the FPGA through 680R).

# Keyboard and mouse (the second Z8530: channel A keyboard, channel B mouse),
# to the Mini-DIN 8 J2.
set_property -dict {PACKAGE_PIN V18  IOSTANDARD LVCMOS33} [get_ports kbd_tx]   ;# J12.9  KBD_TX   -> U1 -> J2.5
set_property -dict {PACKAGE_PIN T20  IOSTANDARD LVCMOS33} [get_ports kbd_rx]   ;# J12.13 KBD_RX   <- U5 <- J2.6
set_property -dict {PACKAGE_PIN V19  IOSTANDARD LVCMOS33} [get_ports mouse_rx] ;# J12.11 MOUSE_RX <- U3 <- J2.4
set_property -dict {PACKAGE_PIN W19  IOSTANDARD LVCMOS33} [get_ports mouse_tx] ;# J12.12 MOUSE_TX -> U4 -> J2.7

# ttyb (the console Z8530's channel B), through the board's CH340N to USB.
# The net names are the CH340N's: its RXD is what the FPGA sends.
set_property -dict {PACKAGE_PIN AA24 IOSTANDARD LVCMOS33} [get_ports ttyb_tx]  ;# J12.23 SERIAL0_RXD
set_property -dict {PACKAGE_PIN V24  IOSTANDARD LVCMOS33} [get_ports ttyb_rx]  ;# J12.25 SERIAL0_TXD

# The Sun's diag register, bit n on LEDn.
set_property -dict {PACKAGE_PIN Y26  IOSTANDARD LVCMOS33} [get_ports {diag_leds0[0]}] ;# J12.32 LED0
set_property -dict {PACKAGE_PIN AA25 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[1]}] ;# J12.30 LED1
set_property -dict {PACKAGE_PIN AC26 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[2]}] ;# J12.28 LED2
set_property -dict {PACKAGE_PIN W24  IOSTANDARD LVCMOS33} [get_ports {diag_leds0[3]}] ;# J12.26 LED3
set_property -dict {PACKAGE_PIN AB25 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[4]}] ;# J12.24 LED4
set_property -dict {PACKAGE_PIN AC24 IOSTANDARD LVCMOS33} [get_ports {diag_leds0[5]}] ;# J12.22 LED5
set_property -dict {PACKAGE_PIN W23  IOSTANDARD LVCMOS33} [get_ports {diag_leds0[6]}] ;# J12.20 LED6
set_property -dict {PACKAGE_PIN V22  IOSTANDARD LVCMOS33} [get_ports {diag_leds0[7]}] ;# J12.18 LED7

# The board's 54 MHz oscillator (X1 through R1) reaches J12.15, W21 =
# IO_L14P_T2_SRCC_13: the P side of a clock-capable pair, so it can drive a
# BUFG or an MMCM with dedicated routing.  Nothing uses it yet; when a clk54
# port exists:
#   set_property -dict {PACKAGE_PIN W21 IOSTANDARD LVCMOS33} [get_ports clk54]
#   create_clock -name clk54 -period 18.519 [get_ports clk54]

# The expansion board's micro-SD slot.  On a V3 the disk is in the board's own
# slot J9 (syn/wukong_sd_v3.xdc); this one would be a second card, which
# nothing drives yet.  Its balls, SPI mode as in wukong_exp_sd_v1.xdc:
#   CLK  J12.34 W26    CMD (MOSI) J12.33 V26    DAT0 (MISO) J12.35 U25
#   DAT3 (/CS) J12.31 W25    DAT1 J12.36 U26    DAT2 J12.29 Y25
