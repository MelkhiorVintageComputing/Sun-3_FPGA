`timescale 1ns / 1ps

// Main memory (and, optionally, the bw2 frame buffer) as a Wishbone B4
// classic master, in the CPU clock domain.
//
// Always live.  The old design gated this on a one-shot latch set through
// System Enable bit 1 (EN_FPA), so that its custom PROM could bring the
// LiteDRAM controller up before the first RAM access; a stock PROM knows
// nothing of that.  Memory readiness is now a reset concern instead: whoever
// owns the memory holds sys_reset until it can take cycles (immediately in
// simulation, MIG's init_calib_complete on the board).
//
// Address map on the Wishbone side (word addresses):
//   MATCH_MEM  physical address as is -- RAM is based at 0
//   MATCH_FB   the top 2 MiB of a 256 MiB memory, 0x0FE00000 (bytes)
//
// Data is passed through unswapped: the Wishbone side is big-endian, like the
// 68020, with sel[3] the byte at the lowest address.

module sun3_wishbone_bridge (input 	       RESET_n,
			     input 	       CLK,
			     // some CPU bus signals
			     input [31:0]      P_ADR_IN,
			     input [31:0]      P_DATA_IN,
			     output reg [31:0] P_DATA_OUT,
			     input 	       P_RW_n,
			     input 	       EN_LLBYTE,
			     input 	       EN_LUBYTE,
			     input 	       EN_ULBYTE,
			     input 	       EN_UUBYTE,

			     // match : response
			     input 	       MATCH_MEM,
			     input 	       MATCH_FB,
			     output 	       W_ACK,

			     // wishbone
			     output 	       wb_cyc_o,
			     output 	       wb_stb_o,
			     output [29:0]     wb_adr_o,
			     output [31:0]     wb_dat_o,
			     output [3:0]      wb_sel_o,
			     output 	       wb_we_o,
			     input [31:0]      wb_dat_i,
			     input 	       wb_ack_i
);

   reg 					   done;
   wire 				   match = MATCH_MEM | MATCH_FB;

   // One Wishbone cycle per CPU cycle: the request drops the clock after the
   // ack and stays down until the CPU ends its cycle (the MATCH_* go away
   // with AS).  The old bridge only held it down for one clock, so against a
   // fast slave a CPU cycle that outlived the ack issued the same access a
   // second time.
   assign wb_cyc_o = match & ~done;
   assign wb_stb_o = match & ~done;
   assign wb_adr_o = MATCH_FB ? {11'h07F, P_ADR_IN[20:2]} : P_ADR_IN[31:2];
   assign wb_dat_o = P_DATA_IN;
   assign wb_sel_o = P_RW_n ? 4'hF : {EN_UUBYTE, EN_ULBYTE, EN_LUBYTE, EN_LLBYTE};
   assign wb_we_o  = ~P_RW_n;
   assign W_ACK    = wb_ack_i;

   always @(posedge CLK)
     begin
	if (~RESET_n) begin
	   done       <= 1'b0;
	   P_DATA_OUT <= 32'h00000000;
	end else begin
	   done <= match & (done | wb_ack_i);
	   if (wb_ack_i & ~wb_we_o)
	     P_DATA_OUT <= wb_dat_i;
	end
     end

endmodule

