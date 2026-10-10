# Reference bitstreams

Known-good bitstreams, kept so a board can be brought up without a toolchain,
and so later changes can be compared against something that was tested.
Each `.zip` holds the `.bit` (JTAG), the `.bin` (SPI flash) and their
`SHA256SUMS`.

## `sun3_60_wukong_v3_40MHz_24MiB_cache128k_fpu.zip`

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

Clock for clock the core is as fast as RD68021 eb346e4, whose reference
bitstream ran at 43.48 MHz (still in git history); this one is 8% slower
because the reworked bus unit no longer meets that clock.

**Loading it:**

```sh
unzip sun3_60_wukong_v3_40MHz_24MiB_cache128k_fpu.zip
# JTAG (hw_server on localhost:3121, as syn/program.tcl expects):
/opt/Xilinx/2025.2/Vivado/bin/vivado -mode batch -nojournal -nolog \
    -source syn/program.tcl -tclargs sun3_60_wukong_v3_40MHz_24MiB_cache128k_fpu.bit
# or the SPI flash: syn/program_flash.tcl with the .bin, as `make -C syn flash` does
```

The bitstream contains Sun Microsystems' boot PROM (Rev 1.9, patched).
