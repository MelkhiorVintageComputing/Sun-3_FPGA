#!/bin/bash
#
# Run the Sun-3 core-level simulation (tb/tb_sun3.sv) under Vivado's xsim.
#
# xsim because the design is mixed-language: the Suska WF68K30L is VHDL,
# everything else Verilog / SystemVerilog.
#
# Environment (sim/Makefile sets these from its knobs):
#   XILINX_VIVADO     Vivado install (default /opt/Xilinx/2025.2/Vivado)
#   SUN3_CPU          suska (default) | rd68021
#   SUN3_ROM          fast (default) | noparity | pristine
#   SUN3_ROM_VER      1.9 (default) | 2.8.3 | 3.0.1  -- patched variants: 1.9 only
#   SUN3_MEM_MIB      installed memory in MiB (default 4)
#   SUN3_ETH          none (default) | wish7990
#   SUN3_MEM_LATENCY  Wishbone wait states (default 0)
#   SUN3_CPU_HZ       CPU clock (default 20000000)
#   SUN3_BAUD         console decode rate (default 9600)
#   SUN3_DEFINES      extra `define's
#   SUN3_VCD          1 to elaborate with signal visibility (for +vcd)
#
# Any arguments are passed through to xsim, so plusargs work:
#   ./run_xsim.sh -testplusarg timeout_ms=500
#
set -e -o pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/.." && pwd)

: "${XILINX_VIVADO:=/opt/Xilinx/2025.2/Vivado}"
if [ ! -x "$XILINX_VIVADO/bin/xvlog" ]; then
	echo "xsim not found under $XILINX_VIVADO -- set XILINX_VIVADO" >&2
	exit 1
fi
export PATH="$XILINX_VIVADO/bin:$PATH"

# xelab links the snapshot with Vivado's bundled gcc, which does not know about
# Debian/Ubuntu multiarch paths and so cannot find crt1.o on its own.
if [ -z "$LIBRARY_PATH" ] && [ -e /usr/lib/x86_64-linux-gnu/crt1.o ]; then
	export LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
fi

cpu=${SUN3_CPU:-suska}
rom=${SUN3_ROM:-fast}
romver=${SUN3_ROM_VER:-1.9}
mem=${SUN3_MEM_MIB:-4}
eth=${SUN3_ETH:-none}
lat=${SUN3_MEM_LATENCY:-0}
hz=${SUN3_CPU_HZ:-20000000}
baud=${SUN3_BAUD:-9600}

romfile="bootrom_sun3_60_v${romver}_${rom}_32bits.vh"

# One directory per configuration.  Two runs sharing a snapshot directory
# clobber each other -- the second recompiles it while the first is executing,
# and xsim dies with a kernel fatal that looks like a design fault (a lesson
# the Sun-2 project paid for).  So every knob that changes the snapshot is in
# the name.
tag="$cpu-v$romver-$rom-${mem}m-$eth"
[ "$lat" != 0 ] && tag="$tag-lat$lat"
[ "$hz" != 20000000 ] && tag="$tag-cpu$((hz / 1000000))"
[ "$baud" != 9600 ] && tag="$tag-baud$baud"
for d in $SUN3_DEFINES; do tag="$tag-${d//=/_}"; done
rundir="$top/build/sim/xsim-$tag"
mkdir -p "$rundir"

# The boot PROM includes live in build/rom; generate them if needed.
make -s -C "$top/tools"
if [ ! -e "$top/build/rom/$romfile" ]; then
	echo "no PROM image $romfile (the patched variants exist for Rev 1.9 only)" >&2
	exit 1
fi

defargs=(-d SUN3_SIM -d "SUN3_MEM_MIB=$mem" -d "SUN3_BOOTROM_FILE=\"$romfile\"")
case "$eth" in
none) ;;
wish7990) defargs+=(-d SUN3_ETH_WISH7990) ;;
*) echo "SUN3_ETH must be none or wish7990, not '$eth'" >&2; exit 1 ;;
esac
for d in $SUN3_DEFINES; do
	defargs+=(-d "$d")
done

"$top/tools/patch_inputs.sh" z8530_scc
"$top/tools/patch_inputs.sh" Suska_Configware
[ "$eth" = wish7990 ] && "$top/tools/patch_inputs.sh" Wish7990

cd "$rundir"
echo "== run directory $rundir =="

. "$here/compile_cpu.sh"
compile_cpu

# The Sun-3 gateware is plain Verilog; compiled as such.
echo "== compiling the Sun-3 gateware (Verilog) =="
xvlog --work sun3 \
	"${defargs[@]}" \
	-i "$top/rtl/sun3" -i "$top/build/rom" \
	"$top/rtl/sun3/sun3_top.v" \
	"$top/rtl/sun3/sun3_fpga.v" \
	"$top/rtl/sun3/sun3_mmu.v" \
	"$top/rtl/sun3/ctx_reg_sun3.v" \
	"$top/rtl/sun3/smap.v" \
	"$top/rtl/sun3/pmap.v" \
	"$top/rtl/sun3/sram_sync.v" \
	"$top/rtl/sun3/idprom_sun3.v" \
	"$top/rtl/sun3/gen8bit_reg.v" \
	"$top/rtl/sun3/cyctr32bit_reg.v" \
	"$top/rtl/sun3/bootrom32.v" \
	"$top/rtl/sun3/icm7170.v" \
	"$top/rtl/sun3/eeprom.v" \
	"$top/rtl/sun3/sun3_irq_priority.v" \
	"$top/rtl/sun3/sun3_wishbone_bridge.v" \
	"$top/rtl/sun3/wish7990_sun3_regs.v" \
	"$top/rtl/sun3/wish7990_dvma_to_020.v"

sv_srcs=("$top/build/inputs/z8530_scc/z8530_scc.sv")
if [ "$eth" = wish7990 ]; then
	w="$top/build/inputs/Wish7990/src"
	sv_srcs+=("$w/wish7990_pkg.sv" "$w/crc32_eth.sv" "$w/sync_fifo.sv"
		"$w/async_fifo.sv" "$w/dp_ram.sv" "$w/mii_rx.sv" "$w/mii_tx.sv"
		"$w/wb_master.sv" "$w/wb_arb.sv" "$w/le_regs.sv" "$w/le_init.sv"
		"$w/le_tx.sv" "$w/le_filt.sv" "$w/le_rx.sv" "$w/wish7990.sv")
fi

echo "== compiling the SCCs, Ethernet and testbench (SystemVerilog) =="
xvlog --sv --work sun3 \
	"${defargs[@]}" \
	-i "$top/rtl/sun3" \
	"${sv_srcs[@]}" \
	"$top/tb/wb_ram_model.sv" \
	"$top/tb/uart_monitor.sv" \
	"$top/tb/uart_console.sv" \
	"$top/tb/tb_sun3.sv"

# Signal visibility for $dumpvars costs a lot of run time, so it is opt-in.
debug=off
[ -n "${SUN3_VCD:-}" ] && debug=typical

echo "== elaborating (debug=$debug) =="
xelab -debug $debug -O3 --timescale 1ns/1ps \
	-L sun3 \
	-generic_top "CPU_HZ=$hz" \
	-generic_top "BAUD=$baud" \
	-generic_top "MEM_LATENCY=$lat" \
	sun3.tb_sun3 -s sun3_sim

echo "== running =="
exec xsim sun3_sim -R "$@"
