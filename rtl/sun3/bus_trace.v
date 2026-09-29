`timescale 1ns / 1ps

// A debugging aid: an on-chip logic analyser for the bus, readable from
// control space next to the fault log.
//
// Every bus cycle (CPU or DVMA) is recorded when it ends, into a ring of 512
// entries.  The ring freezes when TRIGGER fires -- by default a user program
// fetch (FC 2) from the first 8 KiB, which is where a process that returned
// through a smashed stack ends up -- so the cycles leading to it survive.
//
//   control space (FC 3):
//     0xD0001000  status, read: { frozen, 15'h0, 7'h0, next index [8:0] }
//                 any write re-arms (unfreezes) it
//     0xD0002000 + 16*n, n = 0..511, entry n:
//       +0  address
//       +4  data (as read by the master, or as written)
//       +8  { FC[2:0], WR, SIZ[1:0], DVMA, BERR, 24'h0 }
//       +C  cycle counter at the end of the cycle
//
// The entry written last is (next index - 1) mod 512.

module bus_trace (input             CLK,
                  input             RESET_n,
                  // the bus
                  input             AS_n,
                  input [31:0]      ADR,
                  input [2:0]       FC,
                  input             RW_n,
                  input [1:0]       SIZ,
                  input [31:0]      WDATA,     // what the master drives
                  input [31:0]      RDATA,     // what the master is given
                  input             DSACK,     // any DSACK asserted (active high)
                  input             BERR,      // active high
                  input             DVMA,
                  input [31:0]      CYCLES,
                  // control
                  input             REARM,     // a write to the status register
                  // the read port
                  input [12:2]      RD_ADR,
                  input             RD_STATUS,
                  output [31:0]     RD_DATA
                  );

   // Latched while the cycle runs.
   reg [31:0] c_adr, c_wdata, c_rdata;
   reg [2:0]  c_fc;
   reg        c_wr, c_dvma, c_berr, c_ack;
   reg [1:0]  c_siz;
   reg        as_q;

   reg [8:0]  wptr;
   reg        frozen;

   (* ram_style = "block" *) reg [127:0] ring [0:511];

   wire       trigger = (c_fc == 3'd2) && (c_adr[31:13] == 19'h0);
   wire       cycle_end = ~as_q & AS_n;     // AS just went away

   // Read data: the responders' registered output changes a clock after
   // DSACK, the CPU latches it on the falling edge where AS also negates, and
   // the data mux moves on as soon as AS has gone.  Sampling on every falling
   // edge while AS is asserted leaves exactly what the CPU latched.
   always @(negedge CLK)
     if (~AS_n) c_rdata <= RDATA;

   always @(posedge CLK) begin
      as_q <= AS_n;
      if (~AS_n) begin
         if (as_q) begin                    // first clock of the cycle
            c_berr <= 1'b0;
            c_ack  <= 1'b0;
         end
         c_adr   <= ADR;
         c_fc    <= FC;
         c_wr    <= ~RW_n;
         c_siz   <= SIZ;
         c_dvma  <= DVMA;
         c_wdata <= WDATA;
         if (BERR) c_berr <= 1'b1;
         if (DSACK) c_ack <= 1'b1;
      end

      if (~RESET_n) begin
         wptr   <= 9'h0;
         frozen <= 1'b0;
      end else begin
         if (REARM) frozen <= 1'b0;
         if (cycle_end && !frozen) begin
            ring[wptr] <= {c_adr, (c_wr ? c_wdata : c_rdata),
                           c_fc, c_wr, c_siz, c_dvma, c_berr, 24'h0, CYCLES};
            wptr <= wptr + 9'h1;
            if (trigger) frozen <= 1'b1;
         end
      end
   end

   // Registered read: the control-space cycle acknowledges at C_S4, so there
   // is time for one clock of BRAM latency.
   reg [127:0] rd_q;
   always @(posedge CLK) rd_q <= ring[RD_ADR[12:4]];

   assign RD_DATA = RD_STATUS ? {frozen, 22'h0, wptr} :
                    (RD_ADR[3:2] == 0) ? rd_q[127:96] :
                    (RD_ADR[3:2] == 1) ? rd_q[95:64] :
                    (RD_ADR[3:2] == 2) ? rd_q[63:32] :
                                         rd_q[31:0];

endmodule
