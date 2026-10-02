# Sun-3 FPGA replica

A Sun-3/60 ("Carrera") rebuilt in an FPGA, targeting the QMTech Wukong V1
(XC7A100T, 256 MiB DDR3) and the Arrow DECA (MAX 10 10M50, 512 MB DDR3).
The sibling project `../Sun-2_FPGA` does the same for a Sun-2 on the same
two boards; its structure, scripts and conventions are reused here. Read, never modify, anything in it.

## Status

Step 1 (done): a core-level simulation (`tb/tb_sun3.sv`) with
testbench-supplied clocks and a behavioural Wishbone RAM, booting the stock
3/60 PROM (Rev 1.9 + noparity) to the monitor prompt, on both cores (Suska,
RD68021) and with or without `ETH=wish7990`.

Step 2 (done): the QMTech Wukong V1 board layer (`boards/Wukong/`, `syn/`),
adapted from the Sun-2 project: MMCM clocks, the Wishbone to MIG DDR3 path,
reset held until MIG calibrates, pins. On the board both cores boot the stock
PROM to the monitor (UART `/dev/ttyUSB0`, 9600 8N1): Suska at 17.857 MHz,
RD68021 at 20 MHz, 16 MiB of DDR3. In simulation: the board top boots to `>`
(`make -C sim board`, 2045.6 ms with 10 wait states), and MIG calibrates at
125.3 us with Micron's model (`BOARD_MEM=ddr3`). Not yet: ETH=1, SCSI, a
screen.

Step 3 (in progress): Ethernet and an operating system. With `ETH=1` the
board net-boots: RARP, the PROM's TFTP load of NetBSD/sun3's netboot, then
netboot loads NetBSD 10.1's RAMDISK kernel over NFS. The kernel boots on
both cores ("Model: sun3 60", 16 MB, `le0` on the Wish7990, zs, clock,
memerr, intreg), mounts its RAM disk and starts `init`:
- RD68021: user processes ran, then one resumed at address 0 after an
  instruction-fetch page fault (RTE of a format $B frame with RB/RC set) --
  a core problem, reported upstream
  (`RD68021-RTE-format-B-rerun-resumes-at-zero.md`, not committed) and
  fixed in 33d9289. `tools/beprobe/rteprobe.S` reproduces it in
  simulation: 8707c04 ends at PC 0, 33d9289 passes. On the board with
  33d9289, user processes run until `pid 52 killed: no floating point
  support` at 10.35 s, as in the zero-latency simulation.
- Suska: `panic: copyout 14` at the first copyout to `init`'s stack. The
  glue presents the fault right; the core pushed a special status word
  describing the next prefetch (SSW 0x0046: DF clear, read, FC 6), so
  locore took it for an instruction fault. `patches/Suska_Configware/0001`
  fixes the SSW. What remains is the core's own design: its RTE restarts
  the instruction rather than rerunning the cycle, and a `(An)+` has
  already incremented, so a copyin/copyout fault would lose a byte. Not
  pursued: RD68021 is the core of interest.
- Next blocker, on both simulation and board: the FPU. A 3/60 has an
  MC68881 ("fpu: no math support" at boot), and NetBSD's userland uses it.
  Still to do.

Step 4 (in progress): the Arrow DECA (`boards/DECA/`, `syn/quartus.tcl`),
ported from the Sun-2 project's DECA layer. RD68021 only (Suska does not
fit). On the board at 16.667 MHz: DDR3 calibrates, the stock PROM
(noparity) boots to `>` with "16MB memory installed" on the JTAG console,
`h`, DDR3 write/read-back and the Invalid Page bus error past 16 MB all as
on the Wukong. With `ETH=1` (DP83620) NetBSD net-boots to the same FPU
stop as on the Wukong.

Step 5 (done): the 3/60's on-board SCSI (`rtl/sun3/sun3_si.sv`,
`SUN3_SCSI`), its disk on the DECA's micro-SD. **SunOS 4.1.1 GENERIC boots
multi-user from the card** (fsck of `sd0a`/`sd0g`, the rc daemons, `sun3
login:`; root has no password). SunOS's getty runs the console at 7 bits +
even parity: strip bit 7 on the host. `sync` and `halt` before reprogramming
the FPGA, which is a power cut to the disk. In simulation the PROM boots
`sd(0,0,0)` from the SunOS 4.1.1 image (`tb/blk_file.sv`); on the DECA
(`ETH=1 SCSI=1`, 16.667 MHz) the PROM loads SunOS 4.1.1 from the card, whose
kernel probes `si0 at obio 0x140000 pri 2` and `sd0: <SUN300 cyl 2398 alt 2
hd 16 sec 16>`, then stopped with `Exception 0x7C at 0E09C19A` (in `idle`):
the RD68021 took the monitor clock's level-7 interrupt twice when it came out
of STOP, and the outer handler found the clock's status cleared by the inner
one. Reported upstream (`RD68021-level-7-from-STOP-taken-twice.md`, not
committed) and fixed there in e9d1618; `nmiprobe` checks it.
On the Wukong V3 (micro-SD slot J9, `BOARD=v3 CPU=rd68021 CPU_DIV= ETH=1
SCSI=1`, 20 MHz, WNS +1.276 ns) the same card boots SunOS 4.1.1 multi-user,
`le0` up at 192.168.0.121. Dhrystone 1.1 (`user` time, 50000 passes):
1,488/s on the DECA at 16.667 MHz, 1,529/s on the Wukong at 20 MHz -- the
memory path, not the clock, sets the pace; `-DREG=register` changes
nothing (`cc -O` already allocates registers).
The RD68021 on the V3 (-1) goes well past 20 MHz (`CPU_DIV`, VCO 1 GHz);
each row booted SunOS from the card, answered pings and ran a clean
`patwr` pass (32 MiB file on `/usr`, 0 of 16,777,216 words wrong):

| clock | `CPU_DIV` | CPU clock WNS / WHS | Dhrystone 1.1 (`user`) | `patwr` |
|---|---|---|---|---|
| 20 MHz | (none) | (+1.28 overall) | 1,529/s | 14:56 |
| 25 MHz | 40 | +3.557 / +0.052 ns | (built, not run) | |
| 31.25 MHz | 32 | +1.930 / +0.056 ns | 2,083/s | 10:51 |
| 33.33 MHz | 30 | +1.666 / +0.035 ns | 2,165/s | 10:25 |

The design's worst path (+1.276 ns) is outside the CPU clock throughout.

Step 6 (done, merged from branch `fifo-bridge`): the FIFO memory bridge
with its 8 KiB read cache is **the default** (`WB_FIFO=1`, and `WB_CACHE`
follows `WB_FIFO`), on both boards, in simulation and in the synthesis
flows. `WB_FIFO=0` gives back the synchronous bridge; `WB_CACHE=0` the FIFO
bridge without the cache. Both stay buildable for comparison. The FIFO
bridge (`SUN3_WB_FIFO`) is ported from the Sun-2 project. The default Wukong build (Suska, V1, 17.857 MHz) meets timing with
it: WNS +0.931 ns, against +0.62 ns with the synchronous bridge.
`rtl/sun3/sun3_fifo_bridge.v` replaces `sun3_wishbone_bridge` with:
- a request FIFO `{tag, we, adr, dat, sel}` and a response FIFO
  `{tag, dat}` carrying reads only (`sun3_async_fifo.v`, gray pointers);
- writes acknowledged the clock after they are queued, reads on the answer
  carrying their tag (any other answer at the head is dropped);
- one in-order queue for every master (CPU and DVMA all come through
  `MATCH_MEM`/`MATCH_FB`), so a read sees every write queued before it.

The Wishbone side runs in the memory controller's clock, behind adapters
with no crossing: `wb_mig_sync` on MIG's `ui_clk` (Wukong) and
`deca_wb_ddr3_sync` on `CMD_CLK` (DECA).

Checked: the unit tests `asyncfifo`, `fifobridge` (2800 checks; dropping
the tag comparison fails 4) and `decaddr3sync`; the PROM to `>` on both
cores; the board tops (Wukong, DECA); beprobe, rteprobe and nmiprobe.

On the V3 at 33.33 MHz (`CPU_DIV=30 ETH=1 SCSI=1`): SunOS 4.1.1
multi-user from the card. CPU clock WNS +1.871 ns, against +1.666 ns
without the FIFO bridge. The same card and binaries give:

| V3, 33.33 MHz | `WB_FIFO=0` | `WB_FIFO=1` | `WB_FIFO=1 WB_CACHE=1` |
|---|---|---|---|
| Dhrystone 1.1 (`user`, 50000) | 23.1 s, 2,165/s | 21.7 s, 2,304/s | 9.3 s, 5,376/s |
| `patwr pat.dat 0 65536 1` (32 MiB, 0 wrong) | 10:25 | 9:49 | 5:55 |
| `dd` 32 MiB /dev/zero to /dev/null | 25.3 s sys | 23.2 s sys | 10.9 s sys |
| `dd` 32 MiB write to `/usr` (+`sync`) | 63.1 s sys, 3:50 | 57.2 s sys, 3:46 | 27.3 s sys, 3:42 |
| `dd` 32 MiB read back | 34.9 s sys, 0:54 | 30.1 s sys, 0:53 | 17.4 s sys, 0:49 |
| CPU clock WNS | +1.666 ns | +1.871 ns | +1.393 ns |

With a 32 KiB cache (`WB_CACHE_IDX=11`): 41.5 of 135 BRAM tiles (35 at
8 KiB), CPU clock WNS +0.926 ns (now the design's worst path). In the
PROM boot no lookup was refused, so the page-map bits (index bits 13-14)
arrive a clock before `MATCH_MEM` and hits still cost nothing. On the board
it gains little over 8 KiB:
- Dhrystone 9.3 s `user`, unchanged (it fits in 8 KiB);
- `patwr` 5:54, 0 wrong;
- `dd` 10.4 / 26.0 / 17.0 s sys;
- the rc scripts 47 s against 50 s.

The read cache (`WB_CACHE=1`, `SUN3_WB_CACHE`, size `WB_CACHE_IDX`,
default 9) is `rtl/sun3/sun3_cached_fifo_bridge.v`, from the Sun-2's:
- direct-mapped, 2**IDX lines of 16 bytes; write-through, no-allocate;
- in front of the FIFOs, so one cache for every master (DVMA included);
- the response FIFO carries a whole 128-bit line (`wb_line_i`: MIG's beat,
  BrianHG's line, `wb_ram_model`'s), installed only from the answer the
  bridge is waiting for;
- frame-buffer cycles are never cached.

A hit costs no wait. The RAMs are read every clock, and the index is the
line within the page: up to IDX 9 (8 KiB, the Sun-3 page) that is the
CPU's own A[12:4], on the bus long before `MATCH_MEM`. Only the tag
(physical page, from the MMU) is compared, combinationally, in the clock
`MATCH_MEM` rises; a hit acknowledges in that clock. A larger IDX takes
index bits from the page map: its lookups are guarded (a refused lookup is
a miss, or an invalidation for a write) and counted. In simulation, at
IDX 9, no lookup is ever refused. The PROM boot gives 500,198 read hits
for 422 misses (RD68021), and `make -C sim board` reaches `>` at 837 ms
against 1,038 ms without the cache.

Unit test `make -C sim cachedbridge`: 50 checks against a bus-level shadow
of memory, including a physical page arriving only with `MATCH_MEM`. Each
of three mutations fails it: no tag compare, installing any answer, no
index guard.

On the V3 with the cache, SunOS boots from the card (fsck clean; the rc
scripts take 50 s against 65 s), and Dhrystone runs 2.3x faster than with
the FIFO bridge alone.

DECA builds, 16.667 MHz, ETH+SCSI:
- `WB_FIFO=1`: WNS +0.804 ns, 38,885 LE, 140 of 182 M9K, CPU Fmax
  23.42 MHz;
- `WB_CACHE=1` (8 KiB): WNS +0.854 ns, 39,622 LE (80%), 157 M9K, CPU Fmax
  23.63 MHz; its board simulation reaches `>`.

On the DECA itself, the same card and binaries; every build boots SunOS
multi-user, fsck clean:

| DECA, 16.667 MHz | `WB_FIFO=0` | `WB_FIFO=1` | `WB_FIFO=1 WB_CACHE=1` |
|---|---|---|---|
| Dhrystone 1.1 (`user`, 50000) | 33.5 s, 1,493/s | 30.4 s, 1,645/s | 18.8 s, 2,660/s |
| `patwr` (32 MiB, 0 wrong) | 15:48 | 14:24 | 9:54 |
| `dd` /dev/zero to /dev/null | 37.4 s sys | 33.2 s sys | 21.5 s sys |
| `dd` write to `/usr` | 97.8 s sys, 4:13 | 87.4 s sys, 4:08 | 54.3 s sys, 4:04 |
| `dd` read back | 57.0 s sys, 1:17 | 23.8 s sys, 1:06 | 32.0 s sys, 1:06 |
| rc scripts (boot) | 90 s | 85 s | 67 s |

The read-back `sys` times are noisy: the run is mostly waiting on the card.

Step 7 (done, merged from branch `framebuffer`): the 3/60's bw2 on HDMI (`VIDEO=1`,
`SUN3_VIDEO`), ported from the Sun-2 project. **On the DECA the screen
works** ("looks perfect" on the bench monitor), and SunOS 4.1.1 boots with
it (`bwtwo0 at obmem 0xff000000 pri 4`, `resolution 1152 x 900`).
- `rtl/sun3/fb_scanout.sv`: a ping-pong line buffer (one M9K/BRAM),
  9 beats a line, read from DDR3 at byte 0x0FE00000 (the bridges' bw2
  window). VESA 1280x1024@60 with the 1152x900 screen centred (64 x 62
  border). 1 = black; the border, and the whole screen while EN.VIDEO
  (System Enable bit 3, `fb_video_en`) is off, are black.
- The bit order differs from the Sun-2: the 68020 bus and bridges are
  32-bit big-endian, so pixel p of a 128-bit beat is bit `{p[6:5],
  ~p[4:0]}` (the Sun-2's 16-bit bridge needed `{p[6:4], ~p[3:0]}`).
- The vertical blanking drives `V_INT` (level 4, Architecture Manual
  5.3.4), synchronised in `sun3_fpga`.
- The EEPROM's monitor byte (0x016) is now 0x00, 1152x900 (it was 0x20,
  1280x1024, a LiteX leftover). The console stays on ttya;
  `FB_CONSOLE=1` (`SUN3_FB_CONSOLE`, needs `VIDEO=1`) moves the output
  to the screen; with no keyboard the PROM says "No keyboard found: Using
  RS232 Port A as input!", so input stays on ttya (seen in simulation,
  `make -C sim xsim CPU=rd68021 DEFINES=SUN3_FB_CONSOLE XSIMARGS=
  "-testplusarg fb_dump"`, then `tools/fbshot`: logo, banner and `>`
  render correctly). On the DECA (`VIDEO=1 FB_CONSOLE=1`) SunOS 4.1.1
  does the same: boot messages, `login:` and the shell on the monitor,
  typed into from ttya (serial shows nothing; `who` lists `root console`),
  and the machine reachable by telnet. Halt it over telnet or by typing
  `sync; sync; halt` blind on serial.
- DECA: `deca_vidclk` (4th PLL, 108.000 MHz), `video_timing`,
  `deca_hdmi_out` (clock inverted for the ADV7513), `deca_adv7513_init`
  (I2C, DVI mode), the scan-out on BrianHG port 1 behind the
  level-to-strobe adapter. Pins in `deca_pins.qsf` (always assigned, idle
  without the knob), timing in `deca_video.sdc` (read only with it). ISSP
  shows `hdmi: adv7513 cfg_done/nak`. ETH+SCSI+VIDEO: 40,879 LE (82%),
  161 of 182 M9K, WNS +0.505 ns, pixel clock Fmax 154 MHz.
- Wukong: `hdmi_clkgen` (3rd MMCM, 108.125 / 540.625 MHz), hdl-util's
  `hdmi` (`Inputs/hdmi`, VIC 127 from `patches/hdmi/0001`, DVI), the
  scan-out on `mig_arb` client 1, pins and clock group in
  `syn/wukong_hdmi.xdc`, a netlist check for `hdmiclk`. On the V3 (-1) the
  540.625 MHz serialiser clock is 0.305 ns over the BUFG's minimum period:
  the build needs `ALLOW_PW=1` (otherwise WNS +0.611 ns). **It works on
  the bench monitor regardless** (`BOARD=v3 CPU=rd68021 CPU_DIV=30 ETH=1
  SCSI=1 VIDEO=1 ALLOW_PW=1`, 33.33 MHz): picture right, SunOS boots from
  the card with `bwtwo0`, and with `FB_CONSOLE=1` the screen console
  behaves as on the DECA.
- Tests: `make -C sim scanout` (every pixel of a frame against a pattern
  written from the Architecture Manual, the border, 900*9 beats a frame,
  EN.VIDEO blanking; the Sun-2 pixel order or the opposite polarity fail
  it), `vtiming`, `adv7513`. `tb_sun3 +fb_dump` (`+fb_dump_ms=<t>`) writes
  the window, `tools/fbshot` renders it through `fb_scanout` to a PNG.

Memory: a 3/60 takes at most 24 MiB (the PROM's sizing goes wrong above
that). `MEM_MIB=24` works on the V3 (33.33 MHz, ETH+SCSI+VIDEO, WNS
+0.789 ns): the PROM reports "24MB memory installed", SunOS sees `mem =
24576K` (23.5 MB available), and a RAM test (20 MiB in one process, then
two 12 MiB processes at once, forcing paging) finds no wrong word. The bw2
window sits at 254-256 MiB of DDR3, far above main memory. Careful when
writing such a test with SunOS's `cc -O`: a pattern like `i * 69069`
overflows a 32-bit long, and the optimiser's strength-reduced loop then
stops early, which reads back as zeros and looks like a memory fault.

## Commands

| command | what |
|---|---|
| `make -C tools` | unpack and checksum the PROMs, build the patched variants and the Verilog includes in `build/rom/` |
| `make -C tools check` | the noparity patch list reproduces the Old RomPatcher image bit for bit |
| `make -C sim xsim` | compile, elaborate and run `tb_sun3` under xsim; stops on the `>` prompt |
| `make -C sim board` | the board top (`tb_wukong` + `wukong_top`), behavioural clocks and a Wishbone RAM with `BOARD_LATENCY` (10) wait states; `BOARD_MEM=ddr3` for the real MIG + Micron model instead (calibration and first accesses only: far too slow to boot) |
| `make -C sim board-check` | as `check`, for the last board run |
| `make -C syn ip` | generate MIG from `syn/mig/sun3_mig.prj` into `build/ip/<BOARD>/` |
| `make -C syn bitstream` | Vivado non-project build into `build/syn/vivado/<tag>/`; fails on negative WNS/WHS or a pulse-width violation. Knobs: `BOARD` (v1s1), `CPU`, `ETH` (0), `SCSI` (0), `WB_FIFO` (1), `WB_CACHE` (= `WB_FIFO`), `WB_CACHE_IDX` (9), `MEM_MIB` (16), `ROM` (noparity), `CPU_HZ` (20 MHz), `CPU_DIV` |
| `make -C syn program` / `flash` | JTAG / SPI flash, same knobs (`HW_URL`, default localhost:3121) |
| `make -C sim check` | grep that run's `console.log` for a good boot (self test, banner, `MEM_MIB` MB installed, prompt). **Does not run anything**: rerun `xsim` first |
| `make -C syn bitstream BOARD=deca` | the DECA under Quartus (`syn/quartus.tcl`) into `build/syn/quartus/<tag>/sun3.sof`; fails on negative slack (`ALLOW_NEG=1`). Defaults `CPU=rd68021 CPU_DIV=60`; extra knobs `CPU_DUTY`, `BUS_TRACE`, `SEED` |
| `make -C syn program BOARD=deca` | JTAG through the on-board USB-Blaster II (no flash: the board is JTAG-only) |
| `make -C syn lint BOARD=deca` | Quartus analysis & synthesis of `sun3_top` alone |
| `make -C sim board BOARD=deca CPU=rd68021` | `tb_deca` + `deca_top`, behavioural clocks and RAM, the JTAG UART modelled (`jtag.log` must equal `console.log`) |
| `make -C sim decaddr3` / `decaconsole` | unit tests: the DDR3 adapter against BrianHG's command port, the console bridge against the JTAG UART |
| `make -C sim asyncfifo` / `fifobridge` / `cachedbridge` / `decaddr3sync` | unit tests of `WB_FIFO=1`: the dual-clock FIFO, the FIFO bridge (posted writes, tags, lanes, against 83 and 7 MHz Wishbone clocks), its read cache against a shadow of memory, the DECA's crossing-free adapter |
| `make -C sim xsim CPU=rd68021 SCSI=1 XSIMARGS="-testplusarg blk_image=$PWD/build/disk/sunos411-sun3.img"` | with the on-board SCSI and a file as its disk (`tb/blk_file.sv`, first 32 MiB loaded). Always a copy in `build/disk/`, never the original image. Use `STOP_ON` other than `>` past the PROM: the disk label `<SUN300 ...>` has one |
| `make -C syn bitstream BOARD=v3 CPU=rd68021 CPU_DIV= ETH=1 SCSI=1 [DISK_OFF_MIB=n]` | the Wukong V3 with SCSI, its disk in the micro-SD slot (`syn/wukong_sd_v3.xdc`; a V1 has no slot and is refused) |
| `make -C syn bitstream BOARD=deca ETH=1 SCSI=1 VIDEO=1` | the DECA with the bw2 on its HDMI port (1280x1024@60) |
| `make -C syn bitstream BOARD=deca ETH=1 SCSI=1 [DISK_OFF_MIB=n]` | the DECA with SCSI, the disk at n MiB into the micro-SD (`tools/deca_reset.tcl` shows `disk: ready`, size) |

`sim/Makefile` knobs: `CPU=suska|rd68021`, `ROM=fast|noparity|pristine`,
`ROM_VER=1.9|2.8.3|3.0.1` (`noparity`: 1.9 and 3.0.1; `fast`: 1.9 only), `MEM_MIB`,
`ETH=none|wish7990`, `MEM_LATENCY`, `CPU_HZ`, `BAUD`, `TIMEOUT_MS`,
`STOP_ON`, `DIAG`, `DEFINES`, `XSIMARGS`, `SCSI`, `WB_FIFO`, `WB_CACHE`, `WB_CACHE_IDX` (also for `board`); with the cache the run ends with a `[cache]` line (hits, misses, refused lookups, fills).

Bring-up aids in `tb_sun3`:
- `DIAG=1` (`+diag`) turns the diag switch on. The PROM then prints each
  self test on ttya; with it off the self test is **silent** (the print
  routine at 0x0FEF2F18 does nothing) and the memory test is skipped.
- `+trace_from_ms=<t> +trace_until_ms=<t>` (via `XSIMARGS`) logs every bus
  cycle in that window to `trace.txt`: FC, R/W, address, size, how it ended
  (ack / BERR), data, physical address. `+trace_io` leaves out PROM and main
  memory cycles, so a long window stays small. It samples on rising edges
  only, so with the RD68021 (both edges) the "ack"/data columns are not
  reliable.
- `+watch_from_us=<t> +watch_until_us=<t>` prints AS/DS/RW/FC/A/data, the
  `C_Sn` windows, WR/RD, DSACK and BERR 1 ns after every clock edge, i.e.
  what each edge left behind: for strobe timing.
- A run with no bus cycle for `+stall_ms` (default 100) ends with the bus
  state. It is not 1 ms, because the RD68021's instruction cache runs tight
  loops with no bus cycles at all.
- `+load=<file>@<hexaddr>` loads a binary into memory once the PROM is at
  its prompt, `+type=g_4000` (`_` for a space) types a line there (`+type2=k2` a second line at the next prompt), and
  `+keep_running` runs on to the timeout: that is how a NetBSD kernel
  (`objcopy -O binary` of the ELF, at 0x4000) is simulated from the monitor.
- `+berr_log` writes every bus error to `berr.txt` (FC, address, bus error
  register bits, PTE); `+pc_sample_ms=<t>` the last program fetch every
  <t> ms to `pcsample.txt`. `MEM_FILL=ffffffff` makes never-written memory
  read as the PROM's fill leaves it on a real machine.
- LED (diag register) changes are printed with a timestamp; a CPU that
  makes no bus cycle for 1 ms ends the run with its bus state.

Running the same configuration twice at once is not possible (same run
directory); a different `ROM` gives a separate one. Each configuration gets its own run
directory `build/sim/xsim-<tag>/` (with `console.log`), and its full
transcript is `build/sim/xsim-<tag>.log`.

Vivado 2025.2 is at `/opt/Xilinx/2025.2/Vivado` and is not on `PATH`; the
scripts find it there (override with `XILINX_VIVADO`). Speed: roughly 100 ms
of simulated time per minute at 20 MHz with the Suska core.

## Layout

| path | contents |
|---|---|
| `rtl/sun3/` | the machine, vendor-neutral: `sun3_top.v` (CPU + system), `sun3_fpga.v` (MMU, control space, OBIO devices, bus glue), `sun3_config.vh` (every build knob) |
| `tb/` | `tb_sun3.sv`, `wb_ram_model.sv`, `uart_monitor.sv`, `uart_console.sv` (the last three from Sun-2) |
| `sim/` | `Makefile`, `run_xsim.sh`, `compile_cpu.sh`, `check_console.sh` |
| `boards/DECA/` | the DECA's board layer, from the Sun-2 project: `deca_top.sv`, `deca_clkgen.sv` (two altpll), `deca_wb_to_ddr3.sv` (Wishbone -> BrianHG, clock crossing), `deca_jtag_console.sv` + `deca_uart_{rx,tx}.sv`, `phy_dp83620_init.sv` |
| `boards/Wukong/` | vendor-specific board layer: `wukong_top.sv`, `wukong_clkgen.sv` (two MMCMs), `wb_to_mig_ui.sv` (Wishbone -> MIG, clock crossing), `mig_arb.sv`, `phy_rtl8211_init.sv` (all from Sun-2) |
| `syn/` | Vivado flow: `Makefile`, `build.tcl`, `generate_ip.tcl`, `boards.tcl`, `program*.tcl`, `mig/sun3_mig.prj`, XDCs (`wukong_<rev>.xdc`, `wukong_common.xdc`, `wukong_eth.xdc`, `wukong_wbcdc.xdc`) |
| `tools/` | `rom.c` (binary → Verilog case body), `rompatch.c` (verified word patches + Sun-3 checksum fix-up), patch lists, `patch_inputs.sh` |
| `patches/<Input>/` | patches against `Inputs/`, applied to copies in `build/inputs/` |
| `build/` | everything generated; gitignored |
| `Inputs/` | immutable third-party and reference material. Third-party repositories are git submodules (`git submodule update --init`): Suska_Configware, z8530_scc, RD68021, Wish7990, Wish5380, hdmi, BrianHG-DDR3, `doc/QM_XC7A100T_WUKONG_BOARD`, `doc/DECA_board`, `doc/MC68030_Doc_More_Readable`, `ref/qemu-sun3`; loose documents are plain files |
| `Old/` | the previous (LiteX) implementation; never in git, never modified |

## Conventions

- **`Inputs/` is immutable.** Never edit in place. A needed change is a patch
  in `patches/<name>/`, applied by `tools/patch_inputs.sh` to a copy under
  `build/inputs/`; the simulation compiles from those copies. The PROMs work
  the same way: `rompatch` writes patched images into `build/rom/` and checks
  every word it changes.
- **`Old/` is copied from, never referenced or changed.**
- **`rtl/` has no vendor primitive or IP.** Vendor-specific code will live in
  `boards/<name>/` and `syn/`.
- **Every configuration macro is in `rtl/sun3/sun3_config.vh`**, with a
  default, overridable from the command line. No `` `define `` in a source
  file: the old design had two, and between them both Ethernet
  implementations could be built at once.
- **Every knob that changes the snapshot goes into the run directory name.**
  Two runs sharing an xsim snapshot directory clobber each other, and the
  failure looks like a design fault.

## The machine, as built

- **CPU.** Default: Suska WF68K30L from `Inputs/Suska_Configware/68K30L`
  (already carrying a "Sun-3 support" commit in that repo; no icache, unlike
  the variant Old's LiteX script lists). Of its two ALU files,
  `wf68k30L_alu_new.vhd` is the one used, as in Old. `CPU=rd68021` builds
  `Inputs/RD68021` instead.
- **Memory.** By default `sun3_cached_fifo_bridge`: an 8 KiB read cache
  in front of two dual-clock FIFOs (Step 6), its Wishbone side in the
  memory controller's clock. With `WB_FIFO=0`, `sun3_wishbone_bridge`: a
  Wishbone B4 classic master in the CPU clock, always enabled. Either way,
  memory readiness is expressed by holding `sys_reset`. Main memory is `SUN3_MEM_MIB` MiB at physical 0; type-0
  accesses above it time out (bus error), which is how the PROM sizes memory.
  The bw2 window (top 2 MiB of a 256 MiB memory) is only there with `SUN3_FB`.
- **No VME.** Old routed VME32 space straight onto Wishbone at the same
  address (so its custom PROM could reach LiteDRAM's CSRs); that aliased VME
  probes onto RAM, and is gone.
- **Serial.** Both Z8530s (console at OBIO 0x20000, keyboard/mouse at
  OBIO 0x0) are `Inputs/z8530_scc`. Their modem and clock inputs are tied
  (low, RX idle high) rather than left open.
- **EEPROM.** Preloaded; installed memory follows `SUN3_MEM_MIB`, and the
  console is serial A unless `SUN3_FB`.
- **Ethernet.** Wish7990 behind `SUN3_ETH_WISH7990`, off by default.
  Unpatched since upstream 8610ef5, which declares nets before their first
  use (xvlog insists, Verilator/Icarus do not) and samples MDIO reads
  before MDC rises: the three local patches are gone. With it built, the
  PROM boot is unchanged; the PROM's boot path (`sd`) does not exercise it.
  On the DECA (8610ef5, cached bridge) SunOS boots and the PHY is
  configured (10 Mb/s full duplex). 50 pings of 1,400 bytes are all
  answered, and 1 MiB through TCP echo comes back identical (310 kB/s both
  ways).

## The board (QMTech Wukong)

- **Clocks** (`wukong_clkgen`): MMCM A from the 50 MHz oscillator, VCO
  1000 MHz: 166.67 MHz MIG, CPU_CLK_HZ (20 MHz = VCO/50, exact), 200 MHz
  IDELAY reference. MMCM B: 4.915170 MHz for the SCCs (9600 baud from the
  PROM's time constant). `CLKGEN_BEHAVIOURAL` replaces both in fast
  simulation.
- **Memory (default, `WB_FIFO=1`)**: the cached FIFO bridge (its Wishbone side on
  `ui_clk`) -> `wb_mig_sync adapter_sync` -> `mig_arb`.
  `syn/wukong_wbfifo.xdc` bounds the FIFO crossings with
  `set_max_delay -datapath_only` and cuts only the reset synchronisers.
  For those bounds to hold, `wukong_common.xdc` keeps the CPU and MIG
  clocks in one clock group. `wukong_wbcdc.xdc` (`WB_FIFO=0`) declares the
  pair asynchronous, which is why its own bounds stay overridden.
  `exceptions_ignored.rpt` lists nothing from `wbridge`.
- **Memory, `WB_FIFO=0`**: `sun3_wishbone_bridge` (CPU clock) -> `wb_to_mig_ui adapter`
  (toggle handshake into `ui_clk`; keep the instance name, the XDC names it)
  -> `mig_arb` (one client; the second is for a frame buffer) -> `sun3_mig`
  (MT41K128M16, 16-bit, DDR3-667, 4:1). About 10 CPU clocks a read.
- **Reset**: `board_reset | ~mmcm_locked | hold counter | ~init_calib_complete`,
  released through `reset_sync` into the CPU clock. This is where "memory is
  ready" lives.
- **Pins** (V1): console E3/F3 (ttya), diag register on PMOD J10
  (`diag_leds0`), `todebug` on the second header (`extra_leds0`),
  `user_led[0]` lit = out of reset, `user_led[1]` lit = DRAM calibrated (or
  the PHY link, with ETH=1), `user_btn` (H7) = the diag switch, sampled
  through reset. Keyboard/mouse lines are tied idle. Ethernet (ETH=1):
  RTL8211EG as 10/100 MII, limited to 10BASE-T over MDIO by
  `phy_rtl8211_init` (it autonegotiates, advertising 10 half and full
  duplex only).
- **Defaults**: `BOARD=v1s1`, the V1 built for the -1 grade, as the Sun-2
  settled on after a -2 build met timing and failed on its board.
  `CPU_DIV=56`, a 17.857 MHz CPU: the Suska core's bit-field ALU path
  (`I_ALU/BF_WIDTH -> RESULT`, 80 logic levels, 54.3 ns) fails 20 MHz by
  4.5 ns on the -1 model. At 17.857 MHz: WNS +0.62 ns, WHS +0.01 ns.
  `FB=1` (video memory). The RD68021 makes 20 MHz on -1 with room
  (`CPU=rd68021 CPU_DIV=`: WNS +1.28 ns, WHS +0.01 ns) and boots the same.
  `ROM=noparity` on hardware (`fast` shortens tests and the keyboard wait,
  which a real keyboard would need). 16 MiB.
- **The PROM file reaches Vivado by copy**, not by define: build.tcl copies
  it to `<outdir>/bootrom_selected_32bits.vh` and defines
  `SUN3_BOOTROM_SELECTED`. `-verilog_define` mangles a quoted string.

### On the bench

**Debug aids in the FPGA** (control space, FC 3; from the monitor: `s 3`,
then `l`/`v`, then `s 5`):
- `fault_log.v` at 0xD0000000: the last 32 bus errors (address,
  FC/WR/SIZ/DVMA, bus error register bits, PTE, cycle counter), count at
  0xD0000200. `tools/read_fault_log.sh` breaks in and dumps it.
- `bus_trace.v` at 0xD0001000 (status; a write re-arms) and 0xD0002000
  (512 entries): every bus cycle, frozen on a user fetch from page 0, or,
  once armed with an address (write it to 0xD0001000 at the prompt:
  `s 3`, `l d0001000`, the address, `s 5`), 256 cycles after a bus error
  in that 256-byte block -- the fault, the frame pushed and the handler.
  `tools/read_bus_trace.sh` dumps it and `tools/decode_bus_trace.py`
  decodes it (`--syms` takes an `nm`-format kernel symbol list, e.g.
  NetBSD's `netbsd-RAMDISK.symbols.gz`).
- `tools/beprobe/` (`make -C tools/beprobe`, `FAULT_VA=0x01000000` for
  16 MiB): a program for `g 4000` that takes three bus errors (FC 1 byte
  write via `moves.b (An)+`, FC 1 long read, FC 5 word write) and prints
  each frame's SR, PC, format, SSW, fault address, output buffer and a1.
  In simulation: `make -C sim xsim XSIMARGS="-testplusarg
  load=$PWD/build/beprobe/beprobe.bin@4000 -testplusarg type=g_4000"`.
  RD68021 gives what a 68030 would (SSW 0111, 0141, 0125).
  `rteprobe.bin`, the same way: a user `bsr.l` into an invalid page whose
  first instruction is `rts`, the handler validating it and setting FB/FC
  as NetBSD does, then RTE; prints `rteprobe PASS` when the `rts` comes
  back.
  `sccie.bin` leaves the console SCC as a halted SunOS does (interrupts
  and MIE on); with `+type2=k2` after `+type=g_4000` it checks that `k2`
  still reboots.
  `nmiprobe.bin`, the same way: 20 of the monitor's level-7 clock ticks
  taken out of `STOP #$2000`, counting handler entries and entries finding
  the clock status clear; `nmiprobe PASS` is 20 and 0.
- `tools/board_console.py --break` sends a BREAK (faked at 300 baud: the
  CP210x refuses `tcsendbreak`), which drops a Sun kernel into the PROM
  monitor. Not every BREAK lands; retry until "Abort at".
- Careful with `--send` together with `--until`: the lines wait for the
  `--until` string.

- `make -C syn program` loads the FPGA over JTAG (hw_server on localhost:3121,
  started from the Vivado install; the cable is a Platform Cable USB II).
  Nothing goes to the SPI flash unless `make -C syn flash`.
- `tools/board_console.py` reads and types at the console without pyserial:
  `-t SECONDS`, `--until STRING`, `--send LINE` (repeatable), `-o LOG`. Only
  one reader at a time: a second one on the same port sees nothing.
- Checked on the board: boot to `>`; `h` (help); `l 100000` write/read back
  in DDR3; a read past 16 MB takes an Invalid Page bus error, as it should.
  Careful: `q` at the prompt is "open EEPROM", not quit.

## The board (Arrow DECA)

From the Sun-2 project's DECA port, which has the history of every choice.

- **Quartus** 25.1std Lite at `/opt/Altera/quartus` (`QUARTUS_ROOTDIR`),
  run through `syn/altera.sh`. `INTERNAL_FLASH_UPDATE_MODE "SINGLE COMP
  IMAGE WITH ERAM"` is mandatory: without it every initialised memory
  (PROM, EEPROM) is silently built from logic. The Vivado attributes are
  spelled per tool in `sun3_attr.vh` (`SUN3_QUARTUS`, set by quartus.tcl);
  `$random` in `initial` blocks is Error 10174 there, so they are all under
  `SUN3_SIM`.
- **Clocks** (`deca_clkgen`): altpll A, VCO 1 GHz as the Wukong's, CPU =
  1000/`CPU_DIV` MHz; altpll B 4.915254 MHz for the SCCs; BrianHG's own PLL
  for DDR3 (250 MHz; its 400 does not build on Quartus 25.1), CMD_CLK
  125 MHz.
- **Memory**: by default the cached FIFO bridge, its Wishbone side on
  CMD_CLK, -> `deca_wb_ddr3_sync` (no crossing); with `WB_FIFO=0`,
  `sun3_wishbone_bridge` -> `deca_wb_to_ddr3` (toggle handshake
  into CMD_CLK; write mask active high, unlike MIG's) -> BrianHG's soft
  controller (`Inputs/BrianHG-DDR3`, unpatched), caches off,
  `PORT_CACHE_SMART` on (`DDR3_SMART`).
- **Reset**: KEY[0] | PLL unlock | hold counter | ISSP reset, then `| ~DDR3_READY`
  for the machine only (the controller must not wait for itself).
- **Console**: no UART reaches the FPGA. ttya is bridged to a JTAG UART on
  the USB-Blaster II, on the raw 50 MHz (slower than ~5x TCK duplicates or
  swaps bytes). `tools/deca_console_pty.sh` makes it `/tmp/deca-console`;
  `SUN3_CONSOLE=/tmp/deca-console` points `tools/board_console.py` (and the
  scripts using it) there. The raw TX is also on GPIO0_D[0] = PIN_W18
  (P8 pin 3) for a 3.3 V USB-TTL cable.
- **ISSP** (`tools/deca_reset.tcl [reset|break|freeze]` through `altera.sh
  quartus_stp`): DDR3 ready/calibration, PHY state, diag, todebug; source 0
  resets the machine, source 1 holds ttya's RX low (a BREAK: the monitor's
  abort, which the JTAG UART cannot carry), source 2 freezes the bus trace.
  A frozen trace survives the reset. So for a machine that can no longer
  reach its monitor:
  1. Re-arm the trace at the monitor before the experiment (`s 3`,
     `l d0001000`, `0`, `q`, `s 5`).
  2. When it hangs: `freeze`, `reset`, then `break` into the fresh PROM.
  3. `tools/read_bus_trace.sh -n`, then `tools/decode_bus_trace.py`. It and the console share the
  JTAG chain: stop the console first. Output meanwhile queues (2 KiB).
- **Pins** (`syn/deca_pins.qsf`, `deca_ddr3_pins.qsf`): LEDs active low,
  SW[0] down = diag register, up = todebug; SW[1] = the diag switch,
  sampled through reset. No SD, no HDMI yet.
- **Fit** (RD68021, 16.667 MHz, no Ethernet): 36,741 LE (74%), 852,640
  memory bits (51%), 3 of 4 PLLs; WNS +0.445 ns, WHS +0.097 ns; the CPU
  clock's Fmax is 19.0 MHz at the slow corner. The RD68021's microcode is
  built from logic (4.7K LE: its `rom_style` attribute is Vivado's) and its
  instruction cache from flip-flops (2.7K LE, 3.7K registers).
- Configuring the FPGA tears down the JTAG console: the boot banner goes
  out before anything reads it. Attach, then `k2` at the monitor (or an
  ISSP reset with the console stopped) to see a boot.

## The on-board SCSI (`SUN3_SCSI`)

- `rtl/sun3/sun3_si.sv`: OBIO 0x140000, level 2. The NCR 5380 and the disk
  target are `Inputs/Wish5380`'s (`wish5380`, `scsi_targ` as target 0,
  `scsi_fabric`); the board logic around them (CSR, `fifo_count`/`fifo_data`,
  the Am9516 subset with its chain-table fetch, the byte-per-cycle DVMA
  engine) is transcribed from Wish5380's QEMU model of this board
  (`cosim/patches/qemu/0004-...sun3-si...patch`), including the three rules
  SunOS alone enforces: no DMA_IP at terminal count, DMA_ACTIVE clears when
  the chip stops asking (asked once + phase gone + chip interrupting), no
  DMA_CONFLICT. Driver sources: `Inputs/Wish5380/doc/drivers/`.
- DVMA: the Ethernet and the SCSI share `wish7990_dvma_to_020` behind a
  Wishbone arbiter in `sun3_fpga.v` (Ethernet first, as the Architecture
  Manual orders them). The bridge maps bus byte offset k to Wishbone lane
  k^1 (it was written for the little-endian LANCE); `sun3_si` follows it.
- The block seam (Wish5380 `doc/block.md`) leaves `sun3_top` flattened; the
  board supplies the media: `blk_sd` + the micro-SD on the DECA (offset
  `DISK_OFF_MIB`), `tb/blk_file.sv` in simulation.
- The PROM's `si_reset()` waits `DELAY(10000000)` (10 s) after a SCSI bus
  reset: `fast` cuts it to 10 ms (`sun3_60_v1.9_fastboot.txt`); on the board
  it is 10 s of silence after "EEPROM boot device".
- The RD68021's microcode store is a ROM Quartus only builds in M9K if its
  case index is no wider than the program (upstream d1ec453: 11 bits, 1906
  of 2048 used) and the MAX 10 configuration mode carries memory contents
  (the ERAM mode quartus.tcl sets). Built from ~4,700 LE instead, the path
  from the bus unit's falling-edge `early_q` into it (half a period)
  failed timing by 0.9-4.3 ns depending on placement. DECA with ETH+SCSI
  on RD68021 e9d1618: 38,773 LE (78%), 65% memory, WNS +0.668 ns.

## Boot PROM

`Inputs/ref/qemu-sun3/roms/archive/` has Rev 1.9, 2.8.3 and 3.0.1 (gzipped;
1.9 twice). The simulation default is `fast` = Rev 1.9 + `noparity` +
`fastboot`:

- `tools/sun3_60_v1.9_noparity.txt`: **mandatory**, the minimum patch set. The
  stock PROM tests parity, including by forcing a parity error, and main
  memory here has none (nor will the non-parity DDR3). So `ROM=pristine`
  is expected to fail and is only a diagnostic. No parity hardware (NMI handler, parity
  enable, tests 0x0E/0x0F, post-memory-test register checks). Transcribed
  from Old's RomPatcher NoParity image; `make -C tools check` proves it.
- `tools/sun3_60_v1.9_fastboot.txt`, simulation only, on top of noparity:
  two waiting loops cut to 2 iterations; the segment and page map tests cut
  to 16 entries (their setup loops untouched); the diag-mode memory test cut
  to 64 KiB per megabyte found; the RAM initialisation fill cut to 64 KiB per
  megabyte (by shortening its loop bound only -- see Traps); the wait for a
  keyboard's reply cut from 1000 timer ticks to 10.

Rev 3.0.1 has a `noparity` list too (`tools/sun3_60_v3.0.1_noparity.txt`,
`ROM_VER=3.0.1 ROM=noparity`, in both flows). Each of 1.9's six patch
sites appears in 3.0.1 as the same instruction sequence at another address
(checked by disassembly), so the words are 1.9's. The jump past tests
0x0E/0x0F even has the same displacement.

On the DECA (ETH+SCSI, cached bridge) 3.0.1 boots from power-up and from
an ISSP reset: "Model Sun-3/60C/G", "ROM Rev 3.0.1, 16MB memory
installed", then SunOS 4.1.1 from the card multi-user (`zs0`, `zs1`,
`le0`, pings). In simulation (`make -C sim xsim CPU=rd68021 ROM_VER=3.0.1
ROM=noparity TIMEOUT_MS=20000`, no fastboot list) it reaches `>` at
4,667 ms simulated, 1 h 18 min wall clock, and `check` passes.

**Use Rev 1.9 with a screen; 3.0.1's screen output does not work here.**
3.0.1 looks for a frame buffer only if the EEPROM's console byte (0x1F) is
not ttya/ttyb (0x10/0x11): the search at 0x0FEF1F1E tries the EEPROM's type,
then the P4 colour board (0x20), type 0x12, then the on-board bw2 (0). So
with the console on serial (`FB_CONSOLE=0`) it never finds the bw2, prints
"Model Sun-3/60C/G" instead of "60M", and never sets EN.VIDEO (System
Enable reads 0xA0): the monitor syncs to a black screen. With
`FB_CONSOLE=1` the screen turns white but no text is drawn, by the PROM or
by SunOS, although SunOS boots, attaches `bwtwo0` and takes console input
from ttya. Not investigated further. Possibly the missing keyboard, or the
search settling on another frame-buffer type; real 3.0.1 probes the P4
register at OBMEM 0xFF300000 (monitor VA 0x0FE0C000) first. Rev 1.9
always probes the bw2 and works with either console setting.

**`k2` after SunOS hung (fixed).** Under 1.9 and 3.0.1 alike, `k2`
rebooted fine from a fresh PROM but, after SunOS had run and been
`halt`ed, never came back: diag stuck at 0x89, the PROM still fetching.
The bus trace, frozen from ISSP during the hang and read from a fresh
monitor, showed why:
- SunOS leaves the console SCC with its interrupts and master interrupt
  enable on.
- `k2`'s RESET did not reset the SCCs.
- Self test 9 (interrupt test, code 0xF6) enables interrupts expecting a
  soft level 1. It took the SCC's level 6 instead. The unexpected-interrupt
  handler (0x0fef2cec) shows 0x76 (0x89 as read: LEDs active low) and
  restarts the test, forever.

`tools/beprobe/sccie.S` reproduces it in simulation (`+type=g_4000
+type2=k2 +keep_running`). The SCCs are now reset on the RESET line, the
CPU's RESET instruction included; `k2` after SunOS reboots, in simulation
and on the DECA. The production schematic seems to show their RD/WR decode
PAL (U311) taking `INIT-` only; its equations are unreadable, and a real
3/60 must clear the SCCs somehow for `k2` to work.

**Reset nets, from the 3/60 schematics** (`Inputs/doc/
Sun-3_60_Schematic_Jul87.pdf`, production rev 13; `Inputs/doc/f.pdf`, an
earlier "FERRARI" revision):
- `RESET-`, driven by the CPU's RESET instruction and by `INIT-`, reaches
  only the interrupt register, the LANCE chip and the FPU.
- Everything else waits for `INIT-` (power-on, watchdog), which a RESET
  instruction cannot cause: System Enable, diag LEDs, memory error control,
  the SCSI board logic (its CSR holds the 5380 and the UDC in reset), the
  DVMA arbiter, video.
- HALT is asserted with `INIT-` only.

The FPGA follows this, the SCCs excepted (see above): `sun3_fpga.v`
comments each reset with its sheet and part.

After a `k2` the JTAG console bridge may deliver nothing until it is
restarted (`tools/deca_console_pty.sh`).

The last word of a Sun-3 PROM is the 16-bit byte sum of the rest, checked by
the PROM itself (the loop at 0x0FEF1F4A reads all 64 KiB through `moves` and
takes ~100 ms simulated); `rompatch` verifies it on input and rewrites it.

The PROM in Old (`bootrom_patched_32bits.v`, "Rev 2.1F / Sun-3/F") is a
custom rebuild from an older PROM source tree, with LiteDRAM bring-up in it.
It is not a patched stock image and is not used here.

## Boot, as measured

Rev 1.9 `fast`, Suska, 20 MHz, 4 MiB, diag switch off: `make -C sim xsim`
reaches the monitor prompt at 1738.7 ms simulated (~17 min wall clock) and
`make -C sim check` passes:

    Selftest Completed.
    Sun Workstation, Model Sun-3/60M.
    ROM Rev 1.9, 4MB memory installed, Serial #33954.
    Ethernet address 8:0:20:11:22:33.
    EEPROM: Using RS232 A port.
    (banner again, once the console has moved to ttya)
    Testing 0 Megabytes of Memory ... Completed.
    Auto-boot in progress...
    EEPROM boot device...sd(0,0,0)
    Device not found
    >

Timeline: walking LEDs by 0.1 ms, PROM checksum done at 339 ms, MMU tests
432 ms, RAM initialisation, maps set up (diag `F2`) at 584 ms, SCCs
initialised ~960 ms, keyboard wait, banner. With `DIAG=1` each self test is
named on ttya and all pass (checksum, context register, segment and page
maps, memory path, NXM bus error, interrupt, TOD interrupt, MMU
access/modify/invalid/protected, memory size = 4 MB).

A bus cycle is 8 clocks (400 ns) and the Suska core fetches instructions 16
bits at a time, so the PROM is slow in simulation: the unshortened segment
map test alone is ~4.5 s simulated, the RAM fill ~2.4 s, the keyboard wait
~1 s. Every "hang" so far was one of these; a `+trace_from_ms` window
settles it in minutes.

## Traps

- **A 3/60 always has its video memory, and the PROM relies on it.** Built
  without it (`SUN3_NO_FB`), the monitor's `h` command takes an Invalid Page
  Bus Error at vaddr 0xFFFED100, PC 0x0FEFC25E: a raster-op loop drawing a
  form feed into frame buffer memory that was never mapped. It shows only
  when never-written memory reads 0xFFFFFFFF, as a real machine's does after
  the PROM's fill (the board; `MEM_FILL=ffffffff` in simulation), not with
  the model's default 0, which is why the first simulations missed it.
  `SUN3_FB` (the default) gives the bw2 its memory at the top of DDR3; the
  console stays on ttya (the EEPROM says so) unless `SUN3_FB_CONSOLE`.
  With it, the self test's first lines and "EEPROM: Using RS232 A port." go
  to the (unseen) screen before the monitor switches to ttya, as on a real
  3/60 with a monitor.

- **AVEC only in interrupt acknowledge.** The old glue tied AVEC low
  permanently. The Suska core ignores AVEC outside IACK, as the MC68020 UM
  says a CPU must ("AVEC is ignored during all other bus cycles"). The
  RD68021 does not: it terminates any cycle on AVEC, at S3, before a slow
  device has acknowledged. So every write to the diag register, context,
  maps... was lost and the PROM looped at its first tests. `sun3_fpga` now
  asserts AVEC only for FC=7, A19-A16=0xF. Reported upstream
  (`RD68021-AVEC-terminates-any-cycle.md`, not committed). It was found with
  the edge-exact `+watch_from_us` plus the core's `u_biu` state; the first
  reading, a write-timing problem in `sun3_fpga`, was wrong.
- **The RAM fill's end and the monitor's memory size are one register.** At
  0x0FEF2A94 the PROM computes `d2 = megabytes << 20`, copies it to `d1` as
  the fill's bound, and later stores `d2` as the memory size the banner
  prints. Shortening the fill by changing the shift made the banner say
  "0MB"; patch the bound (`d1`), never the shift. `check_console.sh` checks
  the reported size against `MEM_MIB` for exactly this reason.
- **With no keyboard, a normal boot waits for one** (~1 s simulated) after
  the SCCs are set up, and the LEDs show the timer interrupt's pattern
  meanwhile -- it looks like an idle monitor with a dead console.

- **`make -C sim check` does not boot anything.** It will pass on a stale
  log.
- **The legacy RTL is not `default_nettype none` clean** (ports without
  `wire`). Only `sun3_top.v` uses it. An implicit net in `sun3_fpga.v` is a
  silent bug: `MATCH_CYCTR` was one.
- **The TOD chip must know the CPU clock.** `icm7170` divides CLK itself and
  defaulted to 19.6608 MHz under a 20 MHz CLK (time 1.7% fast). It now
  takes `SUN3_CPU_HZ`, which the sim and syn flows set from the same
  variable as the clock.
- **Wish7990's MDIO station sampled reads a cycle late** (after MDC rose),
  until upstream 8610ef5 took Wish82586's fix; an older Wish7990 needs it
  back as a patch.
- **`tools/patch_inputs.sh` rebuilds a copy only when a source or a patch is
  NEWER than its stamp**: removing a patch (to test without it) rebuilds
  nothing, and the run silently uses the patched copy. Delete
  `build/inputs/<name>/.stamp` to force it.
- **An XDC is not Tcl.** `concat` in `wukong_common.xdc` dropped the whole
  `set_clock_groups`, with only a critical warning. The serial and CPU
  clocks were then timed as related, and the build failed by 4.9 ns.
  `build.tcl` now makes that warning (Designutils 20-1307) an error.
- **SunOS's console is 7-bit with even parity: mask bit 7, never delete
  it.** `tr -d '\200-\377'` throws away every character that has its
  parity bit set. `board_console.py --until` compares raw bytes, so it can
  miss its string for the same reason.
- **A SunOS command line is at most 256 characters** (the terminal's
  canonical buffer). A longer line typed at the console never completes:
  every further key only rings the bell, which looks like a hung machine.
  ^U clears it. Over the DECA's JTAG console, typed characters can also be
  dropped (no flow control), so check the echo of anything that matters.
- **`STOP_ON` cannot contain a space** (xsim splits its arguments). With
  `+load`/`+type` it must stay `>`: the prompt is what triggers them.
- **VHDL-2008 is required** for the Suska cores (`buffer` formals on `out`
  actuals).
