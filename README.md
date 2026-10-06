# Sun-3 FPGA

A replica of a Sun-3/60 ("Carrera") workstation in an FPGA: a 68020-class
CPU, the Sun-3 MMU, the on-board Zilog 8530 SCCs, ICM7170 time-of-day clock,
AMD 7990 (LANCE) Ethernet, NCR 5380 SCSI and the monochrome bw2 frame buffer,
booting Sun's real boot PROM.

It runs on two FPGA boards from two vendors, from one vendor-neutral `rtl/`
tree:

* the **QMTech Wukong** (Xilinx Artix-7 XC7A100T, 256 MiB DDR3), built with
  Vivado;
* the **Arrow DECA** (Intel MAX 10 10M50, 512 MB DDR3), built with Quartus.

Everything board-specific lives in `boards/<name>/` and `syn/`. The structure
follows the sibling Sun-2 project, whose design decisions it largely reuses.

## What it does

On real hardware, with the RD68021 CPU core (`CPU=rd68021`):

* **SunOS 4.1.1 boots multi-user** from a disk image on a micro-SD card
  standing in for the SCSI disk: fsck, the rc daemons, `login:`, a working
  `cc`, networking (ping, telnet, rsh) on a 10 Mb/s link.
* **The bw2 frame buffer on HDMI**: the 1152x900 screen, centred in a
  1280x1024@60 signal. The console can be on serial (default) or on the
  screen, with input still taken from serial (there is no keyboard).
* **NetBSD/sun3** net-boots its RAMDISK kernel. With the optional MC68881
  (`FPU=1`) it reports `fpu: mc68881` and reaches the installer's shell;
  without it userland stops for lack of an FPU.
* **Up to 24 MiB of memory**, the 3/60's maximum.
* A memory path with posted writes and an 8 KiB read cache: Dhrystone 1.1
  runs at 5,376/s on the Wukong at 33.33 MHz and 2,660/s on the DECA at
  16.667 MHz.

| | Wukong V3 | Wukong V1 | DECA |
|---|---|---|---|
| CPU clock (RD68021) | up to 33.33 MHz | 20 MHz | 16.667 MHz |
| PROM to monitor | yes | yes | yes |
| SunOS 4.1.1 from micro-SD | yes | no SD slot | yes |
| Ethernet | yes | yes | yes |
| HDMI display | yes (see below) | not tried | yes |

In simulation (Vivado xsim) the PROM passes its self tests and reaches the
monitor prompt on both CPU cores; unit tests cover the memory bridge, the
cache, the DDR3 adapters, the scan-out and the board glue.

## Getting started

Requirements: Vivado 2025.2 (`/opt/Xilinx/2025.2/Vivado`, or set
`XILINX_VIVADO`) for the Wukong and for simulation; Quartus Prime 25.1 Lite
(`/opt/Altera/quartus`, `QUARTUS_ROOTDIR`) for the DECA; a C compiler for the
PROM tools; optionally `m68k-linux-gnu-gcc` for the test programs in
`tools/beprobe/`.

```sh
git submodule update --init      # third-party cores and documents, in Inputs/
make -C tools                    # unpack and patch the boot PROMs into build/rom/
make -C sim xsim CPU=rd68021     # simulate the machine to the PROM's ">" prompt
make -C sim check CPU=rd68021    # ... and check its console log
```

Everything generated goes to `build/`.

### The DECA

```sh
make -C syn bitstream BOARD=deca ETH=1 SCSI=1 VIDEO=1
make -C syn program   BOARD=deca ETH=1 SCSI=1 VIDEO=1
tools/deca_console_pty.sh &                  # the console, as /tmp/deca-console
```

The DECA has no serial port: the console goes over the USB-Blaster II's JTAG
UART, which `tools/deca_console_pty.sh` turns into a pseudo-terminal.
`tools/deca_reset.tcl` (through `syn/altera.sh quartus_stp`) resets the
machine, sends a BREAK and shows the board's status.

### The Wukong

```sh
make -C syn ip BOARD=v3                      # generate the DDR3 controller once
make -C syn bitstream BOARD=v3 CPU=rd68021 CPU_DIV=30 ETH=1 SCSI=1 VIDEO=1 ALLOW_PW=1
make -C syn program   BOARD=v3 CPU=rd68021 CPU_DIV=30 ETH=1 SCSI=1 VIDEO=1
```

The console is the board's USB serial port (`/dev/ttyUSB0`, 9600 8N1);
`tools/board_console.py` reads and types at it. `CPU_DIV=30` gives 33.33 MHz.
`ALLOW_PW=1` is needed with `VIDEO=1` on the V3 (-1 speed grade): the HDMI
serialiser's 540 MHz clock is slightly over its clock buffer's rating. It
works on the bench monitor regardless.

### Build options

| knob | default | |
|---|---|---|
| `BOARD` | `v1s1` | `v1s1`, `v1`, `v3` (Wukong) or `deca` |
| `CPU` | `suska` (Wukong), `rd68021` (DECA) | `rd68021` is the core of interest |
| `CPU_DIV` | 56 (Wukong), 60 (DECA) | CPU clock = 1000 MHz / `CPU_DIV` |
| `ETH` | 0 | the on-board Ethernet |
| `SCSI` | 0 | the on-board SCSI, its disk on the micro-SD (V3, DECA) |
| `DISK_OFF_MIB` | 0 | where on the card the disk image starts |
| `VIDEO` | 0 | the bw2 on HDMI |
| `FB_CONSOLE` | 0 | the console on the screen (needs `VIDEO=1`) |
| `MEM_MIB` | 16 | main memory, up to 24 |
| `FPU` | 0 | the MC68881 (RD68884), with `CPU=rd68021` |
| `FPU_MODEL` | 68881 | 68882: the MC68882 (RD68885) instead |
| `ROM_VER` | 1.9 | boot PROM revision (see below) |
| `WB_FIFO`, `WB_CACHE` | 1, 1 | the FIFO memory bridge and its read cache |

Every option is part of the output directory's name, so builds with different
options do not overwrite each other.

## The disk

The SCSI disk is a raw SunOS disk image written to the micro-SD card (at
`DISK_OFF_MIB` MiB into it). SunOS 4.1.1's GENERIC kernel boots from it as
`sd(0,0,0)`; root has no password. SunOS's console getty uses 7 data bits with
even parity: mask bit 7 on the host side.

**Always `sync` and `halt` SunOS before reprogramming the FPGA**: loading a
bitstream is a power cut to the disk.

## Boot PROMs

The stock Sun-3/60 PROMs (Rev 1.9, 2.8.3, 3.0.1) test parity memory, which
this design does not have, so each is patched (`tools/rompatch`, which checks
every word it changes): `ROM=noparity` is the minimum, and the default for
hardware.

**Use Rev 1.9** (the default). Rev 3.0.1 boots SunOS too, but its screen
output does not work here: with the console on serial it never enables the
display (black screen), and with the console on the screen the display turns
white but nothing is drawn. Rev 1.9 works in both cases.

## Known limitations

* **The FPU is optional** (`FPU=1`, RD68021 only): RD68884, an MC68881, at
  CpID 1. Without it NetBSD's userland stops; with it NetBSD finds
  `fpu: mc68881` and boots on. Not yet on the DECA (block RAM).
* **No keyboard or mouse.** The console input is the serial line (or the
  network).
* **Suska core** (`CPU=suska`): the PROM boots to its monitor, but NetBSD
  panics in `copyout` (a restart-model limitation of the core) and SunOS has
  not been tried; the RD68021 is the core of interest.
* On the Wukong, the HDMI output on a V1 has not been tried.

## Layout

| path | contents |
|---|---|
| `rtl/sun3/` | the machine, vendor-neutral: CPU wrapper, MMU, control space, devices, memory bridges, scan-out |
| `boards/Wukong/`, `boards/DECA/` | clocks, DDR3 adapters, console, HDMI, pins glue per board |
| `syn/` | Vivado and Quartus flows, constraints, pin files |
| `sim/`, `tb/` | xsim scripts and testbenches |
| `tools/` | PROM preparation, console and debug tools, test programs |
| `patches/` | patches applied to copies of third-party inputs |
| `Inputs/` | third-party cores and reference documents (git submodules), never edited |
| `ref_bitstreams/` | tested reference bitstreams, zipped, with how they were built |
| `build/` | everything generated |

`ref_bitstreams/` keeps tested bitstreams with their provenance (commit,
options, test results), so a board can be brought up without a toolchain.

`CLAUDE.md` is the detailed engineering log: every design decision, measured
result, debugging aid and trap found along the way.

## Third-party components

Under `Inputs/`, each under its own licence: the RD68021 and Suska
(WF68K30L) 68020/68030 cores, the z8530_scc SCC, Wish7990 (LANCE) and
Wish5380 (NCR 5380 and SD-card block device), BrianHG's DDR3 controller (DECA),
hdl-util's HDMI encoder (Wukong), board documentation from QMTech and the DECA
project, and a QEMU Sun-3 model used as a reference, whose archive also
supplies the boot PROM images (Sun Microsystems'; this repository only
patches copies of them).
