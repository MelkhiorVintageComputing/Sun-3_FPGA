`timescale 1ns / 1ps

`include "sun3_config.vh"

//
// Board-level testbench: the Sun-3 as it is on a QMTech Wukong.
//
// Unlike tb_sun3, which drives sun3_top directly with ideal clocks, this starts
// from the board's 50 MHz oscillator and reset button and goes through the
// board's clock generation, reset sequencing and memory path.
//
// Two memory configurations, selected by defining BOARD_MEM_FAST or not:
//
//   BOARD_MEM_FAST   no MIG: the board top exposes its Wishbone port and a
//                    behavioural RAM hangs off it, with MEM_LATENCY wait states
//                    (about 10 is what MIG costs at 20 MHz).  Boots to the
//                    monitor prompt, like tb_sun3.
//
//   (default)        the real MIG (simulation variant, fast calibration) and
//                    Micron's DDR3 model.  Proves the clocks lock, MIG
//                    calibrates, the machine comes out of reset and its first
//                    memory transactions work; a full boot is far too slow.
//
// Plusargs: +timeout_ms (default 20), +stop_on, +diag (hold the user button,
// the diag switch, through reset), +reset_at_us.
//
// Adapted from the Sun-2 project's tb/tb_wukong.sv.
//

module tb_wukong #(
    parameter int    CPU_CLK_HZ  = 20_000_000,
    parameter int    BAUD        = 9600,
    parameter int    MEM_LATENCY = 10,
    parameter string CONSOLE     = "console.log"
)();

   // ------------------------------------------------------------------
   // Board inputs
   // ------------------------------------------------------------------
   reg clk50     = 1'b0;
   reg cpu_reset = 1'b0;          // button, active low: 0 = held in reset
   reg user_btn  = 1'b1;          // released
   real reset_at_us = 0.0;
   initial begin
      void'($value$plusargs("reset_at_us=%f", reset_at_us));
      if ($test$plusargs("diag")) user_btn = 1'b0;
   end

   always #10.0 clk50 = ~clk50;   // 50 MHz

   wire        serial_tx;
   wire        serial_rx;         // driven by uart_console below
   wire [1:0]  user_led;
   wire [7:0]  diag_leds0;
   wire [7:0]  extra_leds0;

`ifdef SUN3_ETH_WISH7990
   initial $fatal(1, "tb_wukong: no PHY model yet; build it with ETH=none");
`endif

   // ------------------------------------------------------------------
   // DUT and its memory
   // ------------------------------------------------------------------
`ifdef BOARD_MEM_FAST

   wire        wb_cyc, wb_stb, wb_we, wb_ack;
   wire [29:0] wb_adr;
   wire [31:0] wb_dat_m2s, wb_dat_s2m;
   wire [3:0]  wb_sel;
   wire        cpu_clk, sys_reset;
   wire [127:0] wb_line_unused;

   wukong_top #(.CPU_CLK_HZ(CPU_CLK_HZ)) dut (
       .clk50 (clk50), .cpu_reset (cpu_reset),
       .serial_tx (serial_tx), .serial_rx (serial_rx),
       .user_led (user_led), .user_btn (user_btn),
       .diag_leds0 (diag_leds0), .extra_leds0 (extra_leds0),

       .wb_cyc_o (wb_cyc), .wb_stb_o (wb_stb), .wb_adr_o (wb_adr),
       .wb_dat_o (wb_dat_m2s), .wb_sel_o (wb_sel), .wb_we_o (wb_we),
       .wb_dat_i (wb_dat_s2m), .wb_ack_i (wb_ack),
       .cpu_clk_o (cpu_clk), .sys_reset_o (sys_reset)
   );

   wb_ram_model #(.ACK_LATENCY(MEM_LATENCY)) ram (
       .clk (cpu_clk), .reset (sys_reset),
       .wb_cyc_i (wb_cyc), .wb_stb_i (wb_stb), .wb_adr_i (wb_adr),
       .wb_dat_i (wb_dat_m2s), .wb_sel_i (wb_sel), .wb_we_i (wb_we),
       .wb_dat_o (wb_dat_s2m), .wb_ack_o (wb_ack), .wb_line_o (wb_line_unused)
   );

`else

   wire [15:0] ddr3_dq;
   wire [1:0]  ddr3_dqs_p, ddr3_dqs_n;
   wire [13:0] ddr3_addr;
   wire [2:0]  ddr3_ba;
   wire        ddr3_ras_n, ddr3_cas_n, ddr3_we_n, ddr3_reset_n;
   wire [0:0]  ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_odt;
   wire [1:0]  ddr3_dm;

   wukong_top #(.CPU_CLK_HZ(CPU_CLK_HZ)) dut (
       .clk50 (clk50), .cpu_reset (cpu_reset),
       .serial_tx (serial_tx), .serial_rx (serial_rx),
       .user_led (user_led), .user_btn (user_btn),
       .diag_leds0 (diag_leds0), .extra_leds0 (extra_leds0),

       .ddr3_dq (ddr3_dq), .ddr3_dqs_p (ddr3_dqs_p), .ddr3_dqs_n (ddr3_dqs_n),
       .ddr3_addr (ddr3_addr), .ddr3_ba (ddr3_ba),
       .ddr3_ras_n (ddr3_ras_n), .ddr3_cas_n (ddr3_cas_n), .ddr3_we_n (ddr3_we_n),
       .ddr3_reset_n (ddr3_reset_n),
       .ddr3_ck_p (ddr3_ck_p), .ddr3_ck_n (ddr3_ck_n), .ddr3_cke (ddr3_cke),
       .ddr3_dm (ddr3_dm), .ddr3_odt (ddr3_odt)
   );

   // Micron's DDR3 model, from MIG's generated example design (not committed:
   // it is Micron's AS-IS licence).  See sim/run_xsim_board.sh.
   ddr3_model ddr3 (
       .rst_n   (ddr3_reset_n),
       .ck      (ddr3_ck_p),
       .ck_n    (ddr3_ck_n),
       .cke     (ddr3_cke),
       .cs_n    (1'b0),          // tied low on the board
       .ras_n   (ddr3_ras_n),
       .cas_n   (ddr3_cas_n),
       .we_n    (ddr3_we_n),
       .dm_tdqs (ddr3_dm),
       .ba      (ddr3_ba),
       .addr    (ddr3_addr),
       .dq      (ddr3_dq),
       .dqs     (ddr3_dqs_p),
       .dqs_n   (ddr3_dqs_n),
       .tdqs_n  (),
       .odt     (ddr3_odt)
   );

   // The memory path, as the machine sees it: every Wishbone transaction
   // through the adapter, with its data, so a DDR3 run shows the PROM's first
   // accesses reading back what they wrote.
   int unsigned n_wb = 0;
   always @(posedge dut.cpu_clk)
     if (dut.wb_ack && n_wb < 64) begin
        n_wb++;
        $display("[%t] wb %s %08x sel %b data %08x", $realtime,
                 dut.wb_we ? "W" : "R", {dut.wb_adr, 2'b00}, dut.wb_sel,
                 dut.wb_we ? dut.wb_dat_m2s : dut.wb_dat_s2m);
     end

   always @(posedge dut.init_calib_complete)
     $display("[%t] MIG calibration complete", $realtime);

`endif

   // ------------------------------------------------------------------
   // Console
   // ------------------------------------------------------------------
   uart_monitor #(.BAUD(BAUD), .LOGFILE(CONSOLE)) console_mon (.rx(serial_tx));
   uart_console #(.BAUD(BAUD))                   console_in  (.tx(serial_rx));

   // ------------------------------------------------------------------
   // Progress
   // ------------------------------------------------------------------
   always @(user_led)
     $display("[%t] user_led = %b  (led[0] low = out of reset, led[1] low = DRAM calibrated)",
              $realtime, user_led);

   always @(negedge dut.sys_reset)
     $display("[%t] machine out of reset (diag switch %b)", $realtime, dut.diag_switch);

   // ------------------------------------------------------------------
   // Run control
   // ------------------------------------------------------------------
   real timeout_ms = 20.0;

   task automatic wrap_up(input string why);
      $display("");
      $display("=== %s at %t ===", why, $realtime);
      console_mon.report();
`ifdef BOARD_MEM_FAST
      ram.report();
`endif
      $finish;
   endtask

   initial begin
      $timeformat(-6, 3, " us", 14);
      void'($value$plusargs("timeout_ms=%f", timeout_ms));

      $display("=== Sun-3 on QMTech Wukong ===");
`ifdef BOARD_MEM_FAST
      $display("memory: behavioural Wishbone RAM, %0d wait states (BOARD_MEM_FAST)", MEM_LATENCY);
`else
      $display("memory: MIG 7 Series + Micron DDR3 model");
`endif
      $display("CPU clock %0d Hz, %0d MiB, timeout %0.1f ms", CPU_CLK_HZ, `SUN3_MEM_MIB, timeout_ms);

      // Hold the button down briefly, as a person would.
      #2000 cpu_reset = 1'b1;

      if (reset_at_us > 0.0) begin
         #(reset_at_us * 1000.0 - 2000.0);
         $display("[%t] === reset button pressed ===", $realtime);
         cpu_reset = 1'b0;
         #10000 cpu_reset = 1'b1;
      end

      #(timeout_ms * 1000000.0);
      wrap_up("TIMEOUT");
   end

   always @(posedge console_mon.stop_seen) begin
      #1000000;
      wrap_up("STOP STRING SEEN");
   end

endmodule
