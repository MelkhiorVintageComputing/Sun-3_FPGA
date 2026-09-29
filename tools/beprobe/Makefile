# beprobe: see beprobe.S.  FAULT_VA defaults to the page after 4 MiB (the
# simulation's MEM_MIB); for the board (16 MiB): make FAULT_VA=0x01000000.
TOP      := $(abspath ../..)
OUT      := $(TOP)/build/beprobe
CROSS    ?= m68k-linux-gnu-
FAULT_VA ?= 0x00400000

all: $(OUT)/beprobe.bin

$(OUT)/beprobe.bin: beprobe.S Makefile
	mkdir -p $(OUT)
	$(CROSS)gcc -mcpu=68020 -nostdlib -static -Wl,-Ttext=0x4000 -Wl,-N \
		-DFAULT_VA=$(FAULT_VA) -o $(OUT)/beprobe.elf beprobe.S
	$(CROSS)objcopy -O binary -j .text -j .data $(OUT)/beprobe.elf $@

clean:
	rm -rf $(OUT)
.PHONY: all clean
