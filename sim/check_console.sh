#!/bin/bash
#
# Check a console.log from tb_sun3 for a good boot to the PROM monitor.
#
#   usage: check_console.sh <console.log>
#
# This does not run anything: it greps whatever log it is given, however old.
# Rerun the simulation first.
#
set -e -o pipefail

log=${1:?usage: check_console.sh <console.log>}
[ -e "$log" ] || { echo "FAIL: $log does not exist"; exit 1; }

txt=$(tr -d '\r' <"$log")

fail() { echo "FAIL: $*"; echo "---- $log ----"; cat "$log"; echo; exit 1; }

# The PROM's own failure reports.
if grep -qiE 'fail|error|problem' <<<"$txt"; then
	fail "the PROM reported a failure"
fi
grep -q 'Sun Workstation' <<<"$txt" || fail "no 'Sun Workstation' banner"
# The monitor prompt, after the banner.
awk '/Sun Workstation/{b=1} b && />/{p=1} END{exit !p}' <<<"$txt" || \
	fail "no monitor prompt after the banner"

echo "PASS: $log"
