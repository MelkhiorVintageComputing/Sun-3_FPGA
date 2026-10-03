/*
 * fpuprobe: run from the PROM monitor (`g 4000') on a machine built with the
 * MC68881 (FPU=1).
 *
 *   1. With EN.FPP clear (System Enable bit 6) an FPU instruction must take
 *      the F-line trap -- the coprocessor-space cycle ends in BERR, which the
 *      68020 turns into "no coprocessor" -- and the Bus Error register must
 *      not change (Architecture Manual 3.2).
 *   2. With EN.FPP set, a few operations whose IEEE results are exact or
 *      correctly rounded, checked bit for bit: integer multiply, single add
 *      and divide, square root, sine of pi/2 (pi from the constant ROM),
 *      an FMOVEM save/restore and an FSAVE/FRESTORE round trip.
 *
 * Prints each result and "fpuprobe PASS" or "fpuprobe FAIL".  EN.FPP is put
 * back as it was found.
 */
#define SYSEN	0x40000000	/* control space (FC 3): System Enable */
#define BUSERR	0x60000000	/* control space: Bus Error register */

	.text
	.globl	_start
_start:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	moveq	#3,%d0
	movec	%d0,%dfc
	movec	%d0,%sfc
	clr.l	nfail

	/* Our own vector table, so the F-line trap comes here. */
	movec	%vbr,%a0
	move.l	%a0,oldvbr
	lea	vectab,%a1
	move.w	#255,%d0
1:	move.l	(%a0)+,(%a1)+
	dbf	%d0,1b
	move.l	#fline,vectab+11*4
	lea	vectab,%a0
	movec	%a0,%vbr

	/* ---- 1: EN.FPP clear: F-line, Bus Error register untouched ---- */
	moves.b	SYSEN,%d0
	move.b	%d0,sysen0
	bclr	#6,%d0
	moves.b	%d0,SYSEN
	moves.b	BUSERR,%d0
	move.b	%d0,ber0
	clr.l	nfline
	move.l	#2f,recover
	fmove.l	#1,%fp0			/* must trap */
	addq.l	#1,nfail		/* not reached if it trapped */
2:	moves.b	BUSERR,%d0
	lea	s_fline,%a0
	bsr	puts
	move.l	nfline,%d0
	bsr	hex8
	lea	s_ber,%a0
	bsr	puts
	moveq	#0,%d0
	move.b	ber0,%d0
	bsr	hex8
	lea	s_arrow,%a0
	bsr	puts
	moveq	#0,%d0
	moves.b	BUSERR,%d0
	move.l	%d0,%d2
	bsr	hex8
	lea	s_nl,%a0
	bsr	puts
	cmp.l	#1,nfline
	beq	3f
	addq.l	#1,nfail
3:	cmp.b	ber0,%d2
	beq	4f
	addq.l	#1,nfail
4:
	/* ---- 2: EN.FPP set: arithmetic ---- */
	moves.b	SYSEN,%d0
	bset	#6,%d0
	moves.b	%d0,SYSEN
	move.l	#fpudead,recover	/* an F-line now is a failure */

	fmove.l	#3,%fp0
	fmul.l	#4,%fp0
	fmove.l	%fp0,%d0
	move.l	#12,%d1
	lea	s_mul,%a0
	bsr	check

	fmove.s	#0x3fc00000,%fp1	/* 1.5 */
	fadd.s	#0x40100000,%fp1	/* + 2.25 = 3.75 */
	fmove.s	%fp1,%d0
	move.l	#0x40700000,%d1
	lea	s_add,%a0
	bsr	check

	fmove.l	#1,%fp2
	fdiv.l	#3,%fp2			/* 1/3, rounded to single */
	fmove.s	%fp2,%d0
	move.l	#0x3eaaaaab,%d1
	lea	s_div,%a0
	bsr	check

	fmove.l	#2,%fp3
	fsqrt.x	%fp3
	fmove.s	%fp3,%d0
	move.l	#0x3fb504f3,%d1
	lea	s_sqrt,%a0
	bsr	check

	fmovecr	#0,%fp4			/* pi */
	fdiv.l	#2,%fp4
	fsin.x	%fp4
	fmove.s	%fp4,%d0
	move.l	#0x3f800000,%d1
	lea	s_sin,%a0
	bsr	check

	/* FMOVEM: save fp1, clobber it, restore, compare. */
	fmovem.x %fp1,-(%sp)
	fmove.l	#0,%fp1
	fmovem.x (%sp)+,%fp1
	fmove.s	%fp1,%d0
	move.l	#0x40700000,%d1
	lea	s_fmovem,%a0
	bsr	check

	/* FSAVE/FRESTORE: the state round-trips and fp2 survives it. */
	fsave	-(%sp)
	frestore (%sp)+
	fmove.s	%fp2,%d0
	move.l	#0x3eaaaaab,%d1
	lea	s_fsave,%a0
	bsr	check

	bra	done

fpudead:
	lea	s_dead,%a0
	bsr	puts
	addq.l	#1,nfail

done:	/* EN.FPP back as it was, the monitor's vectors back. */
	moves.b	SYSEN,%d0
	bclr	#6,%d0
	btst	#6,sysen0
	beq	5f
	bset	#6,%d0
5:	moves.b	%d0,SYSEN
	move.l	oldvbr,%a0
	movec	%a0,%vbr
	lea	s_pass,%a0
	tst.l	nfail
	beq	6f
	lea	s_fail,%a0
6:	bsr	puts
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

/* The F-line handler: count it and resume at `recover' (the PC is at
 * offset 2 of every exception frame). */
fline:	addq.l	#1,nfline
	move.l	recover,2(%sp)
	rte

/* check: print "<name> <d0>", compare with d1, count a failure. */
check:	move.l	%d0,-(%sp)
	bsr	puts
	move.l	(%sp),%d0
	bsr	hex8
	move.l	(%sp)+,%d0
	cmp.l	%d1,%d0
	beq	7f
	addq.l	#1,nfail
	lea	s_bad,%a0
	bsr	puts
	move.l	%d1,%d0
	bsr	hex8
7:	lea	s_nl,%a0
	bra	puts

hex8:	movem.l	%d1/%d3,-(%sp)
	moveq	#7,%d1
	move.l	%d0,%d3
8:	rol.l	#4,%d3
	move.b	%d3,%d0
	and.b	#15,%d0
	add.b	#'0',%d0
	cmp.b	#'9',%d0
	bls	9f
	addq.b	#7,%d0
9:	bsr	putc
	dbf	%d1,8b
	movem.l	(%sp)+,%d1/%d3
	rts

puts:	move.b	(%a0)+,%d0
	beq	10f
	bsr	putc
	bra	puts
10:	rts

putc:	move.l	%a4,-(%sp)
	move.l	%d4,-(%sp)
	move.l	#0xF0000004,%a4
11:	moves.b	(%a4),%d4
	btst	#2,%d4
	beq	11b
	moves.b	%d0,2(%a4)
	move.l	(%sp)+,%d4
	move.l	(%sp)+,%a4
	rts

s_fline:  .asciz "fpuprobe EN.FPP=0: F-line traps "
s_ber:	  .asciz " bus error reg "
s_arrow:  .asciz " then "
s_mul:	  .asciz "fpuprobe 3*4      "
s_add:	  .asciz "fpuprobe 1.5+2.25 "
s_div:	  .asciz "fpuprobe 1/3      "
s_sqrt:	  .asciz "fpuprobe sqrt(2)  "
s_sin:	  .asciz "fpuprobe sin(pi/2) "
s_fmovem: .asciz "fpuprobe fmovem   "
s_fsave:  .asciz "fpuprobe fsave    "
s_bad:	  .asciz " want "
s_dead:	  .asciz "fpuprobe: F-line with EN.FPP set: no FPU answered\r\n"
s_nl:	  .asciz "\r\n"
s_pass:	  .asciz "fpuprobe PASS\r\n"
s_fail:	  .asciz "fpuprobe FAIL\r\n"

	.data
	.balign	4
oldvbr:	.long	0
recover: .long	0
nfline:	.long	0
nfail:	.long	0
sysen0:	.byte	0
ber0:	.byte	0
	.balign	4
vectab:	.space	1024
