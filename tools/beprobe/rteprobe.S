/*
 * rteprobe: run from the PROM monitor (`g 4000'), reproduce NetBSD's text
 * page fault on the board: a user program `bsr.l's into a page that is not
 * valid, whose first instruction is an RTS.  The first fetch there takes a
 * bus error (format $B, RB and RC set); the handler sets FB and FC in the
 * SSW as NetBSD's locore does, makes the page valid and returns with RTE.
 * The RTS should then read its return address from the user stack and come
 * back to the `trap #0' after the bsr.
 *
 *   user code, CODE_PG:  bsr.l TEXT_PG ; trap #0
 *   TEXT_PG (invalid):   rts ; nop
 *
 * Prints "rteprobe PASS" or "rteprobe FAIL" with each fault's SSW, PC and
 * stage B address, and the PC trap #0 came from.  RD68021 up to 8707c04
 * resumes to a fetch from 0 (a second fault, at PC 0).
 *
 * Sun-3 page map entries are in control space (FC 3) at 0x10000000 + VA:
 * bit 31 valid, bit 29 supervisor only.
 */
#define CODE_PG	0x6000		/* 8 KiB pages; the probe itself is at 0x4000 */
#define TEXT_PG	0x8000
#define USTACK	(CODE_PG + 0x1ff0)
#define PMAP	0x10000000
#define PTE_V	0x80000000
#define PTE_S	0x20000000

	.text
	.globl	_start
_start:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	move.w	%sr,-(%sp)
	ori.w	#0x0700,%sr
	movec	%vbr,%a0
	move.l	%a0,oldvbr
	lea	vectab,%a1
	move.w	#255,%d0
1:	move.l	(%a0)+,(%a1)+
	dbf	%d0,1b
	move.l	#handler,vectab+2*4
	move.l	#handler,vectab+3*4	/* address error too, to catch a wild PC */
	move.l	#trap0,vectab+32*4
	lea	vectab,%a0
	movec	%a0,%vbr
	moveq	#3,%d0
	movec	%d0,%dfc
	movec	%d0,%sfc

	/* The user program and the text page. */
	move.l	#CODE_PG,%a0
	move.w	#0x61ff,(%a0)+			/* bsr.l TEXT_PG */
	move.l	#TEXT_PG-(CODE_PG+2),(%a0)+
	move.w	#0x4e40,(%a0)+			/* trap #0 */
	move.l	#TEXT_PG,%a0
	move.l	#0x4e754e71,(%a0)		/* rts ; nop */

	/* Both pages user-accessible, the text page invalid. */
	move.l	#PMAP+CODE_PG,%a0
	moves.l	(%a0),%d0
	move.l	%d0,pte_code
	and.l	#~PTE_S,%d0
	moves.l	%d0,(%a0)
	move.l	#PMAP+TEXT_PG,%a0
	moves.l	(%a0),%d0
	move.l	%d0,pte_text
	and.l	#~(PTE_S+PTE_V),%d0
	moves.l	%d0,(%a0)

	/* Into user mode at CODE_PG. */
	move.l	%sp,savesp
	move.l	#USTACK,%a0
	move.l	%a0,%usp
	clr.w	-(%sp)				/* format 0 */
	move.l	#CODE_PG,-(%sp)
	move.w	#0x0700,-(%sp)			/* SR: user, IPL 7 */
	rte

/* Bus or address error.  The first fault: fix the page and go back.  Any
 * other: the resume went wrong; record it and stop. */
handler:
	move.l	nfault,%d0
	addq.l	#1,nfault
	mulu.w	#12,%d0
	lea	flog,%a0
	add.l	%d0,%a0
	move.w	6(%sp),(%a0)+			/* format/vector */
	move.w	10(%sp),(%a0)+			/* SSW */
	move.l	2(%sp),(%a0)+			/* PC */
	move.l	0x24(%sp),(%a0)			/* stage B address */
	cmp.l	#1,nfault
	bne	back
	move.l	#PMAP+TEXT_PG,%a0
	moves.l	(%a0),%d0
	or.l	#PTE_V,%d0
	moves.l	%d0,(%a0)
	ori.w	#0xc000,10(%sp)			/* FC, FB: as NetBSD's locore */
	rte

trap0:	move.l	2(%sp),trappc
back:	move.l	savesp,%sp

	move.l	#PMAP+CODE_PG,%a0
	move.l	pte_code,%d0
	moves.l	%d0,(%a0)
	move.l	#PMAP+TEXT_PG,%a0
	move.l	pte_text,%d0
	moves.l	%d0,(%a0)
	move.l	oldvbr,%a0
	movec	%a0,%vbr

	/* Report. */
	lea	flog,%a2
	move.l	nfault,%d6
	cmp.l	#4,%d6
	bls	2f
	moveq	#4,%d6
2:	subq.l	#1,%d6
	bmi	4f
3:	lea	s_fault,%a0
	bsr	puts
	move.w	(%a2)+,%d0
	bsr	hex4
	lea	s_ssw,%a0
	bsr	puts
	move.w	(%a2)+,%d0
	bsr	hex4
	lea	s_pc,%a0
	bsr	puts
	move.l	(%a2)+,%d0
	bsr	hex8
	lea	s_sb,%a0
	bsr	puts
	move.l	(%a2)+,%d0
	bsr	hex8
	lea	s_nl,%a0
	bsr	puts
	dbf	%d6,3b
4:	lea	s_trap,%a0
	bsr	puts
	move.l	trappc,%d0
	bsr	hex8
	lea	s_nl,%a0
	bsr	puts
	lea	s_pass,%a0
	cmp.l	#1,nfault
	bne	5f
	cmp.l	#CODE_PG+8,trappc
	beq	6f
5:	lea	s_fail,%a0
6:	bsr	puts

	move.w	(%sp)+,%sr
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

hex8:	swap	%d0
	bsr	hex4
	swap	%d0
hex4:	moveq	#3,%d1
	move.l	%d0,%d3
7:	rol.w	#4,%d3
	move.w	%d3,%d0
	and.w	#15,%d0
	add.b	#'0',%d0
	cmp.b	#'9',%d0
	bls	8f
	addq.b	#7,%d0
8:	bsr	putc
	dbf	%d1,7b
	move.l	%d3,%d0
	rts

puts:	move.b	(%a0)+,%d0
	beq	9f
	bsr	putc
	bra	puts
9:	rts

/* putc: d0.b to ttya, polling RR0 (DFC/SFC are 3 here). */
putc:	move.l	%a4,-(%sp)
	move.l	%d4,-(%sp)
	move.l	#0xF0000004,%a4
10:	moves.b	(%a4),%d4
	btst	#2,%d4
	beq	10b
	moves.b	%d0,2(%a4)
	move.l	(%sp)+,%d4
	move.l	(%sp)+,%a4
	rts

s_fault: .asciz	"fault FV "
s_ssw:	.asciz	" SSW "
s_pc:	.asciz	" PC "
s_sb:	.asciz	" stageB "
s_trap:	.asciz	"trap #0 from "
s_nl:	.asciz	"\r\n"
s_pass:	.asciz	"rteprobe PASS\r\n"
s_fail:	.asciz	"rteprobe FAIL\r\n"

	.data
	.balign	4
oldvbr:	.long	0
savesp:	.long	0
nfault:	.long	0
trappc:	.long	0
pte_code: .long	0
pte_text: .long	0
flog:	.space	4*12
vectab:	.space	1024
