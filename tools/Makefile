# Boot PROM preparation for the Sun-3 replica.
#
# The PROM images in Inputs/ are immutable (gzipped, as archived from
# sun3arc.org); everything here is generated into build/rom/.
#
#   build/rom/sun3_60_v<ver>.bin                 unpacked, sha256-checked
#   build/rom/bootrom_sun3_60_v<ver>_pristine_32bits.vh
#   build/rom/bootrom_sun3_60_v<1.9|3.0.1>_noparity_32bits.vh
#                 parity hardware taken out (sun3_60_v<ver>_noparity.txt)
#   build/rom/bootrom_sun3_60_v1.9_fast_32bits.vh
#                 noparity, plus two waiting loops shortened
#                 (sun3_60_v1.9_fastboot.txt) -- the simulation default
#
# The .vh files are Verilog `case' bodies included by rtl/sun3/bootrom32.v.
# Rev 1.9 and 3.0.1 have noparity lists (1.9 alone a fastboot one): the
# patches are addresses and opcodes specific to each image, and rompatch
# refuses to apply them anywhere else.

TOP     = ..
ROMDIR  = $(TOP)/build/rom
ARCHIVE = $(TOP)/Inputs/ref/qemu-sun3/roms/archive

VERSIONS = 1.9 2.8.3 3.0.1

# sha256 of the unpacked images, from Inputs/ref/qemu-sun3/roms/README.md
SHA_1.9   = 471bf34cc9313814726c2e3506d85a13291603e37b45aaffa71bc1154a2d4851
SHA_2.8.3 = 8b29ec9fe1cd08f6d9ed362f3b508e7a7270780dc825d62d8f5eda00e0a0d940
SHA_3.0.1 = b562aa5d7bc51eed732fbafde1fd6ea1340977d2b04fb826201c079f699212c6

CC     ?= cc
CFLAGS ?= -O2 -Wall

all: $(foreach v,$(VERSIONS),$(ROMDIR)/bootrom_sun3_60_v$(v)_pristine_32bits.vh) \
     $(ROMDIR)/bootrom_sun3_60_v1.9_noparity_32bits.vh \
     $(ROMDIR)/bootrom_sun3_60_v3.0.1_noparity_32bits.vh \
     $(ROMDIR)/bootrom_sun3_60_v1.9_fast_32bits.vh

$(ROMDIR):
	mkdir -p $(ROMDIR)

rom: rom.c
	$(CC) $(CFLAGS) -o $@ $<

rompatch: rompatch.c
	$(CC) $(CFLAGS) -o $@ $<

# v1.9 is served double-gzipped, the others once; gunzip until it stops being
# gzip.  The result is checked against the published hash either way.
$(ROMDIR)/sun3_60_v%.bin: $(ARCHIVE)/sun3_60_v%.gz | $(ROMDIR)
	@t=$@.tmp; cp $< $$t.gz; \
	while gzip -t $$t.gz 2>/dev/null; do gunzip -c $$t.gz >$$t; mv $$t $$t.gz; done; \
	mv $$t.gz $@
	@echo "$(SHA_$*)  $@" | sha256sum -c --quiet || { rm -f $@; exit 1; }
	@echo "unpacked $@ (sha256 ok)"

$(ROMDIR)/bootrom_sun3_60_v%_pristine_32bits.vh: $(ROMDIR)/sun3_60_v%.bin rom
	./rom D <$< >$@

$(ROMDIR)/sun3_60_v1.9_noparity.bin: $(ROMDIR)/sun3_60_v1.9.bin rompatch sun3_60_v1.9_noparity.txt
	./rompatch $< $@ sun3_60_v1.9_noparity.txt

$(ROMDIR)/sun3_60_v1.9_fast.bin: $(ROMDIR)/sun3_60_v1.9.bin rompatch sun3_60_v1.9_noparity.txt sun3_60_v1.9_fastboot.txt
	./rompatch $< $@ sun3_60_v1.9_noparity.txt sun3_60_v1.9_fastboot.txt

$(ROMDIR)/bootrom_sun3_60_v1.9_%_32bits.vh: $(ROMDIR)/sun3_60_v1.9_%.bin rom
	./rom D <$< >$@

$(ROMDIR)/sun3_60_v3.0.1_noparity.bin: $(ROMDIR)/sun3_60_v3.0.1.bin rompatch sun3_60_v3.0.1_noparity.txt
	./rompatch $< $@ sun3_60_v3.0.1_noparity.txt

$(ROMDIR)/bootrom_sun3_60_v3.0.1_noparity_32bits.vh: $(ROMDIR)/sun3_60_v3.0.1_noparity.bin rom
	./rom D <$< >$@

# Sanity check: the noparity list must reproduce the RomPatcher image it was
# transcribed from, bit for bit.  Only where Old/ is available (it is
# deliberately not in this repository).
OLDNOPARITY = $(TOP)/Old/VintageBusFPGA_Common/RomPatcher/Sun3_60NoParity/sun3_60_v1.9.bin

check: $(ROMDIR)/sun3_60_v1.9_noparity.bin
	@if [ -f $(OLDNOPARITY) ]; then \
		cmp $< $(OLDNOPARITY) && \
		echo "OK: sun3_60_v1.9_noparity.txt reproduces the RomPatcher NoParity image exactly"; \
	else \
		echo "skipped: $(OLDNOPARITY) not present"; \
	fi

clean:
	rm -f rom rompatch
	rm -rf $(ROMDIR)

.PHONY: all check clean
.SECONDARY: $(foreach v,$(VERSIONS),$(ROMDIR)/sun3_60_v$(v).bin)
