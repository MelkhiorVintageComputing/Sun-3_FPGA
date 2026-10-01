# FPGA build for the QMTech Wukong (V1 by default) or, with BOARD=deca, the
# Arrow DECA (Quartus; see the DECA section at the end).
#
#   make ip                  generate the MIG DDR3 controller from mig/sun3_mig.prj
#   make bitstream           build; writes the .bit and, beside it, the .bin
#                            for the SPI flash
#   make bitstream ETH=1     with the Wish7990 on the board's Ethernet PHY
#   make bitstream CPU=rd68021
#   make bitstream BOARD=v1  build the V1 for its marked -2 grade (see boards.tcl)
#   make program             put the matching bitstream on the board (JTAG)
#   make flash               write it into the SPI flash instead
#   make clean               drop the Vivado output (clean-ip: the MIG too)
#
# Knobs: CPU_HZ (20000000), CPU_DIV (56: 17.86 MHz, wins), BOARD (v1s1), CPU (suska|rd68021),
# ETH (0|1), FB (1), SCSI (0), DISK_OFF_MIB (0), WB_FIFO (0), WB_CACHE (0), WB_CACHE_IDX (9), MEM_MIB (16), ROM (noparity|pristine|fast), ROM_VER (1.9),
# ALLOW_PW (0), HW_URL (localhost:3121).
#
# Nothing here is committed; everything lands in ../build/syn.  Vivado runs
# from a scratch directory, because it drops .Xil/ and clockInfo.txt wherever
# it is invoked.  Adapted from the Sun-2 project's syn/Makefile.

TOP     = ..
# pipefail: a Quartus failure must fail the target through the | grep below.
SHELL  := /bin/bash
.SHELLFLAGS := -o pipefail -c
HERE   := $(CURDIR)
XILINX_VIVADO ?= /opt/Xilinx/2025.2/Vivado
VIVADO        ?= $(XILINX_VIVADO)/bin/vivado

CPU_HZ  ?= 20000000
BOARD   ?= v1s1
ifeq ($(BOARD),deca)
# The DECA: RD68021 only (Suska does not fit a 10M50), and VCO/60 =
# 16.667 MHz until a faster clock has been measured on the part.
CPU_DIV ?= 60
CPU     ?= rd68021
else
# The MMCM's CPU divider named directly (VCO/CPU_DIV), when the frequency is
# not a whole number of hertz.  Wins over CPU_HZ, here and in build.tcl.
# Default 56 = 17.857 MHz: the Suska core's bit-field ALU path (54.3 ns) does
# not make 20 MHz on the -1 timing model.  CPU_DIV= (empty) uses CPU_HZ.
CPU_DIV ?= 56
CPU     ?= suska
endif
ETH     ?= 0
# The on-board SCSI, its disk on the micro-SD (DECA; Wukong V3 only), and
# where on the card the disk starts, in MiB.
SCSI    ?= 0
DISK_OFF_MIB ?= 0
# The FIFO memory bridge (posted writes, tagged reads), its Wishbone side in
# the memory controller's clock: 0 keeps sun3_wishbone_bridge.
WB_FIFO ?= 0
# The read cache in front of it (needs WB_FIFO=1): 2**WB_CACHE_IDX lines of
# 16 bytes, direct-mapped, write-through, no-allocate.
WB_CACHE ?= 0
WB_CACHE_IDX ?= 9
# The 3/60's on-board video memory (the PROM relies on it; see CLAUDE.md).
FB      ?= 1
# The board has 256 MiB; a 3/60 takes at most 24 MB, and the old build ran 16.
MEM_MIB ?= 16
# On hardware, the PROM with the parity tests taken out and nothing else:
# fast's shortened tests and keyboard wait are for simulation.
ROM     ?= noparity
ROM_VER ?= 1.9
ALLOW_PW ?= 0
HW_URL  ?= localhost:3121

CPU_HZ_EFF = $(if $(CPU_DIV),$(shell expr 1000000000 / $(CPU_DIV)),$(CPU_HZ))
# MHz with one decimal where there is one.  build.tcl computes the same tag;
# the two must agree or make reports one directory while Vivado writes another.
CPU_MHZ_TAG = $(shell h=$(CPU_HZ_EFF); i=$$(( $$h / 1000000 )); \
                      f=$$(( ($$h % 1000000) / 100000 )); \
                      if [ $$f -eq 0 ]; then echo $$i; else echo $$i.$$f; fi)

ROMFILE = bootrom_sun3_60_v$(ROM_VER)_$(ROM)_32bits.vh

SYNDIR  = $(TOP)/build/syn
IPDIR   = $(TOP)/build/ip/$(BOARD)/sun3_mig
# Every knob that changes the bitstream is in its directory's name.
OUTDIR  = $(SYNDIR)/vivado/$(BOARD)-$(CPU)-cpu$(CPU_MHZ_TAG)$(if $(CPU_DIV),-div$(CPU_DIV),)-$(MEM_MIB)m-v$(ROM_VER)-$(ROM)$(if $(filter 1,$(ETH)),-eth,)$(if $(filter 0,$(FB)),-nofb,)$(if $(filter 1,$(SCSI)),-scsi$(if $(filter-out 0,$(DISK_OFF_MIB)),-off$(DISK_OFF_MIB)m),)$(if $(filter 1,$(WB_FIFO)),-wbfifo,)$(if $(filter 1,$(WB_CACHE)),-wbcache$(if $(filter-out 9,$(WB_CACHE_IDX)),$(WB_CACHE_IDX)),)
BIT     = $(abspath $(OUTDIR))/sun3_wukong_$(BOARD).bit
BIN     = $(BIT:.bit=.bin)
WORKDIR = $(SYNDIR)/vivado/work-$(BOARD)

all: bitstream

ifneq ($(BOARD),deca)

$(WORKDIR):
	mkdir -p $(WORKDIR)

$(IPDIR)/sun3_mig.xci: mig/sun3_mig.prj generate_ip.tcl boards.tcl | $(WORKDIR)
	cd $(WORKDIR) && $(VIVADO) -mode batch -nojournal -nolog \
		-source $(HERE)/generate_ip.tcl -tclargs $(BOARD)

ip: $(IPDIR)/sun3_mig.xci

# The boot PROM include has to exist before synthesis.
rom:
	$(MAKE) -C $(TOP)/tools

# Immutable inputs, copied (and patched) into build/inputs.
inputs:
	$(TOP)/tools/patch_inputs.sh Suska_Configware
	$(TOP)/tools/patch_inputs.sh RD68021
	$(TOP)/tools/patch_inputs.sh z8530_scc
	$(TOP)/tools/patch_inputs.sh Wish7990
	$(TOP)/tools/patch_inputs.sh Wish5380

bitstream: ip rom inputs | $(WORKDIR)
	cd $(WORKDIR) && $(VIVADO) -mode batch -nojournal -nolog \
		-source $(HERE)/build.tcl -tclargs $(CPU_HZ) $(if $(CPU_DIV),$(CPU_DIV),0) \
		$(BOARD) $(CPU) $(ETH) $(MEM_MIB) $(ROMFILE) $(ALLOW_PW) $(abspath $(OUTDIR)) $(FB) \
		$(SCSI) $(DISK_OFF_MIB) $(WB_FIFO) $(WB_CACHE) $(WB_CACHE_IDX)
	@echo "bitstream: $(BIT)"
	@echo "flash image: $(BIN)"

# Same knobs as bitstream, so `make program ETH=1' programs what `make
# bitstream ETH=1' built.
program: | $(WORKDIR)
	cd $(WORKDIR) && $(VIVADO) -mode batch -nojournal -nolog \
		-source $(HERE)/program.tcl -tclargs $(BIT) $(HW_URL)

flash: | $(WORKDIR)
	cd $(WORKDIR) && $(VIVADO) -mode batch -nojournal -nolog \
		-source $(HERE)/program_flash.tcl -tclargs $(BIN) $(BOARD) $(HW_URL)

endif  # not deca

# ------------------------------------------------------------------ the DECA
#
#   make bitstream BOARD=deca [ETH=1] [CPU_DIV=50] [CPU_DUTY=53]
#   make program BOARD=deca     over the on-board USB-Blaster II (JTAG only)
#   make lint BOARD=deca        Quartus analysis & synthesis of sun3_top alone
#
# Extra knobs: CPU_DUTY (50), BUS_TRACE (1), SCSI (0: the on-board SCSI, its
# disk on the micro-SD), DISK_OFF_MIB (0: where on the card the disk starts),
# ALLOW_NEG (0: a .sof is written only if timing is met), SEED, JOBS.  Quartus is QUARTUS_ROOTDIR
# (/opt/Altera/quartus), through altera.sh.
ifeq ($(BOARD),deca)
CPU_DUTY  ?= 50
BUS_TRACE ?= 1
ALLOW_NEG ?= 0
SEED      ?= 0
JOBS      ?= 8
QOUTDIR = $(SYNDIR)/quartus/deca-$(CPU)-cpu$(CPU_MHZ_TAG)$(if $(CPU_DIV),-div$(CPU_DIV),)$(if $(filter-out 50,$(CPU_DUTY)),-duty$(CPU_DUTY),)-$(MEM_MIB)m-v$(ROM_VER)-$(ROM)$(if $(filter 1,$(ETH)),-eth,)$(if $(filter 0,$(FB)),-nofb,)$(if $(filter 0,$(BUS_TRACE)),-notrace,)$(if $(filter 1,$(SCSI)),-scsi$(if $(filter-out 0,$(DISK_OFF_MIB)),-off$(DISK_OFF_MIB)m),)$(if $(filter 1,$(WB_FIFO)),-wbfifo,)$(if $(filter 1,$(WB_CACHE)),-wbcache$(if $(filter-out 9,$(WB_CACHE_IDX)),$(WB_CACHE_IDX)),)$(if $(filter-out 0,$(SEED)),-seed$(SEED),)
SOF     = $(abspath $(QOUTDIR))/sun3.sof
QARGS   = -root $(abspath $(TOP)) -board deca -cpu $(CPU) \
          -cpu_hz $(CPU_HZ) -cpu_div $(if $(CPU_DIV),$(CPU_DIV),0) -cpu_duty $(CPU_DUTY) \
          -eth $(ETH) -fb $(FB) -bus_trace $(BUS_TRACE) -mem_mib $(MEM_MIB) \
          -scsi $(SCSI) -disk_off_mib $(DISK_OFF_MIB) -wb_fifo $(WB_FIFO) \
          -wb_cache $(WB_CACHE) -wb_cache_idx $(WB_CACHE_IDX) \
          -romfile $(ROMFILE) -allow_neg $(ALLOW_NEG) -jobs $(JOBS) -seed $(SEED)

rom:
	$(MAKE) -C $(TOP)/tools

inputs:
	$(TOP)/tools/patch_inputs.sh RD68021
	$(TOP)/tools/patch_inputs.sh z8530_scc
	$(TOP)/tools/patch_inputs.sh Wish7990
	$(TOP)/tools/patch_inputs.sh Wish5380

bitstream: rom inputs
	mkdir -p $(abspath $(QOUTDIR)); rm -f $(SOF)
	./altera.sh quartus_sh -t $(HERE)/quartus.tcl $(QARGS) \
		-topent deca_top -stage asm -outdir $(abspath $(QOUTDIR)) \
		2>&1 | tee $(abspath $(QOUTDIR)).log | grep '^\(== \|ERROR\|Error\)'; \
		test -f $(SOF) && echo "bitstream: $(SOF)"

lint: rom inputs
	mkdir -p $(abspath $(SYNDIR))/quartus/lint
	./altera.sh quartus_sh -t $(HERE)/quartus.tcl $(QARGS) \
		-topent sun3_top -stage map -outdir $(abspath $(SYNDIR))/quartus/lint \
		2>&1 | tee $(abspath $(SYNDIR))/quartus/lint.log | grep '^\(== \|ERROR\|Error\)'

program:
	./altera.sh quartus_pgm -m JTAG -o "p;$(SOF)"

ip flash:
	@echo "BOARD=deca: no IP to generate and no flash (the board is JTAG-only)"
endif

clean:
	rm -rf $(SYNDIR)

clean-ip:
	rm -rf $(TOP)/build/ip

.PHONY: all ip rom inputs bitstream program flash lint clean clean-ip
