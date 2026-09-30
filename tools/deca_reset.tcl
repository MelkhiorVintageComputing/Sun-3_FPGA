# Read the DECA machine's In-System Sources and Probes, and optionally pulse
# its reset, over the USB-Blaster II.
#
#     syn/altera.sh quartus_stp -t tools/deca_reset.tcl          read
#     syn/altera.sh quartus_stp -t tools/deca_reset.tcl reset    pulse, then read
#     syn/altera.sh quartus_stp -t tools/deca_reset.tcl break    a 300 ms BREAK
#                                                                on ttya (abort)
#
# The DECA's only reset is a button, and configuring the FPGA tears down any
# JTAG console session, so: program, start tools/deca_console_pty.sh (or
# juart-terminal), and only then pulse the reset here to watch the boot from
# its first byte.  ISSP and the console share the chain: stop the console
# first.  Adapted from the Sun-2 project's tools/deca_reset.tcl; the probe
# layout is boards/DECA/deca_top.sv's (instance SUN3).
package require ::quartus::jtag
package require ::quartus::insystem_source_probe

proc b2i {s} { set v 0; foreach c [split $s ""] { set v [expr {$v*2 + ($c eq "1")}] }; return $v }

set hw [lindex [get_hardware_names] 0]
set dv [lindex [get_device_names -hardware_name $hw] 0]
set info [get_insystem_source_probe_instance_info -device_name $dv -hardware_name $hw]
set idx -1
foreach inst $info { if {[lindex $inst 3] eq "SUN3"} { set idx [lindex $inst 0] } }
if {$idx < 0} { puts "no SUN3 probe instance found; is this the DECA Sun-3 build?"; exit 1 }

start_insystem_source_probe -device_name $dv -hardware_name $hw
if {[lindex $argv 0] eq "reset"} {
    write_source_data -instance_index $idx -value 1 -value_in_hex
    after 50
    write_source_data -instance_index $idx -value 0 -value_in_hex
    puts "reset pulsed"
} elseif {[lindex $argv 0] eq "break"} {
    write_source_data -instance_index $idx -value 2 -value_in_hex
    after 300
    write_source_data -instance_index $idx -value 0 -value_in_hex
    puts "BREAK sent on ttya"
}
set raw [read_probe_data -instance_index $idx]
end_insystem_source_probe

# MSB first: bit 31 is character 0.
set rdcal   [b2i [string range $raw  0  7]]
set calpass [string index $raw  8]
set ready   [string index $raw  9]
set link    [string index $raw 10]
set present [string index $raw 11]
set cfgdone [string index $raw 12]
set speed   [b2i [string range $raw 13 14]]
set fd      [string index $raw 15]
set todbg   [b2i [string range $raw 16 23]]
set leds    [b2i [string range $raw 24 31]]

puts [format "DDR3   : ready=%s cal_pass=%s rdcal=0x%02x" $ready $calpass $rdcal]
puts [format "PHY    : present=%s cfg_done=%s link=%s speed=%s duplex=%s" \
        $present $cfgdone $link [expr {$speed == 0 ? "10" : ($speed == 1 ? "100" : "1000")}] \
        [expr {$fd eq "1" ? "full" : "half"}]]
puts [format "diag   : 0x%02x (as lit: 0x%02x)" $leds [expr {~$leds & 0xFF}]]
puts [format "todebug: 0x%02x" $todbg]
