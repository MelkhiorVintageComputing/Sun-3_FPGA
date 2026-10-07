`timescale 1ns / 1ps

`include "sun3_config.vh"

//
// The Sun-3 on a QMTech Wukong (V1; V3 pins in syn/wukong_v3.xdc).
//
// Everything vendor- and board-specific lives here and in syn/: the MMCMs,
// MIG and its DDR3, the pins.  The machine itself is rtl/sun3/sun3_top.v and
// knows none of it -- it has a Wishbone master for main memory and wants to be
// held in reset until that memory answers.
//
// Adapted from the Sun-2 project's boards/Wukong/wukong_top.sv; the memory path
// (wb_to_mig_ui -> mig_arb -> MIG), the clocking and the reset chain are the
// same, and so are the pins.
//
//   clk50 --BUFG-- wukong_clkgen --+-- cpu_clk     (CPU_CLK_HZ, 20 MHz)
//                                  +-- serial_clk  (4.9152 MHz, the SCCs)
//                                  +-- clk_mig_sys / clk_idelay (MIG)
//
//   sun3_top --Wishbone (cpu_clk)-- wb_to_mig_ui adapter --(ui_clk)-- mig_arb -- MIG
//
// or, with SUN3_WB_FIFO, the crossing inside the machine's FIFO bridge:
//
//   sun3_top --Wishbone (ui_clk)-- wb_mig_sync adapter_sync -- mig_arb -- MIG
//
// Options (sun3_config.vh / syn/build.tcl):
//   SUN3_ETH_WISH7990   the Wish7990 on the board's RTL8211EG, run as MII
//   SUN3_WB_FIFO        the FIFO bridge (posted writes), its Wishbone side on
//                       ui_clk
//   SUN3_EXPBOARD       the Wukong-Sun expansion board on J12: keyboard and
//                       mouse, ttyb, the diag LEDs (instead of PMOD J10), and
//                       on a V1 the micro-SD for the disk
//   BOARD_MEM_FAST      simulation only: no MIG, the Wishbone port and the
//                       CPU clock and reset come out to the testbench
//

module wukong_top #(
    // Every knob is a parameter of this module: synth_design -generic reaches
    // the top level and nothing below it.
    parameter int CPU_CLK_HZ = 20_000_000,
    parameter int CPU_DIV    = 0,
    // Where the SCSI disk starts on the micro-SD card, in 512-byte sectors
    // (syn/Makefile DISK_OFF_MIB * 2048), as on the DECA.
    parameter int DISK_LBA_OFFSET = 0
) (
    input  wire        clk50,
    input  wire        cpu_reset,      // board button, active low

    output wire        serial_tx,
    input  wire        serial_rx,

    output wire [1:0]  user_led,       // active low
    input  wire        user_btn,       // active low: the diag switch
    output wire [7:0]  diag_leds0,     // the Sun's diag register: PMOD J10,
                                       // or the expansion board's LEDs
    output wire [7:0]  extra_leds0,    // second LED header: todebug

`ifdef SUN3_EXPBOARD
    // The Wukong-Sun expansion board (syn/wukong_exp_v1.xdc, _v3.xdc).  The
    // keyboard and mouse lines are at the connector's polarity: a 3/60 puts
    // one 74ALS04 between its SCC and each of them (schematic sheet 4, U404),
    // and the board's SN74LV1T125 buffers do not invert, so they are inverted
    // here.  ttyb is at the SCC's polarity, as the CH340N wants it; the
    // CH340N's own pin names are the other way round (its RXD is ttyb_tx).
    output wire        kbd_tx,
    input  wire        kbd_rx,
    output wire        mouse_tx,       // to the connector's pin 7
    input  wire        mouse_rx,
    output wire        ttyb_tx,
    input  wire        ttyb_rx,
`endif

`ifdef SUN3_ETH_WISH7990
    // RTL8211EG, run as 10/100 MII.  rx_dv, rx_er and col are PHY strap pins
    // and must stay plain inputs.
    input  wire        phy_mii_tx_clk,
    output wire [3:0]  phy_mii_txd,
    output wire        phy_mii_tx_en,
    output wire        phy_mii_tx_er,
    input  wire        phy_mii_rx_clk,
    input  wire [3:0]  phy_mii_rxd,
    input  wire        phy_mii_rx_dv,
    input  wire        phy_mii_rx_er,
    input  wire        phy_mii_crs,
    input  wire        phy_mii_col,
    output wire        phy_gtx_clk,
    output wire        phy_reset_n,
    output wire        phy_mdc,
    inout  wire        phy_mdio,
`endif

`ifdef SUN3_VIDEO
    // The bw2 on the board's HDMI connector, TMDS driven by the FPGA
    // (syn/wukong_hdmi.xdc).
    output wire [2:0]  tmds_p,
    output wire [2:0]  tmds_n,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
`endif

`ifdef SUN3_SCSI
    // A micro-SD slot, in SPI mode, for the on-board SCSI's disk: J9 on a V3
    // (syn/wukong_sd_v3.xdc, from the Sun-2 project, which ran its disk from
    // this slot), the expansion board's on a V1, which has none
    // (syn/wukong_exp_sd_v1.xdc).  Card detect is not read, and the
    // expansion board's slot has none.
    output wire        sd_clk,           // CLK
    output wire        sd_cmd,           // CMD  -> MOSI
    input  wire        sd_dat0,          // DAT0 -> MISO
    output wire        sd_dat3,          // DAT3 -> /CS
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
    input  wire [127:0] wb_line_i,     // the read's whole line (cached bridge)
    output wire        cpu_clk_o,
    output wire        sys_reset_o
`else
    // DDR3: the names MIG generates, pins in its .prj.
    inout  wire [15:0] ddr3_dq,
    inout  wire [1:0]  ddr3_dqs_p,
    inout  wire [1:0]  ddr3_dqs_n,
    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_cke,
    output wire [1:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt
`endif
);

   // ------------------------------------------------------------------
   // Clocks
   // ------------------------------------------------------------------
   // An explicit BUFG on the oscillator: the reset assembly (and the PHY reset
   // counter) are clocked by it directly, and Vivado only sometimes infers the
   // buffer -- without it the Sun-2 build measured 0.93 ns of skew across one
   // counter and failed hold.
   wire clk50_g;
   BUFG bufg_clk50 (.I(clk50), .O(clk50_g));

   wire board_reset = ~cpu_reset;

   wire clk_mig_sys, clk_idelay, cpu_clk, serial_clk, mmcm_locked;

   wukong_clkgen #(.CPU_CLK_HZ(CPU_CLK_HZ), .CPU_DIV(CPU_DIV)) clkgen (
       .clk50       (clk50_g),
       .reset       (board_reset),
       .clk_mig_sys (clk_mig_sys),
       .clk_idelay  (clk_idelay),
       .clk_cpu     (cpu_clk),
       .clk_serial  (serial_clk),
       .locked      (mmcm_locked)
   );

   // ------------------------------------------------------------------
   // Reset
   // ------------------------------------------------------------------
   // The machine stays in reset until the MMCMs are locked, a counter has run
   // out, and MIG has calibrated: this is where "memory is ready" lives, now
   // that the Wishbone bridge no longer waits to be switched on.
   wire init_calib_complete;

   reg [7:0] hold_ctr = 8'hFF;
   always @(posedge clk50_g) begin
      if (board_reset || !mmcm_locked) hold_ctr <= 8'hFF;
      else if (hold_ctr != 8'h00)      hold_ctr <= hold_ctr - 8'd1;
   end

   wire sys_reset_raw = board_reset | ~mmcm_locked | (hold_ctr != 8'h00)
                      | ~init_calib_complete;

   // Assembled from three clock domains: released synchronously to the CPU's.
   wire sys_reset;
   reset_sync rst_cpu (
       .clk          (cpu_clk),
       .rst_async_in (sys_reset_raw),
       .rst_sync_out (sys_reset)
   );

   // The diag switch is the user button, sampled while the machine is in
   // reset and held after: the PROM reads it at power-up and expects it to
   // stay put (as the old LiteX build did it).  Pressed = diag.
   reg diag_switch = 1'b0;
   always @(posedge cpu_clk)
     if (sys_reset) diag_switch <= ~user_btn;

   // ------------------------------------------------------------------
   // Ethernet PHY management (RTL8211EG -> 10/100 MII)
   // ------------------------------------------------------------------
   wire phy_cfg_done, phy_link;

`ifdef SUN3_ETH_WISH7990
   // PHY reset: nothing else drives it, so R1 is undefined until the
   // bitstream runs.  20 ms low, then 50 ms more before MDIO, on clk50.
   localparam int PHY_RST_CYCLES  = 50_000 * 20;
   localparam int PHY_WAIT_CYCLES = 50_000 * 50;
   reg [21:0] phy_rst_ctr  = 22'h0;
   reg        phy_rst_done = 1'b0;
   reg        phy_mdio_ok  = 1'b0;
   always @(posedge clk50_g) begin
      if (board_reset) begin
         phy_rst_ctr  <= 22'h0;
         phy_rst_done <= 1'b0;
         phy_mdio_ok  <= 1'b0;
      end else if (phy_rst_ctr != PHY_RST_CYCLES[21:0] + PHY_WAIT_CYCLES[21:0]) begin
         phy_rst_ctr <= phy_rst_ctr + 22'h1;
         if (phy_rst_ctr == PHY_RST_CYCLES[21:0]) phy_rst_done <= 1'b1;
      end else begin
         phy_mdio_ok <= 1'b1;
      end
   end
   assign phy_reset_n = phy_rst_done;

   // Gigabit only, and the board cannot do it: held low.
   assign phy_gtx_clk = 1'b0;

   wire        mdio_cyc, mdio_stb, mdio_we, mdio_ack;
   wire [3:0]  mdio_sel;
   wire [5:0]  mdio_adr;
   wire [31:0] mdio_dat_w, mdio_dat_r;
   wire        mdio_o, mdio_oe, mdio_i;
   wire [15:0] phy_id;
   wire        phy_present, phy_fd;
   wire [1:0]  phy_speed;

   // 20 MHz / (2 * (79 + 1)) = 125 kHz MDC: far under the 2.5 MHz allowed.
   wb_mdio #(.DIV_RESET(79)) mdio_station (
       .clk        (cpu_clk),
       .rst        (sys_reset),
       .wbs_cyc_i  (mdio_cyc),
       .wbs_stb_i  (mdio_stb),
       .wbs_we_i   (mdio_we),
       .wbs_sel_i  (mdio_sel),
       .wbs_adr_i  (mdio_adr),
       .wbs_dat_i  (mdio_dat_w),
       .wbs_dat_o  (mdio_dat_r),
       .wbs_ack_o  (mdio_ack),
       .wbs_err_o  (),
       .mdc        (phy_mdc),
       .mdio_o     (mdio_o),
       .mdio_oe    (mdio_oe),
       .mdio_i     (mdio_i)
   );

   IOBUF mdio_pad (.O(mdio_i), .IO(phy_mdio), .I(mdio_o), .T(~mdio_oe));

   // phy_mdio_ok comes from the clk50 domain.
   (* ASYNC_REG = "TRUE" *) reg phy_ok_s1, phy_ok_s2;
   always @(posedge cpu_clk) begin
      phy_ok_s1 <= phy_mdio_ok;
      phy_ok_s2 <= phy_ok_s1;
   end

   phy_rtl8211_init #(.PHY_ADDR(5'd1)) phy_init (
       .clk         (cpu_clk),
       .rst         (sys_reset),
       .enable      (phy_ok_s2),
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
`else
   assign phy_cfg_done = 1'b0;
   assign phy_link     = 1'b0;
`endif

   // ------------------------------------------------------------------
   // LEDs (user LEDs active low: lit = 0)
   // ------------------------------------------------------------------
   // From sys_reset_raw, not sys_reset: if cpu_clk never runs, the
   // synchronised copy never releases and the LED would lie in exactly the
   // case where it is the only instrument.
   assign user_led[0] = sys_reset_raw;
   // Lit once DRAM has calibrated; with Ethernet, then the link.
   assign user_led[1] = phy_cfg_done ? ~phy_link : ~init_calib_complete;

   // ------------------------------------------------------------------
   // The Sun-3
   // ------------------------------------------------------------------
   wire        wb_cyc, wb_stb, wb_we, wb_ack;
   wire [29:0] wb_adr;

   // The Wishbone port's clock.  The synchronous bridge runs it on cpu_clk and
   // wb_to_mig_ui crosses to MIG; the FIFO bridge (SUN3_WB_FIFO) crosses inside
   // itself and runs it on MIG's ui_clk, so wb_mig_sync needs no crossing.
   // ui_clk is declared here, ahead of its first use, for xvlog's sake.
`ifndef BOARD_MEM_FAST
   wire ui_clk, ui_clk_sync_rst;
`endif
`ifdef SUN3_WB_FIFO
 `ifdef BOARD_MEM_FAST
   wire wb_side_clk = cpu_clk;
   wire wb_side_rst = sys_reset;
 `else
   wire wb_side_clk = ui_clk;
   wire wb_side_rst = ui_clk_sync_rst;
 `endif
`endif
   wire [31:0] wb_dat_m2s, wb_dat_s2m;
   wire [3:0]  wb_sel;
   wire [127:0] wb_line_s2m;          // the read's whole line, for the cached bridge
   wire [7:0]  leds, todebug;
   wire        fb_video_en;    // EN.VIDEO, for the scan-out
   wire        v_int;          // the video interrupt (pixel clock; sun3_fpga syncs it)
   wire        en_boot;

   assign diag_leds0  = leds;
   assign extra_leds0 = todebug;

`ifdef SUN3_SCSI
   // ------------------------------------------------------------------
   // The SCSI disk's media: the micro-SD card, in SPI mode.  blk_sd from
   // Inputs/Wish5380 on cpu_clk (the block seam has no clock crossing), the
   // disk DISK_LBA_OFFSET sectors into the card -- as boards/DECA/deca_top.sv.
   // ------------------------------------------------------------------
   wire        blk_start, blk_we;
   wire [31:0] blk_lba;
   wire [7:0]  blk_buf_rdata;
   blk_rsp_t   blk_rsp;
   blk_req_t   blk_req_media;
   always_comb begin
      blk_req_media.start     = blk_start;
      blk_req_media.we        = blk_we;
      blk_req_media.lba       = blk_lba + DISK_LBA_OFFSET[31:0];
      blk_req_media.buf_rdata = blk_buf_rdata;
   end

   // In picoseconds, in two steps: Vivado rejects a 1e12 literal.
   localparam int SD_CLK_PERIOD_PS = 1_000_000_000 / (CPU_CLK_HZ / 1000);

   blk_sd #(.CLK_PERIOD_PS(SD_CLK_PERIOD_PS)) sdcard (
       .clk_i     (cpu_clk),
       .rst_i     (sys_reset),
       .blk_i     (blk_req_media),
       .blk_o     (blk_rsp),
       .sd_clk_o  (sd_clk),
       .sd_cs_n_o (sd_dat3),
       .sd_mosi_o (sd_cmd),
       .sd_miso_i (sd_dat0)
   );
`endif

`ifdef SUN3_EXPBOARD
   // The 3/60's U404 inverters (see the port list).
   wire kbd_tx_scc, mouse_tx_scc;
   assign kbd_tx   = ~kbd_tx_scc;
   assign mouse_tx = ~mouse_tx_scc;
`endif

   sun3_top machine (
       .CLK         (cpu_clk),
       .clk4m9152   (serial_clk),
       .clk32k768   (1'b0),          // unused inside (the TOD runs on CLK)
       .sys_reset   (sys_reset),
       .trace_freeze (1'b0),
       .tx          (serial_tx),
       .rx          (serial_rx),
`ifdef SUN3_EXPBOARD
       .ttyb_tx     (ttyb_tx),
       .ttyb_rx     (ttyb_rx),
       .kbd_tx      (kbd_tx_scc),
       .kbd_rx      (~kbd_rx),
       .mou_tx      (mouse_tx_scc),
       .mou_rx      (~mouse_rx),
`else
       .ttyb_tx     (),
       .ttyb_rx     (1'b1),          // nothing on ttyb: idle line
       .kbd_tx      (),
       .kbd_rx      (1'b1),          // no keyboard or mouse: idle lines
       .mou_tx      (),
       .mou_rx      (1'b1),
`endif
`ifdef SUN3_ETH_WISH7990
       .phy_txd     (phy_mii_txd),
       .phy_tx_en   (phy_mii_tx_en),
       .phy_tx_er   (phy_mii_tx_er),
       .phy_tx_clk  (phy_mii_tx_clk),
       .phy_col     (phy_mii_col),
       .phy_rxd     (phy_mii_rxd),
       .phy_rx_dv   (phy_mii_rx_dv),
       .phy_rx_er   (phy_mii_rx_er),
       .phy_rx_clk  (phy_mii_rx_clk),
       .phy_crs     (phy_mii_crs),
       .phy_int_n   (1'b1),
       .phy_reset_n (),              // the board's own sequencer above owns it
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
       .V_INT       (v_int),         // vertical blanking, with SUN3_VIDEO
       .leds        (leds),
       .en_boot     (en_boot),
       .diag_switch (diag_switch),
       .todebug     (todebug),
       .fb_video_en (fb_video_en),
       .wb_cyc_o    (wb_cyc),
       .wb_stb_o    (wb_stb),
       .wb_adr_o    (wb_adr),
       .wb_dat_o    (wb_dat_m2s),
       .wb_sel_o    (wb_sel),
       .wb_we_o     (wb_we),
       .wb_dat_i    (wb_dat_s2m),
       .wb_ack_i    (wb_ack)
`ifdef SUN3_WB_FIFO
       ,
       .wb_clk_i    (wb_side_clk),
       .wb_rst_i    (wb_side_rst),
       .wb_line_i   (wb_line_s2m)
`endif
   );

   // ------------------------------------------------------------------
   // Main memory
   // ------------------------------------------------------------------
`ifdef BOARD_MEM_FAST

   assign wb_cyc_o    = wb_cyc;
   assign wb_stb_o    = wb_stb;
   assign wb_adr_o    = wb_adr;
   assign wb_dat_o    = wb_dat_m2s;
   assign wb_sel_o    = wb_sel;
   assign wb_we_o     = wb_we;
   assign wb_dat_s2m  = wb_dat_i;
   assign wb_ack      = wb_ack_i;
   assign wb_line_s2m = wb_line_i;
   assign cpu_clk_o   = cpu_clk;
   assign sys_reset_o = sys_reset;
   assign init_calib_complete = 1'b1;   // nothing to calibrate
   assign v_int = 1'b0;                 // no scan-out without the MIG path
 `ifdef SUN3_VIDEO
   assign tmds_p = 3'b000; assign tmds_n = 3'b111;
   assign tmds_clk_p = 1'b0; assign tmds_clk_n = 1'b1;
 `endif

`else

   wire [27:0]  app_addr;
   wire [2:0]   app_cmd;
   wire         app_en, app_rdy;
   wire [127:0] app_wdf_data;
   wire [15:0]  app_wdf_mask;
   wire         app_wdf_wren, app_wdf_end, app_wdf_rdy;
   wire [127:0] app_rd_data;
   wire         app_rd_data_valid, app_rd_data_end;

   wire [27:0]  c0_addr, c1_addr;
   wire         c0_we, c0_req, c0_done, c1_req, c1_done;
   wire [127:0] c0_wdata, c0_rdata, c1_rdata;
   wire [15:0]  c0_wmask;

`ifdef SUN3_WB_FIFO
   wb_mig_sync adapter_sync (
       .wb_cyc_i (wb_cyc), .wb_stb_i (wb_stb), .wb_adr_i (wb_adr),
       .wb_dat_i (wb_dat_m2s), .wb_sel_i (wb_sel), .wb_we_i (wb_we),
       .wb_dat_o (wb_dat_s2m), .wb_ack_o (wb_ack), .wb_line_o (wb_line_s2m),

       .c_addr (c0_addr), .c_we (c0_we), .c_wdata (c0_wdata), .c_wmask (c0_wmask),
       .c_req (c0_req), .c_done (c0_done), .c_rdata (c0_rdata)
   );
`else
   // Keep the instance name: syn/wukong_wbcdc.xdc names adapter/* by path.
   wb_to_mig_ui adapter (
       .clk_wb   (cpu_clk),
       .rst_wb   (sys_reset),

       .wb_cyc_i (wb_cyc), .wb_stb_i (wb_stb), .wb_adr_i (wb_adr),
       .wb_dat_i (wb_dat_m2s), .wb_sel_i (wb_sel), .wb_we_i (wb_we),
       .wb_dat_o (wb_dat_s2m), .wb_ack_o (wb_ack),

       .ui_clk   (ui_clk), .ui_rst (ui_clk_sync_rst),

       .c_addr (c0_addr), .c_we (c0_we), .c_wdata (c0_wdata), .c_wmask (c0_wmask),
       .c_req (c0_req), .c_done (c0_done), .c_rdata (c0_rdata)
   );
`endif

`ifdef SUN3_VIDEO
   // ------------------------------------------------------------------
   // The bw2 on HDMI: fb_scanout on mig_arb's client 1 (read-only, in
   // ui_clk), VESA 1280x1024@60 from hdl-util's hdmi (VIC 127, from
   // patches/hdmi), the 1152x900 screen centred.  From the Sun-2 project.
   // ------------------------------------------------------------------
   wire clk_pixel, clk_pixel_x5, hdmi_locked;

   hdmi_clkgen hdmiclk (
       .clk50        (clk50_g),
       .reset        (board_reset),
       .clk_pixel    (clk_pixel),
       .clk_pixel_x5 (clk_pixel_x5),
       .locked       (hdmi_locked)
   );

   wire pix_rst;
   reset_sync rst_pix (
       .clk          (clk_pixel),
       .rst_async_in (board_reset | ~hdmi_locked),
       .rst_sync_out (pix_rst)
   );

   // hdmi.sv sizes cx/cy from the mode: 12 and 11 bits for the 1688x1066
   // raster of VIC 127 (patches/hdmi widens BIT_HEIGHT for it; without that
   // the height truncates silently).
   localparam int SCR_W = 1280, SCR_H = 1024;
   wire [11:0] cx;
   wire [10:0] cy;
   wire [23:0] rgb;
   wire [2:0]  tmds;
   wire        tmds_clock;

   fb_scanout #(.FB_APP_BASE(28'h7F00000),    // byte 0x0FE00000, the bridges' window
                .SCREEN_W(SCR_W), .SCREEN_H(SCR_H)) scanout (
       .ui_clk (ui_clk), .ui_rst (ui_clk_sync_rst),
       .c_addr (c1_addr), .c_req (c1_req), .c_done (c1_done), .c_rdata (c1_rdata),
       .clk_pixel (clk_pixel), .pix_rst (pix_rst),
       .cx (cx), .cy (cy), .video_en (fb_video_en), .rgb (rgb)
   );

   // The retrace interrupt: high through the vertical blanking.
   reg vblank = 1'b0;
   always @(posedge clk_pixel) vblank <= (cy >= SCR_H);
   assign v_int = vblank;

   // DVI rather than HDMI: no audio, and every HDMI sink accepts it.
   hdmi #(.VIDEO_ID_CODE(127),
          .DVI_OUTPUT(1'b1),
          .VIDEO_REFRESH_RATE(60.0),
          .IT_CONTENT(1'b1),
          .VENDOR_NAME({"Sun     "}),
          .PRODUCT_DESCRIPTION({"Sun-3/60        "})
   ) hdmi_tx (
       .clk_pixel_x5 (clk_pixel_x5),
       .clk_pixel    (clk_pixel),
       .clk_audio    (clk_pixel),       // unused with DVI_OUTPUT
       .reset        (pix_rst),
       .rgb          (rgb),
       .audio_sample_word ('{16'd0, 16'd0}),
       .tmds         (tmds),
       .tmds_clock   (tmds_clock),
       .cx           (cx),
       .cy           (cy),
       .frame_width  (), .frame_height (), .screen_width (), .screen_height ()
   );

   // TMDS_33 on a 3.3 V HR bank.
   OBUFDS obufds_d0  (.I(tmds[0]),    .O(tmds_p[0]), .OB(tmds_n[0]));
   OBUFDS obufds_d1  (.I(tmds[1]),    .O(tmds_p[1]), .OB(tmds_n[1]));
   OBUFDS obufds_d2  (.I(tmds[2]),    .O(tmds_p[2]), .OB(tmds_n[2]));
   OBUFDS obufds_clk (.I(tmds_clock), .O(tmds_clk_p), .OB(tmds_clk_n));
`else
   // No video output: the scan-out client never asks.
   assign c1_addr = 28'h0;
   assign c1_req  = 1'b0;
   assign v_int   = 1'b0;
`endif

   mig_arb arbiter (
       .ui_clk (ui_clk), .ui_rst (ui_clk_sync_rst),
       .init_calib_complete (init_calib_complete),

       .c0_addr (c0_addr), .c0_we (c0_we), .c0_wdata (c0_wdata), .c0_wmask (c0_wmask),
       .c0_req (c0_req), .c0_done (c0_done), .c0_rdata (c0_rdata),

       .c1_addr (c1_addr), .c1_req (c1_req), .c1_done (c1_done), .c1_rdata (c1_rdata),

       .app_addr (app_addr), .app_cmd (app_cmd), .app_en (app_en), .app_rdy (app_rdy),
       .app_wdf_data (app_wdf_data), .app_wdf_mask (app_wdf_mask),
       .app_wdf_wren (app_wdf_wren), .app_wdf_end (app_wdf_end),
       .app_wdf_rdy (app_wdf_rdy),
       .app_rd_data (app_rd_data), .app_rd_data_valid (app_rd_data_valid)
   );

   // MIG's sys_rst is active low (SysResetPolarity in the .prj).
   sun3_mig ddr3 (
       .ddr3_dq       (ddr3_dq),
       .ddr3_dqs_p    (ddr3_dqs_p),
       .ddr3_dqs_n    (ddr3_dqs_n),
       .ddr3_addr     (ddr3_addr),
       .ddr3_ba       (ddr3_ba),
       .ddr3_ras_n    (ddr3_ras_n),
       .ddr3_cas_n    (ddr3_cas_n),
       .ddr3_we_n     (ddr3_we_n),
       .ddr3_reset_n  (ddr3_reset_n),
       .ddr3_ck_p     (ddr3_ck_p),
       .ddr3_ck_n     (ddr3_ck_n),
       .ddr3_cke      (ddr3_cke),
       .ddr3_dm       (ddr3_dm),
       .ddr3_odt      (ddr3_odt),

       .sys_clk_i     (clk_mig_sys),
       .clk_ref_i     (clk_idelay),
       .sys_rst       (~board_reset),

       .app_addr      (app_addr),
       .app_cmd       (app_cmd),
       .app_en        (app_en),
       .app_rdy       (app_rdy),
       .app_wdf_data  (app_wdf_data),
       .app_wdf_end   (app_wdf_end),
       .app_wdf_mask  (app_wdf_mask),
       .app_wdf_wren  (app_wdf_wren),
       .app_wdf_rdy   (app_wdf_rdy),
       .app_rd_data       (app_rd_data),
       .app_rd_data_end   (app_rd_data_end),
       .app_rd_data_valid (app_rd_data_valid),

       .app_sr_req    (1'b0),
       .app_ref_req   (1'b0),
       .app_zq_req    (1'b0),
       .app_sr_active (),
       .app_ref_ack   (),
       .app_zq_ack    (),

       .ui_clk              (ui_clk),
       .ui_clk_sync_rst     (ui_clk_sync_rst),
       .init_calib_complete (init_calib_complete),
       .device_temp         ()
   );

`endif

endmodule
