# Non-project Vivado build for the Sun-3 on a QMTech Wukong.
#
#   vivado -mode batch -source syn/build.tcl \
#       -tclargs CPU_HZ CPU_DIV BOARD CPU ETH MEM_MIB ROMFILE ALLOW_PW OUTDIR FB
#
# Run through syn/Makefile, which owns the defaults and the output directory's
# name (passed in, not recomputed here, so the two cannot disagree).
#
# Nothing generated is committed: MIG comes from syn/mig/sun3_mig.prj via
# syn/generate_ip.tcl, and everything lands in build/.  The build fails on
# negative slack rather than quietly writing a bitstream that will not work.
#
# Adapted from the Sun-2 project's syn/build.tcl.

set here [file normalize [file dirname [info script]]]
set top  [file normalize $here/..]

source $here/boards.tcl

if {[llength $argv] != 10} {
    puts "ERROR: build.tcl wants 10 arguments (see its header), got [llength $argv]: $argv"
    exit 1
}
lassign $argv cpu_hz cpu_div board cpu eth mem_mib romfile allowpw outdir fb

# CPU_DIV names the MMCM divider directly and wins over CPU_HZ in
# wukong_clkgen.sv, so from here on cpu_hz is the clock that will exist -- it
# also goes to the TOD chip as SUN3_CPU_HZ, and must be right there.
if {$cpu_div != 0} {
    set cpu_hz [expr {1000000000 / $cpu_div}]
}

board_check $board
if {[board_vendor $board] ne "xilinx"} {
    puts "ERROR: BOARD=$board is not a Xilinx board; it is built by syn/quartus.tcl"
    exit 1
}
if {$cpu ne "suska" && $cpu ne "rd68021"} {
    puts "ERROR: CPU must be suska or rd68021, not '$cpu'"
    exit 1
}
if {![file exists $top/build/rom/$romfile]} {
    puts "ERROR: no PROM image build/rom/$romfile (make -C tools; patched ROMs exist for Rev 1.9 only)"
    exit 1
}

set part   [board_part $board]
set ipdir  $top/build/ip/$board
set migrtl $ipdir/sun3_mig/sun3_mig/user_design/rtl
set inputs $top/build/inputs

if {![file isdirectory $migrtl]} {
    puts "ERROR: MIG has not been generated. Run: make -C syn ip BOARD=$board"
    exit 1
}

file mkdir $outdir

# ---------------------------------------------------------------------------
# Defines: every build option, as sun3_config.vh names it
# ---------------------------------------------------------------------------
# The PROM goes in under a fixed name in the output directory: Vivado's
# -verilog_define does not pass a quoted string through intact (the quotes
# arrive backslashed and `include rejects them).
file copy -force $top/build/rom/$romfile $outdir/bootrom_selected_32bits.vh
set defines [list \
    SUN3_CPU_HZ=$cpu_hz \
    SUN3_MEM_MIB=$mem_mib \
    SUN3_BOOTROM_SELECTED ]
if {$cpu eq "rd68021"} { lappend defines SUN3_CPU_RD68021 }
if {$eth == 1}         { lappend defines SUN3_ETH_WISH7990 }
if {$fb == 0}          { lappend defines SUN3_NO_FB }

puts "== Sun-3 for Wukong $board ($part), CPU $cpu at $cpu_hz Hz, $mem_mib MiB, PROM $romfile, ETH=$eth, FB=$fb =="
puts "== output: $outdir =="

# The part before anything is read: read_ip validates against the current part,
# which in non-project mode defaults to something else entirely.
set_part $part

# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
if {$cpu eq "rd68021"} {
    set rd $inputs/RD68021/rtl
    read_verilog -sv [list \
        $rd/rd68021_pkg.sv \
        $rd/gen/rd68021_frame_pkg.sv \
        $rd/gen/rd68021_ucode_pkg.sv \
        $rd/gen/rd68021_cpdec_rom.sv \
        $rd/gen/rd68021_decode_rom.sv \
        $rd/gen/rd68021_eadec_rom.sv \
        $rd/gen/rd68021_eamode_rom.sv \
        $rd/gen/rd68021_ucode_rom.sv \
        $rd/rd68021_sync.sv \
        $rd/rd68021_dedge_ff.sv \
        $rd/rd68021_shifter.sv \
        $rd/rd68021_divider.sv \
        $rd/rd68021_bitfield.sv \
        $rd/rd68021_biu.sv \
        $rd/rd68021_icache.sv \
        $rd/rd68021_ifu.sv \
        $rd/rd68021_seq.sv \
        $rd/rd68021_top.sv ]
} else {
    # VHDL-2008: the core connects `buffer' formals to `out' actuals.  Of the
    # two ALU files (one entity), alu_new, as the old build used.
    set sk $inputs/Suska_Configware/68K30L
    read_vhdl -vhdl2008 [list \
        $sk/wf68k30L_pkg.vhd \
        $sk/wf68k30L_address_registers.vhd \
        $sk/wf68k30L_alu_new.vhd \
        $sk/wf68k30L_bus_interface.vhd \
        $sk/wf68k30L_control.vhd \
        $sk/wf68k30L_data_registers.vhd \
        $sk/wf68k30L_exception_handler.vhd \
        $sk/wf68k30L_opcode_decoder.vhd \
        $sk/wf68k30L_top.vhd ]
}

# The machine: plain Verilog.
read_verilog [list \
    $top/rtl/sun3/sun3_top.v \
    $top/rtl/sun3/sun3_fpga.v \
    $top/rtl/sun3/sun3_mmu.v \
    $top/rtl/sun3/ctx_reg_sun3.v \
    $top/rtl/sun3/smap.v \
    $top/rtl/sun3/pmap.v \
    $top/rtl/sun3/sram_sync.v \
    $top/rtl/sun3/idprom_sun3.v \
    $top/rtl/sun3/gen8bit_reg.v \
    $top/rtl/sun3/cyctr32bit_reg.v \
    $top/rtl/sun3/bootrom32.v \
    $top/rtl/sun3/icm7170.v \
    $top/rtl/sun3/eeprom.v \
    $top/rtl/sun3/sun3_irq_priority.v \
    $top/rtl/sun3/sun3_wishbone_bridge.v \
    $top/rtl/sun3/fault_log.v \
    $top/rtl/sun3/bus_trace.v \
    $top/rtl/sun3/wish7990_sun3_regs.v \
    $top/rtl/sun3/wish7990_dvma_to_020.v ]

set sv [list \
    $inputs/z8530_scc/z8530_scc.sv \
    $top/rtl/sun3/reset_sync.sv \
    $top/boards/Wukong/wukong_clkgen.sv \
    $top/boards/Wukong/wb_to_mig_ui.sv \
    $top/boards/Wukong/mig_arb.sv \
    $top/boards/Wukong/wukong_top.sv ]
if {$eth == 1} {
    set w $inputs/Wish7990/src
    lappend sv \
        $w/wish7990_pkg.sv $w/crc32_eth.sv $w/sync_fifo.sv $w/async_fifo.sv \
        $w/dp_ram.sv $w/mii_rx.sv $w/mii_tx.sv $w/wb_master.sv $w/wb_arb.sv \
        $w/le_regs.sv $w/le_init.sv $w/le_tx.sv $w/le_filt.sv $w/le_rx.sv \
        $w/wish7990.sv $w/wb_mdio.sv \
        $top/boards/Wukong/phy_rtl8211_init.sv
}
read_verilog -sv $sv

# MIG, as generated, synthesised out of context so synth_design can link it.
read_ip $ipdir/sun3_mig/sun3_mig.xci
if {[llength [get_ips sun3_mig]] == 0} {
    puts "ERROR: sun3_mig.xci did not load"
    exit 1
}
synth_ip [get_ips sun3_mig]

# Revision file first: a clock has to exist before anything names it.
read_xdc $here/wukong_$board.xdc
read_xdc $here/wukong_common.xdc
if {$eth == 1} {
    read_xdc $here/wukong_eth.xdc
    puts "== read wukong_eth.xdc =="
}
read_xdc $here/wukong_wbcdc.xdc

# ---------------------------------------------------------------------------
# Synthesis and implementation
# ---------------------------------------------------------------------------
# What the knobs resolved to, in the log: a define that is not passed builds a
# clean bitstream with a whole subsystem missing.
puts "== defines: $defines =="

# An undeclared identifier is an error, not a one-bit undriven wire: that is
# how the Sun-2's frame buffer reached the board dead.
set_msg_config -id {Synth 8-6901} -new_severity ERROR

synth_design -top wukong_top -part $part \
    -include_dirs [list $outdir $top/rtl/sun3 $top/build/rom] \
    -verilog_define $defines \
    -generic CPU_CLK_HZ=$cpu_hz \
    -generic CPU_DIV=$cpu_div

write_checkpoint -force $outdir/post_synth.dcp
report_utilization -file $outdir/post_synth_utilization.rpt
report_clocks      -file $outdir/clocks.rpt

# The feature knobs have to reach the netlist, not just the command line.
if {$eth == 1 && [llength [get_cells -quiet -hier -filter {NAME =~ *mdio_station*}]] == 0} {
    puts "ERROR: ETH=1 but the netlist has no MDIO station: SUN3_ETH_WISH7990 did not reach the RTL"
    exit 1
}
if {[llength [get_cells -quiet -hier -filter {NAME =~ *adapter/req_tgl_reg*}]] == 0} {
    puts "ERROR: adapter/req_tgl_reg matches no cell: wukong_wbcdc.xdc constrains nothing"
    exit 1
}

opt_design
place_design -directive Explore
phys_opt_design
route_design -directive Explore

write_checkpoint -force $outdir/post_route.dcp
report_utilization    -file $outdir/utilization.rpt
report_timing_summary -file $outdir/timing.rpt
# Which exceptions another overrode (set_clock_groups outranks set_max_delay).
report_exceptions -ignored -file $outdir/exceptions_ignored.rpt
report_cdc            -file $outdir/cdc.rpt
report_drc            -file $outdir/drc.rpt

# ---------------------------------------------------------------------------
# Only write a bitstream if it would actually work
# ---------------------------------------------------------------------------
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "== worst setup slack $wns ns, worst hold slack $whs ns =="

# Setup and hold are not the whole of timing: a clock faster than the buffer
# carrying it shows up only as a pulse width violation.
set pwbad {}
foreach line [split [report_pulse_width -all_violators -return_string] "\n"] {
    if {[regexp {^\s*(Min Period|Max Period|Low Pulse Width|High Pulse Width|Max Skew)\s} $line] &&
        [regexp {\s(-\d+\.\d+)\s} $line -> sl]} {
        lappend pwbad [string trim $line]
    }
}
if {[llength $pwbad]} {
    if {$allowpw == 1} {
        puts "== pulse width / period violations, ALLOWED by ALLOW_PW=1 =="
        foreach l $pwbad { puts "     $l" }
    } else {
        puts "ERROR: pulse width / period violations:"
        foreach l $pwbad { puts "         $l" }
        exit 1
    }
}

if {$wns < 0 || $whs < 0} {
    puts "ERROR: timing not met (WNS $wns, WHS $whs); see $outdir/timing.rpt"
    exit 1
}

write_bitstream -force -bin_file $outdir/sun3_wukong_$board.bit
puts "== wrote $outdir/sun3_wukong_$board.bit (and .bin) =="
