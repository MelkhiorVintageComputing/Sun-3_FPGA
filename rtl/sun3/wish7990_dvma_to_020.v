// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
//
// Wish7990's Wishbone master port, as a bus master on the Sun-3's 68020 bus.
//
// This is the half of the LANCE plumbing that has to exist inside sun3_fpga.v
// rather than beside it: ethernet DVMA on a Sun-3 goes through the MMU like
// any other bus cycle, which is the whole reason the driver's DVMA mapping
// works at all.  A master hung off the SoC's Wishbone fabric instead would
// reach physical memory and land the frames in the wrong pages.
//
// The bus timing is deliberately the same shape as bridge_plomb_to_020.v, the
// block this replaces: the same C_S0..C_S5 strobes on alternating edges, the
// same BR / BG / BGACK sequence, the same reaction to BERR.  That code is
// already proven against this core, and the only thing worth changing here is
// the front end.  What is gone is its pair of clock-crossing FIFOs - the MAC
// runs in CLK, the CPU clock, so there is nothing to cross.
//
// Arbitration, MC68030UM section 7.7, which the 68020 shares: assert BR, wait
// for BG with AS negated and no other master holding BGACK, then assert BGACK
// and hold it for the whole of the ownership.  BR is held alongside BGACK
// because sun3_fpga.v muxes the DVMA signals onto the bus on ~BR & ~BGACK.
//
// ---- byte lanes -------------------------------------------------------------
//
// Wish7990 is a little-endian part: byte A of its 24-bit address space is lane
// A[1:0] of the 32-bit Wishbone word.  A 68020 is big endian: byte A sits at
// offset A[1:0] counting down from D31.  The mapping that makes the C-LANCE's
// data structures come out right is chip address A <-> bus address A ^ 1,
// which is a swap of the two 16-bit halves and nothing else.  Doing it that
// way is not a convention chosen here - it is what a real Sun does by wiring
// the part's DAL(15:0) straight to a big-endian bus:
//
//   * a 16-bit field at chip address A reads as the 68k's big-endian u_short
//     at A, so the initialisation block and the descriptor rings need no
//     software byte swapping - which is what doc/drivers/README.md in the
//     Wish7990 tree observes about the Sun headers;
//   * frame data, which the part moves a byte at a time, comes out swapped in
//     pairs - and CSR3.BSWP is the documented fix for exactly that
//     (Am79C90 datasheet p. 23 and p. 32).  Every Sun driver sets it.
//
// ---- how one Wishbone cycle becomes 68020 cycles ---------------------------
//
// SEL carries arbitrary byte lanes, which a 68020 cannot express: it has SIZ
// and A1/A0, so one cycle moves one *contiguous* run of one to four bytes
// (Tables 7-2 and 7-3).  So this walks SEL, issuing one bus cycle per
// contiguous run of bytes and acknowledging the Wishbone cycle only when the
// last of them is done.
//
// In practice almost everything is one cycle: full words of frame data are
// 4'b1111, and every descriptor and initialisation-block access is a halfword.
// The runs appear at the ends of a receive buffer that does not start or end
// on a word boundary, which is a handful per frame.  A gap can only appear
// with BSWP clear - with BSWP set, which is what a Sun driver uses, the swap
// inside the part cancels the one above and the run is always contiguous.
//
// The data needs no shifting in either direction.  For a transfer of n bytes
// at offset k on a 32-bit port, the 68020 puts them on the lanes for k..k+n-1
// (Table 7-5), which is where they already are.

module wish7990_dvma_to_020
  #(
    // The eight address bits above the part's own 24.  The Sun-3 puts ethernet
    // DVMA at the top of the address space; this is the ts_lance eth_ba value
    // that sun3_fpga.v tied to 8'hFF.
    parameter [7:0] DVMA_BASE = 8'hFF,
    // Supervisor data, which is what sun3_fpga.v's FC_GENERAL wants and what
    // ts_lance asked for with ASI 0x0B.
    parameter [2:0] DVMA_FC   = 3'b101,
    // How long to stay off the bus after giving it back, in CPU clocks, so a
    // saturated receive path cannot starve the CPU completely.
    parameter [3:0] BACKOFF   = 4'h7
    )
   (
    input 	      clk, // CLK, the CPU clock: the MAC runs in it too
    input 	      reset_n,

    // ---- Wishbone B4 classic slave, from wish7990's master port -----------
    input 	      wb_cyc_i,
    input 	      wb_stb_i,
    input 	      wb_we_i,
    input [3:0]       wb_sel_i,
    input [29:0]      wb_adr_i, // word address; only [21:0] are significant
    input [31:0]      wb_dat_i,
    output [31:0]     wb_dat_o,
    output 	      wb_ack_o,
    output 	      wb_err_o,

    // ---- MC68020 bus, as master -------------------------------------------
    output [31:0]     mc_A_OUT,
    input [31:0]      mc_D_IN,
    output [31:0]     mc_D_OUT,
    output [2:0]      mc_FC,
    output [1:0]      mc_SIZ,
    input 	      mc_AS_N_IN,
    output 	      mc_AS_N_OUT,
    output 	      mc_DS_N,
    output 	      mc_RW_N,
    input 	      mc_DSACK0_N,
    input 	      mc_DSACK1_N,
    input 	      mc_BERR_N,

    output 	      mc_BR_N,
    input 	      mc_BG_N,
    output 	      mc_BGACK_N
    );

   // ---- the request, as it stands ------------------------------------------
   wire 	      req = wb_cyc_i & wb_stb_i & ~wb_ack_o;

   // SEL in bus order: bo[k] is the byte at offset k from the top of the long
   // word, which is chip lane k ^ 1.  See the note above.
   wire [3:0] 	      bo_req = {wb_sel_i[2], wb_sel_i[3], wb_sel_i[0], wb_sel_i[1]};

   // What is left to move of the current request.
   reg [3:0] 	      bo;

   // The next contiguous run: where it starts, and how long it is.
   wire [1:0] 	      a10 = bo[0] ? 2'd0 : bo[1] ? 2'd1 : bo[2] ? 2'd2 : 2'd3;
   reg [2:0] 	      run;
   always @(*)
     begin
	case (a10)
	  2'd0:    run = bo[1] ? (bo[2] ? (bo[3] ? 3'd4 : 3'd3) : 3'd2) : 3'd1;
	  2'd1:    run = bo[2] ? (bo[3] ? 3'd3 : 3'd2) : 3'd1;
	  2'd2:    run = bo[3] ? 3'd2 : 3'd1;
	  default: run = 3'd1;
	endcase
     end

   // Table 7-2: 01 byte, 10 word, 11 three bytes, 00 long word.
   wire [1:0] 	      siz = (run == 3'd4) ? 2'b00 :
			    (run == 3'd3) ? 2'b11 :
			    (run == 3'd2) ? 2'b10 : 2'b01;

   // The bytes this cycle covers, in bus order and as a data mask.
   wire [3:0] 	      bo_mask = (4'b1111 << a10) & ~(4'b1111 << (a10 + run));
   wire [31:0] 	      d_mask = {{8{bo_mask[0]}}, {8{bo_mask[1]}},
				{8{bo_mask[2]}}, {8{bo_mask[3]}}};

   assign mc_A_OUT = {DVMA_BASE, wb_adr_i[21:0], a10};
   assign mc_FC    = DVMA_FC;
   assign mc_SIZ   = siz;
   assign mc_RW_N  = ~wb_we_i;
   // Chip lanes to bus lanes: swap the two halves, and every byte is then
   // already sitting where the 68020 wants it.
   assign mc_D_OUT = {wb_dat_i[15:0], wb_dat_i[31:16]};

   // ---- the bus side --------------------------------------------------------
   localparam [2:0]   FSMMC_IDLE       = 3'b000;
   localparam [2:0]   FSMMC_WAITFORBUS = 3'b001;
   localparam [2:0]   FSMMC_READ       = 3'b010;
   localparam [2:0]   FSMMC_WRITE      = 3'b011;
   localparam [2:0]   FSMMC_DELAY      = 3'b100;

   reg [2:0] 	      fsmmc_state;
   reg 		      br, bgack, as;
   reg [3:0] 	      delay_cnt;
   reg [31:0] 	      d68;          // what has been read back, in bus order
   reg 		      done, berr;

   reg 		      C_S0, C_S1, C_S2, C_S3, C_S4, C_S5;

   assign mc_BR_N     = ~br;
   assign mc_BGACK_N  = ~bgack;
   assign mc_AS_N_OUT = ~as;
   assign mc_DS_N     = ~as;

   assign wb_ack_o = done;
   assign wb_err_o = berr;
   assign wb_dat_o = {d68[15:0], d68[31:16]};

   always @(posedge clk)
     begin
	C_S0 <= 1'b0;   // one-cycle strobes; C_S2 may stretch on wait states
	C_S4 <= 1'b0;
	done <= 1'b0;
	berr <= 1'b0;
	if (delay_cnt != 4'h0) delay_cnt <= delay_cnt - 4'h1;

	case (fsmmc_state)
	  FSMMC_IDLE:
	    begin
	       if (req & (bo_req != 4'h0))
		 begin
		    bo <= bo_req;
		    if (~(br & bgack))
		      begin
			 br <= 1'b1;
			 fsmmc_state <= FSMMC_WAITFORBUS;
		      end
		    else
		      begin
			 C_S0 <= 1'b1;
			 fsmmc_state <= wb_we_i ? FSMMC_WRITE : FSMMC_READ;
		      end
		 end
	       else if (req)
		 begin
		    // Nothing enabled: nothing to do on the bus, but the
		    // requester still has to be released.
		    done <= 1'b1;
		 end
	       else if (br & bgack)
		 begin
		    // Give the bus back and stay off it for a moment, so the
		    // CPU gets a turn even under sustained receive traffic.
		    br <= 1'b0;
		    bgack <= 1'b0;
		    delay_cnt <= BACKOFF;
		    fsmmc_state <= FSMMC_DELAY;
		 end
	    end

	  FSMMC_DELAY:
	    if (delay_cnt == 4'h0) fsmmc_state <= FSMMC_IDLE;

	  FSMMC_WAITFORBUS:
	    // Section 7.7: BG, with AS negated so no cycle is in progress.
	    if (~mc_BG_N & mc_AS_N_IN)
	      begin
		 bgack <= 1'b1;
		 C_S0 <= 1'b1;
		 fsmmc_state <= wb_we_i ? FSMMC_WRITE : FSMMC_READ;
	      end

	  FSMMC_WRITE, FSMMC_READ:
	    begin
	       if (C_S1) C_S2 <= 1'b1;

	       if (C_S3)
		 begin
		    C_S2 <= 1'b0;
		    C_S4 <= 1'b1;
		 end

	       if (C_S5)
		 begin
		    // This run is done.  Either start the next one of the same
		    // Wishbone cycle, or finish it.
		    if ((bo & ~bo_mask) != 4'h0)
		      begin
			 bo <= bo & ~bo_mask;
			 C_S0 <= 1'b1;   // keep the bus, run the next cycle
		      end
		    else
		      begin
			 done <= 1'b1;
			 bo <= 4'h0;
			 fsmmc_state <= FSMMC_IDLE;
		      end
		 end

	       if (~mc_BERR_N)
		 begin
		    // Give up on the whole request and say so: the engines
		    // turn this into CSR0.MERR, which is what the driver reads.
		    C_S0 <= 1'b0;
		    C_S2 <= 1'b0;
		    C_S4 <= 1'b0;
		    bo <= 4'h0;
		    done <= 1'b1;
		    berr <= 1'b1;
		    br <= 1'b0;
		    bgack <= 1'b0;
		    fsmmc_state <= FSMMC_IDLE;
		 end
	    end

	  default: fsmmc_state <= FSMMC_IDLE;
	endcase

	if (~reset_n)
	  begin
	     C_S0 <= 1'b0;
	     C_S2 <= 1'b0;
	     C_S4 <= 1'b0;
	     fsmmc_state <= FSMMC_IDLE;
	     br <= 1'b0;
	     bgack <= 1'b0;
	     bo <= 4'h0;
	     done <= 1'b0;
	     berr <= 1'b0;
	     delay_cnt <= 4'h0;
	  end
     end

   always @(negedge clk)
     begin
	as <= (C_S0 | C_S2);   // the cycle is on the bus from S0 until S5
	C_S1 <= 1'b0;
	C_S3 <= 1'b0;
	C_S5 <= 1'b0;

	if (C_S0) C_S1 <= 1'b1;

	// Table 7-1: either DSACK asserted ends the cycle.  Everything in this
	// machine answers as a 32-bit port, so one cycle moves the whole run.
	if (C_S2 & (~mc_DSACK0_N | ~mc_DSACK1_N)) C_S3 <= 1'b1;

	if (C_S4)
	  begin
	     d68 <= (d68 & ~d_mask) | (mc_D_IN & d_mask);
	     C_S5 <= 1'b1;
	  end

	if (~mc_BERR_N & bgack)
	  begin
	     C_S1 <= 1'b0;
	     C_S3 <= 1'b0;
	     C_S5 <= 1'b0;
	  end

	if (~reset_n)
	  begin
	     d68 <= 32'h00000000;
	     C_S1 <= 1'b0;
	     C_S3 <= 1'b0;
	     C_S5 <= 1'b0;
	  end
     end

   // The part has 24 address bits, so only 22 word address bits ever carry
   // anything; the rest of the Wishbone address is zero by construction.
   /* verilator lint_off UNUSEDSIGNAL */
   wire _unused = &{1'b0, wb_adr_i[29:22], 1'b0};
   /* verilator lint_on UNUSEDSIGNAL */

endmodule // wish7990_dvma_to_020
