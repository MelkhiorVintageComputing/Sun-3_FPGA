module sun3_irq_priority(input CLK,
    			input 	     EN_IRQ7,
			input 	     EN_IRQ6,
			input 	     EN_IRQ5,
			input 	     EN_IRQ4,
			input 	     EN_IRQ3,
			input 	     EN_IRQ2,
			input 	     EN_IRQ1,
			input 	     EN_INT,
    			input 	     RTC,
			input 	     V_INT,
			input 	     SCC_IRQ,
			input 	     E_IRQ,
			input 	     PAR_IRQ,
			input 	     S_IRQ,
			output [2:0] IPL_n);
/* ***** WARNING ***** */
/* The 'hold' syntax from the PAL code isn't valid PLD! */
/* Intermediate can't depend on itself! */
/* f16-f20 must have pins for this to compile with WinCUPL */
/* ***** WARNING ***** */
/*
f20	= !((EN_IRQ4 & V_INT) #
            (EN_IRQ4 & !f20));
f19	= !((!f16 & EN_IRQ7 & RTC) #
 	    (!f19 & EN_IRQ7) #
	     PAR_IRQ);
f18	= !((!f17 & EN_IRQ5 & RTC) #
	    (!f18 & EN_IRQ5));
f17	= !((EN_IRQ5 & !RTC) #
            (EN_IRQ5 & !f17));
f16	= !((EN_IRQ7 & !RTC) #
            (EN_IRQ7 & !f16));
 */
   reg 				     f16, f17, f18, f19, f20;
   reg 				     IPL0, IPL1, IPL2;

   initial
     begin
	f16 <= $random;
	f17 <= $random;
	f18 <= $random;
	f19 <= $random;
	f20 <= $random;
	IPL0 <= $random;
	IPL1 <= $random;
	IPL2 <= $random;
     end
   
   /* try with quick synchronous update */
   always @(posedge CLK)
     begin
	f19	<= ~((~f16 & EN_IRQ7 & RTC) |
 		     (~f19 & EN_IRQ7) |
		     PAR_IRQ);
	f18	<= ~((~f17 & EN_IRQ5 & RTC) |
		     (~f18 & EN_IRQ5));
	f20	<= ~((EN_IRQ4 & V_INT) |
		     (EN_IRQ4 & ~f20));
	f17	<= ~((EN_IRQ5 & ~RTC) |
		     (EN_IRQ5 & ~f17));
	f16	<= ~((EN_IRQ7 & ~RTC) |
		     (EN_IRQ7 & ~f16));

/*
  Set the CPU interrupt lines.
  EN_INT disabled cut off all interrupts here.
  ~f19                 the Lvl7 interrupt (from clock or parity error)
                       has maximum priority and set all three lines (== 7).
                       All other lower IRQs check for f19 (== disabled)
  SCC_IRQ (positive)   Second highest priority; generate IPL2 and IPL1 (== 6)
                       All other lower IRQs check for ~SCC_IRQ
  ~f18		       the Lvl5 interrupt (from clock)
  		       set IPL2 and IPL0 (== 5)
                       All other lower IRQs check for f18 (== disabled)
  ~f20                 Video interrupt, generate IPL2 only (== 4)
                       All other lower IRQs check for f20 (== disabled)
  EN_IRQ3, E_IRQ       SW Lvl 3 and Ethernet, same priority
                       (they don't check for each other)
		       Set IPL1 and IPL0 (== 3)
		       All other lower IRQs check for ~EN_IRQ3 & ~E_IRQ
  EN_IRQ2, S_IRQ       SW Lvl 2 and SCSI, same priority
                       (they don't check for each other)
		       Set IPL1  (== 2)
		       The lower IRQs check for ~EN_IRQ2 & ~S_IRQ
  EN_IRQ1              SW Lvl 1. Set IPL0 (== 1)
  		       Only activate when no-one else interrupts
                       
*/

	IPL0	<= ((       ~f19                 & EN_INT) |
		    (~f18 &  f19                 & EN_INT                                          & ~SCC_IRQ) |
		    ( f18 &  f19 &  f20          & EN_INT & EN_IRQ3                                & ~SCC_IRQ) |
		    ( f18 &  f19 &  f20 &  E_IRQ & EN_INT                                          & ~SCC_IRQ) |
		    ( f18 &  f19 &  f20 & ~E_IRQ & EN_INT & EN_IRQ1 & ~EN_IRQ2 & ~EN_IRQ3 & ~S_IRQ & ~SCC_IRQ));
	IPL1	<= ((       ~f19                 & EN_INT) |
		    (        f19                 & EN_INT                                          &  SCC_IRQ) |
		    ( f18 &  f19 &  f20          & EN_INT                       & EN_IRQ3          & ~SCC_IRQ) |
		    ( f18 &  f19 &  f20 &  E_IRQ & EN_INT                                          & ~SCC_IRQ) |
		    ( f18 &  f19 &  f20 & ~E_IRQ & EN_INT            & EN_IRQ2 & ~EN_IRQ3          & ~SCC_IRQ) |
		    ( f18 &  f19 &  f20 & ~E_IRQ & EN_INT                      & ~EN_IRQ3 & S_IRQ  & ~SCC_IRQ));
	IPL2	<= ((       ~f19                 & EN_INT) |
		    (        f19                 & EN_INT                                          &  SCC_IRQ) |
		    (~f18 &  f19                 & EN_INT                                          & ~SCC_IRQ) |
		    ( f18 &  f19 & ~f20          & EN_INT                                          & ~SCC_IRQ));
     end

   assign IPL_n[0] = EN_INT ? ~IPL0 : 1'b1; // protection against 'x'-valued IRQ that corrupt the internal signals
   assign IPL_n[1] = EN_INT ? ~IPL1 : 1'b1;
   assign IPL_n[2] = EN_INT ? ~IPL2 : 1'b1;
  
endmodule // sun3_irq_priority
