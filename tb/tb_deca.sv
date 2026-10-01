`timescale 1ns / 1ps

`include "sun3_config.vh"

//
// Board-level testbench: the Sun-3 as it is on an Arrow DECA.
//
// deca_top with its behavioural clock generator (CLKGEN_BEHAVIOURAL) and, in
// place of DDR3, a behavioural Wishbone RAM with MEM_LATENCY wait states
// (BOARD_MEM_FAST): the board's reset sequencing, diag switch and console
// bridge around the unchanged machine.  There is no DDR3 model: BrianHG's
// controller is simulated only through its command port (make -C sim
// decaddr3), and on the board.
//
// The console is watched twice: the raw ttya line on GPIO0_D[0] (console.log,
// through uart_monitor as in every other testbench), and what reaches the
// host through deca_jtag_console and a model of the JTAG UART (jtag.log).
// The two must agree.
//
// Plusargs: +timeout_ms, +stop_on, +diag (SW[1] up: the diag switch).
//
module tb_deca #(
    parameter int    CPU_CLK_HZ  = 20_000_000,
    parameter int    BAUD        = 9600,
    parameter int    MEM_LATENCY = 10,
    parameter string CONSOLE     = "console.log"
)();

   reg        clk50 = 1'b0;
   reg  [1:0] key   = 2'b10;      // KEY[0] pressed (active low): held in reset
   reg  [1:0] sw    = 2'b00;
   initial if ($test$plusargs("diag")) sw[1] = 1'b1;

   always #10.0 clk50 = ~clk50;   // 50 MHz

   wire [7:0] led, gpio0, gpio1;
   wire       sun_tx = gpio0[0];

   wire        av_address, av_chipselect, av_read_n, av_write_n, av_waitrequest;
   wire [31:0] av_writedata, av_readdata;

   wire        wb_cyc, wb_stb, wb_we, wb_ack;
   wire [29:0] wb_adr;
   wire [31:0] wb_dat_m2s, wb_dat_s2m;
   wire [3:0]  wb_sel;
   wire        cpu_clk, sys_reset;
   wire [127:0] wb_line;

   wire [3:0] net_txd;
   wire       net_tx_en, net_reset_n, net_mdc, net_pcf_en;
   wire       net_mdio;

   deca_top #(.CPU_CLK_HZ(CPU_CLK_HZ)) dut (
       .MAX10_CLK1_50 (clk50),
       .KEY (key), .SW (sw), .LED (led),
       .GPIO0_D (gpio0), .GPIO1_D (gpio1),

       .NET_TX_CLK (1'b0), .NET_TXD (net_txd), .NET_TX_EN (net_tx_en),
       .NET_RX_CLK (1'b0), .NET_RXD (4'h0), .NET_RX_DV (1'b0), .NET_RX_ER (1'b0),
       .NET_CRS (1'b0), .NET_COL (1'b0), .NET_RESET_n (net_reset_n),
       .NET_MDC (net_mdc), .NET_PCF_EN (net_pcf_en), .NET_MDIO (net_mdio),

       .av_address_o (av_address), .av_chipselect_o (av_chipselect),
       .av_read_n_o (av_read_n), .av_write_n_o (av_write_n),
       .av_writedata_o (av_writedata), .av_readdata_i (av_readdata),
       .av_waitrequest_i (av_waitrequest),

       .wb_cyc_o (wb_cyc), .wb_stb_o (wb_stb), .wb_adr_o (wb_adr),
       .wb_dat_o (wb_dat_m2s), .wb_sel_o (wb_sel), .wb_we_o (wb_we),
       .wb_dat_i (wb_dat_s2m), .wb_ack_i (wb_ack), .wb_line_i (wb_line),
       .cpu_clk_o (cpu_clk), .sys_reset_o (sys_reset)
   );

   wb_ram_model #(.ACK_LATENCY(MEM_LATENCY)) ram (
       .clk (cpu_clk), .reset (sys_reset),
       .wb_cyc_i (wb_cyc), .wb_stb_i (wb_stb), .wb_adr_i (wb_adr),
       .wb_dat_i (wb_dat_m2s), .wb_sel_i (wb_sel), .wb_we_i (wb_we),
       .wb_dat_o (wb_dat_s2m), .wb_ack_o (wb_ack), .wb_line_o (wb_line)
   );

   // ------------------------------------------------------------------
   // Console: the raw line, and the host's side of the JTAG UART
   // ------------------------------------------------------------------
   uart_monitor #(.BAUD(BAUD), .LOGFILE(CONSOLE)) console_mon (.rx(sun_tx));

   wire [7:0] host_rx_data;
   wire       host_rx_valid, host_tx_full;

   jtag_uart_model juart (
       .clk (clk50), .rst_n (~dut.con_rst),
       .av_address (av_address), .av_chipselect (av_chipselect),
       .av_read_n (av_read_n), .av_write_n (av_write_n),
       .av_writedata (av_writedata), .av_readdata (av_readdata),
       .av_waitrequest (av_waitrequest),
       .host_rx_data (host_rx_data), .host_rx_valid (host_rx_valid),
       .host_tx_data (8'h00), .host_tx_push (1'b0), .host_tx_full (host_tx_full),
       .drain (1'b1)
   );

   integer jlog;
   int unsigned n_host = 0;
   initial jlog = $fopen("jtag.log", "w");
   always @(posedge clk50)
     if (host_rx_valid) begin
        $fwrite(jlog, "%c", host_rx_data);
        $fflush(jlog);
        n_host++;
     end

   // ------------------------------------------------------------------
   // Progress
   // ------------------------------------------------------------------
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
      $display("JTAG UART: the host received %0d bytes (jtag.log); console_dropped=%b frame_err=%b",
               n_host, dut.con_dropped, dut.con_frame_err);
      ram.report();
      $fclose(jlog);
      $finish;
   endtask

   initial begin
      $timeformat(-6, 3, " us", 14);
      void'($value$plusargs("timeout_ms=%f", timeout_ms));
      $display("=== Sun-3 on Arrow DECA ===");
      $display("memory: behavioural Wishbone RAM, %0d wait states (BOARD_MEM_FAST)", MEM_LATENCY);
      $display("CPU clock %0d Hz, %0d MiB, timeout %0.1f ms", CPU_CLK_HZ, `SUN3_MEM_MIB, timeout_ms);

      #2000 key[0] = 1'b1;           // release the reset button
      #(timeout_ms * 1000000.0);
      wrap_up("TIMEOUT");
   end

   always @(posedge console_mon.stop_seen) begin
      #1000000;
      wrap_up("STOP STRING SEEN");
   end

endmodule
