// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
//
// The C-LANCE's two registers on the Sun-3's 68020 bus.
//
// This is the counterpart of sun3_wishbone_bridge.v for the LANCE, and it is
// smaller than that one because there is nothing to invent: the Am79C90
// decodes its own registers.  The part has a slave bus of its own - /CS, ADR,
// READ, DAL(15:0), READY (datasheet p. 19) - and Wish7990 brings those out as
// wish7990's cs_i / adr_i / we_i / wdata_i / rdata_o / ready_o.  So this
// drives them directly rather than going through wb_le, the Wishbone version:
// wb_le exists for a Wishbone SoC, and a Sun-3 is not one.
//
// The window is the two 16-bit ports the drivers declare:
//
//     struct le_device { u_short le_rdp; u_short le_rap; };
//
// at OBIO 0x120000 on a Sun-3, which sun3_fpga.v decodes as device nibble 9.
// So A1 picks the port, exactly as the ADR pin does on the real chip: p. 19,
// "ADR L -> Register Data Port (RDP), ADR H -> Register Address Port (RAP)".
//
// Endianness needs no thought here and that is the point of using the part's
// own port.  Both sides are 16 bits wide and the half is chosen by the
// address, so a big-endian u_short at 0x120000 is D(31:16) and one at
// 0x120002 is D(15:0) - which is all this has to know.  The byte-lane
// question that a 32-bit master does have to answer lives in
// wish7990_dvma_to_020.v, on the other port.
//
// One access takes one clock: le_regs holds READY high because every register
// answers immediately.  DSACK therefore comes as soon as the access has been
// presented, and the CPU sees a device with no wait states beyond the two
// clocks sun3_fpga.v's C_S6 already costs.

module wish7990_sun3_regs
  (
   input 	     CLK,
   input 	     RESET_n,

   // ---- the CPU side, as sun3_fpga.v presents it -------------------------
   input [31:0]      P_ADR_IN, // full physical address
   input [31:0]      P_DATA_IN,
   output reg [31:0] P_DATA_OUT,
   input 	     P_RW_n,
   input 	     MATCH, // MATCH_AMDLE, already qualified by C_S6
   output 	     W_ACK, // -> DSACK

   // ---- the part's own slave pins ----------------------------------------
   output 	     cs_o,
   output 	     adr_o,
   output 	     we_o,
   output [15:0]     wdata_o,
   input [15:0]      rdata_i,
   input 	     ready_i
   );

   // A1 is the ADR pin: 0 selects RDP at +0, 1 selects RAP at +2.
   wire 	     port = P_ADR_IN[1];

   // A big-endian u_short sits in the upper half of the long word at offset 0
   // and the lower half at offset 2.
   assign wdata_o = port ? P_DATA_IN[15:0] : P_DATA_IN[31:16];
   assign adr_o   = port;
   assign we_o    = ~P_RW_n;

   // One access per MATCH, and no more: MATCH is a level that lasts to the end
   // of the CPU cycle, and the part performs the access in whichever clock
   // /CS is high - so a /CS that stayed high would write the register several
   // times over.
   localparam [1:0] ST_IDLE = 2'd0;
   localparam [1:0] ST_ACC  = 2'd1;
   localparam [1:0] ST_DONE = 2'd2;

   reg [1:0] 	    state;

   assign cs_o  = (state == ST_ACC);
   assign W_ACK = (state == ST_DONE);

   always @(posedge CLK)
     begin
	case (state)
	  ST_IDLE: if (MATCH) state <= ST_ACC;
	  ST_ACC:
	    // ready_i is the part's READY pin.  It is tied high inside le_regs
	    // today, but it is honoured rather than assumed, because it is the
	    // hook the datasheet leaves for a CSR1/CSR2 access that takes
	    // longer than a CSR0 one.
	    if (ready_i)
	      begin
		 P_DATA_OUT <= port ? {16'h0000, rdata_i} : {rdata_i, 16'h0000};
		 state <= ST_DONE;
	      end
	  ST_DONE: if (!MATCH) state <= ST_IDLE;   // hold DSACK until AS drops
	  default: state <= ST_IDLE;
	endcase

	if (~RESET_n)
	  begin
	     state <= ST_IDLE;
	     P_DATA_OUT <= 32'h00000000;
	  end
     end

   /* verilator lint_off UNUSEDSIGNAL */
   wire _unused = &{1'b0, P_ADR_IN[31:2], P_ADR_IN[0], 1'b0};
   /* verilator lint_on UNUSEDSIGNAL */

endmodule // wish7990_sun3_regs
