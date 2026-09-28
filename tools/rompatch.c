/*
 * rompatch - apply a word-granular patch list to a Sun-3/60 boot PROM image.
 *
 * usage: rompatch <in-file> <out-file> <patch-file>...
 *
 * Several patch files may be given; they are applied in order, so a file can
 * build on the state an earlier one left behind.
 *
 * The patch file holds one patch per line:
 *
 *     <address> <expected> <new>      ; all hexadecimal, 16-bit words
 *
 * <address> is a CPU address in PROM space (the 3/60 PROM appears at
 * 0x0fef0000, which is what the ROM disassembly uses); it must be even.  The
 * word currently at that address must equal <expected>, otherwise the patch is
 * rejected -- that guards against silently mis-patching a different image.
 * Blank lines and lines starting with '#' are ignored.
 *
 * All values are big-endian, as the 68020 sees them.
 *
 * The last word of a Sun-3 PROM is a checksum: the 16-bit sum of every byte
 * before it.  Once all patches are applied it is recomputed, so a patched
 * image passes the same self-check the pristine one does.  The pristine
 * checksum is verified first -- an image that fails it was not what we thought
 * it was.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ROM_BASE 0x0fef0000u
#define ROM_SIZE (64u * 1024u)

static unsigned char rom[ROM_SIZE];

static void usage(void)
{
	fprintf(stderr, "usage: rompatch <in-file> <out-file> <patch-file>...\n");
	exit(1);
}

static unsigned checksum(void)
{
	unsigned sum = 0, i;

	for (i = 0; i < ROM_SIZE - 2; i++)
		sum += rom[i];
	return sum & 0xffff;
}

static unsigned stored_checksum(void)
{
	return (rom[ROM_SIZE - 2] << 8) | rom[ROM_SIZE - 1];
}

static int apply(FILE *pf, const char *pname)
{
	char line[1024];
	int lineno = 0, applied = 0;

	while (fgets(line, sizeof(line), pf)) {
		unsigned addr, expected, replacement, offset, old;
		char *p = line;

		lineno++;
		while (*p == ' ' || *p == '\t') p++;
		if (*p == '#' || *p == '\n' || *p == '\0') continue;

		if (sscanf(p, "%x %x %x", &addr, &expected, &replacement) != 3) {
			fprintf(stderr, "%s:%d: expected '<addr> <expected> <new>'\n",
				pname, lineno);
			exit(2);
		}
		/* The checksum word is ours to maintain, not a patch's. */
		if (addr < ROM_BASE || addr >= ROM_BASE + ROM_SIZE - 2 || (addr & 1)) {
			fprintf(stderr, "%s:%d: address %08x out of PROM range or odd\n",
				pname, lineno, addr);
			exit(2);
		}
		if (expected > 0xffff || replacement > 0xffff) {
			fprintf(stderr, "%s:%d: values must be 16-bit\n", pname, lineno);
			exit(2);
		}

		offset = addr - ROM_BASE;
		old = (rom[offset] << 8) | rom[offset + 1];
		if (old != expected) {
			fprintf(stderr, "%s:%d: %08x holds %04x, expected %04x\n",
				pname, lineno, addr, old, expected);
			exit(3);
		}

		rom[offset]     = replacement >> 8;
		rom[offset + 1] = replacement & 0xff;
		printf("  %08x: %04x -> %04x\n", addr, old, replacement);
		applied++;
	}

	return applied;
}

int main(int argc, char *argv[])
{
	FILE *fin, *fout, *fpatch;
	int applied = 0, i;
	unsigned sum;

	if (argc < 4) usage();

	fin = fopen(argv[1], "rb");
	if (!fin) { perror(argv[1]); return 1; }
	if (fread(rom, 1, ROM_SIZE, fin) != ROM_SIZE) {
		fprintf(stderr, "%s: expected a %u-byte PROM image\n", argv[1], ROM_SIZE);
		return 1;
	}
	fclose(fin);

	if (checksum() != stored_checksum()) {
		fprintf(stderr, "%s: checksum %04x does not match the stored %04x\n",
			argv[1], checksum(), stored_checksum());
		return 3;
	}

	for (i = 3; i < argc; i++) {
		fpatch = fopen(argv[i], "r");
		if (!fpatch) { perror(argv[i]); return 1; }
		applied += apply(fpatch, argv[i]);
		fclose(fpatch);
	}

	sum = checksum();
	printf("  checksum: %04x -> %04x\n", stored_checksum(), sum);
	rom[ROM_SIZE - 2] = sum >> 8;
	rom[ROM_SIZE - 1] = sum & 0xff;

	fout = fopen(argv[2], "wb");
	if (!fout) { perror(argv[2]); return 1; }
	if (fwrite(rom, 1, ROM_SIZE, fout) != ROM_SIZE) { perror(argv[2]); return 2; }
	fclose(fout);

	printf("%d patch(es) applied to %s\n", applied, argv[2]);
	return 0;
}
