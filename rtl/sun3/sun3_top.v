`timescale 1ns / 1ps
`default_nettype none

`include "sun3_config.vh"

// The Sun-3 machine: the MC68020 and the system logic around it (sun3_fpga).
//
// This is the boundary the board layer and the testbench build on.  Main
// memory is outside, behind the Wishbone master; so are the clocks, which
// must be:
//
//   CLK         the CPU and bus clock (20 MHz by default; the RD68021 uses
//               both edges)
//   clk4m9152   4.9152 MHz, the SCCs' baud rate generators
//   clk32k768   32.768 kHz, not currently used by anything
//
// sys_reset is the board reset, active high.  It must stay asserted until main
// memory can take cycles: nothing in here waits for it.
//
// The CPU is chosen by SUN3_CPU_RD68021 (see sun3_config.vh): the Suska
// WF68K30L (VHDL, an MC68030 programming model without MMU or caches) by
// default, or the RD68021.

module sun3_top(/* clock, reset */
	   input wire 	     CLK,
	   input wire 	     clk4m9152,
	   input wire 	     clk32k768,
	   /* reset */
	   input wire 	     sys_reset,
	   /* serial */
	   output wire 	     tx,
	   input wire 	     rx,
	   /* kbd, mouse */
	   output wire 	     kbd_tx,
	   input wire 	     kbd_rx,
	   input wire 	     mou_rx,
`ifdef SUN3_ETH_WISH7990
	   /* MII eth */
	   output wire [3:0] phy_txd,
	   output wire 	     phy_tx_en,
	   output wire 	     phy_tx_er,
	   input wire 	     phy_tx_clk,
	   input wire 	     phy_col,
	   input wire [3:0]  phy_rxd,
	   input wire 	     phy_rx_dv,
	   input wire 	     phy_rx_er,
	   input wire 	     phy_rx_clk,
	   input wire 	     phy_crs,
	   input wire 	     phy_int_n,
	   output wire 	     phy_reset_n,
`endif
`ifdef SUN3_SCSI
	   /* the SCSI disk's block seam (Inputs/Wish5380 doc/block.md) */
	   output wire 	     blk_start,
	   output wire 	     blk_we,
	   output wire [31:0] blk_lba,
	   output wire [7:0] blk_buf_rdata,
	   input wire 	     blk_done,
	   input wire 	     blk_err,
	   input wire 	     blk_ready,
	   input wire [31:0] blk_count,
	   input wire 	     blk_buf_we,
	   input wire [8:0]  blk_buf_addr,
	   input wire [7:0]  blk_buf_wdata,
`endif
	   /* video irq */
	   input wire 	     V_INT,
	   /* leds, debug */
	   output wire [7:0] leds,
	   output wire 	     en_boot,
	   input wire 	     diag_switch,
	   output wire [7:0] todebug,

	   /* wishbone */
	   output wire 	      wb_cyc_o,
	   output wire 	      wb_stb_o,
	   output wire [29:0] wb_adr_o,
	   output wire [31:0] wb_dat_o,
	   output wire [3:0]  wb_sel_o,
	   output wire 	      wb_we_o,
	   input wire [31:0]  wb_dat_i,
	   input wire 	      wb_ack_i
`ifdef SUN3_WB_FIFO
	   ,
	   /* the Wishbone side's own clock and reset (the memory controller's) */
	   input wire 	      wb_clk_i,
	   input wire 	      wb_rst_i
`endif
	   );
   wire [31:0] ADR_OUT;
   wire [31:0] DATA_IN;
   wire [31:0] DATA_OUT;
   wire        DATA_EN;
   wire        BERRn;
   wire        P_RESET_n;
   wire        P_HALT_n;
   wire [2:0]  FC_OUT;
   wire        AVECn;
   wire [2:0]  IPLn;
   wire        IPENDn;
   wire [1:0]  DSACKn;
   wire [1:0]  SIZE;
   wire        ASn;
   wire        RWn;
   wire        RMCn;
   wire        DSn;
   wire        ECSn;
   wire        OCSn;
   wire        DBENn;
   wire        BUS_EN;
   wire        STERMn;
   wire        STATUSn;
   wire        REFILLn;
   wire        BRn;
   wire        BGn;
   wire        BGACKn;

   wire [7:0]  leds_n;
   assign leds = ~leds_n;

   sun3_fpga sun3(.clk32k768(clk32k768),
		  .clk4m9152(clk4m9152),
		  .CLK(CLK),
		  .sys_reset(sys_reset),

		  // Address and data:
		  .P_ADR_IN(ADR_OUT),  // OUT for CPU, IN for sun3
		  .P_DATA_IN(DATA_OUT),// OUT for CPU, IN for sun3
		  .P_DATA_OUT(DATA_IN),// IN for CPU, OUT for sun3
		  .P_DATA_EN(DATA_EN), // Enables the data port.

		  // System control:
		  .P_BERR_n(BERRn),
		  .P_RESET_n(P_RESET_n),
		  .P_HALT_n(P_HALT_n),

		  // Processor status:
		  .P_FC(FC_OUT),// OUT for CPU, IN for sun3

		  // Interrupt control:
		  .P_AVEC_n(AVECn),
		  .P_IPL_n(IPLn),
		  .P_IPEND_n(IPENDn),

		  // Aynchronous bus control:
		  .P_DSACK_n(DSACKn),
		  .P_SIZ(SIZE),
		  .P_AS_n(ASn),
		  .P_RW_n(RWn),
		  .P_RMC_n(RMCn),
		  .P_DS_n(DSn),
		  .P_ECS_n(ECSn),
		  .P_OCS_n(OCSn),
		  .P_DBEN_n(DBENn), // Data buffer enable.
		  .P_BUS_EN(BUS_EN), // Enables ADR, ASn, DSn, RWn, RMCn, FC and SIZE.

		  // Synchronous bus control:
		  .P_STERM_n(STERMn),

		  // Status controls:
		  .P_STATUS_n(STATUSn),
		  .P_REFILL_n(REFILLn),

		  // Bus arbitration control:
		  .P_BR_n(BRn),
		  .P_BG_n(BGn),
		  .P_BGACK_n(BGACKn),

		  .tx(tx),
		  .rx(rx),

		  .kbd_tx(kbd_tx),
		  .kbd_rx(kbd_rx),
		  .mou_rx(mou_rx),

`ifdef SUN3_ETH_WISH7990
		  .phy_txd(phy_txd),
		  .phy_tx_en(phy_tx_en),
		  .phy_tx_er(phy_tx_er),
		  .phy_tx_clk(phy_tx_clk),
		  .phy_col(phy_col),
		  .phy_rxd(phy_rxd),
		  .phy_rx_dv(phy_rx_dv),
		  .phy_rx_er(phy_rx_er),
		  .phy_rx_clk(phy_rx_clk),
		  .phy_crs(phy_crs),
		  .phy_int_n(phy_int_n),
		  .phy_reset_n(phy_reset_n),
`endif

`ifdef SUN3_SCSI
		  .blk_start(blk_start),
		  .blk_we(blk_we),
		  .blk_lba(blk_lba),
		  .blk_buf_rdata(blk_buf_rdata),
		  .blk_done(blk_done),
		  .blk_err(blk_err),
		  .blk_ready(blk_ready),
		  .blk_count(blk_count),
		  .blk_buf_we(blk_buf_we),
		  .blk_buf_addr(blk_buf_addr),
		  .blk_buf_wdata(blk_buf_wdata),
`endif
		  .V_INT(V_INT),

		  .leds(leds_n),
		  .en_boot(en_boot),
		  .diag_switch(diag_switch),
		  .todebug(todebug),

		  // wishbone
		  .wb_cyc_o(wb_cyc_o),
		  .wb_stb_o(wb_stb_o),
		  .wb_adr_o(wb_adr_o),
		  .wb_dat_o(wb_dat_o),
		  .wb_sel_o(wb_sel_o),
		  .wb_we_o(wb_we_o),
		  .wb_dat_i(wb_dat_i),
		  .wb_ack_i(wb_ack_i)
`ifdef SUN3_WB_FIFO
		  ,
		  .wb_clk_i(wb_clk_i),
		  .wb_rst_i(wb_rst_i)
`endif
		  );

   wire        RESET_INn;
   wire        HALT_INn;
   wire        RESET_OUT;
   wire        HALT_OUTn; // ignored

   assign RESET_INn = ~sys_reset; /* board reset => reset CPU */
   assign P_RESET_n = ~sys_reset & ~RESET_OUT; /* board reset or CPU reset => reset system */

   assign HALT_INn = ~sys_reset & ~RESET_OUT; /* board reset => reset CPU (HALTn seem needed) */

`ifndef SUN3_CPU_RD68021
   WF68K30L_TOP suska_68k30l (
        .CLK(CLK),

        // Address and data:
        .ADR_OUT(ADR_OUT),
        .DATA_IN(DATA_IN),
        .DATA_OUT(DATA_OUT),
        .DATA_EN(DATA_EN), // Enables the data port.

        // System control:
        .BERRn(BERRn),
        .RESET_INn(RESET_INn),
        .RESET_OUT(RESET_OUT), // Open drain.
        .HALT_INn(HALT_INn),
        .HALT_OUTn(HALT_OUTn), // Open drain.

        // Processor status:
        .FC_OUT(FC_OUT),

        // Interrupt control:
        .AVECn(AVECn),
        .IPLn(IPLn),
        .IPENDn(IPENDn),

        // Aynchronous bus control:
        .DSACKn(DSACKn),
        .SIZE(SIZE),
        .ASn(ASn),
        .RWn(RWn),
        .RMCn(RMCn),
        .DSn(DSn),
        .ECSn(ECSn),
        .OCSn(OCSn),
        .DBENn(DBENn), // Data buffer enable.
        .BUS_EN(BUS_EN), // Enables ADR, ASn, DSn, RWn, RMCn, FC and SIZE.

        // Synchronous bus control (an MC68030 pin; sun3_fpga holds it high):
        .STERMn(STERMn),

        // Status controls:
        .STATUSn(STATUSn),
        .REFILLn(REFILLn),

        // Bus arbitration control:
        .BRn(BRn),
        .BGn(BGn),
        .BGACKn(BGACKn)
    );
`else // SUN3_CPU_RD68021
   wire        fc_oe, a_oe, siz_oe, rw_oe, rmc_oe, as_oe, ds_oe, dben_oe, reset_n_oe, halt_n_oe;
   wire        xRESET_OUTn, xHALT_OUTn;
   assign BUS_EN = fc_oe | a_oe | siz_oe | rw_oe | rmc_oe | as_oe | ds_oe;
   assign RESET_OUT = ~xRESET_OUTn & reset_n_oe;
   assign HALT_OUTn = xHALT_OUTn | ~halt_n_oe;
   // The '020 has neither STATUS nor REFILL.
   assign STATUSn = 1'b1;
   assign REFILLn = 1'b1;

   rd68021_top rd68021_cpu(
			   .clk(CLK),      // free-running, both edges used
			   .rst_n(RESET_INn | HALT_INn),    // not an MC68020 pin: async init, see doc/pinout.md

			   // Function codes (UM 3.2) ------------------------------------------------
			   .fc_o(FC_OUT),
			   .fc_oe(fc_oe),

			   // Address bus (UM 3.3) ---------------------------------------------------
			   .a_o(ADR_OUT),      // A1 and A0 are real pins
			   .a_oe(a_oe),

			   // Data bus (UM 3.4) ------------------------------------------------------
			   .d_i(DATA_IN),
			   .d_o(DATA_OUT),      // all 32 bits driven on every write (UM 5.2.4)
			   .d_oe(DATA_EN),

			   // Transfer size (UM 3.5) -------------------------------------------------
			   .siz_o(SIZE),    // bytes REMAINING, not operand size (UM 5.1.1)
			   .siz_oe(siz_oe),

			   // Asynchronous bus control (UM 3.6) --------------------------------------
			   .ecs_n_o(ECSn),  // one half clock, every bus cycle; never three-stated
			   .ocs_n_o(OCSn),  // ... but only the first cycle of an operand
			   .rw_o(RWn),     // high = read, low = write
			   .rw_oe(rw_oe),
			   .rmc_n_o(RMCn),
			   .rmc_oe(rmc_oe),
			   .as_n_o(ASn),
			   .as_oe(as_oe),
			   .ds_n_o(DSn),
			   .ds_oe(ds_oe),
			   .dben_o(DBENn),
			   .dben_oe(dben_oe),
			   .dsack_n_i(DSACKn),  // [1] is DSACK1; sample both on the same edge

			   // Interrupt control (UM 3.7) ---------------------------------------------
			   .ipl_n_i(IPLn),
			   .ipend_n_o(IPENDn),  // never three-stated
			   .avec_n_i(AVECn),

			   // Bus arbitration (UM 3.8) -----------------------------------------------
			   .br_n_i(BRn),
			   .bg_n_o(BGn),     // never three-stated
			   .bgack_n_i(BGACKn),

			   // Bus exception control (UM 3.9) -----------------------------------------
			   .berr_n_i(BERRn),
			   .reset_n_i(RESET_INn),
			   .reset_n_o(xRESET_OUTn),  // open drain: constant 0
			   .reset_n_oe(reset_n_oe), // the RESET instruction holds it 512 clocks
			   .halt_n_i(HALT_INn),
			   .halt_n_o(xHALT_OUTn),   // open drain: constant 0
			   .halt_n_oe(halt_n_oe),

			   // Emulator support (UM 3.10) ---------------------------------------------
			   .cdis_n_i(1'b1)
			   );
`endif

endmodule

`default_nettype wire
