`timescale 1ns / 1ps

`include "sun3_attr.vh"

//
// sun3_fifo_bridge with a read cache in front of it (SUN3_WB_CACHE).
//
// Everything sun3_fifo_bridge.v says about the two FIFOs, the tags, ordering,
// resets and the machine-visible timing holds here and is not repeated.  What
// is added is a direct-mapped cache of 128-bit lines -- the width of a MIG beat
// and of a BrianHG line, so a read miss brings a whole line back for the cost
// of one word -- on the machine's side of the request queue, in CLK.  Ported
// from the Sun-2 project's sun2_cached_fifo_bridge.v.
//
// **Why it cannot go stale.**  Every master's every memory cycle -- the CPU,
// and DVMA (Ethernet, SCSI) through the same 68020 bus and MMU -- comes
// through this one bridge, and nothing else writes DDR3.
//   * Writes are write-through, no-allocate: queued exactly as before, and a
//     write that hits updates the cached line on the edge it is queued.  A
//     read that hits afterwards sees it before DDR3 does, which is correct.
//   * A read miss holds the bus until its line comes back, so nothing can
//     write that line while it is being fetched; and the fill request is
//     queued behind any writes still waiting, so the line it brings back
//     contains them.
//   * A line is installed only from the answer this bridge is waiting for --
//     the tag check that already drops stale answers.  An abandoned read's
//     late answer could arrive after a write to that very line.
//   * The frame buffer window is not cached: MATCH_FB reads go to memory and
//     its writes never touch the cache.
//
// **A hit costs no memory wait.**  The cache RAMs are read every clock, so
// what they show in the first clock of MATCH_MEM is the lookup made with the
// address of the edge before.  The index is the line within the page: with
// IDX <= 9 (8 KiB, the Sun-3 page) it is P_ADR_IN[12:4], which is the CPU's
// own address (sun3_fpga passes A[12:0] straight through), valid from the
// start of the cycle -- long before MATCH_MEM (C_S6).  Only the tag compare
// uses the MMU's physical page, and it is made combinationally against the
// address of the clock MATCH_MEM is up in.  A hit raises W_ACK in that first
// clock and loads P_DATA_OUT on the edge that ends it, as a miss's answer is.
//
// A larger IDX takes index bits from the page map's output too.  Whether
// those are stable an edge before C_S6 depends on the MMU's timing, so the
// lookup is guarded: it counts only if it was made with the index now on the
// bus, and no cache write landed on the edge that registered it.  Anything
// else is treated as a miss (reads) or invalidates the line (writes), which
// is always safe; the simulation counts how often it happens.
//
// **Storage.**  Four RAMs of 32 bits, one per word of a line, with a write
// enable per byte, so a fill writes all four in one clock and a write hit
// writes its bytes; and a tag RAM of {valid, tag}.  The valid bits are
// cleared by a sweep at reset, one line per clock (2**IDX clocks, long before
// the PROM's first memory access), not by trusting either vendor's RAM to
// power up as zeros.  Main memory is at most 256 MiB, so the tag is the
// physical line address above the index, below bit 28.
//
// Line layout, as wb_mig_sync, deca_wb_ddr3_sync and wb_ram_model return it:
// word k of the line (P_ADR_IN[3:2] == k) is wb_line_i[k*32 +: 32], and a
// word's bytes are as on the bus (wb_sel_o[3] = bits 31:24).
//
module sun3_cached_fifo_bridge #(
   parameter TAG_BITS = 4,
   parameter REQ_ADDR = 4,                  // request FIFO depth 2**REQ_ADDR
   parameter RSP_ADDR = 2,
   parameter IDX      = 9                   // 2**IDX lines of 16 bytes
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
   input             wb_ack_i,
   input     [127:0] wb_line_i              // the whole line, valid with wb_ack_i
);

   localparam RQW   = TAG_BITS + 1 + 30 + 32 + 4;
   localparam RSW   = TAG_BITS + 128;
   localparam LINES = 1 << IDX;
   localparam TAGW  = 28 - (IDX + 4);       // P_ADR_IN[27:IDX+4]

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
   wire CACHEABLE = MATCH_MEM & ~MATCH_FB;

   wire [29:0] q_adr = MATCH_FB ? {11'h07F, P_ADR_IN[20:2]} : P_ADR_IN[31:2];
   wire [31:0] q_dat = P_DATA_IN;
   wire  [3:0] q_sel = P_RW_n ? 4'hF : {EN_UUBYTE, EN_ULBYTE, EN_LUBYTE, EN_LLBYTE};
   wire        q_we  = ~P_RW_n;

   // ---- the cache ----------------------------------------------------------
   wire [IDX-1:0]  cur_idx  = P_ADR_IN[IDX+3:4];
   wire [TAGW-1:0] cur_tag  = P_ADR_IN[27:IDX+4];
   wire [1:0]      cur_w    = P_ADR_IN[3:2];          // word within the line

   // Reset sweep of the valid bits.
   reg [IDX:0] swp;                                    // top bit = done
   wire        swp_done = swp[IDX];

   // One write port on every cache RAM, driven by exactly one of: the sweep,
   // a fill, a write hit, an invalidation.
   reg             t_we;                // tag RAM
   reg  [IDX-1:0]  t_wa;
   reg  [TAGW:0]   t_wd;                // {valid, tag}
   reg  [15:0]     d_we;                // per word, per byte: [w*4 + b]
   reg  [IDX-1:0]  d_wa;
   reg  [127:0]    d_wd;
   wire            cache_we = t_we | (|d_we);

   // The read ports, free-running on the bus address.
   `SUN3_RAM_BLOCK reg [TAGW:0] tmem [0:LINES-1];
   reg  [TAGW:0]   tq;
   always @(posedge CLK) begin
      if (t_we) tmem[t_wa] <= t_wd;
      tq <= tmem[cur_idx];
   end

   wire [31:0] dq [0:3];
   genvar g;
   generate
      for (g = 0; g < 4; g = g + 1) begin : dline
         `SUN3_RAM_BLOCK reg [31:0] dmem [0:LINES-1];
         reg [31:0] q;
         always @(posedge CLK) begin
            if (d_we[g*4+3]) dmem[d_wa][31:24] <= d_wd[g*32+24 +: 8];
            if (d_we[g*4+2]) dmem[d_wa][23:16] <= d_wd[g*32+16 +: 8];
            if (d_we[g*4+1]) dmem[d_wa][15: 8] <= d_wd[g*32+ 8 +: 8];
            if (d_we[g*4+0]) dmem[d_wa][ 7: 0] <= d_wd[g*32    +: 8];
            q <= dmem[cur_idx];
         end
         assign dq[g] = q;
      end
   endgenerate

   // Is what the RAMs are showing now a lookup of the index on the bus now?
   reg  [IDX-1:0] lk_idx;
   reg            lk_cwr;
   always @(posedge CLK) begin
      lk_idx <= cur_idx;
      lk_cwr <= cache_we;
   end
   wire lk_ok  = swp_done & (lk_idx == cur_idx) & ~lk_cwr;
   wire lk_hit = lk_ok & tq[TAGW] & (tq[TAGW-1:0] == cur_tag);

   // ---- the transaction ----------------------------------------------------
   reg                 issued, done;
   reg  [TAG_BITS-1:0] tag;            // the tag of the read now waiting, or last sent

   wire                rd_hit = CACHEABLE & P_RW_n & ~issued & ~done & lk_hit;

   wire                rq_full;
   wire                enq = MATCH_ANY & ~issued & ~done & ~rq_full & ~rd_hit;

   wire                rs_empty;
   wire [RSW-1:0]      rs_head;
   wire [TAG_BITS-1:0] rs_tag  = rs_head[RSW-1:128];
   wire [127:0]        rs_line = rs_head[127:0];

   wire                rd_wait  = MATCH_ANY & issued & ~done & P_RW_n;
   wire                rs_ours  = ~rs_empty & rd_wait & (rs_tag == tag);
   wire                rs_stale = ~rs_empty & ~rs_ours;
   wire                rs_pop   = rs_ours | rs_stale;

   // One clock each: a read hit at once, a write the clock after it was
   // queued, a read miss the clock its answer is taken.
   wire                wr_ack = MATCH_ANY & issued & ~done & q_we;
   assign W_ACK = rd_hit | rs_ours | wr_ack;

   wire [TAG_BITS-1:0] tag_next = tag + {{(TAG_BITS-1){1'b0}}, 1'b1};

   // What the cache RAMs are told to do on this edge.
   wire wr_now = enq & q_we & CACHEABLE;    // a write being queued
   wire fill   = rs_ours & CACHEABLE;       // our line has come back
   always @(*) begin
      t_we = 1'b0; t_wa = cur_idx; t_wd = {1'b0, cur_tag};
      d_we = 16'h0000; d_wa = cur_idx;
      d_wd = {4{P_DATA_IN}};
      if (~swp_done) begin
         t_we = 1'b1; t_wa = swp[IDX-1:0]; t_wd = {(TAGW+1){1'b0}};
      end else if (fill) begin
         t_we = 1'b1; t_wd = {1'b1, cur_tag};
         d_we = 16'hFFFF; d_wd = rs_line;
      end else if (wr_now & lk_hit) begin
         d_we[cur_w*4 +: 4] = q_sel;
      end else if (wr_now & ~lk_ok) begin
         // Could not tell whether the line is here: make sure it is not.
         t_we = 1'b1; t_wd = {(TAGW+1){1'b0}};
      end
   end

   always @(posedge CLK) begin
      if (cpu_side_rst)   swp <= {(IDX+1){1'b0}};
      else if (~swp_done) swp <= swp + {{IDX{1'b0}}, 1'b1};

      if (cpu_side_rst)
        tag <= {TAG_BITS{1'b0}};
      else if (enq & ~q_we)
        tag <= tag_next;

      if (cpu_side_rst | ~MATCH_ANY) begin
         issued <= 1'b0;
         done   <= 1'b0;
      end else begin
         if (enq)                       issued <= 1'b1;
         if (wr_ack | rs_ours | rd_hit) done   <= 1'b1;
      end

      if (cpu_side_rst)
        P_DATA_OUT <= 32'h0;
      else if (rd_hit)
        P_DATA_OUT <= dq[cur_w];
      else if (rs_ours)
        P_DATA_OUT <= rs_line[cur_w*32 +: 32];
   end

   // A read's tag is the next one; a write carries the current tag, unused.
   wire [TAG_BITS-1:0] q_tag = q_we ? tag : tag_next;

`ifdef SUN3_SIM
   // What the cache did, for tb_sun3's report and the unit test.
   integer n_hit = 0, n_miss = 0, n_uncached = 0, n_whit = 0, n_wmiss = 0,
           n_winval = 0, n_fill = 0, n_rd_notok = 0;
   always @(posedge CLK) if (~cpu_side_rst) begin
      if (rd_hit)                           n_hit      = n_hit + 1;
      if (enq & ~q_we & CACHEABLE)          n_miss     = n_miss + 1;
      if (enq & ~q_we & ~CACHEABLE)         n_uncached = n_uncached + 1;
      if (enq & ~q_we & CACHEABLE & ~lk_ok) n_rd_notok = n_rd_notok + 1;
      if (wr_now & lk_hit)                  n_whit     = n_whit + 1;
      if (wr_now & lk_ok & ~lk_hit)         n_wmiss    = n_wmiss + 1;
      if (wr_now & ~lk_ok)                  n_winval   = n_winval + 1;
      if (fill)                             n_fill     = n_fill + 1;
   end
`endif

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

   // Take a request only with room to answer it.
   wire start = ~busy & ~rq_empty & ~rs_full;

   assign rq_pop  = start;
   assign rs_push = busy & wb_ack_i & ~c_we;
   assign rs_in   = {c_tag, wb_line_i};

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
