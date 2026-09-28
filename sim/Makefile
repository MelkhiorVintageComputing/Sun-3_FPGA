# Sun-3 simulation.
#
#   make -C sim xsim      build and run tb_sun3 under xsim, to the monitor prompt
#   make -C sim check     grep the last run's console.log for a good boot
#                         (does NOT run anything: rerun xsim first)
#
# Knobs (all optional):
#   CPU=suska|rd68021           default suska
#   ROM=fast|noparity|pristine  default fast (v1.9 + noparity + fastboot)
#   ROM_VER=1.9|2.8.3|3.0.1     default 1.9; the patched ROMs are 1.9 only
#   MEM_MIB=<n>                 default 4
#   ETH=none|wish7990           default none
#   MEM_LATENCY=<n>             Wishbone wait states, default 0
#   CPU_HZ=<hz>                 default 20000000
#   BAUD=<n>                    default 9600
#   TIMEOUT_MS=<ms>             simulated time limit, default 2000
#   STOP_ON=<string>            stop once this is on the console, default "> "
#   DEFINES="A B=1"             extra `define's
#   DIAG=1                      diag switch on: the self test prints as it goes
#   XSIMARGS=...                anything else for xsim, e.g. -testplusarg trace_from_ms=12

CPU         ?= suska
ROM         ?= fast
ROM_VER     ?= 1.9
MEM_MIB     ?= 4
ETH         ?= none
MEM_LATENCY ?= 0
CPU_HZ      ?= 20000000
BAUD        ?= 9600
TIMEOUT_MS  ?= 2000
STOP_ON     ?= >
DEFINES     ?=
XSIMARGS    ?=
DIAG        ?=

TOP = ..
SHELL = /bin/bash

# The run directory run_xsim.sh picks, so `check' reads the right log.
TAG := $(CPU)-v$(ROM_VER)-$(ROM)-$(MEM_MIB)m-$(ETH)$(if $(filter-out 0,$(MEM_LATENCY)),-lat$(MEM_LATENCY))$(if $(filter-out 20000000,$(CPU_HZ)),-cpu$(shell echo $$(($(CPU_HZ)/1000000))))$(if $(filter-out 9600,$(BAUD)),-baud$(BAUD))$(foreach d,$(DEFINES),-$(subst =,_,$(d)))
RUNDIR := $(TOP)/build/sim/xsim-$(TAG)

export SUN3_CPU=$(CPU)
export SUN3_ROM=$(ROM)
export SUN3_ROM_VER=$(ROM_VER)
export SUN3_MEM_MIB=$(MEM_MIB)
export SUN3_ETH=$(ETH)
export SUN3_MEM_LATENCY=$(MEM_LATENCY)
export SUN3_CPU_HZ=$(CPU_HZ)
export SUN3_BAUD=$(BAUD)
export SUN3_DEFINES=$(DEFINES)

xsim:
	mkdir -p $(TOP)/build/sim
	set -o pipefail; ./run_xsim.sh -testplusarg timeout_ms=$(TIMEOUT_MS) \
		-testplusarg "stop_on=$(STOP_ON)" $(if $(DIAG),-testplusarg diag) $(XSIMARGS) 2>&1 | tee $(RUNDIR).log

check:
	./check_console.sh $(RUNDIR)/console.log

clean:
	rm -rf $(TOP)/build/sim

.PHONY: xsim check clean
