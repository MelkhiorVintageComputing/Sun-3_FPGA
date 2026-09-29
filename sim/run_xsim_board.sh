#!/bin/bash
#
# Run the board-level simulation (tb/tb_wukong.sv + boards/Wukong/wukong_top.sv)
# under xsim.
#
# Environment (sim/Makefile sets these from its knobs):
#   BOARD             v1s1 (default) | v1 | v3 -- which MIG to take (ddr3 mode)
#   BOARD_MEM         fast (default): behavioural Wishbone RAM, no MIG
#                     ddr3: the generated MIG (simulation variant) + Micron's model
#   BOARD_CLKGEN      behavioural (default with fast) | real (default with ddr3)
#   SUN3_CPU, SUN3_ROM, SUN3_ROM_VER, SUN3_MEM_MIB, SUN3_MEM_LATENCY,
#   SUN3_CPU_HZ, SUN3_BAUD, SUN3_DEFINES   as for run_xsim.sh
#
# Arguments go to xsim, so plusargs work.  Adapted from the Sun-2 project.
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
if [ -z "$LIBRARY_PATH" ] && [ -e /usr/lib/x86_64-linux-gnu/crt1.o ]; then
	export LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
fi

: "${BOARD:=v1s1}"
: "${BOARD_MEM:=fast}"
cpu=${SUN3_CPU:-suska}
rom=${SUN3_ROM:-fast}
romver=${SUN3_ROM_VER:-1.9}
mem=${SUN3_MEM_MIB:-4}
lat=${SUN3_MEM_LATENCY:-10}
hz=${SUN3_CPU_HZ:-20000000}
baud=${SUN3_BAUD:-9600}
eth=none
romfile="bootrom_sun3_60_v${romver}_${rom}_32bits.vh"

# The MMCM simulation model runs its VCO at 1 GHz and costs more events than the
# rest of the machine (about 6x, measured on the Sun-2): the fast configuration
# generates the same frequencies behaviourally.  ddr3 always uses the real ones.
: "${BOARD_CLKGEN:=$([ "$BOARD_MEM" = fast ] && echo behavioural || echo real)}"

# One directory per configuration (see run_xsim.sh).
tag="$BOARD-$BOARD_MEM-$cpu-v$romver-$rom-${mem}m"
[ "$BOARD_MEM" = fast ] && [ "$lat" != 10 ] && tag="$tag-lat$lat"
[ "$BOARD_CLKGEN" = real ] && [ "$BOARD_MEM" = fast ] && tag="$tag-mmcm"
[ "$hz" != 20000000 ] && tag="$tag-cpu$((hz / 1000000))"
for d in $SUN3_DEFINES; do tag="$tag-${d//=/_}"; done
rundir="$top/build/sim/board-$tag"
mkdir -p "$rundir"

make -s -C "$top/tools"
if [ ! -e "$top/build/rom/$romfile" ]; then
	echo "no PROM image $romfile" >&2
	exit 1
fi

defargs=(-d SUN3_SIM -d "SUN3_CPU_HZ=$hz" -d "SUN3_MEM_MIB=$mem" -d "SUN3_BOOTROM_FILE=\"$romfile\"")
for d in $SUN3_DEFINES; do defargs+=(-d "$d"); done

mig="$top/build/ip/$BOARD/sun3_mig/sun3_mig/user_design/rtl"
ex="$top/build/ip/$BOARD/sun3_mig/sun3_mig/example_design/sim"
if [ "$BOARD_MEM" = ddr3 ]; then
	if [ ! -d "$mig" ]; then
		echo "MIG has not been generated for $BOARD: run make -C syn ip BOARD=$BOARD" >&2
		exit 1
	fi
elif [ "$BOARD_MEM" = fast ]; then
	defargs+=(-d BOARD_MEM_FAST)
else
	echo "BOARD_MEM must be fast or ddr3, not '$BOARD_MEM'" >&2
	exit 1
fi
[ "$BOARD_CLKGEN" = behavioural ] && defargs+=(-d CLKGEN_BEHAVIOURAL)
echo "== BOARD=$BOARD, BOARD_MEM=$BOARD_MEM, clock generation: $BOARD_CLKGEN =="

cd "$rundir"
echo "== run directory $rundir =="

. "$here/compile_cpu.sh"
. "$here/compile_sun3.sh"
compile_cpu
compile_sun3

board_src=("$top/rtl/sun3/reset_sync.sv" "$top/boards/Wukong/wukong_clkgen.sv"
           "$top/boards/Wukong/wukong_top.sv")
tb_src=("$top/tb/wb_ram_model.sv" "$top/tb/uart_monitor.sv" "$top/tb/uart_console.sv"
        "$top/tb/tb_wukong.sv")
incargs=()
if [ "$BOARD_MEM" = ddr3 ]; then
	board_src+=("$top/boards/Wukong/wb_to_mig_ui.sv" "$top/boards/Wukong/mig_arb.sv")
	# MIG's RTL, with the simulation top (SIM_BYPASS_INIT_CAL="FAST") instead
	# of the synthesis one: both define the same module.
	mapfile -t mig_src < <(find "$mig" -name '*.v' -o -name '*.sv' \
	                       | grep -v '/sun3_mig_mig\.v$' | sort)
	board_src+=("${mig_src[@]}")
	# Micron's model, filled in for our part by MIG's example design.
	tb_src+=("$ex/ddr3_model.sv")
	incargs=(-i "$ex" -i "$mig")
fi

echo "== compiling the SCCs, board layer and testbench (SystemVerilog) =="
xvlog --sv --work sun3 "${defargs[@]}" "${incargs[@]}" \
	-i "$top/rtl/sun3" -i "$top/build/rom" \
	"${sun3_sv[@]}" "${board_src[@]}" "${tb_src[@]}"

xvlog --work sun3 "$XILINX_VIVADO/data/verilog/src/glbl.v" >/dev/null

debug=off
[ -n "${SUN3_VCD:-}" ] && debug=typical

echo "== elaborating (BOARD_MEM=$BOARD_MEM, debug=$debug) =="
xelab -debug $debug -O3 --timescale 1ns/1ps \
	-L sun3 -L unisims_ver -L unisim -L secureip \
	-generic_top "CPU_CLK_HZ=$hz" \
	-generic_top "BAUD=$baud" \
	-generic_top "MEM_LATENCY=$lat" \
	sun3.tb_wukong sun3.glbl -s wukong_sim

echo "== running =="
exec xsim wukong_sim -R "$@"
