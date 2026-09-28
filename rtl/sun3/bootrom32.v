`timescale 1ns / 1ps

`include "sun3_config.vh"

// The 64 KiB boot PROM, as 16384 32-bit words.  The contents are generated
// into build/rom/ by tools/ (see tools/Makefile) and selected by
// SUN3_BOOTROM_FILE in sun3_config.vh.
module bootrom32(input CLK,
		 input [13:0] 	   idx,
		 output reg [31:0] dout
		 );

  always @(posedge CLK)
    begin
       case(idx)
`include `SUN3_BOOTROM_FILE
       endcase // case (idx)
    end

endmodule // bootrom32

