# Non-project Vivado build for the Sun-3 on a QMTech Wukong.
#
#   vivado -mode batch -source syn/build.tcl \
#       -tclargs CPU_HZ CPU_DIV BOARD CPU ETH MEM_MIB ROMFILE ALLOW_PW OUTDIR FB \
#                SCSI DISK_OFF_MIB WB_FIFO WB_CACHE WB_CACHE_IDX VIDEO FB_CONSOLE FPU FPU_WAIT FPU_MODEL
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

if {[llength $argv] != 20} {
    puts "ERROR: build.tcl wants 20 arguments (see its header), got [llength $argv]: $argv"
    exit 1
}
lassign $argv cpu_hz cpu_div board cpu eth mem_mib romfile allowpw outdir fb scsi disk_off_mib wb_fifo wb_cache wb_cache_idx video fb_console fpu fpu_wait fpu_model

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
if {$scsi == 1} {
    # The disk is the micro-SD slot, which only the V3 has.
    if {![file exists $here/wukong_sd_$board.xdc]} {
        puts "ERROR: SCSI=1 needs a micro-SD slot; BOARD=$board has none (V3 only)"
        exit 1
    }
    lappend defines SUN3_SCSI
}
if {$fb == 0}          { lappend defines SUN3_NO_FB }
# The bw2 on the board's HDMI connector (needs its memory, FB=1).
if {$video == 1} {
    if {$fb != 1} {
        puts "ERROR: VIDEO=1 needs FB=1: the screen shows the bw2's memory"
        exit 1
    }
    lappend defines SUN3_VIDEO
}
# The MC68881 (RD68884), or the MC68882 (RD68885, FPU_MODEL=68882), next to
# the RD68021, at CpID 1.
if {$fpu == 1} {
    if {$cpu ne "rd68021"} {
        puts "ERROR: FPU=1 needs CPU=rd68021 (its coprocessor interface)"
        exit 1
    }
    if {$fpu_model != 68881 && $fpu_model != 68882} {
        puts "ERROR: FPU_MODEL is 68881 or 68882, not $fpu_model"
        exit 1
    }
    lappend defines SUN3_FPU SUN3_FPU_WAIT=$fpu_wait SUN3_FPU_MODEL=$fpu_model
}
if {$fb_console == 1} {
    if {$video != 1} {
        puts "ERROR: FB_CONSOLE=1 needs VIDEO=1: a console nobody can see"
        exit 1
    }
    lappend defines SUN3_FB_CONSOLE
}
# The FIFO bridge: its Wishbone side on MIG's ui_clk, wb_mig_sync in place of
# wb_to_mig_ui.
if {$wb_fifo == 1}     { lappend defines SUN3_WB_FIFO }
# The read cache in front of the FIFO bridge, which it needs.
if {$wb_cache == 1} {
    if {$wb_fifo != 1} {
        puts "ERROR: WB_CACHE=1 needs WB_FIFO=1: the cache sits in front of the FIFO bridge"
        exit 1
    }
    lappend defines SUN3_WB_CACHE SUN3_WB_CACHE_IDX=$wb_cache_idx
}

puts "== Sun-3 for Wukong $board ($part), CPU $cpu at $cpu_hz Hz, $mem_mib MiB, PROM $romfile, ETH=$eth, FB=$fb, WB_FIFO=$wb_fifo, WB_CACHE=$wb_cache (IDX $wb_cache_idx), VIDEO=$video, FB_CONSOLE=$fb_console, FPU=$fpu (wait $fpu_wait, model $fpu_model) =="
if {$scsi == 1} {
    puts "== SCSI disk at $disk_off_mib MiB on the micro-SD ([expr {$disk_off_mib * 2048}] sectors) =="
}
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
    if {$fpu == 1} {
        set fp $inputs/RD68884/rtl
        read_verilog -sv [list \
            $fp/rd68884_pkg.sv \
            $fp/gen/rd68884_ucode_pkg.sv \
            $fp/gen/rd68884_crom.sv \
            $fp/gen/rd68884_ucode_rom.sv \
            $fp/gen/rd68885_ucode_rom.sv \
            $fp/rd68884_sync.sv \
            $fp/rd68884_cu_decode.sv \
            $fp/rd68884_biu.sv \
            $fp/rd68884_regfile.sv \
            $fp/rd68884_seq.sv \
            $fp/rd68884_top.sv ]
    }
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
    $top/rtl/sun3/wish7990_dvma_to_020.v \
    $top/rtl/sun3/sun3_async_fifo.v \
    $top/rtl/sun3/sun3_fifo_bridge.v \
    $top/rtl/sun3/sun3_cached_fifo_bridge.v ]

set sv [list]
if {$scsi == 1} {
    # The package first: its struct types are declared at file scope.
    set w5 $inputs/Wish5380/src
    lappend sv $w5/wish5380_pkg.sv $w5/sci_regs.sv $w5/sci_bus.sv $w5/wish5380.sv \
        $w5/scsi_fabric.sv $w5/scsi_targ.sv $w5/sd_spi.sv $w5/blk_sd.sv \
        $top/rtl/sun3/sun3_si.sv
}
lappend sv \
    $inputs/z8530_scc/z8530_scc.sv \
    $top/rtl/sun3/reset_sync.sv \
    $top/boards/Wukong/wukong_clkgen.sv \
    $top/boards/Wukong/wb_to_mig_ui.sv \
    $top/boards/Wukong/wb_mig_sync.sv \
    $top/boards/Wukong/mig_arb.sv \
    $top/boards/Wukong/wukong_top.sv
if {$video == 1} {
    set hd $inputs/hdmi/src
    lappend sv \
        $top/rtl/sun3/fb_scanout.sv \
        $top/boards/Wukong/hdmi_clkgen.sv \
        $hd/tmds_channel.sv $hd/serializer.sv $hd/packet_assembler.sv \
        $hd/packet_picker.sv $hd/audio_clock_regeneration_packet.sv \
        $hd/audio_info_frame.sv $hd/audio_sample_packet.sv \
        $hd/auxiliary_video_information_info_frame.sv \
        $hd/source_product_description_info_frame.sv $hd/hdmi.sv
}
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
if {$wb_fifo == 1} {
    read_xdc $here/wukong_wbfifo.xdc
    puts "== read wukong_wbfifo.xdc =="
} else {
    read_xdc $here/wukong_wbcdc.xdc
    puts "== read wukong_wbcdc.xdc =="
}
if {$video == 1} {
    read_xdc $here/wukong_hdmi.xdc
    puts "== read wukong_hdmi.xdc =="
}
if {$scsi == 1} {
    read_xdc $here/wukong_sd_$board.xdc
    puts "== read wukong_sd_$board.xdc =="
}

# ---------------------------------------------------------------------------
# Synthesis and implementation
# ---------------------------------------------------------------------------
# What the knobs resolved to, in the log: a define that is not passed builds a
# clean bitstream with a whole subsystem missing.
puts "== defines: $defines =="

# An undeclared identifier is an error, not a one-bit undriven wire: that is
# how the Sun-2's frame buffer reached the board dead.
set_msg_config -id {Synth 8-6901} -new_severity ERROR
# An XDC command Vivado does not support drops the whole constraint with only
# a critical warning (a `concat' once took the clock groups with it).
set_msg_config -id {Designutils 20-1307} -new_severity ERROR

synth_design -top wukong_top -part $part \
    -include_dirs [list $outdir $top/rtl/sun3 $top/build/rom] \
    -verilog_define $defines \
    -generic CPU_CLK_HZ=$cpu_hz \
    -generic CPU_DIV=$cpu_div \
    -generic DISK_LBA_OFFSET=[expr {$disk_off_mib * 2048}]

write_checkpoint -force $outdir/post_synth.dcp
report_utilization -file $outdir/post_synth_utilization.rpt
report_clocks      -file $outdir/clocks.rpt

# The feature knobs have to reach the netlist, not just the command line.
# With no HDMI clock in the design nothing can violate, so a lost SUN3_VIDEO
# would pass every gate below (a Sun-2 lesson).
if {$video == 1 && [llength [get_cells -quiet -hier -filter {NAME =~ *hdmiclk*}]] == 0} {
    puts "ERROR: VIDEO=1 but the netlist has no HDMI clock generator: SUN3_VIDEO did not reach the RTL"
    exit 1
}
if {$eth == 1 && [llength [get_cells -quiet -hier -filter {NAME =~ *mdio_station*}]] == 0} {
    puts "ERROR: ETH=1 but the netlist has no MDIO station: SUN3_ETH_WISH7990 did not reach the RTL"
    exit 1
}
if {$wb_fifo == 1} {
    # wukong_wbfifo.xdc bounds the FIFO bridge's crossings by pattern, and a
    # pattern that matches nothing turns its constraint into a warning.
    foreach f {req_fifo rsp_fifo} {
        foreach c {wgray_reg[*] wgray_r1_reg[*] rgray_reg[*] rgray_w1_reg[*] mem_reg*} {
            set n [llength [get_cells -quiet -hier -filter "NAME =~ *wbridge/$f/$c"]]
            if {$n == 0} {
                puts "ERROR: wukong_wbfifo.xdc: *wbridge/$f/$c matches no cells -- its constraint is not applied"
                exit 1
            }
            puts "== wbfifo xdc: $f/$c matches $n cells =="
        }
    }
    foreach c {wbrst_s_reg[0] cpurst_s_reg[0]} {
        if {[llength [get_cells -quiet -hier -filter "NAME =~ *wbridge/$c"]] == 0} {
            puts "ERROR: wukong_wbfifo.xdc: *wbridge/$c matches no cell"
            exit 1
        }
    }
} elseif {[llength [get_cells -quiet -hier -filter {NAME =~ *adapter/req_tgl_reg*}]] == 0} {
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
