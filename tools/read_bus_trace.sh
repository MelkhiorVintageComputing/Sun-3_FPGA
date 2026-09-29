#!/bin/bash
#
# Break into the PROM monitor and dump the FPGA's bus trace (rtl/sun3/bus_trace.v)
# to stdout as the monitor prints it; decode it with tools/decode_bus_trace.py.
#
#   usage: tools/read_bus_trace.sh [-n] > trace.txt
#          (-n: the monitor is already at its prompt)
#
# Leaves the machine in the monitor.
set -e
here=$(cd "$(dirname "$0")" && pwd)
con="$here/board_console.py"
if [ "$1" != -n ]; then
	for i in 1 2 3 4 5; do
		timeout 30 "$con" -t 8 --break --until "Abort at" >/dev/null 2>&1 && break
		sleep 3
	done
	sleep 2
fi
timeout 400 "$con" -t 300 --quiet-gap 8 \
	--send "" --send "s 3" --send "l d0001000" --send "q" \
	--send "v d0002000 d0003fff" --send "s 5" 2>&1 | tr -d '\r'
