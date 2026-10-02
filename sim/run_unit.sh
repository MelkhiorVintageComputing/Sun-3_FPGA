#!/bin/bash
#
# Unit tests for the board layer: small, fast, and each one fails loudly.
#
#   ./run_unit.sh decaddr3     deca_wb_to_ddr3 against a model of BrianHG's
#                              command port (mask polarity, strobe handshake,
#                              lanes, high addresses)
#   ./run_unit.sh decaconsole  deca_jtag_console against a model of the JTAG
#                              UART's Avalon slave: what the host receives is
#                              what the machine sent, once each, in order
#   ./run_unit.sh asyncfifo    sun3_async_fifo across two unrelated clocks
#   ./run_unit.sh fifobridge   sun3_fifo_bridge (SUN3_WB_FIFO): posted writes,
#                              tagged reads, stale answers dropped, lanes
#   ./run_unit.sh scanout      fb_scanout: every pixel of a 1280x1024 frame
#   ./run_unit.sh adv7513      deca_adv7513_init: the HDMI transmitter's setup
#   ./run_unit.sh vtiming      video_timing: VESA 1280x1024@60
#   ./run_unit.sh cachedbridge sun3_cached_fifo_bridge (SUN3_WB_CACHE) against
#                              a bus-level shadow of memory
#   ./run_unit.sh decaddr3sync deca_wb_ddr3_sync, decaddr3's checks on CMD_CLK
#
# Copied, with its testbenches, from the Sun-2 project's sim/run_unit.sh.
#
set -e -o pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/.." && pwd)

: "${XILINX_VIVADO:=/opt/Xilinx/2025.2/Vivado}"
export PATH="$XILINX_VIVADO/bin:$PATH"
if [ -z "${LIBRARY_PATH:-}" ] && [ -e /usr/lib/x86_64-linux-gnu/crt1.o ]; then
	export LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
fi

what=${1:?usage: run_unit.sh decaddr3|decaconsole|asyncfifo|fifobridge|cachedbridge|scanout|vtiming|adv7513|decaddr3sync}
rundir="$top/build/sim/unit-$what"
rm -rf "$rundir"; mkdir -p "$rundir"; cd "$rundir"

# A tool can fail with a status or succeed while printing ERROR; both stop
# the run, or xsim would pick up a stale snapshot and report PASS.
step() {
	local log="$rundir/.step.log"
	if ! "$@" > "$log" 2>&1; then
		cat "$log"; echo "FAIL: $1 exited non-zero"; exit 1
	fi
	if grep -qE '^(ERROR|CRITICAL)' "$log"; then
		cat "$log"; echo "FAIL: $1 printed an error"; exit 1
	fi
}

# The verdict is the testbench's own: it prints PASS or FAIL.
verdict() {
	local out="$rundir/xsim.out"
	xsim "$1" -R > "$out" 2>&1 || true
	grep -E '===|PASS|FAIL|ok:' "$out"
	grep -q FAIL "$out" && exit 1
	grep -q PASS "$out" || { echo "FAIL: no verdict"; exit 1; }
}

case "$what" in
decaddr3)
	step xvlog --sv \
		"$top/boards/DECA/deca_wb_to_ddr3.sv" \
		"$top/tb/tb_deca_wb_ddr3.sv" \
		-i "$top/rtl/sun3"
	step xelab -debug off --timescale 1ns/1ps work.tb_deca_wb_ddr3 -s decaddr3_sim
	verdict decaddr3_sim
	;;
decaconsole)
	step xvlog --sv \
		"$top/boards/DECA/deca_uart_rx.sv" \
		"$top/boards/DECA/deca_uart_tx.sv" \
		"$top/boards/DECA/deca_jtag_console.sv" \
		"$top/tb/jtag_uart_model.sv" \
		"$top/tb/tb_deca_console.sv" \
		-d SUN3_SIM -i "$top/rtl/sun3"
	step xelab -debug off --timescale 1ns/1ps work.tb_deca_console -s decaconsole_sim
	verdict decaconsole_sim
	;;
asyncfifo)
	# The dual-clock FIFO under sun3_fifo_bridge: order, full, empty and fall
	# through, across two unrelated clocks each way round.
	step xvlog -i "$top/rtl/sun3" -d SUN3_SIM "$top/rtl/sun3/sun3_async_fifo.v"
	step xvlog --sv "$top/tb/tb_async_fifo.sv"
	step xelab -debug off --timescale 1ns/1ps work.tb_async_fifo -s asyncfifo_sim
	verdict asyncfifo_sim
	;;
fifobridge)
	# The FIFO bridge against a registered slave on a clock of its own.
	step xvlog -i "$top/rtl/sun3" -d SUN3_SIM "$top/rtl/sun3/sun3_async_fifo.v" \
		"$top/rtl/sun3/sun3_fifo_bridge.v"
	step xvlog --sv "$top/tb/tb_fifo_bridge.sv"
	step xelab -debug off --timescale 1ns/1ps work.tb_fifo_bridge -s fifobridge_sim
	verdict fifobridge_sim
	;;
scanout)
	# fb_scanout (the bw2 on HDMI) against a pattern: every pixel of a frame,
	# the border, the beats per frame, EN.VIDEO.  XSIMARGS: +fb_image=<mem>
	# replays a captured frame buffer, +fb_ppm=<file> writes the picture.
	step xvlog --sv -i "$top/rtl/sun3" \
		"$top/rtl/sun3/fb_scanout.sv" "$top/tb/tb_fb_scanout.sv"
	step xelab -debug off --timescale 1ns/1ps work.tb_fb_scanout -s scanout_sim
	xsim scanout_sim -R ${XSIMARGS:-} > "$rundir/xsim.out" 2>&1 || true
	grep -E '===|PASS|FAIL|checked|beats read|line starts|white|wrote' "$rundir/xsim.out"
	grep -q FAIL "$rundir/xsim.out" && exit 1
	grep -q "PASS: fb_scanout" "$rundir/xsim.out" || { echo "FAIL: no verdict"; exit 1; }
	;;
adv7513)
	# The ADV7513's I2C setup against an I2C slave model and an independently
	# written expected register table.
	step xvlog --sv -i "$top/rtl/sun3" \
		"$top/boards/DECA/deca_adv7513_init.sv" \
		"$top/tb/i2c_slave_model.sv" "$top/tb/tb_adv7513_init.sv"
	step xelab -debug off --timescale 1ns/1ps work.tb_adv7513_init -s adv7513_sim
	verdict adv7513_sim
	;;
vtiming)
	# The raster (VESA 1280x1024@60) and nothing else.
	step xvlog --sv "$top/rtl/sun3/video_timing.sv" "$top/tb/tb_video_timing.sv"
	step xelab -debug off --timescale 1ns/1ps work.tb_video_timing -s vtiming_sim
	verdict vtiming_sim
	;;
cachedbridge)
	# The cached FIFO bridge against a bus-level shadow of memory.
	step xvlog -i "$top/rtl/sun3" -d SUN3_SIM "$top/rtl/sun3/sun3_async_fifo.v" \
		"$top/rtl/sun3/sun3_cached_fifo_bridge.v"
	step xvlog --sv "$top/tb/tb_cached_bridge.sv"
	step xelab -debug off --timescale 1ns/1ps work.tb_cached_bridge -s cachedbridge_sim
	verdict cachedbridge_sim
	;;
decaddr3sync)
	# The decaddr3 checks against deca_wb_ddr3_sync, the FIFO bridge's
	# adapter, with the Wishbone master on CMD_CLK and no crossing.
	step xvlog --sv -d DECA_SYNC \
		"$top/boards/DECA/deca_wb_ddr3_sync.sv" \
		"$top/tb/tb_deca_wb_ddr3.sv" \
		-i "$top/rtl/sun3"
	step xelab -debug off --timescale 1ns/1ps work.tb_deca_wb_ddr3 -s decaddr3sync_sim
	verdict decaddr3sync_sim
	;;
*)
	echo "unknown unit test '$what'"; exit 2
	;;
esac
