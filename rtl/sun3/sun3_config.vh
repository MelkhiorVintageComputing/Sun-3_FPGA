// Build configuration for the Sun-3 replica.
//
// Every knob has a default here; the simulation scripts and the synthesis
// flow override them with -d / -define.  Nothing else in rtl/ defines a
// configuration macro -- a `define buried in a source file is a knob that
// silently wins over the command line (the old design had two such, which
// could turn both Ethernet implementations on at once).
//
//   SUN3_CPU_RD68021     build Inputs/RD68021 instead of the Suska 68K30L
//   SUN3_ETH_WISH7990    the on-board Ethernet, Wish7990 (Am79C90), at OBIO 0x120000
//   SUN3_FB              the bw2 frame buffer window (off: the PROM's probe
//                        times out and the console is serial A)
//   SUN3_MEM_MIB         installed main memory, in MiB
//   SUN3_BOOTROM_FILE    the boot PROM case body, from build/rom/
//   DEVICE_8BITS_ON_32BITS_BUS
//                        byte devices answer as 32-bit ports with the byte
//                        replicated on all lanes (on unless SUN3_BYTE_PORTS_8)

`ifndef SUN3_CONFIG_VH
`define SUN3_CONFIG_VH

`ifndef SUN3_MEM_MIB
 `define SUN3_MEM_MIB 4
`endif

`ifndef SUN3_BOOTROM_FILE
 `define SUN3_BOOTROM_FILE "bootrom_sun3_60_v1.9_fast_32bits.vh"
`endif

`ifndef SUN3_BYTE_PORTS_8
 `define DEVICE_8BITS_ON_32BITS_BUS
`endif

`endif // SUN3_CONFIG_VH
