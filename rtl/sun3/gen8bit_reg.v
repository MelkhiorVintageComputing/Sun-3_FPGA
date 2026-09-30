`timescale 1ns / 1ps

module gen8bit_reg(input CLK,
		   input [7:0] 	    din,
		   input 	    WR,
		   output reg [7:0] dout,
		   input 	    CLR_n
		   );
   reg [7:0] 			 data;
`ifdef SUN3_SIM
   // Power-up garbage, in simulation only: $random is not synthesisable
   // (Quartus refuses it outright, Error 10174).
   initial
     begin
        data = $random;
     end
`endif
   
   always @(posedge CLK)
     begin
	if (WR) data <= din;
	if (~CLR_n) data <= 8'h00;
	dout <= data;
     end
   
endmodule
