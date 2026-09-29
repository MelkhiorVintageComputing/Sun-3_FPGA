# Sun-3 FPGA replica

A Sun-3/60 ("Carrera") rebuilt in an FPGA, targeting the QMTech Wukong V1
(XC7A100T, 256 MiB DDR3). The sibling project `../Sun-2_FPGA` does the same
for a Sun-2 on the same board; its structure, scripts and conventions are
reused here. Read, never modify, anything in it.

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
- RD68021: user processes run, then one resumes at address 0 after an
  instruction-fetch page fault (RTE of a format $B frame with RB/RC set) --
  a core problem, reported upstream
  (`RD68021-RTE-format-B-rerun-resumes-at-zero.md`, not committed).
- Suska: `panic: copyout 14` at the first copyout to `init`'s stack. The
  glue presents the fault right; the core pushed a special status word
  describing the next prefetch (SSW 0x0046: DF clear, read, FC 6), so
  locore took it for an instruction fault. `patches/Suska_Configware/0001`
  fixes the SSW. What remains is the core's own design: its RTE restarts
  the instruction rather than rerunning the cycle, and a `(An)+` has
  already incremented, so a copyin/copyout fault would lose a byte. Not
  pursued: RD68021 is the core of interest.
- In simulation (zero-latency memory) the RD68021 gets further and a
  process is killed for want of an FPU: a 3/60 has an MC68881, and
  NetBSD's userland uses it. Still to do.

## Commands

| command | what |
|---|---|
| `make -C tools` | unpack and checksum the PROMs, build the patched variants and the Verilog includes in `build/rom/` |
| `make -C tools check` | the noparity patch list reproduces the Old RomPatcher image bit for bit |
| `make -C sim xsim` | compile, elaborate and run `tb_sun3` under xsim; stops on the `>` prompt |
| `make -C sim board` | the board top (`tb_wukong` + `wukong_top`), behavioural clocks and a Wishbone RAM with `BOARD_LATENCY` (10) wait states; `BOARD_MEM=ddr3` for the real MIG + Micron model instead (calibration and first accesses only: far too slow to boot) |
| `make -C sim board-check` | as `check`, for the last board run |
| `make -C syn ip` | generate MIG from `syn/mig/sun3_mig.prj` into `build/ip/<BOARD>/` |
| `make -C syn bitstream` | Vivado non-project build into `build/syn/vivado/<tag>/`; fails on negative WNS/WHS or a pulse-width violation. Knobs: `BOARD` (v1s1), `CPU`, `ETH` (0), `MEM_MIB` (16), `ROM` (noparity), `CPU_HZ` (20 MHz), `CPU_DIV` |
| `make -C syn program` / `flash` | JTAG / SPI flash, same knobs (`HW_URL`, default localhost:3121) |
| `make -C sim check` | grep that run's `console.log` for a good boot (self test, banner, `MEM_MIB` MB installed, prompt). **Does not run anything**: rerun `xsim` first |

`sim/Makefile` knobs: `CPU=suska|rd68021`, `ROM=fast|noparity|pristine`,
`ROM_VER=1.9|2.8.3|3.0.1` (patched variants: 1.9 only), `MEM_MIB`,
`ETH=none|wish7990`, `MEM_LATENCY`, `CPU_HZ`, `BAUD`, `TIMEOUT_MS`,
`STOP_ON`, `DIAG`, `DEFINES`, `XSIMARGS`.

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
  its prompt, `+type=g_4000` (`_` for a space) types a line there, and
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
| `boards/Wukong/` | vendor-specific board layer: `wukong_top.sv`, `wukong_clkgen.sv` (two MMCMs), `wb_to_mig_ui.sv` (Wishbone -> MIG, clock crossing), `mig_arb.sv`, `phy_rtl8211_init.sv` (all from Sun-2) |
| `syn/` | Vivado flow: `Makefile`, `build.tcl`, `generate_ip.tcl`, `boards.tcl`, `program*.tcl`, `mig/sun3_mig.prj`, XDCs (`wukong_<rev>.xdc`, `wukong_common.xdc`, `wukong_eth.xdc`, `wukong_wbcdc.xdc`) |
| `tools/` | `rom.c` (binary → Verilog case body), `rompatch.c` (verified word patches + Sun-3 checksum fix-up), patch lists, `patch_inputs.sh` |
| `patches/<Input>/` | patches against `Inputs/`, applied to copies in `build/inputs/` |
| `build/` | everything generated; gitignored |
| `Inputs/` | immutable third-party and reference material. Third-party repositories are git submodules (`git submodule update --init`): Suska_Configware, z8530_scc, RD68021, Wish7990, Wish5380, hdmi, `doc/QM_XC7A100T_WUKONG_BOARD`, `doc/MC68030_Doc_More_Readable`, `ref/qemu-sun3`; loose documents are plain files |
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
- **Memory.** `sun3_wishbone_bridge` is a Wishbone B4 classic master in the
  CPU clock, always enabled; memory readiness is expressed by holding
  `sys_reset`. Main memory is `SUN3_MEM_MIB` MiB at physical 0; type-0
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
  `patches/Wish7990/` moves declarations ahead of their first use, which
  xvlog insists on and Verilator/Icarus do not. With it built, the boot is
  unchanged; the PROM's boot path (`sd`) does not exercise it.

## The board (QMTech Wukong)

- **Clocks** (`wukong_clkgen`): MMCM A from the 50 MHz oscillator, VCO
  1000 MHz: 166.67 MHz MIG, CPU_CLK_HZ (20 MHz = VCO/50, exact), 200 MHz
  IDELAY reference. MMCM B: 4.915170 MHz for the SCCs (9600 baud from the
  PROM's time constant). `CLKGEN_BEHAVIOURAL` replaces both in fast
  simulation.
- **Memory**: `sun3_wishbone_bridge` (CPU clock) -> `wb_to_mig_ui adapter`
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
  RTL8211EG as 10/100 MII, forced to 10BASE-T over MDIO by
  `phy_rtl8211_init`.
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
- **Wish7990's MDIO station samples reads a cycle late** (after MDC rises);
  `patches/Wish7990/0003` carries Wish82586's fix.
- **VHDL-2008 is required** for the Suska cores (`buffer` formals on `out`
  actuals).
