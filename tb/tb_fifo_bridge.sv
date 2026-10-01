`timescale 1ns/1ps
//
// sun3_fifo_bridge, driven as sun3_fpga drives a bridge, with its Wishbone
// side on a clock of its own.  Adapted from the Sun-2 project's
// tb_fifo_bridge.sv to the 68020's 32-bit bus and four byte enables.
//
// Two scenarios run at once, identical but for the Wishbone clock:
//
//   fast  83 MHz against a 20 MHz CPU clock -- MIG's ui_clk against cpu_clk
//   slow  7 MHz, *slower* than the CPU      -- nothing builds this, which is
//                                              why it is worth having
//
//   1  back-to-back writes then reads, across slave latencies 0..63: every
//      word lands and reads back; a write is acknowledged the clock after it
//      is queued unless the request FIFO is full, and at high latency it
//      must fill -- the control that says backpressure was exercised
//   2  a read straight after a write to the same word, with the write still
//      queued behind a slow slave: the read must see the write
//   3  a read abandoned before its answer arrives, then another read: the
//      late answer carries the old tag and must be dropped, not taken by the
//      new cycle.  Control: stale answers were actually dropped
//   4  a read-modify-write (TAS: AS held across both): one read, one write,
//      and the write lands
//   5  byte writes on each of the four enables, and a word on each half,
//      straight through as sun3_wishbone_bridge passes them
//   6  the frame buffer window: the top 2 MiB of the first 256 MiB
//
// A read's data is taken the clock after W_ACK, as sun3_fpga takes it.
//

module fifo_bridge_scenario #(
   parameter real   WBH  = 6.0,
   parameter string NAME = "?"
) (
   output bit done,
   output int checks,
   output int fails
);
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

   wire         wb_cyc_o, wb_stb_o, wb_we_o;
   wire  [29:0] wb_adr_o;
   wire  [31:0] wb_dat_o;
   wire   [3:0] wb_sel_o;
   logic [31:0] wb_dat_i = '0;
   bit          wb_ack_i = 0;

   sun3_fifo_bridge dut (
      .RESET_n(RESET_n), .CLK(CLK),
      .P_ADR_IN(P_ADR_IN), .P_DATA_IN(P_DATA_IN), .P_DATA_OUT(P_DATA_OUT),
      .P_RW_n(P_RW_n),
      .EN_LLBYTE(EN[0]), .EN_LUBYTE(EN[1]), .EN_ULBYTE(EN[2]), .EN_UUBYTE(EN[3]),
      .MATCH_MEM(MATCH_MEM), .MATCH_FB(MATCH_FB), .W_ACK(W_ACK),
      .WB_CLK(WB_CLK), .WB_RESET(WB_RESET),
      .wb_cyc_o(wb_cyc_o), .wb_stb_o(wb_stb_o), .wb_adr_o(wb_adr_o),
      .wb_dat_o(wb_dat_o), .wb_sel_o(wb_sel_o), .wb_we_o(wb_we_o),
      .wb_dat_i(wb_dat_i), .wb_ack_i(wb_ack_i));

   task automatic check(input string what, input bit cond);
      checks++;
      if (!cond) begin
         fails++;
         if (fails <= 16) $display("  %s: FAIL %s", NAME, what);
      end
   endtask

   // ---- a registered Wishbone slave on WB_CLK, with settable wait states ----
   int          LAT = 0;
   logic [31:0] mem [0:1023];
   int          n_wr = 0, n_rd = 0, wcnt = 0;
   logic [29:0] last_adr;

   always @(posedge WB_CLK) begin
      wb_ack_i <= 1'b0;
      if (wb_cyc_o && wb_stb_o && !wb_ack_i) begin
         if (wcnt >= LAT) begin
            wcnt <= 0;
            wb_ack_i <= 1'b1;
            last_adr <= wb_adr_o;
            if (wb_we_o) begin
               n_wr++;
               if (wb_sel_o[0]) mem[wb_adr_o[9:0]][ 7: 0] <= wb_dat_o[ 7: 0];
               if (wb_sel_o[1]) mem[wb_adr_o[9:0]][15: 8] <= wb_dat_o[15: 8];
               if (wb_sel_o[2]) mem[wb_adr_o[9:0]][23:16] <= wb_dat_o[23:16];
               if (wb_sel_o[3]) mem[wb_adr_o[9:0]][31:24] <= wb_dat_o[31:24];
            end else begin
               n_rd++;
               wb_dat_i <= mem[wb_adr_o[9:0]];
            end
         end else
            wcnt <= wcnt + 1;
      end else if (!wb_cyc_o)
         wcnt <= 0;
   end

   int n_stale = 0;
   always @(posedge CLK) if (dut.rs_stale) n_stale++;

   // ---- one memory cycle, as sun3_fpga presents it -------------------------
   task automatic bus_cycle(input logic [31:0] adr, input bit rw_n, input logic [31:0] wdata,
                            input logic [3:0] en, input bit fb, input int gap,
                            output logic [31:0] rdata, output int nclk);
      int guard;
      begin
         @(posedge CLK);
         P_ADR_IN <= adr; P_RW_n <= rw_n; P_DATA_IN <= wdata; EN <= en;
         MATCH_MEM <= ~fb; MATCH_FB <= fb;
         guard = 0;
         do begin @(posedge CLK); guard++; end while (W_ACK !== 1'b1 && guard < 2000);
         nclk = guard;
         check($sformatf("%s at %08x acknowledged", rw_n ? "read" : "write", adr), guard < 2000);
         @(posedge CLK);
         rdata = P_DATA_OUT;                 // the clock after W_ACK
         MATCH_MEM <= 0; MATCH_FB <= 0; EN <= 0; P_RW_n <= 1;
         repeat (gap) @(posedge CLK);
      end
   endtask

   function automatic logic [31:0] pattern(input int k);
      pattern = 32'hC0DE0000 ^ (k * 32'h00010203);
   endfunction

   initial begin
      logic [31:0] rd;
      int nclk, bad, slow_acks, max_free_ack, wr0, rd0;

      for (int i = 0; i < 1024; i++) mem[i] = 32'hDEADBEEF;
      repeat (6) @(posedge CLK);
      repeat (6) @(posedge WB_CLK);
      WB_RESET = 0;
      @(posedge CLK) RESET_n <= 1;
      repeat (8) @(posedge CLK);

      // ---- 1: back-to-back writes then reads, across latencies ----
      slow_acks = 0; max_free_ack = 0;
      for (int li = 0; li < 5; li++) begin
         automatic int lat = (li == 0) ? 0 : (li == 1) ? 3 : (li == 2) ? 7 : (li == 3) ? 15 : 63;
         for (int gap = 1; gap <= 2; gap++) begin
            LAT = lat;
            for (int i = 0; i < 1024; i++) mem[i] = 32'hDEADBEEF;
            wr0 = n_wr; bad = 0;
            for (int i = 0; i < 64; i++) begin
               bus_cycle(32'h400 + 4*i, 0, pattern(i), 4'hF, 0, gap, rd, nclk);
               // Queued on the first edge, W_ACK on the second; more is a write
               // held back by a full (or not yet seen draining) request FIFO.
               if (nclk > 2) slow_acks++;
               else if (nclk > max_free_ack) max_free_ack = nclk;
            end
            begin
               automatic int g = 0;
               while ((n_wr - wr0 < 64 || dut.busy) && g < 200000) begin @(posedge CLK); g++; end
            end
            check($sformatf("1: lat %0d gap %0d: all 64 writes reached memory", lat, gap),
                  n_wr - wr0 == 64);
            for (int i = 0; i < 64; i++)
               if (mem[10'h100 + i] !== pattern(i)) bad++;
            check($sformatf("1: lat %0d gap %0d: every word landed with the right value", lat, gap), bad == 0);
            bad = 0;
            for (int i = 0; i < 64; i++) begin
               bus_cycle(32'h400 + 4*i, 1, 32'h0, 4'hF, 0, gap, rd, nclk);
               if (rd !== pattern(i)) begin
                  if (bad < 3) $display("  %s: lat %0d read %0d returned %08x, want %08x",
                                        NAME, lat, i, rd, pattern(i));
                  bad++;
               end
            end
            check($sformatf("1: lat %0d gap %0d: every read returned its word", lat, gap), bad == 0);
         end
      end
      $display("  %s: writes with room in the queue saw W_ACK on sampled edge %0d; %0d waited on a full queue",
               NAME, max_free_ack, slow_acks);
      check("1: a write with room in the queue is acknowledged the clock after it is queued",
            max_free_ack == 2);
      check("1: control: the request FIFO filled and held a write back", slow_acks > 0);

      // ---- 2: read straight after a write to the same word, write still queued ----
      LAT = 15; bad = 0;
      for (int i = 0; i < 32; i++) begin
         automatic logic [31:0] v = 32'h71007100 ^ (i * 32'h01230123);
         bus_cycle(32'h600 + 8*i, 0, v, 4'hF, 0, 1, rd, nclk);
         bus_cycle(32'h600 + 8*i, 1, 32'h0, 4'hF, 0, 1, rd, nclk);
         if (rd !== v) begin
            if (bad < 3) $display("  %s: read after write returned %08x, want %08x", NAME, rd, v);
            bad++;
         end
      end
      check("2: a read queued behind an unperformed write sees the write (32 of 32)", bad == 0);

      // ---- 3: an abandoned read's late answer is dropped ----
      LAT = 20; bad = 0;
      mem[10'h300] = 32'hAAAA1111;
      mem[10'h301] = 32'hBBBB2222;
      repeat (400) @(posedge CLK);
      for (int k = 0; k < 8; k++) begin
         @(posedge CLK);
         P_ADR_IN <= 32'hC00; P_RW_n <= 1; EN <= 4'hF; MATCH_MEM <= 1;
         repeat (3) @(posedge CLK);
         MATCH_MEM <= 0; EN <= 0;
         @(posedge CLK);
         bus_cycle(32'hC04, 1, 32'h0, 4'hF, 0, 1, rd, nclk);
         if (rd !== 32'hBBBB2222) begin
            if (bad < 3) $display("  %s: second read returned %08x, want bbbb2222", NAME, rd);
            bad++;
         end
      end
      $display("  %s: stale answers dropped: %0d", NAME, n_stale);
      check("3: a read after an abandoned one returns its own word (8 of 8)", bad == 0);
      check("3: control: the abandoned reads' answers arrived and were dropped", n_stale >= 8);

      // ---- 4: read-modify-write, AS held across both cycles ----
      for (int li = 0; li < 2; li++) begin
         LAT = li ? 7 : 0;
         mem[10'h200] = 32'h11112222;
         repeat (400) @(posedge CLK);
         wr0 = n_wr; rd0 = n_rd;
         @(posedge CLK);
         P_ADR_IN <= 32'h800; P_RW_n <= 1; EN <= 4'hF; MATCH_MEM <= 1;
         begin automatic int g = 0; do begin @(posedge CLK); g++; end while (W_ACK !== 1'b1 && g < 2000); end
         @(posedge CLK);
         rd = P_DATA_OUT;
         // Between the two cycles of a TAS the 68020 drops DS but not AS; in
         // sun3_fpga MATCH_MEM follows the C_S chain, which restarts with DS.
         MATCH_MEM <= 0; EN <= 0;
         repeat (2) @(posedge CLK);
         P_RW_n <= 0; P_DATA_IN <= rd | 32'h80000000;
         @(posedge CLK);
         EN <= 4'b1000; MATCH_MEM <= 1;
         begin automatic int g = 0; do begin @(posedge CLK); g++; end while (W_ACK !== 1'b1 && g < 2000); end
         @(posedge CLK);
         MATCH_MEM <= 0; EN <= 0; P_RW_n <= 1;
         repeat (400) @(posedge CLK);
         check($sformatf("4: lat %0d: RMW issues one read and one write, and the write lands", LAT),
               n_rd - rd0 == 1 && n_wr - wr0 == 1 && mem[10'h200] === 32'h91112222
               && rd === 32'h11112222);
      end

      // ---- 5: byte lanes ----
      LAT = 1;
      mem[10'h280] = 32'h0;
      bus_cycle(32'hA00, 0, 32'hA1000000, 4'b1000, 0, 1, rd, nclk);
      bus_cycle(32'hA01, 0, 32'h00B20000, 4'b0100, 0, 1, rd, nclk);
      bus_cycle(32'hA02, 0, 32'h0000C300, 4'b0010, 0, 1, rd, nclk);
      bus_cycle(32'hA03, 0, 32'h000000D4, 4'b0001, 0, 1, rd, nclk);
      repeat (100) @(posedge CLK);
      check($sformatf("5: byte writes on each enable (memory %08x, want a1b2c3d4)", mem[10'h280]),
            mem[10'h280] === 32'hA1B2C3D4);
      bus_cycle(32'hA00, 0, 32'hE5F60000, 4'b1100, 0, 1, rd, nclk);
      bus_cycle(32'hA02, 0, 32'h00000718, 4'b0011, 0, 1, rd, nclk);
      bus_cycle(32'hA00, 1, 32'h0, 4'hF, 0, 1, rd, nclk);
      check($sformatf("5: word writes on each half read back (%08x)", rd), rd === 32'hE5F60718);

      // ---- 6: frame buffer window ----
      bus_cycle(32'hFF1234A8, 0, 32'h1234, 4'hF, 1, 1, rd, nclk);
      repeat (100) @(posedge CLK);
      check($sformatf("6: the frame buffer is at the top 2 MiB of 256 MiB (%08x)", last_adr),
            last_adr === {11'h07F, 19'(32'h1234A8 >> 2)});

      done = 1;
   end
endmodule

module tb_fifo_bridge;
   bit done_f, done_s;
   int checks_f, checks_s, fails_f, fails_s;

   fifo_bridge_scenario #(.WBH(6.0),  .NAME("fast WB clock")) f (.done(done_f), .checks(checks_f), .fails(fails_f));
   fifo_bridge_scenario #(.WBH(71.0), .NAME("slow WB clock")) s (.done(done_s), .checks(checks_s), .fails(fails_s));

   initial begin
      $display("=== tb_fifo_bridge: sun3_fifo_bridge, CPU at 20 MHz, Wishbone at 83 and 7 MHz ===");
      wait (done_f && done_s);
      $display("=== %0d checks, %0d failures ===", checks_f + checks_s, fails_f + fails_s);
      if (fails_f + fails_s == 0) $display("PASS"); else $display("FAIL");
      $finish;
   end
   initial begin #2_000_000_000; $display("FAIL: timeout"); $finish; end
endmodule
