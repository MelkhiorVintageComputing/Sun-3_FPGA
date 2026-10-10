# Reference bitstreams

Known-good bitstreams, kept so a board can be brought up without a toolchain,
and so later changes can be compared against something that was tested.
Each `.zip` holds the `.bit` (JTAG), the `.bin` (SPI flash) and their
`SHA256SUMS`.

## Current: `sun3_60_wukong_v3_40MHz_24MiB_cache128k_fpu.zip`

A Sun-3/60 with its **MC68881** on the **QMTech Wukong V3**
(xc7a100tfgg676-**1**), with RD68021's reworked bus unit and RESET pin.

| | |
|---|---|
| Source | commit `b72fa73` (branch `rd68021-reset`, merged into master); built from it with no local changes to `rtl/`, `boards/`, `syn/`, the PROM tools or the submodules |
| Submodules | RD68021 `8727c9c`, RD68884 `0595f34` (built as the MC68881), Wish7990 `8610ef5`, Wish5380 `bde4ef3`, z8530_scc `b9bcd67`, hdmi `83b1c95` (+ `patches/hdmi/0001`) |
| Tools | Vivado 2025.2 |
| Build | `make -C syn bitstream BOARD=v3 CPU=rd68021 CPU_DIV=25 ETH=1 SCSI=1 VIDEO=1 FPU=1 FPU_WAIT=1 MEM_MIB=24 WB_CACHE_IDX=13 ALLOW_PW=1 EFFORT=1` |
| CPU | RD68021 at 40 MHz (1000 MHz / 25) |
| FPU | RD68884 (MC68881-compatible) at CpID 1, same-clock bus with one wait state, enabled by EN.FPP |
| Memory | 24 MiB (the 3/60's maximum), FIFO bridge with a 128 KiB read cache |
| PROM | Rev 1.9 + `noparity` (`tools/sun3_60_v1.9_noparity.txt`) |
| Devices | Ethernet (RTL8211EG, 10 Mb/s), on-board SCSI with its disk on the micro-SD card at offset 0, bw2 frame buffer on HDMI (1280x1024@60, 1152x900 centred); no expansion board (`EXP=0`: diag register on PMOD J10) |
| Console | ttya: the board's USB serial port, 9600 8N1 (`FB_CONSOLE=0`) |
| Timing | WNS +0.034 ns, WHS +0.013 ns, with `EFFORT=1` (aggressive physical optimisation before and after routing; the default flow misses 40 MHz by 0.362 ns). One known exception, accepted by `ALLOW_PW=1`: the 540.625 MHz HDMI serialiser clock is 0.305 ns over the -1 part's BUFG minimum period |
| Resources | 22,609 LUTs (36%), 11,475 registers (9%), 89.5 of 135 block RAM tiles, 11 DSPs |

SHA-256:

```
602896072c9073a3b9e4b5585b81890eff9fd1af57ebc7a61c7a048e7182d448  sun3_60_wukong_v3_40MHz_24MiB_cache128k_fpu.bit
b3b28888f904b0c8ad4781aa5c04bddffd69a8fa8d3d6e8c88c1b3ba11709b73  sun3_60_wukong_v3_40MHz_24MiB_cache128k_fpu.bin
```

**Tested on the board:**
- SunOS 4.1.1 GENERIC boots multi-user from the micro-SD card; fsck is
  clean and `bwtwo0` attaches at 1152x900.
- Floating point: the test program gives the correctly rounded results
  with gcc 2.3.3 `-m68881` (29.8 s) and Sun `cc -f68881` (67.7 s).
  Whetstone (double precision, gcc 2.3.3 -O -m68881): 1.4 MIPS (70.7 s).
- Dhrystone 1.1: 7.2 s `user` for 50,000 passes.
- A RAM test (20 MiB, then two 12 MiB processes at once, forcing paging)
  and `patwr` (a 32 MiB file written and checked, 5:00) find no wrong word.
- With the same core at 38.46 MHz: `halt`, then `k2` at the monitor,
  reboots through the self test to `login:`.
- In simulation: the PROM boot, beprobe, rteprobe, nmiprobe, fpuprobe and
  `k2` after sccie all pass.

Clock for clock the core is as fast as the one in the previous reference;
this bitstream is 8% slower because its bus unit no longer meets 43.48 MHz.

Load it as the one below (`unzip`, then `syn/program.tcl` with the `.bit`).

## Previous: `sun3_60_wukong_v3_43MHz_24MiB_cache128k_fpu.zip`

A Sun-3/60 with its **MC68881** on the **QMTech Wukong V3**
(xc7a100tfgg676-**1**), with the updated CPU and FPU cores.

| | |
|---|---|
| Source | commit `a812c48` (branch `cores-update`, merged into master); built from it with no local changes to `rtl/`, `boards/`, `syn/`, the PROM tools or the submodules |
| Submodules | RD68021 `eb346e4`, RD68884 `2dfb1a9`, Wish7990 `8610ef5`, Wish5380 `bde4ef3`, z8530_scc `b9bcd67`, hdmi `83b1c95` (+ `patches/hdmi/0001`) |
| Tools | Vivado 2025.2 |
| Build | `make -C syn bitstream BOARD=v3 CPU=rd68021 CPU_DIV=23 ETH=1 SCSI=1 VIDEO=1 FPU=1 FPU_WAIT=1 MEM_MIB=24 WB_CACHE_IDX=13 ALLOW_PW=1` |
| CPU | RD68021 at 43.48 MHz (1000 MHz / 23), with posted writes |
| FPU | RD68884 (MC68881-compatible) at CpID 1, same-clock bus with one wait state, enabled by EN.FPP |
| Memory | 24 MiB (the 3/60's maximum), FIFO bridge with a 128 KiB read cache |
| PROM | Rev 1.9 + `noparity` (`tools/sun3_60_v1.9_noparity.txt`) |
| Devices | Ethernet (RTL8211EG, 10 Mb/s), on-board SCSI with its disk on the micro-SD card at offset 0, bw2 frame buffer on HDMI (1280x1024@60, 1152x900 centred) |
| Console | ttya: the board's USB serial port, 9600 8N1 (`FB_CONSOLE=0`) |
| Timing | WNS +0.082 ns, WHS +0.035 ns. One known exception, accepted by `ALLOW_PW=1`: the 540.625 MHz HDMI serialiser clock is 0.305 ns over the -1 part's BUFG minimum period |
| Resources | 22,150 LUTs (35%), 11,450 registers (9%), 89.5 of 135 block RAM tiles, 11 DSPs |

SHA-256:

```
a66162b83cb2d466d45fa1141ecdd3cd38872143e3f9690161d9d190d1023daa  sun3_60_wukong_v3_43MHz_24MiB_cache128k_fpu.bit
274d4d6cf44a06016233dcf5bc3be9fcf3f27bb2b7467f52e6e758588a85b138  sun3_60_wukong_v3_43MHz_24MiB_cache128k_fpu.bin
```

**Tested on the board:**
- SunOS 4.1.1 GENERIC boots multi-user from the micro-SD card; fsck is
  clean, `bwtwo0` attaches at 1152x900, the network answers.
- Floating point: the test program gives the same correctly rounded digits
  as before, with gcc 2.3.3 `-m68881` (27.5 s) and Sun `cc -f68881`
  (62.2 s). Whetstone (double precision, gcc 2.3.3 -O -m68881): 1.5 MIPS.
- Dhrystone 1.1: 6.6 s `user` for 50,000 passes (7,576/s).
- A RAM test (two 12 MiB processes at once, then 20 MiB) and `patwr` (a
  32 MiB file written and checked, 4:49) find no wrong word.
- In simulation: the PROM boot, beprobe, rteprobe, nmiprobe, fpuprobe and
  `k2` after sccie all pass.

Slower clock, faster machine: with the new cores this build beats the
previous reference at 45.45 MHz on every test (FP work by 9-14%). The new
RD68021 no longer meets timing at 45.45 MHz in this design (-0.539 ns,
inside the core: its bus unit to its fetch unit).

Load it as the one below (`unzip`, then `syn/program.tcl` with the `.bit`).

## Older: `sun3_60_wukong_v3_45MHz_24MiB_cache128k_fpu.zip`

The same configuration at 45.45 MHz with the earlier cores.

A Sun-3/60 with its **MC68881** on the **QMTech Wukong V3**
(xc7a100tfgg676-**1**).

| | |
|---|---|
| Source | commit `ec139d5` (branch `fpu`, merged into master); built from it with no local changes to `rtl/`, `boards/`, `syn/`, the PROM tools or the submodules |
| Submodules | RD68021 `1b57478`, RD68884 `557e806`, Wish7990 `8610ef5`, Wish5380 `bde4ef3`, z8530_scc `b9bcd67`, hdmi `83b1c95` (+ `patches/hdmi/0001`) |
| Tools | Vivado 2025.2 |
| Build | `make -C syn bitstream BOARD=v3 CPU=rd68021 CPU_DIV=22 ETH=1 SCSI=1 VIDEO=1 FPU=1 FPU_WAIT=1 MEM_MIB=24 WB_CACHE_IDX=13 ALLOW_PW=1` |
| CPU | RD68021 at 45.45 MHz (1000 MHz / 22) |
| FPU | RD68884 (MC68881-compatible) at CpID 1, same-clock bus with one wait state, enabled by EN.FPP |
| Memory | 24 MiB (the 3/60's maximum), FIFO bridge with a 128 KiB read cache |
| PROM | Rev 1.9 + `noparity` (`tools/sun3_60_v1.9_noparity.txt`) |
| Devices | Ethernet (RTL8211EG, 10 Mb/s), on-board SCSI with its disk on the micro-SD card at offset 0, bw2 frame buffer on HDMI (1280x1024@60, 1152x900 centred) |
| Console | ttya: the board's USB serial port, 9600 8N1 (`FB_CONSOLE=0`) |
| Timing | WNS +0.186 ns, WHS +0.033 ns. One known exception, accepted by `ALLOW_PW=1`: the 540.625 MHz HDMI serialiser clock is 0.305 ns over the -1 part's BUFG minimum period |
| Resources | 22,404 LUTs (35%), 11,438 registers (9%), 89.5 of 135 block RAM tiles, 11 DSPs |

SHA-256:

```
634710b363dd6f81ee691f2ff92c7beb40e5ff74dde491d51e0adfeb0f31952b  sun3_60_wukong_v3_45MHz_24MiB_cache128k_fpu.bit
8c3281138f2925613a5c91e91e81c0294785d9c0b64c5d5c1c4945effc353040  sun3_60_wukong_v3_45MHz_24MiB_cache128k_fpu.bin
```

**Tested on the board:**
- SunOS 4.1.1 GENERIC boots multi-user from the micro-SD card; fsck is
  clean, the rc scripts take 40 s, and `bwtwo0` attaches at 1152x900.
- Floating point: a test program (`sqrt`, `sin`, `exp`, a 200,000-term
  sum) gives the correctly rounded results with Sun `cc -f68881` (68.4 s)
  and gcc 2.3.3 `-m68881` (31.6 s), against ~245 s in software.
  Whetstone (double precision, gcc 2.3.3 -O -m68881): 1.3 MIPS.
- Dhrystone 1.1: 6.8 s `user` for 50,000 passes (7,353/s).
- A RAM test (20 MiB, then two 12 MiB processes at once, forcing paging)
  and `patwr` (a 32 MiB file written and checked, 5:15) find no wrong word.
- In simulation, `tools/beprobe/fpuprobe` passes (F-line with EN.FPP
  clear, bit-exact results with it set).
- An earlier build of the same sources (no SCSI, 40 MHz) net-boots NetBSD
  10.1, which reports `fpu: mc68881`.

The same configuration at 43.48 MHz (`CPU_DIV=23`) keeps a 256 KiB cache
with a zero-wait FPU (WNS +0.119 ns) and gives the same results within 3%;
45.45 MHz with the 256 KiB cache fails timing inside the RD68021.

Load it as the one below (`unzip`, then `syn/program.tcl` with the `.bit`).

## Older: `sun3_60_wukong_v3_45MHz_24MiB_cache256k.zip`

Without the FPU.

A Sun-3/60 on the **QMTech Wukong V3** (xc7a100tfgg676-**1**).

| | |
|---|---|
| Source | commit `024acd9` (master, 2026-10-02); the bitstream was built from it with no local changes to `rtl/`, `boards/`, `syn/` or the PROM tools |
| Submodules | RD68021 `e9d1618`, Wish7990 `8610ef5`, Wish5380 `bde4ef3`, z8530_scc `b9bcd67`, hdmi `83b1c95` (+ `patches/hdmi/0001`) |
| Tools | Vivado 2025.2 |
| Build | `make -C syn bitstream BOARD=v3 CPU=rd68021 CPU_DIV=22 ETH=1 SCSI=1 VIDEO=1 MEM_MIB=24 WB_CACHE_IDX=14 ALLOW_PW=1` |
| CPU | RD68021 at 45.45 MHz (1000 MHz / 22) |
| Memory | 24 MiB (the 3/60's maximum), FIFO bridge with a 256 KiB read cache |
| PROM | Rev 1.9 + `noparity` (`tools/sun3_60_v1.9_noparity.txt`) |
| Devices | Ethernet (RTL8211EG, 10 Mb/s), on-board SCSI with its disk on the micro-SD card at offset 0, bw2 frame buffer on HDMI (1280x1024@60, 1152x900 centred) |
| Console | ttya: the board's USB serial port, 9600 8N1 (`FB_CONSOLE=0`) |
| Timing | WNS +0.198 ns, WHS +0.030 ns. One known exception, accepted by `ALLOW_PW=1`: the 540.625 MHz HDMI serialiser clock is 0.305 ns over the -1 part's BUFG minimum period |
| Resources | 18,300 LUTs (29%), 10,536 registers (8%), 104 of 135 block RAM tiles |

SHA-256:

```
ae0b494089473d281f714df9d782f89bd77b8e28888a694bd9bc4de0d87155d2  sun3_60_wukong_v3_45MHz_24MiB_cache256k.bit
0e5efe82879725bcd23b717b2a57ba4af40f89cdfefc60f69125e860db79a18e  sun3_60_wukong_v3_45MHz_24MiB_cache256k.bin
```

**Tested on the board:**
- SunOS 4.1.1 GENERIC boots multi-user from the micro-SD card; fsck is
  clean, the rc scripts take 40 s, and `bwtwo0` attaches at 1152x900.
- The HDMI picture is correct on a bench monitor.
- Dhrystone 1.1 runs in 6.8 s `user` for 50,000 passes (7,353/s).
- A RAM test (20 MiB, then two 12 MiB processes at once, forcing paging)
  and `patwr` (a 32 MiB file written and checked, 5:06) find no wrong word.

The timing margin at this clock is small (0.198 ns): 47.62 MHz fails, in
the RD68021's microcode path. For a margin, rebuild with `CPU_DIV=25`
(40 MHz, WNS +1.225 ns).

**Loading it:**

```sh
unzip sun3_60_wukong_v3_45MHz_24MiB_cache256k.zip
# JTAG (hw_server on localhost:3121, as syn/program.tcl expects):
/opt/Xilinx/2025.2/Vivado/bin/vivado -mode batch -nojournal -nolog \
    -source syn/program.tcl -tclargs sun3_60_wukong_v3_45MHz_24MiB_cache256k.bit
# or the SPI flash: syn/program_flash.tcl with the .bin, as `make -C syn flash` does
```

The bitstream contains Sun Microsystems' boot PROM (Rev 1.9, patched).
