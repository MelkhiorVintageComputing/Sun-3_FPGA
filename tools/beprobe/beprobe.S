/*
 * beprobe: run from the PROM monitor (`g 4000'), take three bus errors on
 * purpose and print the frame the CPU pushed for each, on ttya, through the
 * console SCC in control space (FC 3, 0xF0000004/6, sun3_fpga's bypass), so
 * the monitor's own I/O routines are not needed.
 *
 *   T1  moves.b %d2,(%a1)+  FC 1 byte write  (NetBSD's copyout)
 *   T2  moves.l (%a1),%d2   FC 1 long read
 *   T3  move.w  %d2,(%a1)   FC 5 word write
 *
 * All at FAULT_VA, a page past the end of memory, which the PROM leaves
 * invalid.  A 68030 would push a format $B frame with DF set, RW, SIZE and
 * FC describing the cycle, and the cycle's address as the fault address:
 *   T1 SSW 0111, T2 SSW 0141, T3 SSW 0125.
 * Each line also prints a1 as the handler found it.
 *
 * Build: make -C tools/beprobe; the binary is linked at 0x4000.
 */
#ifndef FAULT_VA
#define FAULT_VA 0x00400000	/* MEM_MIB=4 */
#endif
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
	lea	handler,%a0
	move.l	%a0,vectab+8
	lea	vectab,%a0
	movec	%a0,%vbr
	moveq	#1,%d0
	movec	%d0,%dfc
	movec	%d0,%sfc
	move.l	%sp,savesp

	/* T1 */
	lea	frames+0*0x60,%a2
	lea	t1ret,%a0
	move.l	%a0,resume
	move.l	#FAULT_VA+1,%a1
	moveq	#0x5a,%d2
	moves.b	%d2,(%a1)+
	nop
t1ret:
	/* T2 */
	lea	frames+1*0x60,%a2
	lea	t2ret,%a0
	move.l	%a0,resume
	move.l	#FAULT_VA,%a1
	moves.l	(%a1),%d2
	nop
t2ret:
	/* T3 */
	lea	frames+2*0x60,%a2
	lea	t3ret,%a0
	move.l	%a0,resume
	move.l	#FAULT_VA+2,%a1
	move.w	%d2,(%a1)
	nop
t3ret:
	move.l	oldvbr,%a0
	movec	%a0,%vbr
	moveq	#3,%d0
	movec	%d0,%dfc
	movec	%d0,%sfc

	lea	frames,%a2
	moveq	#'1',%d7
	moveq	#2,%d6
2:	bsr	report
	lea	0x60(%a2),%a2
	addq.l	#1,%d7
	dbf	%d6,2b
	lea	s_done,%a0
	bsr	puts

	move.w	(%sp)+,%sr
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

/* The bus error handler: keep the frame (0x5C bytes) and a1 at a2, resume. */
handler:
	move.l	%sp,%a0
	move.l	%a2,%a3
	moveq	#22,%d0
3:	move.l	(%a0)+,(%a3)+
	dbf	%d0,3b
	move.l	%a1,(%a3)
	move.l	savesp,%sp
	move.l	resume,%a0
	jmp	(%a0)

/* report: a frame at a2, test digit in d7. */
report:
	moveq	#'T',%d0
	bsr	putc
	move.l	%d7,%d0
	bsr	putc
	lea	s_sr,%a0
	bsr	puts
	move.w	0(%a2),%d0
	bsr	hex4
	lea	s_pc,%a0
	bsr	puts
	move.l	2(%a2),%d0
	bsr	hex8
	lea	s_fv,%a0
	bsr	puts
	move.w	6(%a2),%d0
	bsr	hex4
	lea	s_ssw,%a0
	bsr	puts
	move.w	10(%a2),%d0
	bsr	hex4
	lea	s_fa,%a0
	bsr	puts
	move.l	16(%a2),%d0
	bsr	hex8
	lea	s_dob,%a0
	bsr	puts
	move.l	24(%a2),%d0
	bsr	hex8
	lea	s_a1,%a0
	bsr	puts
	move.l	0x5c(%a2),%d0
	bsr	hex8
	lea	s_nl,%a0
	bra	puts

hex8:	swap	%d0
	bsr	hex4
	swap	%d0
hex4:	moveq	#3,%d1
	move.l	%d0,%d3
4:	rol.w	#4,%d3
	move.w	%d3,%d0
	and.w	#15,%d0
	add.b	#'0',%d0
	cmp.b	#'9',%d0
	bls	5f
	addq.b	#7,%d0
5:	bsr	putc
	dbf	%d1,4b
	move.l	%d3,%d0
	rts

puts:	move.b	(%a0)+,%d0
	beq	6f
	bsr	putc
	bra	puts
6:	rts

/* putc: d0.b to ttya, by polling RR0's Tx buffer empty bit. */
putc:	move.l	%a4,-(%sp)
	move.l	%d4,-(%sp)
	move.l	#0xF0000004,%a4
7:	moves.b	(%a4),%d4
	btst	#2,%d4
	beq	7b
	moves.b	%d0,2(%a4)
	move.l	(%sp)+,%d4
	move.l	(%sp)+,%a4
	rts

s_sr:	.asciz	" SR "
s_pc:	.asciz	" PC "
s_fv:	.asciz	" FV "
s_ssw:	.asciz	" SSW "
s_fa:	.asciz	" FA "
s_dob:	.asciz	" DOB "
s_a1:	.asciz	" a1 "
s_nl:	.asciz	"\r\n"
s_done:	.asciz	"beprobe done\r\n"

	.data
	.even
oldvbr:	.long	0
savesp:	.long	0
resume:	.long	0
	.balign	4
vectab:	.space	1024
frames:	.space	3*0x60
