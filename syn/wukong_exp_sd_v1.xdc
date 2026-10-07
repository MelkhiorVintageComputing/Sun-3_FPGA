# The disk's micro-SD on a QMTech Wukong V1: the Wukong-Sun expansion
# board's slot P1, on the 40-pin header J12.  Read with EXP=1 SCSI=1 on a V1,
# which has no slot of its own (a V3 uses its J9: syn/wukong_sd_v3.xdc).
# Header pins as in syn/wukong_exp_v1.xdc.
#
# SPI mode uses four of the six lines: CLK, CMD as MOSI, DAT0 as MISO and DAT3
# as /CS.  As on the V3's slot, CMD and DAT0-DAT3 have 4.7k pull-ups to 3.3 V
# on the board (R12-R16, Wukong-Sun cfed966), so an idle card stays in SD mode
# until CMD0 arrives with /CS low.  DAT1 (J12.36, U19) and DAT2 (J12.29, U22)
# are left alone.  There is no card detect.

set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33}             [get_ports sd_clk]  ;# J12.34 SD_CLK
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33}             [get_ports sd_cmd]  ;# J12.33 SD_CMD
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33}             [get_ports sd_dat0] ;# J12.35 SD_D0
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33}             [get_ports sd_dat3] ;# J12.31 SD_D3

# As in wukong_sd_v3.xdc: the card is clocked from a divider off cpu_clk, and
# sd_dat0 is sampled half a bit period after the edge that drove sd_clk -- an
# asynchronous input as far as the tools are concerned.
set_false_path -from [get_ports sd_dat0]
