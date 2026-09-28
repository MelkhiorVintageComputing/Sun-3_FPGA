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
//   +trace_from_ms=<t>   log every bus cycle from then on to trace.txt
//   +trace_until_ms=<t>  ... and stop logging at <t>
//   +trace_io            ... leaving out PROM and main memory cycles
//   +vcd                 dump everything to sun3.vcd (needs SUN3_VCD=1 at
//                        elaboration for signal visibility)
//
// Parameters (-generic_top):
//   CPU_HZ        CPU/bus clock (default 20 MHz, as the old build ran)
//   BAUD          console decode rate (default 9600)
//   MEM_LATENCY   Wishbone wait states before ack (default 0)
//

module tb_sun3 #(
    parameter int CPU_HZ      = 20000000,
    parameter int BAUD        = 9600,
    parameter int MEM_LATENCY = 0
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

   sun3_top dut (
      .CLK         (CLK),
      .clk4m9152   (clk4m9152),
      .clk32k768   (clk32k768),
      .sys_reset   (sys_reset),
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
      .V_INT       (1'b0),
      .leds        (leds),
      .en_boot     (en_boot),
      .diag_switch (diag_switch),
      .todebug     (todebug),
      .wb_cyc_o    (wb_cyc),
      .wb_stb_o    (wb_stb),
      .wb_adr_o    (wb_adr),
      .wb_dat_o    (wb_dat_w),
      .wb_sel_o    (wb_sel),
      .wb_we_o     (wb_we),
      .wb_dat_i    (wb_dat_r),
      .wb_ack_i    (wb_ack)
   );

   // ---- main memory -------------------------------------------------------
   wire [127:0] wb_line_unused;

   wb_ram_model #(.ACK_LATENCY(MEM_LATENCY)) mem (
      .clk      (CLK),
      .reset    (sys_reset),
      .wb_cyc_i (wb_cyc),
      .wb_stb_i (wb_stb),
      .wb_adr_i (wb_adr),
      .wb_dat_i (wb_dat_w),
      .wb_sel_i (wb_sel),
      .wb_we_i  (wb_we),
      .wb_dat_o (wb_dat_r),
      .wb_ack_o (wb_ack),
      .wb_line_o(wb_line_unused)
   );

   // ---- console -----------------------------------------------------------
   uart_monitor #(.BAUD(BAUD), .LOGFILE("console.log")) console_mon (.rx(tx));
   uart_console #(.BAUD(BAUD)) console_in (.tx(rx));

   // ---- run control -------------------------------------------------------
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

   task automatic wrap_up(input string why);
      $display("");
      $display("==== %s at %0.3f ms ====", why, $realtime / 1.0e6);
      $display("last PROM access at %08x, diag LEDs %02x", last_prom_adr, ~leds);
      console_mon.report();
      mem.report();
      $finish;
   endtask

   // A CPU that stops making bus cycles: say so once, with where it was.
   realtime last_as = 0;
   bit      quiet_reported = 0;
   always @(negedge dut.sun3.SUN3_AS_n) begin
      last_as = $realtime;
      quiet_reported = 0;
   end
   always @(posedge CLK)
     if (!quiet_reported && !sys_reset && $realtime - last_as > 1.0e6) begin
        quiet_reported = 1;
        $display("[%0.3f ms] no bus cycle for 1 ms: AS_n=%b FC=%0d A=%08x DSACK_n=%b BERR_n=%b HALT(out)=%b RESET_OUT=%b",
                 $realtime / 1.0e6, dut.sun3.SUN3_AS_n, dut.sun3.SUN3_FC, dut.sun3.SUN3_ADR_IN,
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

   // Let the line finish printing before stopping.
   always @(posedge console_mon.stop_seen) begin
      #1000000;
      wrap_up("STOP STRING SEEN");
   end

endmodule
