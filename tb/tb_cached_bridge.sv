`timescale 1ns/1ps
//
// sun3_cached_fifo_bridge: a read cache in front of the FIFO bridge.  Adapted
// from the Sun-2 project's tb_cached_bridge.sv to the 68020's 32-bit bus.
//
// The cache's whole claim is that it can never return anything the bus would
// not have returned without it.  So the heart of this test is a *bus-level
// shadow*: every write, as the bus presents it, updates the shadow the moment
// it is acknowledged, and every read, hit or miss, is compared against it.
// The Wishbone slave behind the bridge is only the backing store.
//
// Directed checks, one per rule the design relies on:
//   1  the reset sweep: the first read of a line is a miss
//   2  a line brought in by one miss serves its other three words as hits,
//      with W_ACK in the cycle's first clock
//   3  a write hit updates the cached line (each byte enable on its own)
//   4  a write miss allocates nothing, and the next read of that line sees it
//   5  two lines on the same index evict each other and both stay right
//   6  a write whose lookup cannot be trusted (its index on the bus too late)
//      invalidates the line rather than leaving it stale
//   7  an abandoned read's late answer is never installed -- held under a long
//      cacheable write cycle, which is when a careless install would land
//   8  frame-buffer reads are never cached, even on a cached line's address
//   9  the Sun-3's case: the index (page offset) is on the bus early but the
//      physical page arrives only with MATCH_MEM, as the MMU may deliver it.
//      The lookup is used, and the tag is compared with the page now: a hit
//      only when that page's line is the cached one
// then a long randomised run of all of it, against the shadow.  The tag RAM
// starts full of false "valid" lines, so a missing reset sweep shows.
//
// Two scenarios, Wishbone at 83 MHz and at 7 MHz against a 20 MHz CPU, each
// with an 8-line cache so that aliasing is constant rather than rare.
//

module cached_scenario #(
   parameter real   WBH  = 6.0,
   parameter string NAME = "?"
) (
   output bit done,
   output int checks,
   output int fails
);
   localparam int IDX = 3;                  // 8 lines of 16 bytes

   bit CLK = 0, WB_CLK = 0;
   always #25    CLK    = ~CLK;
   always #(WBH) WB_CLK = ~WB_CLK;

   bit          RESET_n = 0, WB_RESET = 1;
   logic [31:0] P_ADR_IN = '0;
   logic [31:0] P_DATA_IN = '0;
   wire  [31:0] P_DATA_OUT;
   bit          P_RW_n = 1, MATCH_MEM = 0, MATCH_FB = 0;
   logic  [3:0] EN = '0;                     // {UU, UL, LU, LL}
   wire         W_ACK;

   wire          wb_cyc_o, wb_stb_o, wb_we_o;
   wire  [29:0]  wb_adr_o;
   wire  [31:0]  wb_dat_o;
   wire   [3:0]  wb_sel_o;
   logic [31:0]  wb_dat_i = '0;
   logic [127:0] wb_line_i = '0;
   bit           wb_ack_i = 0;

   sun3_cached_fifo_bridge #(.IDX(IDX)) dut (
      .RESET_n(RESET_n), .CLK(CLK),
      .P_ADR_IN(P_ADR_IN), .P_DATA_IN(P_DATA_IN), .P_DATA_OUT(P_DATA_OUT),
      .P_RW_n(P_RW_n),
      .EN_LLBYTE(EN[0]), .EN_LUBYTE(EN[1]), .EN_ULBYTE(EN[2]), .EN_UUBYTE(EN[3]),
      .MATCH_MEM(MATCH_MEM), .MATCH_FB(MATCH_FB), .W_ACK(W_ACK),
      .WB_CLK(WB_CLK), .WB_RESET(WB_RESET),
      .wb_cyc_o(wb_cyc_o), .wb_stb_o(wb_stb_o), .wb_adr_o(wb_adr_o),
      .wb_dat_o(wb_dat_o), .wb_sel_o(wb_sel_o), .wb_we_o(wb_we_o),
      .wb_dat_i(wb_dat_i), .wb_ack_i(wb_ack_i), .wb_line_i(wb_line_i));

   task automatic check(input string what, input bit cond);
      checks++;
      if (!cond) begin
         fails++;
         if (fails <= 16) $display("  %s: FAIL %s", NAME, what);
      end
   endtask

   // ---- the backing store: a registered Wishbone slave returning whole lines ----
   int          LAT = 2;
   logic [31:0] mem [int unsigned];
   int          wcnt = 0;
   function automatic logic [31:0] initword(input int unsigned a);
      initword = {a[15:0] ^ 16'hA55A, a[15:0] ^ 16'h0F0F};
   endfunction
   function automatic logic [31:0] rdw(input int unsigned a);
      rdw = mem.exists(a) ? mem[a] : initword(a);
   endfunction

   always @(posedge WB_CLK) begin
      wb_ack_i <= 1'b0;
      if (wb_cyc_o && wb_stb_o && !wb_ack_i) begin
         if (wcnt >= LAT) begin
            automatic int unsigned a = wb_adr_o;
            automatic logic [31:0] w = rdw(a);
            wcnt <= 0;
            wb_ack_i <= 1'b1;
            if (wb_we_o) begin
               if (wb_sel_o[0]) w[ 7: 0] = wb_dat_o[ 7: 0];
               if (wb_sel_o[1]) w[15: 8] = wb_dat_o[15: 8];
               if (wb_sel_o[2]) w[23:16] = wb_dat_o[23:16];
               if (wb_sel_o[3]) w[31:24] = wb_dat_o[31:24];
               mem[a] = w;
            end else begin
               wb_dat_i  <= w;
               wb_line_i <= {rdw(a | 3), rdw((a & ~3) | 2), rdw((a & ~3) | 1), rdw(a & ~3)};
            end
         end else
            wcnt <= wcnt + 1;
      end else if (!wb_cyc_o)
         wcnt <= 0;
   end

   // ---- the architecture: a bus-level shadow of every word --------------------
   logic [31:0] shadow [int unsigned];
   function automatic logic [29:0] wbword(input bit fb, input logic [31:0] a);
      wbword = fb ? {11'h07F, a[20:2]} : a[31:2];
   endfunction
   function automatic logic [31:0] expect_w(input bit fb, input logic [31:0] a);
      automatic int unsigned k = wbword(fb, a);
      expect_w = shadow.exists(k) ? shadow[k] : initword(k);
   endfunction

   // ---- one memory cycle ----------------------------------------------------
   //   pre    the address on the bus before the cycle (the lookup is made with
   //          it); MATCH and the real address arrive together
   //   setup  clocks `pre' is on the bus before the cycle; 0 = the address
   //          and MATCH on the same edge
   //   hold   clocks the cycle stays up after W_ACK
   //   abandon  drop the cycle after that many clocks, answered or not
   int n_rd = 0, n_bad = 0, n_first_clock_ack = 0;
   task automatic cyc(input bit fb, input logic [31:0] pre, input logic [31:0] a,
                      input bit rw_n, input logic [31:0] d, input logic [3:0] en,
                      input int setup, input int hold, input int abandon,
                      output logic [31:0] q, output bit acked);
      int n;
      begin
         @(posedge CLK);
         P_ADR_IN <= pre; P_RW_n <= rw_n; P_DATA_IN <= d;
         repeat (setup) @(posedge CLK);
         P_ADR_IN <= a;
         MATCH_MEM <= ~fb; MATCH_FB <= fb; EN <= rw_n ? 4'hF : en;
         n = 0; acked = 0;
         do begin
            @(posedge CLK); n++;
            if (W_ACK === 1'b1) acked = 1;
         end while (!acked && n < 3000 && !(abandon > 0 && n >= abandon));
         if (acked) begin
            if (n == 1 && rw_n) n_first_clock_ack++;
            @(posedge CLK);
            q = P_DATA_OUT;                         // the clock after W_ACK
            if (!rw_n) begin
               automatic logic [31:0] v = expect_w(fb, a);
               for (int b = 0; b < 4; b++) if (en[b]) v[b*8 +: 8] = d[b*8 +: 8];
               shadow[wbword(fb, a)] = v;
            end else begin
               n_rd++;
               if (q !== expect_w(fb, a)) begin
                  n_bad++;
                  if (n_bad <= 4)
                    $display("  %s: read %s %08x returned %08x, the bus says %08x", NAME,
                             fb ? "FB" : "mem", a, q, expect_w(fb, a));
               end
            end
         end else if (abandon == 0)
            check($sformatf("cycle at %08x acknowledged", a), 0);
         repeat (hold) @(posedge CLK);
         MATCH_MEM <= 0; MATCH_FB <= 0; EN <= 0; P_RW_n <= 1;
         @(posedge CLK);
      end
   endtask

   task automatic rd(input logic [31:0] a, output logic [31:0] q);
      bit k; cyc(0, a, a, 1, 32'h0, 4'hF, 1, 0, 0, q, k);
   endtask
   task automatic wr(input logic [31:0] a, input logic [31:0] d, input logic [3:0] en, input int setup);
      logic [31:0] q; bit k; cyc(0, a, a, 0, d, en, setup, 0, 0, q, k);
   endtask

   // A word of a line: 16 bytes = 4 words.
   function automatic logic [31:0] L(input int line, input int w);
      L = 32'(line * 16 + w * 4);
   endfunction

   task automatic settle();
      int g = 0;
      while ((dut.busy || !dut.rq_empty) && g < 20000) begin @(posedge CLK); g++; end
      repeat (20) @(posedge CLK);
   endtask

   int st_hit0, st_miss0, st_fill0, st_winval0, st_whit0, st_wmiss0, st_notok0, stale0;
   int n_stale = 0;
   always @(posedge CLK) if (dut.rs_stale) n_stale++;

   // In simulation RAM powers up X, which makes the hit logic fall through to
   // a miss and would hide a missing sweep.  So start from the worst case:
   // every line "valid", tagged as lines the test is about to read.
   initial for (int i = 0; i < (1 << IDX); i++) dut.tmem[i] = (1 << dut.TAGW) | 5;   // lines 40..47

   initial begin
      logic [31:0] q;
      bit          k;
      repeat (6) @(posedge CLK);
      repeat (6) @(posedge WB_CLK);
      WB_RESET = 0;
      @(posedge CLK) RESET_n <= 1;
      repeat (40) @(posedge CLK);                   // the valid-bit sweep: 8 clocks

      // ---- 1, 2: a fresh line misses, then serves its other words ----
      st_hit0 = dut.n_hit; st_miss0 = dut.n_miss;
      for (int w = 0; w < 4; w++) rd(L(40, w), q);
      check("1: the first read of a line after the sweep is a miss",
            dut.n_miss - st_miss0 == 1);
      check($sformatf("2: the line's other three words are hits (%0d)", dut.n_hit - st_hit0),
            dut.n_hit - st_hit0 == 3);
      check($sformatf("2: a hit raises W_ACK in the cycle's first clock (%0d of 3)", n_first_clock_ack),
            n_first_clock_ack >= 3);

      // ---- 3: a write hit updates the line, each byte on its own ----
      st_whit0 = dut.n_whit; st_hit0 = dut.n_hit;
      wr(L(40, 2), 32'hAB000000, 4'b1000, 1);
      wr(L(40, 2), 32'h00CD0000, 4'b0100, 1);
      wr(L(40, 2), 32'h0000EF00, 4'b0010, 1);
      wr(L(40, 2), 32'h00000012, 4'b0001, 1);
      wr(L(40, 1), 32'h12345678, 4'b1111, 1);
      rd(L(40, 2), q); check($sformatf("3: four byte writes land in the cached line (%08x)", q), q === 32'hABCDEF12);
      rd(L(40, 1), q); check("3: a whole-word write lands in the cached line", q === 32'h12345678);
      check("3: all five writes were hits, and both reads", dut.n_whit - st_whit0 == 5 && dut.n_hit - st_hit0 == 2);

      // ---- 4: a write miss allocates nothing, and memory has it ----
      st_wmiss0 = dut.n_wmiss; st_fill0 = dut.n_fill; st_miss0 = dut.n_miss;
      wr(L(41, 3), 32'h41414141, 4'hF, 1);
      check("4: a write to an absent line is a write miss, and fills nothing",
            dut.n_wmiss - st_wmiss0 == 1 && dut.n_fill == st_fill0);
      rd(L(41, 3), q);
      check("4: the next read of that line misses and sees the write", q === 32'h41414141 && dut.n_miss - st_miss0 == 1);

      // ---- 5: two lines on one index (8 lines, so line+8) evict each other ----
      st_miss0 = dut.n_miss;
      rd(L(42, 0), q); rd(L(50, 0), q); rd(L(42, 1), q); rd(L(50, 1), q);
      check("5: two lines sharing an index miss every time they alternate", dut.n_miss - st_miss0 == 4);

      // ---- 6: a write with no trustworthy lookup invalidates the line ----
      rd(L(43, 0), q);                                   // bring line 43 in
      rd(L(47, 0), q);                                   // leave another index on the bus
      st_winval0 = dut.n_winval; st_miss0 = dut.n_miss;
      wr(L(43, 3), 32'h66666666, 4'hF, 0);               // index arrives with MATCH
      check("6: a write whose lookup cannot be trusted invalidates", dut.n_winval - st_winval0 == 1);
      rd(L(43, 3), q);
      check("6: ... so the next read misses and sees the write", q === 32'h66666666 && dut.n_miss - st_miss0 == 1);

      // ---- 7: an abandoned read's late answer is never installed ----
      LAT = (WBH > 20) ? 30 : 200;
      stale0 = n_stale;
      cyc(0, L(44, 0), L(44, 0), 1, 32'h0, 4'hF, 1, 0, 3, q, k);   // read line 44, walk away
      cyc(0, L(45, 1), L(45, 1), 0, 32'h45454545, 4'hF, 1, 400, 0, q, k);
      LAT = 2;
      settle();
      check("7: the abandoned read's answer came back and was dropped", n_stale > stale0);
      rd(L(45, 1), q);
      check("7: the line written meanwhile reads back what was written, not line 44", q === 32'h45454545);
      rd(L(45, 0), q);
      check("7: ... and its other words are memory's, not line 44's", q === expect_w(0, L(45, 0)));

      // ---- 8: frame-buffer reads are never cached ----
      rd(L(46, 0), q);                                    // memory line 46 cached
      st_hit0 = dut.n_hit;
      cyc(1, L(46, 0), L(46, 0), 0, 32'hFBFBFBFB, 4'hF, 1, 0, 0, q, k);
      cyc(1, L(46, 0), L(46, 0), 1, 32'h0, 4'hF, 1, 0, 0, q, k);
      check("8: a frame-buffer read on a cached line's address is not a hit", dut.n_hit == st_hit0);
      check("8: ... and returns the frame buffer's word", q === 32'hFBFBFBFB);
      rd(L(46, 0), q);
      check("8: the memory line beside it is untouched by the FB write", q === expect_w(0, L(46, 0)));

      // ---- 9: the physical page arrives with MATCH, the index before it ----
      // Line 48 cached (index 0); line 56 shares the index, another page's line.
      rd(L(48, 1), q);
      st_hit0 = dut.n_hit; st_miss0 = dut.n_miss; st_notok0 = dut.n_rd_notok;
      // The bus shows line 56's address, then line 48's comes with MATCH: hit.
      cyc(0, L(56, 1), L(48, 1), 1, 32'h0, 4'hF, 1, 0, 0, q, k);
      check("9: late page, index early, cached line: a hit", dut.n_hit - st_hit0 == 1);
      // ... and the other way round: a miss, and line 56's own word.
      cyc(0, L(48, 2), L(56, 2), 1, 32'h0, 4'hF, 1, 0, 0, q, k);
      check("9: late page onto another line on the same index: a miss",
            dut.n_miss - st_miss0 == 1);
      check("9: neither was refused as an untrustworthy lookup", dut.n_rd_notok == st_notok0);
      // A write the same way: line 56 is now cached; the page of line 48 comes late.
      wr(L(56, 3), 32'h56565656, 4'hF, 1);
      cyc(0, L(56, 3), L(48, 3), 0, 32'h48484848, 4'hF, 1, 0, 0, q, k);
      rd(L(56, 3), q);
      check("9: a late-page write to another line leaves the cached line alone", q === 32'h56565656);
      rd(L(48, 3), q);
      check("9: ... and lands in its own", q === 32'h48484848);

      // ---- random: everything, against the shadow ----
      begin
         automatic int unsigned seed = 32'hC0FFEE11;
         for (int i = 0; i < 6000; i++) begin
            automatic int r = $urandom(seed) & 32'hFFFF;
            automatic int line = 32 + ((r >> 3) & 31);        // 32 lines on 8 indices
            automatic int pline = 32 + ((r >> 1) & 31);       // what the bus showed first
            automatic int w = r & 3;
            automatic bit fb = ((r >> 8) & 15) == 0;
            automatic bit wr_ = ((r >> 12) & 3) == 0;
            automatic int setup = ((r >> 14) & 3) == 0 ? 0 : 1 + ((r >> 5) & 1);
            automatic logic [3:0] en = 4'((r >> 9) & 15);
            automatic int ab = (!wr_ && ((r >> 10) & 63) == 0) ? 2 : 0;
            // Mostly the address is steady; sometimes only the page changes
            // with MATCH (the MMU), sometimes the index too.
            automatic logic [31:0] a  = L(line, w);
            automatic logic [31:0] pa = L(pline, w);
            automatic logic [31:0] pre = ((r >> 6) & 3) == 0 ? pa :
                                         ((r >> 6) & 3) == 1 ? {pa[31:IDX+4], a[IDX+3:0]} : a;
            seed = seed * 1103515245 + 12345;
            if (en == 0) en = 4'hF;
            LAT = ((r >> 13) & 7) == 0 ? 20 : 2;
            cyc(fb, pre, a, !wr_, 32'(r * 40503) ^ 32'h5A5A0000, en, setup, 0, ab, q, k);
         end
      end
      settle();
      $display("  %s: %0d reads checked against the bus, %0d wrong; cache: %0d hits, %0d misses (%0d not usable), %0d uncached, %0d fills, %0d write hits, %0d write misses, %0d invalidations; %0d stale answers dropped",
               NAME, n_rd, n_bad, dut.n_hit, dut.n_miss, dut.n_rd_notok, dut.n_uncached, dut.n_fill,
               dut.n_whit, dut.n_wmiss, dut.n_winval, n_stale);
      check("every read, hit or miss, returned what the bus says it should", n_bad == 0);
      check("control: hits, misses, fills, write hits, write misses and invalidations all happened",
            dut.n_hit > 0 && dut.n_miss > 0 && dut.n_fill > 0 && dut.n_whit > 0 && dut.n_wmiss > 0 && dut.n_winval > 0);
      check("control: stale answers were dropped", n_stale > 0);
      done = 1;
   end
endmodule

module tb_cached_bridge;
   bit done_f, done_s;
   int checks_f, checks_s, fails_f, fails_s;
   cached_scenario #(.WBH(6.0),  .NAME("fast WB clock")) f (.done(done_f), .checks(checks_f), .fails(fails_f));
   cached_scenario #(.WBH(71.0), .NAME("slow WB clock")) s (.done(done_s), .checks(checks_s), .fails(fails_s));
   initial begin
      $display("=== tb_cached_bridge: sun3_cached_fifo_bridge, 8 lines, CPU at 20 MHz, Wishbone at 83 and 7 MHz ===");
      wait (done_f && done_s);
      $display("=== %0d checks, %0d failures ===", checks_f + checks_s, fails_f + fails_s);
      if (fails_f + fails_s == 0) $display("PASS"); else $display("FAIL");
      $finish;
   end
   initial begin #(4.0e9); $display("FAIL: timeout"); $finish; end
endmodule
