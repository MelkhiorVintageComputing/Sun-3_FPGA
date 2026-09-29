#!/usr/bin/env python3
"""Decode a bus trace dumped by tools/read_bus_trace.sh (rtl/sun3/bus_trace.v).

    tools/decode_bus_trace.py trace.txt [--syms netbsd.symbols] [-n LAST]

Prints the ring oldest first (or only the LAST entries): cycle counter delta,
FC, R/W, size, how it ended, DVMA, address (with a kernel symbol if --syms is
given, an `nm'-format list), and the data.
"""
import argparse, bisect, re

ap = argparse.ArgumentParser()
ap.add_argument("dump")
ap.add_argument("--syms")
ap.add_argument("-n", type=int, default=0)
a = ap.parse_args()

txt = open(a.dump).read()
status = re.search(r"^D0001000: ([0-9A-F]{8})", txt, re.M)
st = int(status.group(1), 16) if status else 0
frozen, nxt = st >> 31, st & 0x1ff
data = {}
for off, b in re.findall(r"^D000([23][0-9A-F]{3}):  ((?:[0-9A-F]{2} ){15}[0-9A-F]{2})", txt, re.M):
    data[int(off, 16) - 0x2000] = bytes.fromhex(b.replace(" ", ""))

syms = []
if a.syms:
    for l in open(a.syms):
        p = l.split()
        if len(p) == 3 and p[1] in "TtWwDdBbRr":
            syms.append((int(p[0], 16), p[2]))
    syms.sort()
addrs = [s[0] for s in syms]
def name(x):
    if not syms or x < 0x0e000000:
        return ""
    i = bisect.bisect_right(addrs, x) - 1
    return "%s+0x%x" % (syms[i][1], x - syms[i][0]) if i >= 0 else ""

print("status %08x: %s, next entry %d" % (st, "FROZEN" if frozen else "running", nxt))
order = [(nxt + i) % 512 for i in range(512)]
if a.n:
    order = order[-a.n:]
prev = None
for i in order:
    e = data.get(i * 16)
    if e is None:
        continue
    adr = int.from_bytes(e[0:4], "big"); dat = int.from_bytes(e[4:8], "big")
    inf = int.from_bytes(e[8:12], "big"); cyc = int.from_bytes(e[12:16], "big")
    if adr == 0 and dat == 0 and inf == 0 and cyc == 0:
        continue
    fc = inf >> 29; wr = (inf >> 28) & 1; siz = (inf >> 26) & 3
    dvma = (inf >> 25) & 1; berr = (inf >> 24) & 1
    d = "" if prev is None else "+%d" % ((cyc - prev) & 0xffffffff)
    prev = cyc
    print("%3d %8s fc%d %s siz%d %s%s %08x %08x %s" % (
        i, d, fc, "W" if wr else "R", siz, "BERR" if berr else "ok  ",
        " DVMA" if dvma else "", adr, dat, name(adr)))
