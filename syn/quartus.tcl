# Build the Sun-3 for an Altera board (the Arrow DECA) with Quartus Prime.
#
#   quartus_sh -t quartus.tcl -root <dir> -outdir <dir> [-name value ...]
#
# The twin of build.tcl (Vivado, the Wukong).  Everything below boards/ is
# shared.  Adapted from the Sun-2 project's syn/quartus.tcl, which builds a
# Sun-2 for the same board; its comments hold the history of the traps below.
#
# Arguments (run through syn/Makefile, which owns the defaults):
#   -root      the repository root (required)
#   -outdir    where to work (required)
#   -board     deca
#   -cpu       rd68021 (Suska does not fit a 10M50)
#   -topent    deca_top | sun3_top   sun3_top is the machine alone, no board:
#                                    a synthesis-only check of the RTL
#   -stage     map | fit | asm       how far to go
#   -cpu_hz    <hz>                  CPU clock ...
#   -cpu_div   <n>                   ... or the PLL divider (wins; VCO 1 GHz)
#   -cpu_duty  <percent>             the CPU clock's duty cycle
#   -eth       0 | 1                 the Wish7990 on the DP83620
#   -fb        0 | 1                 the bw2 video memory (the PROM needs it)
#   -bus_trace 0 | 1                 the on-chip bus trace (8 M9K)
#   -scsi      0 | 1                 the on-board SCSI, its disk on the micro-SD
#   -disk_off_mib <n>                where on the card the disk starts, MiB
#   -wb_fifo   0 | 1                 the FIFO memory bridge, its Wishbone side on CMD_CLK
#   -wb_cache  0 | 1  -wb_cache_idx <n>   its read cache, 2**n lines of 16 bytes
#   -video     0 | 1                 the bw2 on the ADV7513 (HDMI), 1280x1024@60
#   -fb_console 0 | 1                the console on the screen (needs -video 1)
#   -mem_mib   <n>                   main memory
#   -romfile   <name>                the PROM, from build/rom/
#   -eram      0 | 1                 see below; 1 for any real build
#   -allow_neg 0 | 1                 write a .sof despite negative slack
#   -jobs <n>  -seed <n>
#
package require ::quartus::project
package require ::quartus::flow

set here [file dirname [file normalize [info script]]]
source $here/boards.tcl

# ---------------------------------------------------------------- arguments
array set opt {
    -root      ""
    -outdir    ""
    -board     deca
    -cpu       rd68021
    -topent    deca_top
    -stage     asm
    -cpu_hz    20000000
    -cpu_div   0
    -cpu_duty  50
    -eth       0
    -fb        1
    -bus_trace 1
    -scsi      0
    -disk_off_mib 0
    -wb_fifo   1
    -wb_cache  1
    -wb_cache_idx 9
    -video     0
    -fb_console 0
    -mem_mib   16
    -romfile   bootrom_sun3_60_v1.9_noparity_32bits.vh
    -eram      1
    -allow_neg 0
    -jobs      8
    -seed      0
}
foreach {k v} $argv {
    if {![info exists opt($k)]} { puts "ERROR: unknown argument '$k'"; exit 1 }
    set opt($k) $v
}
if {$opt(-root) eq "" || $opt(-outdir) eq ""} {
    puts "ERROR: -root and -outdir are required"; exit 1
}
set top $opt(-root)
set out $opt(-outdir)

board_check $opt(-board)
if {[board_vendor $opt(-board)] ne "altera"} {
    puts "ERROR: BOARD=$opt(-board) is a [board_vendor $opt(-board)] board; this is the Quartus flow"
    exit 1
}
if {$opt(-cpu) ne "rd68021"} {
    puts "ERROR: only CPU=rd68021 fits a MAX 10 10M50.  Suska's 68K30L is ~24K"
    puts "       LUT6 on Artix-7, some 50K LE here: the whole device."
    exit 1
}
if {![file exists $top/build/rom/$opt(-romfile)]} {
    puts "ERROR: no PROM image build/rom/$opt(-romfile) (make -C tools)"
    exit 1
}

# CPU_DIV wins over CPU_HZ, and the reported and TOD frequency is recomputed
# from it: the clock that will exist.
if {$opt(-cpu_div) != 0} {
    set opt(-cpu_hz) [expr {1000000000 / $opt(-cpu_div)}]
}

# ------------------------------------------------------------------ defines
# The PROM reaches the RTL by copy, as in build.tcl.
file mkdir $out
file copy -force $top/build/rom/$opt(-romfile) $out/bootrom_selected_32bits.vh

set defines [list SUN3_QUARTUS SUN3_CPU_RD68021 \
                 SUN3_CPU_HZ=$opt(-cpu_hz) SUN3_MEM_MIB=$opt(-mem_mib) \
                 SUN3_BOOTROM_SELECTED]
if {$opt(-eth) == 1}       { lappend defines SUN3_ETH_WISH7990 }
if {$opt(-fb) == 0}        { lappend defines SUN3_NO_FB }
if {$opt(-bus_trace) == 0} { lappend defines SUN3_NO_BUS_TRACE }
if {$opt(-scsi) == 1}      { lappend defines SUN3_SCSI }
if {$opt(-wb_fifo) == 1}   { lappend defines SUN3_WB_FIFO }
if {$opt(-wb_cache) == 1} {
    if {$opt(-wb_fifo) != 1} {
        puts "ERROR: -wb_cache 1 needs -wb_fifo 1: the cache sits in front of the FIFO bridge"
        exit 1
    }
    lappend defines SUN3_WB_CACHE SUN3_WB_CACHE_IDX=$opt(-wb_cache_idx)
}
if {$opt(-video) == 1} {
    if {$opt(-fb) != 1} {
        puts "ERROR: -video 1 needs -fb 1: the screen shows the bw2's memory"; exit 1
    }
    lappend defines SUN3_VIDEO
}
if {$opt(-fb_console) == 1} {
    if {$opt(-video) != 1} {
        puts "ERROR: -fb_console 1 needs -video 1: a console nobody can see"; exit 1
    }
    lappend defines SUN3_FB_CONSOLE
}

puts "== Sun-3 for [board_family $opt(-board)] [board_device $opt(-board)], entity $opt(-topent) =="
puts "== CPU $opt(-cpu) at $opt(-cpu_hz) Hz[expr {$opt(-cpu_div) ? " (VCO/$opt(-cpu_div))" : ""}], duty $opt(-cpu_duty)%, $opt(-mem_mib) MiB, PROM $opt(-romfile), ETH=$opt(-eth), FB=$opt(-fb), WB_FIFO=$opt(-wb_fifo), WB_CACHE=$opt(-wb_cache) (IDX $opt(-wb_cache_idx)), VIDEO=$opt(-video), FB_CONSOLE=$opt(-fb_console) =="
if {$opt(-scsi) == 1} {
    puts "== SCSI disk at $opt(-disk_off_mib) MiB on the micro-SD ([expr {$opt(-disk_off_mib) * 2048}] sectors) =="
}
puts "== defines: $defines =="
puts "== output: $out =="

cd $out

# ------------------------------------------------------------------ project
project_new sun3 -overwrite

set_global_assignment -name FAMILY           [board_family $opt(-board)]
set_global_assignment -name DEVICE           [board_device $opt(-board)]
set_global_assignment -name TOP_LEVEL_ENTITY $opt(-topent)
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY $out
if {$opt(-seed) != 0} { set_global_assignment -name SEED $opt(-seed) }
set_global_assignment -name NUM_PARALLEL_PROCESSORS $opt(-jobs)

# set_parameter reaches the top-level entity's parameters and nothing below:
# deca_top forwards them.
if {$opt(-topent) eq "deca_top"} {
    set_parameter -name CPU_CLK_HZ $opt(-cpu_hz)
    set_parameter -name CPU_DIV    $opt(-cpu_div)
    set_parameter -name CPU_DUTY   $opt(-cpu_duty)
    set_parameter -name DISK_LBA_OFFSET [expr {$opt(-disk_off_mib) * 2048}]
}

# --- the trap that emits no warning ---------------------------------------
# MAX 10 loads initialised embedded RAM from its configuration flash only when
# the image is built to carry it.  Without this, Quartus silently builds every
# initialised memory -- the 64 KiB PROM, RD68021's microcode, the EEPROM --
# out of logic, and the design does not fit (Sun-2: 113% of the device).
if {$opt(-eram)} {
    set_global_assignment -name INTERNAL_FLASH_UPDATE_MODE "SINGLE COMP IMAGE WITH ERAM"
}

# Bank 8 runs at 1.2 V for the LEDs, which gives up the configuration pins:
# the board is JTAG-only.
set_global_assignment -name USE_CONFIGURATION_DEVICE   OFF
set_global_assignment -name AUTO_RESTART_CONFIGURATION OFF
set_global_assignment -name ENABLE_CONFIGURATION_PINS  OFF
set_global_assignment -name ENABLE_BOOT_SEL_PIN        OFF

# The global stand-in for ASYNC_REG (sun3_attr.vh's Quartus arm relies on it).
set_global_assignment -name SYNCHRONIZER_IDENTIFICATION "FORCED IF ASYNCHRONOUS"

# Quartus refuses a constant loop past 5000 iterations (Error 10106).
set_global_assignment -name VERILOG_CONSTANT_LOOP_LIMIT 65536

# `include search path: the PROM copy first, then the RTL headers.
set_global_assignment -name SEARCH_PATH $out
set_global_assignment -name SEARCH_PATH $top/rtl/sun3
set_global_assignment -name SEARCH_PATH $top/build/rom

foreach d $defines { set_global_assignment -name VERILOG_MACRO $d }

# -------------------------------------------------------------------- files
# The same lists as build.tcl, in the same order.  Inputs come from their
# patched copies in build/inputs (tools/patch_inputs.sh), BrianHG's controller
# from Inputs/ as is.
# Wish5380's package first: its struct types are declared at file scope, and
# deca_top uses the block seam's whether or not the SCSI is built.
set w5 $top/build/inputs/Wish5380/src
set sv [list $w5/wish5380_pkg.sv]
if {$opt(-scsi) == 1} {
    lappend sv $w5/sci_regs.sv $w5/sci_bus.sv $w5/wish5380.sv \
        $w5/scsi_fabric.sv $w5/scsi_targ.sv $top/rtl/sun3/sun3_si.sv
    if {$opt(-topent) eq "deca_top"} { lappend sv $w5/sd_spi.sv $w5/blk_sd.sv }
}

set rd $top/build/inputs/RD68021/rtl
lappend sv \
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
    $rd/rd68021_top.sv

set v2001 [list \
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
    $top/rtl/sun3/sun3_async_fifo.v \
    $top/rtl/sun3/sun3_fifo_bridge.v \
    $top/rtl/sun3/sun3_cached_fifo_bridge.v \
    $top/rtl/sun3/fault_log.v \
    $top/rtl/sun3/bus_trace.v \
    $top/rtl/sun3/wish7990_sun3_regs.v \
    $top/rtl/sun3/wish7990_dvma_to_020.v ]

lappend sv $top/build/inputs/z8530_scc/z8530_scc.sv $top/rtl/sun3/reset_sync.sv

if {$opt(-eth) == 1 || $opt(-topent) eq "deca_top"} {
    # wb_mdio is the board's; the MAC only with ETH=1.
    set w $top/build/inputs/Wish7990/src
    if {$opt(-eth) == 1} {
        lappend sv $w/wish7990_pkg.sv $w/crc32_eth.sv $w/sync_fifo.sv $w/async_fifo.sv \
            $w/dp_ram.sv $w/mii_rx.sv $w/mii_tx.sv $w/wb_master.sv $w/wb_arb.sv \
            $w/le_regs.sv $w/le_init.sv $w/le_tx.sv $w/le_filt.sv $w/le_rx.sv \
            $w/wish7990.sv
    }
    lappend sv $w/wb_mdio.sv
}

if {$opt(-topent) eq "deca_top"} {
    foreach f [lsort [glob -nocomplain $top/boards/DECA/*.sv]] { lappend sv $f }
    if {$opt(-video) == 1} {
        lappend sv $top/rtl/sun3/fb_scanout.sv $top/rtl/sun3/video_timing.sv
    }

    set bhg $top/Inputs/BrianHG-DDR3/BrianHG_DDR3
    foreach f [list BrianHG_DDR3_CONTROLLER_v16_top.sv BrianHG_DDR3_COMMANDER_v16.sv \
                    BrianHG_DDR3_CMD_SEQUENCER_v16.sv BrianHG_DDR3_PHY_SEQ_v16.sv \
                    BrianHG_DDR3_PLL.sv BrianHG_DDR3_GEN_tCK.sv \
                    BrianHG_DDR3_FIFOs.sv BrianHG_DDR3_IO_PORT_ALTERA.sv \
                    altera_gpio_lite.sv] {
        if {![file exists $bhg/$f]} {
            puts "ERROR: the DDR3 controller is missing: $bhg/$f"
            puts "       run: git submodule update --init Inputs/BrianHG-DDR3"
            exit 1
        }
        lappend sv $bhg/$f
    }
    set_global_assignment -name SEARCH_PATH $bhg

    # The JTAG UART, straight from the Quartus installation.  Quartus-only
    # (read_comments_as_HDL): never in a Vivado or xsim list.
    set juart $::env(QUARTUS_ROOTDIR)/../ip/altera/sopc_builder_ip/altera_avalon_jtag_uart
    foreach f [list altera_avalon_jtag_uart.sv \
                    altera_avalon_jtag_uart_scfifo_r.sv \
                    altera_avalon_jtag_uart_scfifo_w.sv] {
        if {![file exists $juart/$f]} {
            puts "ERROR: the JTAG UART IP is missing: $juart/$f (the console)"
            exit 1
        }
        lappend sv $juart/$f
    }
}

foreach f $v2001 {
    if {![file exists $f]} { puts "ERROR: missing source $f"; exit 1 }
    set_global_assignment -name VERILOG_FILE $f
}
foreach f $sv {
    if {![file exists $f]} { puts "ERROR: missing source $f"; exit 1 }
    set_global_assignment -name SYSTEMVERILOG_FILE $f
}

if {$opt(-topent) eq "deca_top"} {
    set_global_assignment -name SDC_FILE $here/deca.sdc
    if {$opt(-video) == 1} {
        set_global_assignment -name SDC_FILE $here/deca_video.sdc
    }
    source $here/deca_pins.qsf
    source $here/deca_ddr3_pins.qsf
}

export_assignments

# ------------------------------------------------------------------- stages
if {[catch {execute_module -tool map} err]} {
    puts "== analysis & synthesis FAILED =="; puts $err; project_close; exit 1
}
puts "== analysis & synthesis ok =="

# An implicit net is a silent bug (MATCH_CYCTR was one): refuse it.
set fh [open sun3.map.rpt]; set maprpt [read $fh]; close $fh
set implicit [regexp -all -inline {[^\n]*(?:10236|[Ii]mplicit net)[^\n]*} $maprpt]
if {[llength $implicit]} {
    puts "ERROR: implicit nets:"
    foreach l $implicit { puts "   $l" }
    project_close; exit 1
}

# The console is the only instrument this board has.
if {$opt(-topent) eq "deca_top"} {
    if {![regexp {alt_jtag_atlantic} $maprpt]} {
        puts "ERROR: no alt_jtag_atlantic in the netlist: the console is missing"
        puts "       (did SUN3_SIM leak into this build?)"
        project_close; exit 1
    }
    puts "== console: alt_jtag_atlantic present =="
}

if {$opt(-stage) eq "map"} { project_close; exit 0 }

if {[catch {execute_module -tool fit} err]} {
    puts "== fit FAILED =="; puts $err; project_close; exit 1
}
puts "== fit ok =="

# Resource use, from the fit summary.
if {[file exists sun3.fit.summary]} {
    set fh [open sun3.fit.summary]
    foreach line [split [read $fh] "\n"] {
        if {[regexp {^(Total logic elements|Total registers|Total memory bits|Embedded Multiplier|Total PLLs|UFM blocks)[^:]*:\s*(.*)$} $line -> k v]} {
            puts "== $k: [string trim $v] =="
        }
    }
    close $fh
}

if {[catch {execute_module -tool sta} err]} {
    puts "== timing analysis FAILED =="; puts $err; project_close; exit 1
}
puts "== sta ok =="

# The clocks as programmed, Fmax, and the worst setup and hold slack.
set worst_setup 1e9; set worst_hold 1e9
if {[file exists sun3.sta.rpt]} {
    set fh [open sun3.sta.rpt]; set sta [read $fh]; close $fh
    foreach line [split $sta "\n"] {
        if {[regexp {^; *([^;]*pll_[ab][^;]*) *; *Generated *; *([0-9.]+) *; *([0-9.]+ [Mk]Hz)} \
                 $line -> nm pd fq]} {
            puts "== clock [string trim $nm]: [string trim $pd] ns, [string trim $fq] =="
        }
    }
    set inf 0
    foreach line [split $sta "\n"] {
        if {[regexp {Slow 1200mV 85C Model Fmax Summary} $line]} { set inf 1 }
        if {$inf && [regexp {^; *([0-9.]+ MHz) *; *([0-9.]+ MHz) *; *([^;]+) *;} $line -> f rf cn]} {
            puts "== Fmax [string trim $cn]: [string trim $f] (restricted [string trim $rf]) =="
        }
    }
}
if {[file exists sun3.sta.summary]} {
    set fh [open sun3.sta.summary]; set summ [read $fh]; close $fh
    set type ""
    foreach line [split $summ "\n"] {
        regexp {^Type\s*:\s*(.*)$} $line -> type
        if {[regexp {^Slack\s*:\s*(-?[0-9.]+)} $line -> sl]} {
            if {[regexp {Setup} $type] && $sl < $worst_setup} { set worst_setup $sl }
            if {[regexp {Hold}  $type] && $sl < $worst_hold}  { set worst_hold  $sl }
        }
    }
}
puts "== worst setup slack $worst_setup ns, worst hold slack $worst_hold ns (all corners) =="
if {$worst_setup < 0 || $worst_hold < 0} {
    if {$opt(-allow_neg)} {
        puts "== timing NOT met, ALLOWED by ALLOW_NEG=1 =="
    } else {
        puts "ERROR: timing not met; see $out/sun3.sta.rpt (ALLOW_NEG=1 to build anyway)"
        project_close; exit 1
    }
}

if {$opt(-stage) eq "fit"} { project_close; exit 0 }

# The assembler is the only end-to-end check that the image can carry the
# initialised RAM contents (the ERAM mode above).
if {[catch {execute_module -tool asm} err]} {
    puts "== assembler FAILED =="; puts $err; project_close; exit 1
}
puts "== assembler ok: $out/sun3.sof =="

project_close
