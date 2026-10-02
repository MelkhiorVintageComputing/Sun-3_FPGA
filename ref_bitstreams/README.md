# Reference bitstreams

Known-good bitstreams, kept so a board can be brought up without a toolchain,
and so later changes can be compared against something that was tested.
Each `.zip` holds the `.bit` (JTAG), the `.bin` (SPI flash) and their
`SHA256SUMS`.

## `sun3_60_wukong_v3_45MHz_24MiB_cache256k.zip`

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
