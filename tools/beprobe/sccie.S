/*
 * sccie: run from the PROM monitor (`g 4000'), then `k2'.  Leaves the console
 * SCC (zs0, channel A) as a halted SunOS leaves it: receive, transmit and
 * external/status interrupts enabled (WR1 = 0x13) and the master interrupt
 * enable on (WR9 = 0x08), then returns to the monitor.  The monitor's next
 * characters empty the transmit buffer, so a transmit interrupt is pending
 * at level 6 from then on.
 *
 * The PROM's `k2' executes RESET and reruns its self tests; test 9 (the
 * interrupt test, diag 0xF6) enables interrupts expecting a soft level 1,
 * and takes that level 6 instead -- unless RESET has reset the SCCs.
 */
#define ZS0_CTL_A 0x0fe02004	/* the monitor's mapping of OBIO 0x20004 */

	.text
	.globl	_start
_start:
	lea	ZS0_CTL_A,%a0
	move.b	#1,(%a0)
	nop
	move.b	#0x13,(%a0)	/* WR1: Rx int on all chars, Tx int, Ext int */
	nop
	move.b	#9,(%a0)
	nop
	move.b	#0x08,(%a0)	/* WR9: MIE */
	rts
