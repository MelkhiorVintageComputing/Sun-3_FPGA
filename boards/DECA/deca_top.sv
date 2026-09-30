`timescale 1ns / 1ps

`include "sun3_config.vh"
`include "sun3_attr.vh"

//
// The Sun-3 on an Arrow DECA (MAX 10 10M50DAF484C6GES).
//
// The twin of boards/Wukong/wukong_top.sv: board pins in, the machine
// (rtl/sun3/sun3_top.v, unchanged) out.  The board side comes from the Sun-2
// project's boards/DECA/deca_top.sv, which runs a Sun-2 on this exact board;
// its comments hold the history behind most of the choices below.
//
//   MAX10_CLK1_50 -- deca_clkgen --+-- cpu_clk     (1000 MHz / CPU_DIV)
//                                  +-- clk_serial  (4.915254 MHz, the SCCs)
//                 -- BrianHG DDR3 controller (its own PLL; CMD_CLK 125 MHz)
//                 -- deca_jtag_console (the raw 50 MHz: 5x TCK)
//
//   sun3_top --Wishbone (cpu_clk)-- deca_wb_to_ddr3 --(CMD_CLK)-- BrianHG -- DDR3
//
// What differs from the Wukong:
//  * No UART reaches the FPGA.  The console is the SCC's ttya bridged to a
//    JTAG UART on the USB-Blaster II (deca_jtag_console); its TX also goes out
//    on GPIO0_D[0] = PIN_W18, the board's own UART_TXD, for a USB-TTL cable.
//  * No hard memory controller: BrianHG's soft one, at 250 MHz DDR3 (400 does
//    not build on Quartus 25.1), with its caches off.
//  * Eight active-low LEDs: SW[0] down shows the Sun's diag register, up
//    shows todebug.  Both always go out on the GPIO headers.
//  * The diag switch is SW[1], sampled through reset.
//  * Reset can be pulsed over JTAG (ISSP, tools/deca_reset.tcl): the board's
//    only reset is a button, and configuring the FPGA tears down the console.
//    A BREAK on ttya (the monitor's abort) is sent the same way.
//
// Options (sun3_config.vh / syn/quartus.tcl):
//   SUN3_ETH_WISH7990   the Wish7990 on the board's DP83620, as MII
//   BOARD_MEM_FAST      simulation only: no DDR3, the Wishbone port and the
//                       CPU clock and reset come out to the testbench
//   SUN3_SIM            the JTAG UART's Avalon port comes out to the
//                       testbench (tb/jtag_uart_model.sv), as in the Sun-2
//

module deca_top #(
    // Parameters of this module because a generic given at synthesis reaches
    // the top level and nothing below it.
    parameter int CPU_CLK_HZ = 20_000_000,
    parameter int CPU_DIV    = 0,
    parameter int CPU_DUTY   = 50,
    // BrianHG's PORT_CACHE_SMART: serve a read from the write cache when the
    // addresses match.  With it off, a read landing between a write's
    // acceptance and its arrival in DRAM returns the old contents (the Sun-2
    // traced the mechanism, though it proved not to be its corruption).  On,
    // at ~460 LE, for correctness by construction.
    parameter bit DDR3_SMART = 1'b1,
    // Where the SCSI disk starts on the micro-SD card, in 512-byte sectors
    // (syn/Makefile DISK_OFF_MIB * 2048).  The card can hold several copies
    // of a disk; moving to another one is how a damaged copy is set aside.
    parameter int DISK_LBA_OFFSET = 0
) (
    input  wire        MAX10_CLK1_50,   // PIN_M8,  2.5 V
    input  wire [1:0]  KEY,             // H21 H22, 1.5 V Schmitt, active low
    input  wire [1:0]  SW,              // J21 J22, 1.5 V Schmitt
    output wire [7:0]  LED,             // bank 8, 1.2 V, ACTIVE LOW
    output wire [7:0]  GPIO0_D,         // P8 header, 3.3 V
    output wire [7:0]  GPIO1_D,         // P9 header, 3.3 V

    // MII to the on-board TI DP83620, 2.5 V.  Declared whether or not the
    // Ethernet is built, so the pin file needs no condition; driven idle
    // without it.
    input  wire        NET_TX_CLK,
    output wire [3:0]  NET_TXD,
    output wire        NET_TX_EN,
    input  wire        NET_RX_CLK,
    input  wire [3:0]  NET_RXD,
    input  wire        NET_RX_DV,
    input  wire        NET_RX_ER,
    input  wire        NET_CRS,
    input  wire        NET_COL,
    output wire        NET_RESET_n,
    output wire        NET_MDC,
    output wire        NET_PCF_EN,
    inout  wire        NET_MDIO,

    // micro-SD, SPI mode, through the U22 level translator (SN74AVCA406L);
    // four of these only configure the translator.  Pinout: DECA user
    // manual Table 3-21; from the Sun-2 project's deca_top.
    output wire        SD_CLK,          // T20, SCK
    output wire        SD_CMD,          // T21, MOSI
    input  wire        SD_MISO,         // R18, DAT0
    output wire        SD_CS_N,         // R20, DAT3 as chip select
    output wire        SD_DAT1,         // T18, unused in SPI mode
    output wire        SD_DAT2,         // T19, unused in SPI mode
    output wire        SD_SEL,          // P13, card VCCIO select
    output wire        SD_CMD_DIR,      // U22
    output wire        SD_D0_DIR,       // T22
    output wire        SD_D123_DIR,     // U21

`ifdef SUN3_SIM
    output wire        av_address_o,
    output wire        av_chipselect_o,
    output wire        av_read_n_o,
    output wire        av_write_n_o,
    output wire [31:0] av_writedata_o,
    input  wire [31:0] av_readdata_i,
    input  wire        av_waitrequest_i,
`endif

`ifdef BOARD_MEM_FAST
    output wire        wb_cyc_o,
    output wire        wb_stb_o,
    output wire [29:0] wb_adr_o,
    output wire [31:0] wb_dat_o,
    output wire [3:0]  wb_sel_o,
    output wire        wb_we_o,
    input  wire [31:0] wb_dat_i,
    input  wire        wb_ack_i,
    output wire        cpu_clk_o,
    output wire        sys_reset_o
`else
    // DDR3.  MT41K256M16, 512 MB, 16-bit; pins from BrianHG's own DECA
    // project via syn/deca_ddr3_pins.qsf.
    output wire        DDR3_RESET_n,
    output wire        DDR3_CK_p,
    output wire        DDR3_CK_n,
    output wire        DDR3_CKE,
    output wire        DDR3_CS_n,
    output wire        DDR3_RAS_n,
    output wire        DDR3_CAS_n,
    output wire        DDR3_WE_n,
    output wire        DDR3_ODT,
    output wire [14:0] DDR3_A,
    output wire [2:0]  DDR3_BA,
    inout  wire [1:0]  DDR3_DM,
    inout  wire [15:0] DDR3_DQ,
    inout  wire [1:0]  DDR3_DQS_p,
    inout  wire [1:0]  DDR3_DQS_n
`endif
);

   // ------------------------------------------------------------------
   // Clocks
   // ------------------------------------------------------------------
   wire cpu_clk, clk_serial, pll_locked;

   deca_clkgen #(.CPU_CLK_HZ(CPU_CLK_HZ), .CPU_DIV(CPU_DIV),
                 .CPU_DUTY(CPU_DUTY)) clkgen (
       .clk50      (MAX10_CLK1_50),
       .reset      (~KEY[0]),
       .clk_cpu    (cpu_clk),
       .clk_serial (clk_serial),
       .locked     (pll_locked)
   );

   // ------------------------------------------------------------------
   // Reset
   //
   // As the Sun-2 DECA: every term synchronised into cpu_clk and the result
   // registered, never an OR of asynchronous terms into an asynchronous reset.
   // Two levels, and the split is load-bearing: board_reset_raw holds the DDR3
   // controller; board_reset additionally waits for DDR3_READY and is what the
   // machine sees.  Feeding ~ready into the controller's own reset would stop
   // it ever calibrating.
   // ------------------------------------------------------------------
   wire ddr3_ready;
   wire jtag_reset;
   // A BREAK on ttya (the Sun monitor's abort), held for as long as it is
   // set over JTAG: the JTAG UART carries bytes, not line states.
   wire jtag_break;

   reg [15:0] hold_ctr = 16'hFFFF;
   always @(posedge cpu_clk or negedge pll_locked)
     if (!pll_locked)          hold_ctr <= 16'hFFFF;
     else if (hold_ctr != 0)   hold_ctr <= hold_ctr - 16'd1;

   `SUN3_ASYNC_REG reg key_s1, key_s2;
   `SUN3_ASYNC_REG reg rdy_s1, rdy_s2;
   `SUN3_ASYNC_REG reg jrst_s1, jrst_s2;

   always @(posedge cpu_clk) begin
      key_s1  <= ~KEY[0];    key_s2  <= key_s1;
      rdy_s1  <= ddr3_ready; rdy_s2  <= rdy_s1;
      jrst_s1 <= jtag_reset; jrst_s2 <= jrst_s1;
   end

   reg board_reset_raw = 1'b1;
   reg board_reset     = 1'b1;

   always @(posedge cpu_clk) begin
      board_reset_raw <= key_s2 | ~pll_locked | (hold_ctr != 16'd0) | jrst_s2;
      board_reset     <= board_reset_raw | ~rdy_s2;
   end

   wire sys_reset;
   reset_sync rst_cpu (.clk(cpu_clk),
                       .rst_async_in (board_reset),
                       .rst_sync_out (sys_reset));

   // The diag switch is SW[1], sampled while the machine is in reset and held
   // after: the PROM reads it at power-up and expects it to stay put.  Up =
   // diag.  Synchronised: it is a 1.5 V Schmitt input from the outside world.
   `SUN3_ASYNC_REG reg sw1_s1, sw1_s2;
   reg diag_switch = 1'b0;
   always @(posedge cpu_clk) begin
      sw1_s1 <= SW[1]; sw1_s2 <= sw1_s1;
      if (sys_reset) diag_switch <= sw1_s2;
   end

   // ------------------------------------------------------------------
   // The Sun-3
   // ------------------------------------------------------------------
   wire        wb_cyc, wb_stb, wb_we, wb_ack;
   wire [29:0] wb_adr;
   wire [31:0] wb_dat_m2s, wb_dat_s2m;
   wire [3:0]  wb_sel;
   wire [7:0]  leds, todebug;
   wire        en_boot;
   wire        sun_tx, sun_rx;

   // The SCSI disk's block seam (Inputs/Wish5380 doc/block.md): flattened on
   // the machine's side, which is Verilog; the types come from wish5380_pkg.
   wire        blk_start, blk_we;
   wire [31:0] blk_lba;
   wire [7:0]  blk_buf_rdata;
   blk_rsp_t   blk_rsp;

   sun3_top machine (
       .CLK         (cpu_clk),
       .clk4m9152   (clk_serial),
       .clk32k768   (1'b0),          // unused inside (the TOD runs on CLK)
       .sys_reset   (sys_reset),
       .tx          (sun_tx),
       .rx          (sun_rx & ~jtag_break),
       .kbd_tx      (),
       .kbd_rx      (1'b1),          // no keyboard or mouse: idle lines
       .mou_rx      (1'b1),
`ifdef SUN3_ETH_WISH7990
       .phy_txd     (NET_TXD),
       .phy_tx_en   (NET_TX_EN),
       .phy_tx_er   (),              // the DP83620's TX_ER is not wired to the FPGA
       .phy_tx_clk  (NET_TX_CLK),
       .phy_col     (NET_COL),
       .phy_rxd     (NET_RXD),
       .phy_rx_dv   (NET_RX_DV),
       .phy_rx_er   (NET_RX_ER),
       .phy_rx_clk  (NET_RX_CLK),
       .phy_crs     (NET_CRS),
       .phy_int_n   (1'b1),
       .phy_reset_n (),              // the board owns the PHY's reset, below
`endif
`ifdef SUN3_SCSI
       .blk_start     (blk_start),
       .blk_we        (blk_we),
       .blk_lba       (blk_lba),
       .blk_buf_rdata (blk_buf_rdata),
       .blk_done      (blk_rsp.done),
       .blk_err       (blk_rsp.err),
       .blk_ready     (blk_rsp.ready),
       .blk_count     (blk_rsp.count),
       .blk_buf_we    (blk_rsp.buf_we),
       .blk_buf_addr  (blk_rsp.buf_addr),
       .blk_buf_wdata (blk_rsp.buf_wdata),
`endif
       .V_INT       (1'b0),
       .leds        (leds),
       .en_boot     (en_boot),
       .diag_switch (diag_switch),
       .todebug     (todebug),
       .wb_cyc_o    (wb_cyc),
       .wb_stb_o    (wb_stb),
       .wb_adr_o    (wb_adr),
       .wb_dat_o    (wb_dat_m2s),
       .wb_sel_o    (wb_sel),
       .wb_we_o     (wb_we),
       .wb_dat_i    (wb_dat_s2m),
       .wb_ack_i    (wb_ack)
   );

   // ------------------------------------------------------------------
   // Main memory: the board's 512 MB of DDR3
   // ------------------------------------------------------------------
   wire ddr3_cal_pass;
   wire [7:0] ddr3_rdcal;

`ifdef BOARD_MEM_FAST

   assign wb_cyc_o    = wb_cyc;
   assign wb_stb_o    = wb_stb;
   assign wb_adr_o    = wb_adr;
   assign wb_dat_o    = wb_dat_m2s;
   assign wb_sel_o    = wb_sel;
   assign wb_we_o     = wb_we;
   assign wb_dat_s2m  = wb_dat_i;
   assign wb_ack      = wb_ack_i;
   assign cpu_clk_o   = cpu_clk;
   assign sys_reset_o = sys_reset;
   assign ddr3_ready    = 1'b1;       // nothing to calibrate
   assign ddr3_cal_pass = 1'b1;
   assign ddr3_rdcal    = 8'h0;

`else

   // One port: the CPU's.  The frame buffer is memory the PROM draws into, not
   // yet a display, so there is no scan-out port.
   localparam int PORT_ADDR_SIZE  = 29;    // byte address: 512 MB
   localparam int PORT_CACHE_BITS = 128;

   wire                         cmd_clk, ddr3_rst_out;
   wire                         cmd_busy_a      [0:0];
   wire                         cmd_ena_a       [0:0];
   wire                         cmd_write_ena_a [0:0];
   wire [PORT_ADDR_SIZE-1:0]    cmd_addr_a      [0:0];
   wire [PORT_CACHE_BITS-1:0]   cmd_wdata_a     [0:0];
   wire [PORT_CACHE_BITS/8-1:0] cmd_wmask_a     [0:0];
   wire                         cmd_rready_a    [0:0];
   wire [PORT_CACHE_BITS-1:0]   cmd_rdata_a     [0:0];
   wire [7:0]                   cmd_rvec_out_a  [0:0];

   deca_wb_to_ddr3 #(.PORT_ADDR_SIZE(PORT_ADDR_SIZE),
                     .PORT_CACHE_BITS(PORT_CACHE_BITS)) memif (
       .clk_wb   (cpu_clk),
       .rst_wb   (sys_reset),
       .wb_cyc_i (wb_cyc),
       .wb_stb_i (wb_stb),
       .wb_adr_i (wb_adr),
       .wb_dat_i (wb_dat_m2s),
       .wb_sel_i (wb_sel),
       .wb_we_i  (wb_we),
       .wb_dat_o (wb_dat_s2m),
       .wb_ack_o (wb_ack),

       .cmd_clk        (cmd_clk),
       .cmd_rst        (ddr3_rst_out),
       .ddr3_ready     (ddr3_ready),
       .CMD_busy       (cmd_busy_a[0]),
       .CMD_ena        (cmd_ena_a[0]),
       .CMD_write_ena  (cmd_write_ena_a[0]),
       .CMD_addr       (cmd_addr_a[0]),
       .CMD_wdata      (cmd_wdata_a[0]),
       .CMD_wmask      (cmd_wmask_a[0]),
       .CMD_read_ready (cmd_rready_a[0]),
       .CMD_read_data  (cmd_rdata_a[0])
   );

   BrianHG_DDR3_CONTROLLER_v16_top #(
       .FPGA_VENDOR     ("Altera"),
       .FPGA_FAMILY     ("MAX 10"),
       .CLK_KHZ_IN      (50000),
       // 250 MHz: at BrianHG's 400 the Quartus 25.1 fitter refuses DDR3_CK_p
       // (800 Mbps against 600 for differential 1.5-V SSTL Class I).
       .CLK_IN_MULT     (20),
       .CLK_IN_DIV      (4),
       .INTERFACE_SPEED ("Half"),
       .DDR3_SIZE_GB    (4),          // MT41K256M16, the DECA's part
       .DDR3_WIDTH_DQ   (16),
       .DDR3_NUM_CHIPS  (1),
       .PORT_TOTAL      (1),
       // No caching: a timeout-based cache in front of a CPU that issues one
       // access at a time buys nothing, and on the Sun-2 it returned a stale
       // word 47 clocks after the write (Sun-2 CLAUDE.md).
       .PORT_W_CACHE_TOUT ('{16{9'd0}}),
       .PORT_R_CACHE_TOUT ('{16{9'd0}}),
       .PORT_CACHE_SMART  ('{16{DDR3_SMART}})
   ) ddr3 (
       .RST_IN   (board_reset_raw),
       .CLK_IN   (MAX10_CLK1_50),
       .DDR3_CLK (), .DDR3_CLK_50 (), .DDR3_CLK_25 (),
       .CMD_CLK      (cmd_clk),
       .RST_OUT      (ddr3_rst_out),
       .DDR3_READY   (ddr3_ready),
       .SEQ_CAL_PASS (ddr3_cal_pass),
       .PLL_LOCKED   (),
       .RDCAL_data   (ddr3_rdcal),

       .CMD_busy            (cmd_busy_a),
       .CMD_ena             (cmd_ena_a),
       .CMD_write_ena       (cmd_write_ena_a),
       .CMD_addr            (cmd_addr_a),
       .CMD_wdata           (cmd_wdata_a),
       .CMD_wmask           (cmd_wmask_a),
       .CMD_read_vector_in  ('{1{8'h00}}),
       .CMD_read_ready      (cmd_rready_a),
       .CMD_read_data       (cmd_rdata_a),
       .CMD_read_vector_out (cmd_rvec_out_a),
       .CMD_priority_boost  ('{1{1'b0}}),
       .SEQ_refresh_hold    (1'b0),

       .DDR3_RESET_n (DDR3_RESET_n), .DDR3_CK_p (DDR3_CK_p), .DDR3_CK_n (DDR3_CK_n),
       .DDR3_CKE (DDR3_CKE), .DDR3_CS_n (DDR3_CS_n), .DDR3_RAS_n (DDR3_RAS_n),
       .DDR3_CAS_n (DDR3_CAS_n), .DDR3_WE_n (DDR3_WE_n), .DDR3_ODT (DDR3_ODT),
       .DDR3_A (DDR3_A), .DDR3_BA (DDR3_BA), .DDR3_DM (DDR3_DM),
       .DDR3_DQ (DDR3_DQ), .DDR3_DQS_p (DDR3_DQS_p), .DDR3_DQS_n (DDR3_DQS_n)
   );

`endif

   // ------------------------------------------------------------------
   // Console: ttya <-> JTAG UART, on the raw 50 MHz oscillator.
   //
   // Not clk_serial and not cpu_clk: the JTAG Atlantic crosses into TCK
   // (10 MHz), and a user clock near or below that duplicates and swaps bytes
   // (the Sun-2 measured both).  50 MHz is 5x TCK.  A bit is 5208 clocks,
   // 0.006% off 9600 baud.
   // ------------------------------------------------------------------
   localparam int CON_CLK_HZ = 50_000_000;

   wire con_rst, con_dropped, con_frame_err;
   reset_sync rst_con (.clk(MAX10_CLK1_50),
                       .rst_async_in (board_reset),
                       .rst_sync_out (con_rst));

   deca_jtag_console #(.CLKS_PER_BIT(CON_CLK_HZ / 9600)) console (
       .clk       (MAX10_CLK1_50),
       .rst       (con_rst),
       .sun_tx    (sun_tx),
       .sun_rx    (sun_rx),
       .dropped   (con_dropped),
       .frame_err (con_frame_err),
       .ev_rx_valid (),
       .ev_wr_data  (),
       .ev_rd_valid (),
       .ev_tx_start ()
`ifdef SUN3_SIM
       ,
       .av_address_o     (av_address_o),
       .av_chipselect_o  (av_chipselect_o),
       .av_read_n_o      (av_read_n_o),
       .av_write_n_o     (av_write_n_o),
       .av_writedata_o   (av_writedata_o),
       .av_readdata_i    (av_readdata_i),
       .av_waitrequest_i (av_waitrequest_i)
`endif
   );

   // ------------------------------------------------------------------
   // The SCSI disk's media: the micro-SD card, in SPI mode
   //
   // blk_sd from Inputs/Wish5380, unchanged, on cpu_clk: the block seam has
   // no clock crossing by contract, so the back end shares the target's
   // clock.  The disk starts DISK_LBA_OFFSET sectors into the card, applied
   // here at the media.  The translator's four control pins are constants:
   // SPI never turns a line around.  DAT1/DAT2 share D123_DIR with the chip
   // select, so they point at the card too and are driven to their idle
   // high rather than left to Quartus's reserved-pin ground.
   // ------------------------------------------------------------------
   assign SD_SEL      = 1'b0;   // VCCIO_SD = 3.3 V at the card
   assign SD_CMD_DIR  = 1'b1;   // MOSI out
   assign SD_D0_DIR   = 1'b0;   // MISO in
   assign SD_D123_DIR = 1'b1;   // DAT3 (chip select) out
   assign SD_DAT1     = 1'b1;
   assign SD_DAT2     = 1'b1;

`ifdef SUN3_SCSI
   blk_req_t blk_req_media;
   always_comb begin
      blk_req_media.start     = blk_start;
      blk_req_media.we        = blk_we;
      blk_req_media.lba       = blk_lba + DISK_LBA_OFFSET[31:0];
      blk_req_media.buf_rdata = blk_buf_rdata;
   end

   // In picoseconds, in two steps: some front ends mangle a 1e12 literal.
   localparam int SD_CLK_PERIOD_PS = 1_000_000_000 / (CPU_CLK_HZ / 1000);

   blk_sd #(.CLK_PERIOD_PS(SD_CLK_PERIOD_PS)) sdcard (
       .clk_i     (cpu_clk),
       .rst_i     (sys_reset),
       .blk_i     (blk_req_media),
       .blk_o     (blk_rsp),
       .sd_clk_o  (SD_CLK),
       .sd_cs_n_o (SD_CS_N),
       .sd_mosi_o (SD_CMD),
       .sd_miso_i (SD_MISO)
   );
`else
   // No disk: the card deselected, not floating.
   assign blk_rsp = '0;
   assign SD_CLK  = 1'b0;
   assign SD_CMD  = 1'b0;
   assign SD_CS_N = 1'b1;
   wire _unused_sd = &{1'b0, SD_MISO, blk_start, blk_we, blk_lba, blk_buf_rdata, 1'b0};
   assign blk_start = 1'b0; assign blk_we = 1'b0;
   assign blk_lba = 32'h0;  assign blk_buf_rdata = 8'h0;
`endif

   // ------------------------------------------------------------------
   // Ethernet PHY management (DP83620 -> 10BASE-T MII)
   // ------------------------------------------------------------------
   wire        phy_present, phy_cfg_done, phy_link, phy_fd;
   wire [1:0]  phy_speed;

`ifdef SUN3_ETH_WISH7990
   wire        mdio_cyc, mdio_stb, mdio_we, mdio_ack;
   wire [3:0]  mdio_sel;
   wire [5:0]  mdio_adr;
   wire [31:0] mdio_dat_w, mdio_dat_r;
   wire        mdio_o, mdio_oe, mdio_i;
   wire [15:0] phy_id;

   // MDC = CPU_CLK / (2 * (DIV + 1)), about 125 kHz: far under the 2.5 MHz
   // allowed, and a slow bus tolerates whatever is on the trace.
   localparam int MDIO_DIV = CPU_CLK_HZ / 250_000 - 1;

   wb_mdio #(.DIV_RESET(MDIO_DIV)) mdio_station (
       .clk       (cpu_clk),
       .rst       (sys_reset),
       .wbs_cyc_i (mdio_cyc),
       .wbs_stb_i (mdio_stb),
       .wbs_we_i  (mdio_we),
       .wbs_sel_i (mdio_sel),
       .wbs_adr_i (mdio_adr),
       .wbs_dat_i (mdio_dat_w),
       .wbs_dat_o (mdio_dat_r),
       .wbs_ack_o (mdio_ack),
       .wbs_err_o (),
       .mdc       (NET_MDC),
       .mdio_o    (mdio_o),
       .mdio_oe   (mdio_oe),
       .mdio_i    (mdio_i)
   );

   // Quartus infers the tristate: no IOBUF to instantiate.
   assign NET_MDIO = mdio_oe ? mdio_o : 1'bz;
   assign mdio_i   = NET_MDIO;

   // The DP83620 needs RESET_N low for only 1 us (datasheet 6.6), which the
   // hold counter covers many times over; MDIO waits 2^15 clocks more.
   reg [15:0] phy_wait;
   always @(posedge cpu_clk)
     if (board_reset)          phy_wait <= 16'd0;
     else if (!phy_wait[15])   phy_wait <= phy_wait + 16'd1;

   phy_dp83620_init #(.PHY_ADDR(5'd1)) phy_init (
       .clk         (cpu_clk),
       .rst         (sys_reset),
       .enable      (phy_wait[15]),
       .wbm_cyc_o   (mdio_cyc),
       .wbm_stb_o   (mdio_stb),
       .wbm_we_o    (mdio_we),
       .wbm_sel_o   (mdio_sel),
       .wbm_adr_o   (mdio_adr),
       .wbm_dat_o   (mdio_dat_w),
       .wbm_dat_i   (mdio_dat_r),
       .wbm_ack_i   (mdio_ack),
       .phy_id      (phy_id),
       .phy_present (phy_present),
       .cfg_done    (phy_cfg_done),
       .link        (phy_link),
       .speed       (phy_speed),
       .full_duplex (phy_fd)
   );
   wire _unused_phy = &{1'b0, phy_id, 1'b0};
`else
   // No Ethernet: the MII outputs idle, the PHY management bus quiet.
   assign NET_TXD   = 4'h0;
   assign NET_TX_EN = 1'b0;
   assign NET_MDC   = 1'b0;
   assign NET_MDIO  = 1'bz;
   assign phy_present  = 1'b0;
   assign phy_cfg_done = 1'b0;
   assign phy_link     = 1'b0;
   assign phy_fd       = 1'b0;
   assign phy_speed    = 2'b00;
   wire _unused_mii = &{1'b0, NET_TX_CLK, NET_RX_CLK, NET_RXD, NET_RX_DV,
                        NET_RX_ER, NET_CRS, NET_COL, 1'b0};
`endif

   assign NET_RESET_n = ~board_reset_raw;
   // PCF_EN low disables the power-control-frame feature.
   assign NET_PCF_EN  = 1'b0;

   // ------------------------------------------------------------------
   // In-System Sources and Probes: a reset and a BREAK in, the board's state
   // out.  Read and pulsed by tools/deca_reset.tcl (source bit 0 = reset,
   // bit 1 = BREAK on ttya).
   //
   //   probe 65:58 ddr3_rdcal   57 ddr3_cal_pass  56 ddr3_ready  55 phy_link
   //         54 phy_present  53 phy_cfg_done  52:51 phy_speed  50 phy_fd
   //         49:42 todebug  41:34 leds (the diag register, as written: 0 = lit)
   //         33 disk ready  32 disk error (last)  31:0 disk blocks
   //   (appended at the bottom, so tools/deca_reset.tcl's MSB-first offsets
   //   of the fields above did not move)
   // ------------------------------------------------------------------
   // The disk's last error, held: err is only meaningful with done.
   reg blk_err_q = 1'b0;
   always @(posedge cpu_clk)
     if (sys_reset)         blk_err_q <= 1'b0;
     else if (blk_rsp.done) blk_err_q <= blk_rsp.err;

`ifdef SUN3_SIM
   assign jtag_reset = 1'b0;
   assign jtag_break = 1'b0;
`else
   altsource_probe #(
       .sld_auto_instance_index ("YES"),
       .instance_id             ("SUN3"),
       .probe_width             (66),
       .source_width            (2),
       .source_initial_value    ("0"),
       .enable_metastability    ("YES")
   ) u_issp (
       .source_clk (cpu_clk),
       .probe  ({ddr3_rdcal, ddr3_cal_pass, ddr3_ready, phy_link,
                 phy_present, phy_cfg_done, phy_speed, phy_fd,
                 todebug, leds,
                 blk_rsp.ready, blk_err_q, blk_rsp.count}),
       .source ({jtag_break, jtag_reset})
   );
`endif

   // ------------------------------------------------------------------
   // Board outputs
   // ------------------------------------------------------------------
   // Active low.  `leds' is the diag register as the PROM writes it (0 = lit,
   // as on the real front panel), so it goes out as is; todebug is active
   // high and is inverted.
   assign LED = SW[0] ? ~todebug : leds;

   // GPIO0_D[0] is the console's TX (PIN_W18, the board's UART_TXD); [1] and
   // [2] the console's sticky health flags.
   assign GPIO0_D = {~leds[7:3], con_frame_err, con_dropped, sun_tx};
   assign GPIO1_D = todebug;

   wire _unused = &{1'b0, en_boot, KEY[1], 1'b0};

endmodule
