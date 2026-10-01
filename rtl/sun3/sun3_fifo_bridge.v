`timescale 1ns / 1ps

`include "sun3_attr.vh"

//
// The Sun-3 bus to Wishbone, through two dual-clock FIFOs (SUN3_WB_FIFO).
//
// sun3_wishbone_bridge is synchronous: a memory cycle raises wb_cyc and DSACK
// waits for the Wishbone acknowledgement, which on a board comes back through
// the adapter's own clock crossing -- reads and writes alike.  This is a
// drop-in alternative with the same ports plus the Wishbone side's own clock
// and reset, so the Wishbone side can run in the memory controller's clock
// (MIG's ui_clk, BrianHG's CMD_CLK) with no crossing left in the adapter:
//
//   request FIFO   CLK -> WB_CLK   {tag, we, adr, dat, sel}
//   response FIFO  WB_CLK -> CLK   {tag, dat}, reads only
//
// Ported from the Sun-2 project's sun2_fifo_bridge.v, whose header holds the
// argument in full; in short:
//
//  * A write is acknowledged as soon as it is queued.  Nothing can refuse it
//    once MATCH_MEM / MATCH_FB is up: those come at C_S6, after the MMU's
//    protection and validity check, only for installed memory, and memory is
//    exempt from the bus timeout.  A full request FIFO delays the
//    acknowledgement: backpressure, never loss.
//  * A read waits for its own answer, matched by tag; any other answer at the
//    head of the response FIFO is dropped, so whatever might put a stray
//    transaction into the memory path, its answer cannot be taken by the next
//    cycle.
//  * Order is the correctness argument.  Every master -- the CPU and DVMA
//    (Ethernet, SCSI), which all go through the 68020 bus and the MMU -- goes
//    through the one request FIFO, and the Wishbone side runs one transaction
//    at a time from its head, so a read queued behind a posted write sees it.
//    A read-modify-write (TAS: no bus grant inside RMC) is a blocking read and
//    a posted write.
//  * The machine sees today's timing: W_ACK is a one-clock pulse, and for a
//    read P_DATA_OUT is loaded on the edge that ends it, as
//    sun3_wishbone_bridge does with wb_ack_i.
//  * One transaction per bus cycle: MATCH_* drop with AS, which clears
//    `issued'.
//  * Reset: each FIFO side takes its own reset OR the other side's,
//    synchronised, so the two sides always overlap.  RESET_n is the system
//    reset, never the CPU's RESET instruction: queued writes must survive it.
//
module sun3_fifo_bridge #(
   parameter TAG_BITS = 4,
   parameter REQ_ADDR = 4,                  // request FIFO depth 2**REQ_ADDR
   parameter RSP_ADDR = 2
) (
   input             RESET_n,
   input             CLK,

   input      [31:0] P_ADR_IN,
   input      [31:0] P_DATA_IN,
   output reg [31:0] P_DATA_OUT,
   input             P_RW_n,
   input             EN_LLBYTE,
   input             EN_LUBYTE,
   input             EN_ULBYTE,
   input             EN_UUBYTE,
   input             MATCH_MEM,
   input             MATCH_FB,
   output            W_ACK,

   input             WB_CLK,
   input             WB_RESET,
   output            wb_cyc_o,
   output            wb_stb_o,
   output     [29:0] wb_adr_o,
   output     [31:0] wb_dat_o,
   output      [3:0] wb_sel_o,
   output            wb_we_o,
   input      [31:0] wb_dat_i,
   input             wb_ack_i
);

   localparam RQW = TAG_BITS + 1 + 30 + 32 + 4;
   localparam RSW = TAG_BITS + 32;

   // =========================================================================
   // Resets, crossed both ways so the two FIFO sides always overlap
   // =========================================================================
   `SUN3_ASYNC_REG reg [1:0] wbrst_s;     // WB_RESET seen in CLK
   `SUN3_ASYNC_REG reg [1:0] cpurst_s;    // ~RESET_n seen in WB_CLK
   always @(posedge CLK)    wbrst_s  <= {wbrst_s[0],  WB_RESET};
   always @(posedge WB_CLK) cpurst_s <= {cpurst_s[0], ~RESET_n};
   wire cpu_side_rst = ~RESET_n | wbrst_s[1];
   wire wb_side_rst  = WB_RESET | cpurst_s[1];

   // =========================================================================
   // CLK side: the machine's bus
   // =========================================================================
   wire MATCH_ANY = MATCH_MEM | MATCH_FB;

   // The request's fields, formed as sun3_wishbone_bridge forms its Wishbone
   // outputs: the frame buffer at the top 2 MiB of the first 256 MiB of DDR3.
   wire [29:0] q_adr = MATCH_FB ? {11'h07F, P_ADR_IN[20:2]} : P_ADR_IN[31:2];
   wire [31:0] q_dat = P_DATA_IN;
   wire  [3:0] q_sel = P_RW_n ? 4'hF : {EN_UUBYTE, EN_ULBYTE, EN_LUBYTE, EN_LLBYTE};
   wire        q_we  = ~P_RW_n;

   reg                 issued, done;
   reg  [TAG_BITS-1:0] tag;            // the tag of the read now waiting, or last sent

   wire                rq_full;
   wire                enq = MATCH_ANY & ~issued & ~rq_full;

   wire                rs_empty;
   wire [RSW-1:0]      rs_head;
   wire [TAG_BITS-1:0] rs_tag = rs_head[RSW-1:32];
   wire [31:0]         rs_dat = rs_head[31:0];

   // Waiting for a read's answer: queued in this cycle, not yet answered.
   wire                rd_wait = MATCH_ANY & issued & ~done & P_RW_n;
   wire                rs_ours = ~rs_empty & rd_wait & (rs_tag == tag);
   // Anything else at the head is a stale answer and is dropped.
   wire                rs_stale = ~rs_empty & ~rs_ours;
   wire                rs_pop   = rs_ours | rs_stale;

   // One clock each: a write the clock after it was queued, a read the clock
   // its answer is taken.
   wire                wr_ack = MATCH_ANY & issued & ~done & q_we;
   assign W_ACK = rs_ours | wr_ack;

   wire [TAG_BITS-1:0] tag_next = tag + {{(TAG_BITS-1){1'b0}}, 1'b1};

   always @(posedge CLK) begin
      if (cpu_side_rst)
        tag <= {TAG_BITS{1'b0}};
      else if (enq & ~q_we)
        tag <= tag_next;

      if (cpu_side_rst | ~MATCH_ANY) begin
         issued <= 1'b0;
         done   <= 1'b0;
      end else begin
         if (enq)              issued <= 1'b1;
         if (wr_ack | rs_ours) done   <= 1'b1;
      end

      if (cpu_side_rst)
        P_DATA_OUT <= 32'h0;
      else if (rs_ours)
        P_DATA_OUT <= rs_dat;
   end

   // A read's tag is the next one; a write carries the current tag, unused.
   wire [TAG_BITS-1:0] q_tag = q_we ? tag : tag_next;

   // =========================================================================
   // The FIFOs
   // =========================================================================
   wire               rq_empty;
   wire [RQW-1:0]     rq_head;
   wire               rq_pop;

   sun3_async_fifo #(.WIDTH(RQW), .ADDR(REQ_ADDR)) req_fifo (
      .wclk(CLK),    .wrst(cpu_side_rst), .wr_en(enq),
      .wr_data({q_tag, q_we, q_adr, q_dat, q_sel}), .wfull(rq_full),
      .rclk(WB_CLK), .rrst(wb_side_rst),  .rd_en(rq_pop),
      .rd_data(rq_head), .rempty(rq_empty));

   wire               rs_full;
   wire               rs_push;
   wire [RSW-1:0]     rs_in;

   sun3_async_fifo #(.WIDTH(RSW), .ADDR(RSP_ADDR)) rsp_fifo (
      .wclk(WB_CLK), .wrst(wb_side_rst),  .wr_en(rs_push),
      .wr_data(rs_in), .wfull(rs_full),
      .rclk(CLK),    .rrst(cpu_side_rst), .rd_en(rs_pop),
      .rd_data(rs_head), .rempty(rs_empty));

   // =========================================================================
   // WB_CLK side: one Wishbone transaction at a time, from the queue's head
   // =========================================================================
   reg                busy;
   reg [TAG_BITS-1:0] c_tag;
   reg                c_we;
   reg [29:0]         c_adr;
   reg [31:0]         c_dat;
   reg  [3:0]         c_sel;

   assign wb_cyc_o = busy;
   assign wb_stb_o = busy;
   assign wb_we_o  = busy & c_we;
   assign wb_adr_o = c_adr;
   assign wb_dat_o = c_dat;
   assign wb_sel_o = c_sel;

   // Take a request only with room to answer it, so a read's answer is never
   // dropped for want of space.
   wire start = ~busy & ~rq_empty & ~rs_full;

   assign rq_pop  = start;
   assign rs_push = busy & wb_ack_i & ~c_we;
   assign rs_in   = {c_tag, wb_dat_i};

   always @(posedge WB_CLK) begin
      if (wb_side_rst) begin
         busy <= 1'b0;
      end else if (start) begin
         busy <= 1'b1;
         {c_tag, c_we, c_adr, c_dat, c_sel} <= rq_head;
      end else if (busy & wb_ack_i) begin
         busy <= 1'b0;
      end
   end

endmodule
