#!/bin/bash
#
# Check a console.log from tb_sun3 for a good boot to the PROM monitor.
#
#   usage: check_console.sh <console.log> [<expected MiB>]
#
# A good boot, in order: "Selftest Completed.", the model banner, the memory
# installed (checked against <expected MiB> when given), and the monitor
# prompt.  Any "fail" / "error" / "problem" from the PROM is a failure.
#
# This does not run anything: it greps whatever log it is given, however old.
# Rerun the simulation first.
#
set -e -o pipefail

log=${1:?usage: check_console.sh <console.log> [<expected MiB>]}
mib=${2:-}
[ -e "$log" ] || { echo "FAIL: $log does not exist"; exit 1; }

# The PROM pads its lines with NULs; drop those and the CRs.
txt=$(tr -d '\r\000' <"$log")

fail() { echo "FAIL: $*"; echo "---- $log ----"; echo "$txt"; exit 1; }

if grep -qiE 'fail|error|problem' <<<"$txt"; then
	fail "the PROM reported a failure"
fi
grep -q 'Selftest Completed\.' <<<"$txt" || fail "no 'Selftest Completed.'"
grep -q 'Sun Workstation, Model Sun-3/60' <<<"$txt" || fail "no Sun-3/60 banner"
got=$(sed -n 's/.*ROM Rev [^,]*, \([0-9]*\)MB memory installed.*/\1/p' <<<"$txt" | tail -1)
[ -n "$got" ] || fail "no 'MB memory installed' line"
if [ -n "$mib" ] && [ "$got" != "$mib" ]; then
	fail "the monitor says ${got}MB installed, expected ${mib}MB"
fi
# The monitor prompt, after the (last) banner.
awk '/Sun Workstation/{b=1} b && /^>/{p=1} END{exit !p}' <<<"$txt" || \
	fail "no monitor prompt after the banner"

echo "PASS: $log (${got}MB)"
