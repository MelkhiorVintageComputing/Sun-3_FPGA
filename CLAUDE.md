# Sun-3 FPGA replica

A Sun-3/60 ("Carrera") rebuilt in an FPGA, targeting the QMTech Wukong V1
(XC7A100T, 256 MiB DDR3). The sibling project `../Sun-2_FPGA` does the same
for a Sun-2 on the same board; its structure, scripts and conventions are
reused here. Read, never modify, anything in it.

## Status

Step 1: a core-level simulation (`tb/tb_sun3.sv`) with testbench-supplied
clocks and a behavioural Wishbone RAM, booting the stock 3/60 PROM. No
board layer yet (`boards/`, `syn/`, MIG, MMCM, XDC come in step 2).

## Commands

| command | what |
|---|---|
| `make -C tools` | unpack and checksum the PROMs, build the patched variants and the Verilog includes in `build/rom/` |
| `make -C tools check` | the noparity patch list reproduces the Old RomPatcher image bit for bit |
| `make -C sim xsim` | compile, elaborate and run `tb_sun3` under xsim; stops on the `>` prompt |
| `make -C sim check` | grep that run's `console.log` for a good boot. **Does not run anything**: rerun `xsim` first |

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
  (ack / BERR), data, physical address.
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
- `tools/sun3_60_v1.9_fastboot.txt`, simulation only: two waiting loops cut
  to 2 iterations; the segment map and page map tests cut to 16 entries
  (their setup loops untouched); the diag-mode memory test cut to 64 KiB per
  megabyte found.

The last word of a Sun-3 PROM is the 16-bit byte sum of the rest, checked by
the PROM itself (the loop at 0x0FEF1F4A reads all 64 KiB through `moves` and
takes ~100 ms simulated); `rompatch` verifies it on input and rewrites it.

The PROM in Old (`bootrom_patched_32bits.v`, "Rev 2.1F / Sun-3/F") is a
custom rebuild from an older PROM source tree, with LiteDRAM bring-up in it.
It is not a patched stock image and is not used here.

## Self test, as measured

Rev 1.9 `fast`, Suska, 20 MHz, `DIAG=1`: every test up to and including the
memory size passes -- PROM checksum, context register, segment map wr/rd and
address, page map, memory path, NXM bus error, interrupt, TOD interrupt, MMU
access / modify / invalid / protected page, "Memory Size = 0x00000004
Megabytes". Timeline (diag off): walking LEDs by 0.1 ms, PROM checksum done
at 339 ms. A bus cycle is 8 clocks (400 ns) and the Suska core fetches
instructions 16 bits at a time, so the unshortened segment map test alone
is ~4.5 s simulated -- slow, not stuck.

## Traps

- **`make -C sim check` does not boot anything.** It will pass on a stale
  log.
- **The legacy RTL is not `default_nettype none` clean** (ports without
  `wire`). Only `sun3_top.v` uses it. An implicit net in `sun3_fpga.v` is a
  silent bug: `MATCH_CYCTR` was one.
- **VHDL-2008 is required** for the Suska cores (`buffer` formals on `out`
  actuals).
