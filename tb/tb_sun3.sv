`timescale 1ns / 1ps

`include "sun3_config.vh"

//
// Core-level testbench for the Sun-3 replica: sun3_top with the clocks it
// needs, a behavioural Wishbone RAM for main memory, and the serial console
// decoded into console.log.
//
// Plusargs:
//   +timeout_ms=<real>   give up after this much simulated time (default 2000)
//   +stop_on=<string>    finish as soon as this appears on the console
//   +diag                set the diag switch: the self test prints as it goes
//   +type=<line>         at the prompt, type <line> (`_' for a space) and stop at the next prompt
//   +keep_running        ... or keep running to the timeout after typing it
//   +load=<file>@<addr>  at the prompt, load a raw binary into memory (hex byte address)
//   +berr_log            every bus error to berr.txt
//   +pc_sample_ms=<t>    the last program fetch every <t> ms, to pcsample.txt
//   +fb_dump             write the bw2 window to fb.mem at the end (for
//                        make -C sim screenshot); +fb_dump_ms=<t> also during
//   +stall_ms=<t>        end the run after this long with no bus cycle (default 100)
//   +trace_from_ms=<t>   log every bus cycle from then on to trace.txt
//   +trace_until_ms=<t>  ... and stop logging at <t>
//   +trace_io            ... leaving out PROM and main memory cycles
//   +watch_from_us=<t> +watch_until_us=<t>  bus signals on every clock edge
//   +vcd                 dump everything to sun3.vcd (needs SUN3_VCD=1 at
//                        elaboration for signal visibility)
//
// Parameters (-generic_top):
//   CPU_HZ        CPU/bus clock (default 20 MHz, as the old build ran)
//   BAUD          console decode rate (default 9600)
//   MEM_LATENCY   Wishbone wait states before ack (default 0)
//   MEM_FILL      what never-written memory reads as (default 0)
//

module tb_sun3 #(
    parameter int CPU_HZ      = 20000000,
    parameter int BAUD        = 9600,
    parameter int MEM_LATENCY = 0,
    // What a never-written word of memory reads as.  0 by default; a real
    // machine's PROM fills all of memory with 0xFFFFFFFF, which the fast ROM
    // only does for 64 KiB per megabyte.
    parameter logic [31:0] MEM_FILL = 32'h00000000
) ();

   // ---- clocks ------------------------------------------------------------
   localparam real CPU_HALF = 1.0e9 / real'(CPU_HZ) / 2.0;
   localparam real SCC_HALF = 1.0e9 / 4915200.0 / 2.0;
   localparam real TOD_HALF = 1.0e9 / 32768.0 / 2.0;

   logic CLK = 1'b0;
   logic clk4m9152 = 1'b0;
   logic clk32k768 = 1'b0;

   always #(CPU_HALF) CLK       = ~CLK;
   always #(SCC_HALF) clk4m9152 = ~clk4m9152;
   always #(TOD_HALF) clk32k768 = ~clk32k768;

   // ---- reset -------------------------------------------------------------
   // Memory is ready at once here, so the board reset is just long enough for
   // everything to see it.
   logic sys_reset = 1'b1;
   initial begin
      #1000;
      @(posedge CLK);
      sys_reset <= 1'b0;
   end

   // ---- DUT ---------------------------------------------------------------
   // The diag switch: with it on, the PROM narrates its self test on ttya
   // (and does not autoboot); off, the self test is silent.
   logic diag_switch = 1'b0;
   initial diag_switch = $test$plusargs("diag");

   wire        tx;
   wire        rx;
   wire        kbd_tx;
   wire [7:0]  leds;
   wire        en_boot;
   wire [7:0]  todebug;
   wire        fb_video_en;

   wire        wb_cyc, wb_stb, wb_we, wb_ack;
   wire [29:0] wb_adr;
   wire [31:0] wb_dat_w, wb_dat_r;
   wire [3:0]  wb_sel;

`ifdef SUN3_ETH_WISH7990
   // No PHY: an idle MII, with the clocks a 100 Mb/s link would give.
   logic       mii_clk = 1'b0;
   always #20 mii_clk = ~mii_clk;
   wire [3:0]  phy_txd;
   wire        phy_tx_en, phy_tx_er, phy_reset_n;
`endif

   wire [127:0] wb_line;          // the read's whole line, for the cached bridge

`ifdef SUN3_WB_FIFO
   // The FIFO bridge's Wishbone side runs in the memory controller's clock:
   // MIG's ui_clk on the Wukong, 83.33 MHz, stood in for here (MEM_LATENCY
   // then counts its cycles), with its own reset released from sys_reset.
   logic wb_clk = 1'b0;
   always #6.0 wb_clk = ~wb_clk;
   logic wb_rst = 1'b1;
   always @(posedge wb_clk) wb_rst <= sys_reset;
   wire mem_clk = wb_clk, mem_rst = wb_rst;
`else
   wire mem_clk = CLK, mem_rst = sys_reset;
`endif

`ifdef SUN3_SCSI
   // The SCSI disk: a file (+blk_image=<file>), behind the block seam.
   wire        blk_start, blk_we, blk_done, blk_err, blk_ready, blk_buf_we;
   wire [31:0] blk_lba, blk_count;
   wire [7:0]  blk_buf_rdata, blk_buf_wdata;
   wire [8:0]  blk_buf_addr;

   blk_file #(.MAX_BLOCKS(65536)) disk (
      .clk (CLK), .rst (sys_reset),
      .blk_start (blk_start), .blk_we (blk_we), .blk_lba (blk_lba),
      .blk_buf_rdata (blk_buf_rdata),
      .blk_done (blk_done), .blk_err (blk_err), .blk_ready (blk_ready),
      .blk_count (blk_count), .blk_buf_we (blk_buf_we),
      .blk_buf_addr (blk_buf_addr), .blk_buf_wdata (blk_buf_wdata));
`endif

   sun3_top dut (
      .CLK         (CLK),
      .clk4m9152   (clk4m9152),
      .clk32k768   (clk32k768),
      .sys_reset   (sys_reset),
      .trace_freeze (1'b0),
      .tx          (tx),
      .rx          (rx),
      .kbd_tx      (kbd_tx),
      .kbd_rx      (1'b1),          // idle line: no keyboard
      .mou_rx      (1'b1),          // idle line: no mouse
`ifdef SUN3_ETH_WISH7990
      .phy_txd     (phy_txd),
      .phy_tx_en   (phy_tx_en),
      .phy_tx_er   (phy_tx_er),
      .phy_tx_clk  (mii_clk),
      .phy_col     (1'b0),
      .phy_rxd     (4'h0),
      .phy_rx_dv   (1'b0),
      .phy_rx_er   (1'b0),
      .phy_rx_clk  (mii_clk),
      .phy_crs     (1'b0),
      .phy_int_n   (1'b1),
      .phy_reset_n (phy_reset_n),
`endif
`ifdef SUN3_SCSI
      .blk_start     (blk_start),
      .blk_we        (blk_we),
      .blk_lba       (blk_lba),
      .blk_buf_rdata (blk_buf_rdata),
      .blk_done      (blk_done),
      .blk_err       (blk_err),
      .blk_ready     (blk_ready),
      .blk_count     (blk_count),
      .blk_buf_we    (blk_buf_we),
      .blk_buf_addr  (blk_buf_addr),
      .blk_buf_wdata (blk_buf_wdata),
`endif
      .V_INT       (1'b0),
      .leds        (leds),
      .en_boot     (en_boot),
      .diag_switch (diag_switch),
      .todebug     (todebug),
      .fb_video_en (fb_video_en),
      .wb_cyc_o    (wb_cyc),
      .wb_stb_o    (wb_stb),
      .wb_adr_o    (wb_adr),
      .wb_dat_o    (wb_dat_w),
      .wb_sel_o    (wb_sel),
      .wb_we_o     (wb_we),
      .wb_dat_i    (wb_dat_r),
      .wb_ack_i    (wb_ack)
`ifdef SUN3_WB_FIFO
      ,
      .wb_clk_i    (wb_clk),
      .wb_rst_i    (wb_rst),
      .wb_line_i   (wb_line)
`endif
   );

   // ---- main memory -------------------------------------------------------

   wb_ram_model #(.ACK_LATENCY(MEM_LATENCY), .FILL(MEM_FILL)) mem (
      .clk      (mem_clk),
      .reset    (mem_rst),
      .wb_cyc_i (wb_cyc),
      .wb_stb_i (wb_stb),
      .wb_adr_i (wb_adr),
      .wb_dat_i (wb_dat_w),
      .wb_sel_i (wb_sel),
      .wb_we_i  (wb_we),
      .wb_dat_o (wb_dat_r),
      .wb_ack_o (wb_ack),
      .wb_line_o(wb_line)
   );

   // ---- console -----------------------------------------------------------
   uart_monitor #(.BAUD(BAUD), .LOGFILE("console.log")) console_mon (.rx(tx));
   uart_console #(.BAUD(BAUD)) console_in (.tx(rx));

   // ---- run control -------------------------------------------------------
   // +berr_log: every bus error, one line each, to berr.txt -- page faults,
   // protection faults and timeouts, with what the MMU made of the address.
   // +pc_sample_ms=<t>: every <t> ms, the FC and address of the last program
   // fetch, to pcsample.txt -- where the CPU spends its time, and whether in
   // user (FC 2) or supervisor (FC 6) mode.
   int   berrfd = 0, pcfd = 0;
   real  pc_sample_ms = 0.0;
   logic [31:0] last_fetch = '0;
   logic [2:0]  last_fetch_fc = '0;
   initial begin
      if ($test$plusargs("berr_log")) berrfd = $fopen("berr.txt", "w");
      if ($value$plusargs("pc_sample_ms=%f", pc_sample_ms)) begin
         pcfd = $fopen("pcsample.txt", "w");
         forever begin
            #(pc_sample_ms * 1.0e6);
            $fwrite(pcfd, "%0.3f fc%0d %08x\n", $realtime / 1.0e6, last_fetch_fc, last_fetch);
            $fflush(pcfd);
         end
      end
   end
   always @(negedge CLK)
     if (!dut.sun3.SUN3_AS_n && (dut.sun3.SUN3_FC == 3'd2 || dut.sun3.SUN3_FC == 3'd6)) begin
        last_fetch    <= dut.sun3.SUN3_ADR_IN;
        last_fetch_fc <= dut.sun3.SUN3_FC;
     end
   logic berr_q = 1'b1;
   always @(posedge CLK) begin
      berr_q <= dut.sun3.P_BERR_n;
      if (berrfd != 0 && berr_q && !dut.sun3.P_BERR_n) begin
         $fwrite(berrfd, "%0.3f us fc%0d %s %08x pa=%08x siz%0d berrreg_in=%02x pte=%02x_%05x\n",
                 $realtime / 1.0e3, dut.sun3.SUN3_FC, dut.sun3.SUN3_RW_n ? "R" : "W",
                 dut.sun3.SUN3_ADR_IN, {dut.sun3.ma_pmap2devices, dut.sun3.SUN3_ADR_IN[12:0]},
                 dut.sun3.SUN3_SIZ, dut.sun3.berr_in, dut.sun3.ps_pmap2devices, dut.sun3.ma_pmap2devices);
         $fflush(berrfd);
      end
   end

   // Bus watch: +watch_from_us=<t> +watch_until_us=<t> prints the bus and the
   // decode's timing signals on every clock edge in that window -- for a
   // CPU whose strobes do not line up with sun3_fpga's C_Sn windows.
   real watch_from_us = -1.0, watch_until_us = -1.0;
   initial begin
      void'($value$plusargs("watch_from_us=%f", watch_from_us));
      void'($value$plusargs("watch_until_us=%f", watch_until_us));
   end
   // Sampled 1 ns after each edge, so what is printed is what that edge left
   // behind -- flops updated, combinational logic settled.
   always @(CLK)
     if (watch_from_us >= 0) #1
     if (watch_from_us >= 0 && $realtime >= watch_from_us * 1.0e3 && $realtime <= watch_until_us * 1.0e3)
       $display("[watch %0.3f us] CLK=%b AS=%b DS=%b RW=%b FC=%0d A=%08x SIZ=%0d D_cpu=%08x | C_S3..8=%b%b%b%b WR=%b RD=%b DIAG=%b SYSEN=%b | DSACK=%b BERR=%b D_sys=%08x",
                $realtime / 1.0e3, CLK, dut.sun3.SUN3_AS_n, dut.sun3.SUN3_DS_n, dut.sun3.SUN3_RW_n,
                dut.sun3.SUN3_FC, dut.sun3.SUN3_ADR_IN, dut.sun3.SUN3_SIZ, dut.sun3.SUN3_DATA_IN,
                dut.sun3.C_S3, dut.sun3.C_S4, dut.sun3.C_S6, dut.sun3.C_S8,
                dut.sun3.WR, dut.sun3.RD, dut.sun3.MATCH_DIAG, dut.sun3.MATCH_SYSEN,
                dut.sun3.P_DSACK_n, dut.sun3.P_BERR_n, dut.sun3.P_DATA_OUT);

   real timeout_ms = 2000.0;

   // Where the CPU is, roughly: the last PROM fetch address, for a run that
   // stops without saying anything.
   logic [31:0] last_prom_adr = '0;
   always @(negedge CLK)
     if (dut.sun3.MATCH_PROM_BOOT | dut.sun3.MATCH_PROM)
       last_prom_adr <= dut.sun3.SUN3_ADR_IN;

   // Bus cycle trace: +trace_from_ms=<t> logs every CPU (or DVMA) bus cycle
   // from that simulated time on to trace.txt -- one line per cycle, at the
   // end of it, with how it ended.
   // The address as the cycle had it (the bus may have moved by AS negation).
   logic [31:0] tr_adr;
   logic [18:0] tr_pa;
   always @(posedge CLK)
     if (!dut.sun3.SUN3_AS_n) begin
        tr_adr <= dut.sun3.SUN3_ADR_IN;
        tr_pa  <= dut.sun3.ma_pmap2devices;
     end
   real  trace_from_ms = -1.0;
   real  trace_until_ms = 1.0e9;
   bit   trace_io = 0;       // only control space and devices
   logic tr_mem = 1'b0;
   int   tracefd = 0;
   logic tr_as_q = 1'b1;
   logic tr_dsack = 1'b0, tr_berr = 1'b0;
   logic [31:0] tr_data;
   always @(posedge CLK) begin
      tr_as_q <= dut.sun3.SUN3_AS_n;
      if (!dut.sun3.SUN3_AS_n) begin
         if (dut.sun3.P_DSACK_n != 2'b11) begin
            tr_dsack <= 1'b1;
            tr_data  <= dut.sun3.SUN3_RW_n ? dut.sun3.P_DATA_OUT : dut.sun3.SUN3_DATA_IN;
         end
         if (!dut.sun3.P_BERR_n) tr_berr <= 1'b1;
         if (dut.sun3.MATCH_MEM | dut.sun3.MATCH_PROM_BOOT | dut.sun3.MATCH_PROM) tr_mem <= 1'b1;
      end
      if (dut.sun3.SUN3_AS_n && !tr_as_q) begin
         if (tracefd != 0 && $realtime >= trace_from_ms * 1.0e6 && $realtime <= trace_until_ms * 1.0e6 &&
             !(trace_io && tr_mem))
           $fwrite(tracefd, "%0.3f us fc%0d %s %08x siz%0d %s %08x pa=%08x\n",
                   $realtime / 1.0e3, dut.sun3.SUN3_FC, dut.sun3.SUN3_RW_n ? "R" : "W",
                   tr_adr, dut.sun3.SUN3_SIZ, tr_berr ? "BERR " : (tr_dsack ? "ack  " : "none "),
                   tr_data, {tr_pa, tr_adr[12:0]});
         tr_dsack <= 1'b0;
         tr_berr  <= 1'b0;
         tr_mem   <= 1'b0;
      end
   end

   // The bw2 window (Wishbone word 0x03F80000 = byte 0x0FE00000, where the
   // bridges put it), as 32-bit words in DDR3 order, for "make -C sim
   // screenshot" to render through the real fb_scanout.  +fb_dump writes
   // fb.mem when the run ends; +fb_dump_ms=<t> also rewrites fb-live<n>.mem
   // (n = 0..2, rotating) every <t> ms, so a long run can be looked at while
   // it goes (tools/fbshot picks the newest complete one).
   localparam int unsigned FB_WB_WORD = 32'h03F80000;
   localparam int unsigned FB_WORDS   = 32768;           // 128 KiB
   task automatic fb_dump(input string path);
      int fd;
      begin
         fd = $fopen(path, "w");
         if (fd == 0) begin
            $display("note: could not write %s", path);
            return;
         end
         for (int unsigned w = 0; w < FB_WORDS; w++)
           $fdisplay(fd, "%08x", mem.fetch(FB_WB_WORD + w));
         $fclose(fd);
         $display("[%0.3f ms] frame buffer written to %s", $realtime / 1.0e6, path);
      end
   endtask
   real fb_dump_ms = 0.0;
   int  fb_dump_idx = 0;
   initial begin
      if ($value$plusargs("fb_dump_ms=%f", fb_dump_ms) && fb_dump_ms > 0.0)
        forever begin
           #(fb_dump_ms * 1.0e6);
           fb_dump($sformatf("fb-live%0d.mem", fb_dump_idx));
           fb_dump_idx = (fb_dump_idx + 1) % 3;
        end
   end

   task automatic wrap_up(input string why);
      $display("");
      $display("==== %s at %0.3f ms ====", why, $realtime / 1.0e6);
      $display("last PROM access at %08x, diag LEDs %02x", last_prom_adr, ~leds);
      console_mon.report();
      mem.report();
      if ($test$plusargs("fb_dump") || fb_dump_ms > 0.0) fb_dump("fb.mem");
`ifdef SUN3_WB_CACHE
      $display("[cache] %0d lines: reads %0d hit, %0d miss (%0d lookups not usable), %0d uncached; writes %0d hit, %0d miss, %0d invalidated; %0d fills",
               1 << `SUN3_WB_CACHE_IDX, dut.sun3.wbridge.n_hit, dut.sun3.wbridge.n_miss,
               dut.sun3.wbridge.n_rd_notok, dut.sun3.wbridge.n_uncached,
               dut.sun3.wbridge.n_whit, dut.sun3.wbridge.n_wmiss,
               dut.sun3.wbridge.n_winval, dut.sun3.wbridge.n_fill);
`endif
      $finish;
   endtask

   // A CPU that stops making bus cycles: say so once, with where it was.
   // A CPU with an instruction cache (the RD68021's) runs a tight loop with no
   // bus cycle at all -- the PROM's TOD interrupt test waits like that -- so
   // "quiet" has to mean quiet for much longer than one loop takes.
   real     stall_ms = 100.0;
   initial void'($value$plusargs("stall_ms=%f", stall_ms));
   realtime last_as = 0;
   bit      quiet_reported = 0;
   always @(negedge dut.sun3.SUN3_AS_n) begin
      last_as = $realtime;
      quiet_reported = 0;
   end
   always @(posedge CLK)
     if (!quiet_reported && !sys_reset && $realtime - last_as > stall_ms * 1.0e6) begin
        quiet_reported = 1;
        $display("[%0.3f ms] no bus cycle for %0.1f ms: AS_n=%b FC=%0d A=%08x DSACK_n=%b BERR_n=%b HALT(out)=%b RESET_OUT=%b",
                 $realtime / 1.0e6, stall_ms, dut.sun3.SUN3_AS_n, dut.sun3.SUN3_FC, dut.sun3.SUN3_ADR_IN,
                 dut.sun3.P_DSACK_n, dut.sun3.P_BERR_n, dut.HALT_OUTn, dut.RESET_OUT);
        wrap_up("CPU STOPPED");
     end

   initial begin
      void'($value$plusargs("timeout_ms=%f", timeout_ms));
      void'($value$plusargs("trace_until_ms=%f", trace_until_ms));
      trace_io = $test$plusargs("trace_io");
      if ($value$plusargs("trace_from_ms=%f", trace_from_ms)) begin
         tracefd = $fopen("trace.txt", "w");
         $display("tracing bus cycles from %0.3f ms to trace.txt", trace_from_ms);
      end
      if ($test$plusargs("vcd")) begin
         $dumpfile("sun3.vcd");
         $dumpvars(0, tb_sun3);
      end
      $display("tb_sun3: CPU %0d Hz, console %0d baud, memory %0d MiB, %0d wait states",
               CPU_HZ, BAUD, `SUN3_MEM_MIB, MEM_LATENCY);
      $display("timeout %0.1f ms of simulated time", timeout_ms);
      #(timeout_ms * 1000000.0);
      wrap_up("TIMEOUT");
   end

   // Let the line finish printing before stopping -- or, with +type=<line>,
   // type that line at the prompt first and stop at the next one.
   string type_line = "", type2_line = "";
   // A plusarg cannot carry a space: `_' in +type stands for one (+type=g_4000).
   initial begin
      void'($value$plusargs("type=%s", type_line));
      for (int i = 0; i < type_line.len(); i++)
        if (type_line[i] == "_") type_line[i] = " ";
      // +type2=<line>: a second line, typed at the prompt that follows the
      // first (e.g. +type=g_4000 +type2=k2).
      void'($value$plusargs("type2=%s", type2_line));
      for (int i = 0; i < type2_line.len(); i++)
        if (type2_line[i] == "_") type2_line[i] = " ";
   end

   // +load=<file>@<hex byte address>: put a binary in memory once the PROM is
   // at its prompt (after its RAM fill), e.g. a kernel for `g 4000'.
   // +keep_running: after typing +type, run on to the timeout rather than
   // stopping at the next prompt (a program that never returns to one).
   string load_arg = "";
   initial void'($value$plusargs("load=%s", load_arg));

   always @(posedge console_mon.stop_seen) begin
      #1000000;
      if (load_arg.len() > 0) begin
         int at;
         int unsigned base;
         at = -1;
         for (int i = 0; i < load_arg.len(); i++) if (load_arg[i] == "@") at = i;
         if (at < 0) begin $display("+load wants <file>@<hexaddr>"); $finish; end
         base = load_arg.substr(at + 1, load_arg.len() - 1).atohex();
         mem.load_bin(load_arg.substr(0, at - 1), base);
      end
      if (type_line.len() > 0 && type2_line.len() > 0) begin
         bit ok;
         $display("\n[%0.3f ms] typing \"%s\"", $realtime / 1.0e6, type_line);
         console_in.send_line(type_line);
         console_mon.wait_for(">", 2000_000_000.0, ok);
         #1000000;
         if (!ok) wrap_up("TYPED, NO PROMPT");
         $display("\n[%0.3f ms] typing \"%s\"%s", $realtime / 1.0e6, type2_line,
                  $test$plusargs("keep_running") ? " and running on" : "");
         console_in.send_line(type2_line);
         if (!$test$plusargs("keep_running")) begin
            console_mon.wait_for(">", 2000_000_000.0, ok);
            #1000000;
            wrap_up(ok ? "TYPED TWICE, PROMPT AGAIN" : "TYPED TWICE, NO PROMPT");
         end
      end else if (type_line.len() > 0 && $test$plusargs("keep_running")) begin
         $display("\n[%0.3f ms] typing \"%s\" and running on", $realtime / 1.0e6, type_line);
         console_in.send_line(type_line);
      end else if (type_line.len() > 0) begin
         bit ok;
         $display("\n[%0.3f ms] typing \"%s\"", $realtime / 1.0e6, type_line);
         console_in.send_line(type_line);
         console_mon.wait_for(">", 2000_000_000.0, ok);
         #1000000;
         wrap_up(ok ? "TYPED, PROMPT AGAIN" : "TYPED, NO PROMPT");
      end else
         wrap_up("STOP STRING SEEN");
   end

endmodule
