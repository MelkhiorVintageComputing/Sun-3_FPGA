`timescale 1ns / 1ps

module cyctr32bit_reg(input CLK,
		      output [31:0] dout,
		      input 		CLR_n
		   );
   reg [31:0] 			 data;
   
   always @(posedge CLK)
     begin
	if (~CLR_n) data <= 32'h00000000;
	else data <= data + 1;
     end
   assign dout = data;
   
endmodule // gen32bit_reg
