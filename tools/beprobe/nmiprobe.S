/*
 * nmiprobe: run from the PROM monitor (`g 4000'), whose 100 Hz level-7 clock
 * (the ICM7170 through the interrupt register's level-7 enable) is running.
 * Take that non-maskable interrupt out of STOP twenty times, with a handler
 * that does what the monitor's does -- read the clock's status, toggle the
 * level-7 enable to reset the latch, read the status again -- and count the
 * entries, and the entries that found the status already clear.
 *
 * A level-7 request is held until the handler toggles the enable, so a core
 * that takes it a second time at the handler's first instruction (RD68021
 * before patches/RD68021/0002) enters twice per tick, the inner entry
 * clearing the status the outer one then finds clear.  Prints
 * "nmiprobe entries E clear C" and PASS when E is 20 and C is 0.
 */
#define TOD_STATUS 0x0fe06010   /* the monitor's mapping of OBIO 0x60010 */
#define INTREG     0x0fe0a000   /* ... and of OBIO 0xa0000 */

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
	move.l	#nmi,vectab+31*4
	lea	vectab,%a0
	movec	%a0,%vbr
	moveq	#3,%d0
	movec	%d0,%dfc
	movec	%d0,%sfc

2:	stop	#0x2700 & 0x2000	/* mask 0: wait for anything */
	cmp.l	#20,nticks
	blt	2b

	ori.w	#0x0700,%sr
	move.l	oldvbr,%a0
	movec	%a0,%vbr

	lea	s_ent,%a0
	bsr	puts
	move.l	nentries,%d0
	bsr	hex8
	lea	s_clr,%a0
	bsr	puts
	move.l	nclear,%d0
	bsr	hex8
	lea	s_nl,%a0
	bsr	puts
	lea	s_pass,%a0
	cmp.l	#20,nentries
	bne	3f
	tst.l	nclear
	beq	4f
3:	lea	s_fail,%a0
4:	bsr	puts

	move.w	(%sp)+,%sr
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

/* The level-7 handler, as the monitor's: status, toggle, status. */
nmi:	move.l	%d0,-(%sp)
	addq.l	#1,nentries
	move.b	TOD_STATUS,%d0
	bne	5f
	addq.l	#1,nclear
	bra	6f
5:	addq.l	#1,nticks
	andi.b	#0x7f,INTREG
	ori.b	#0x80,INTREG
	move.b	TOD_STATUS,%d0
6:	move.l	(%sp)+,%d0
	rte

hex8:	moveq	#7,%d1
	move.l	%d0,%d3
7:	rol.l	#4,%d3
	move.b	%d3,%d0
	and.b	#15,%d0
	add.b	#'0',%d0
	cmp.b	#'9',%d0
	bls	8f
	addq.b	#7,%d0
8:	bsr	putc
	dbf	%d1,7b
	rts

puts:	move.b	(%a0)+,%d0
	beq	9f
	bsr	putc
	bra	puts
9:	rts

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

s_ent:	.asciz	"nmiprobe entries "
s_clr:	.asciz	" clear "
s_nl:	.asciz	"\r\n"
s_pass:	.asciz	"nmiprobe PASS\r\n"
s_fail:	.asciz	"nmiprobe FAIL\r\n"

	.data
	.balign	4
oldvbr:	 .long	0
nentries: .long	0
nclear:	 .long	0
nticks:	 .long	0
vectab:	 .space	1024
