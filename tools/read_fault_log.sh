#!/bin/bash
#
# Break into the PROM monitor and dump the FPGA's fault log (rtl/sun3/fault_log.v):
# the number of bus errors since reset, and the last 32 of them, each as
#   address / {FC,WR,SIZ,DVMA,-,BER,PTE bits,00} / PTE page / cycle count.
#
#   usage: tools/read_fault_log.sh [-n]     (-n: the monitor is already at its prompt)
#
# Leaves the machine in the monitor; type `c' to continue a kernel.
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
timeout 200 "$con" -t 150 --quiet-gap 6 \
	--send "" --send "s 3" --send "l d0000200" --send "q" \
	--send "v d0000000 d00001ff" --send "s 5" 2>&1 | tr -d '\r'
