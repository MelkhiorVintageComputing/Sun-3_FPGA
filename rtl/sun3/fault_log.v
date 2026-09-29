`timescale 1ns / 1ps

// A debugging aid: the last 32 bus errors, readable from control space.
//
// The simulation has tb_sun3's +berr_log; the board had nothing like it, and a
// kernel's bus error path is silent (the Sun-2 project learned that the hard
// way).  This keeps, for each faulting bus cycle -- captured on its first
// clock -- what the MMU made of it:
//
//   control space (FC 3) 0xD0000000 + 16*n, n = 0..31, entry n of the ring:
//     +0  the virtual address
//     +4  { FC[2:0], WR (1 = write), SIZ[1:0], DVMA, 1'b0, bus error register bits [7:0],
//           PTE protection/status bits [7:0] (V W S X T1 T0 A M), 8'h00 }
//     +8  { 13'h0, PTE page number [18:0] }
//     +C  the cycle counter when it happened
//   0xD0000200  the number of faults logged since reset (the next entry is
//               count mod 32)
//
// Read-only: writes are acknowledged and ignored.  Nothing in a PROM or an OS
// touches this space, which the Sun-3 architecture leaves unused.

module fault_log (input             CLK,
                  input             RESET_n,
                  // the fault, as sun3_fpga sees it
                  input             FAULT,       // BERRCLK: high while a cycle faults
                  input [31:0]      ADR,
                  input [2:0]       FC,
                  input             RW_n,
                  input [1:0]       SIZ,
                  input             DVMA,
                  input [7:0]       BER,
                  input [7:0]       PTE_PS,
                  input [18:0]      PTE_MA,
                  input [31:0]      CYCLES,
                  // the read port
                  input [9:2]       RD_ADR,
                  output [31:0]     RD_DATA
                  );

   reg [31:0] f_adr [0:31];
   reg [31:0] f_inf [0:31];
   reg [18:0] f_ma  [0:31];
   reg [31:0] f_cyc [0:31];
   reg [31:0] count;
   reg        fault_q;

   wire [4:0] wr = count[4:0];

   always @(posedge CLK) begin
      if (~RESET_n) begin
         count   <= 32'h0;
         fault_q <= 1'b0;
      end else begin
         fault_q <= FAULT;
         if (FAULT & ~fault_q) begin
            f_adr[wr] <= ADR;
            f_inf[wr] <= {FC, ~RW_n, SIZ, DVMA, 1'b0, BER, PTE_PS, 8'h00};
            f_ma[wr]  <= PTE_MA;
            f_cyc[wr] <= CYCLES;
            count     <= count + 32'h1;
         end
      end
   end

   wire [4:0] rd = RD_ADR[8:4];
   assign RD_DATA = RD_ADR[9]          ? count :
                    (RD_ADR[3:2] == 0) ? f_adr[rd] :
                    (RD_ADR[3:2] == 1) ? f_inf[rd] :
                    (RD_ADR[3:2] == 2) ? {13'h0, f_ma[rd]} :
                                         f_cyc[rd];

endmodule
