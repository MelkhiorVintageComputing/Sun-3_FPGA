`timescale 1ns / 1ps

module ctx_reg_sun3 #(parameter VALID_BITS=3)(input CLK,
					      input [7:0]     din,
					      input 	       WR,
					      output reg [7:0] dout,
					      output [VALID_BITS-1:0]     cx
		    );
   reg [7:0] 			 ctx;
   
   initial
     begin
        ctx = $random;
     end
   
   always @(posedge CLK)
     begin
	if (WR) ctx <= din[VALID_BITS-1:0];
	dout <= {5'b0, ctx[VALID_BITS-1:0]};
     end
   assign cx = dout[VALID_BITS-1:0];
   
endmodule
