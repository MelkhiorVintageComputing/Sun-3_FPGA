# Sun-3 simulation.
#
#   make -C sim xsim      build and run tb_sun3 under xsim, to the monitor prompt
#   make -C sim check     grep the last run's console.log for a good boot
#                         (does NOT run anything: rerun xsim first)
#   make -C sim board     the board top (tb_wukong) with a behavioural RAM
#   make -C sim board BOARD_MEM=ddr3
#                         ... with the real MIG and Micron's DDR3 model
#   make -C sim board-check   as check, for the last board run
#
# Knobs (all optional):
#   CPU=suska|rd68021           default suska
#   ROM=fast|noparity|pristine  default fast (v1.9 + noparity + fastboot)
#   ROM_VER=1.9|2.8.3|3.0.1     default 1.9; the patched ROMs are 1.9 only
#   MEM_MIB=<n>                 default 4
#   ETH=none|wish7990           default none
#   MEM_LATENCY=<n>             Wishbone wait states, default 0
#   MEM_FILL=<hex>              never-written memory reads as this, default 00000000
#   CPU_HZ=<hz>                 default 20000000
#   BAUD=<n>                    default 9600
#   TIMEOUT_MS=<ms>             simulated time limit, default 2000
#   STOP_ON=<string>            stop once this is on the console, default "> "
#   DEFINES="A B=1"             extra `define's
#   BOARD=v1s1|v1|v3            board runs: which MIG (ddr3 mode)
#   BOARD_MEM=fast|ddr3         board runs, default fast
#   BOARD_LATENCY=<n>           board runs, fast: wait states, default 10
#   DIAG=1                      diag switch on: the self test prints as it goes
#   XSIMARGS=...                anything else for xsim, e.g. -testplusarg trace_from_ms=12

CPU         ?= suska
ROM         ?= fast
ROM_VER     ?= 1.9
MEM_MIB     ?= 4
ETH         ?= none
# SCSI=1: the on-board SCSI, its disk a file (XSIMARGS="-testplusarg blk_image=<img>")
SCSI        ?= 0
# WB_FIFO=1 (default): the FIFO memory bridge (posted writes, tagged reads),
# the RAM model on its own 83.33 MHz clock; 0: the synchronous bridge
WB_FIFO     ?= 1
# WB_CACHE=1 (needs WB_FIFO=1; defaults to it): the read cache in front of it,
# 2**WB_CACHE_IDX lines of 16 bytes
WB_CACHE    ?= $(WB_FIFO)
WB_CACHE_IDX ?= 9
MEM_LATENCY ?= 0
MEM_FILL    ?= 00000000
CPU_HZ      ?= 20000000
BAUD        ?= 9600
TIMEOUT_MS  ?= 2000
STOP_ON     ?= >
DEFINES     ?=
XSIMARGS    ?=
DIAG        ?=
BOARD       ?= v1s1
BOARD_MEM   ?= fast
BOARD_LATENCY ?= 10

TOP = ..
SHELL = /bin/bash

# The run directory run_xsim.sh picks, so `check' reads the right log.
TAG := $(CPU)-v$(ROM_VER)-$(ROM)-$(MEM_MIB)m-$(ETH)$(if $(filter 1,$(SCSI)),-scsi)$(if $(filter 1,$(WB_FIFO)),-wbfifo)$(if $(filter 1,$(WB_CACHE)),-wbcache$(if $(filter-out 9,$(WB_CACHE_IDX)),$(WB_CACHE_IDX)))$(if $(filter-out 0,$(MEM_LATENCY)),-lat$(MEM_LATENCY))$(if $(filter-out 00000000,$(MEM_FILL)),-fill$(MEM_FILL))$(if $(filter-out 20000000,$(CPU_HZ)),-cpu$(shell echo $$(($(CPU_HZ)/1000000))))$(if $(filter-out 9600,$(BAUD)),-baud$(BAUD))$(foreach d,$(DEFINES),-$(subst =,_,$(d)))
RUNDIR := $(TOP)/build/sim/xsim-$(TAG)
BTAG := $(BOARD)-$(BOARD_MEM)-$(CPU)-v$(ROM_VER)-$(ROM)-$(MEM_MIB)m$(if $(filter fast,$(BOARD_MEM)),$(if $(filter-out 10,$(BOARD_LATENCY)),-lat$(BOARD_LATENCY)))$(if $(filter-out 20000000,$(CPU_HZ)),-cpu$(shell echo $$(($(CPU_HZ)/1000000))))$(if $(filter 1,$(WB_FIFO)),-wbfifo)$(if $(filter 1,$(WB_CACHE)),-wbcache$(if $(filter-out 9,$(WB_CACHE_IDX)),$(WB_CACHE_IDX)))$(foreach d,$(DEFINES),-$(subst =,_,$(d)))
BRUNDIR := $(TOP)/build/sim/board-$(BTAG)

export SUN3_CPU=$(CPU)
export SUN3_ROM=$(ROM)
export SUN3_ROM_VER=$(ROM_VER)
export SUN3_MEM_MIB=$(MEM_MIB)
export SUN3_ETH=$(ETH)
export SUN3_SCSI=$(SCSI)
export SUN3_WB_FIFO=$(WB_FIFO)
export SUN3_WB_CACHE=$(WB_CACHE)
export SUN3_WB_CACHE_IDX=$(WB_CACHE_IDX)
export SUN3_MEM_LATENCY=$(MEM_LATENCY)
export SUN3_MEM_FILL=$(MEM_FILL)
export SUN3_CPU_HZ=$(CPU_HZ)
export SUN3_BAUD=$(BAUD)
export SUN3_DEFINES=$(DEFINES)

xsim:
	mkdir -p $(TOP)/build/sim
	set -o pipefail; ./run_xsim.sh -testplusarg timeout_ms=$(TIMEOUT_MS) \
		-testplusarg "stop_on=$(STOP_ON)" $(if $(DIAG),-testplusarg diag) $(XSIMARGS) 2>&1 | tee $(RUNDIR).log

board:
	mkdir -p $(TOP)/build/sim
	set -o pipefail; BOARD=$(BOARD) BOARD_MEM=$(BOARD_MEM) SUN3_MEM_LATENCY=$(BOARD_LATENCY) \
		./run_xsim_board.sh -testplusarg timeout_ms=$(TIMEOUT_MS) \
		-testplusarg "stop_on=$(STOP_ON)" $(if $(DIAG),-testplusarg diag) $(XSIMARGS) 2>&1 | tee $(BRUNDIR).log

board-check:
	./check_console.sh $(BRUNDIR)/console.log $(MEM_MIB)

check:
	./check_console.sh $(RUNDIR)/console.log $(MEM_MIB)

# Board-layer unit tests (sim/run_unit.sh): the DECA's DDR3 adapter and its
# JTAG console bridge, each against a model of the IP it talks to; the FIFO
# bridge, its dual-clock FIFO and its DECA adapter.
decaddr3 decaconsole asyncfifo fifobridge cachedbridge decaddr3sync:
	./run_unit.sh $@

clean:
	rm -rf $(TOP)/build/sim

.PHONY: xsim check board board-check decaddr3 decaconsole asyncfifo fifobridge cachedbridge decaddr3sync clean
