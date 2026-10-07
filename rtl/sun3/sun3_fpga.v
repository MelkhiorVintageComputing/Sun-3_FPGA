`timescale 1ns / 1ps

// The Sun-3/60 system logic: MMU, control space, on-board I/O and the bus
// glue between the CPU and all of it.  Main memory is not in here -- it is
// reached through a Wishbone master (sun3_wishbone_bridge), which the
// testbench or the board layer connects to whatever memory it has.
//
// Vendor-neutral: no primitives, no IP.  Build options are in sun3_config.vh.

`include "sun3_config.vh"
`include "sun3_attr.vh"

module sun3_fpga(/* clock, reset */
		 input 		CLK,
		 input 		clk32k768, // improveme
		 input 		clk4m9152,
		 input 		sys_reset, // board reset => also CPU reset
		 /* CPU */
		 input [31:0] 	P_ADR_IN,
		 input [31:0] 	P_DATA_IN,
		 output [31:0] 	P_DATA_OUT,
		 input 		P_DATA_EN,
		 output 	P_BERR_n,
		 input 		trace_freeze, // freeze bus_trace from outside (the DECA's ISSP)
		 input 		P_RESET_n, // the RESET- net: board reset or the CPU's RESET instruction
		 // On the 3/60 (production schematic, Jul87) RESET- reaches only the
		 // interrupt register (sh3 U304), the LANCE chip (sh5 U500) and the
		 // FPU; everything else is cleared by INIT- (power-on, watchdog),
		 // which the RESET instruction cannot cause: here, sys_reset.
		 output 	P_HALT_n,
		 input [2:0] 	P_FC,
		 output 	P_AVEC_n,
		 output [2:0] 	P_IPL_n,
		 input 		P_IPEND_n,
		 output [1:0] 	P_DSACK_n,
		 input [1:0] 	P_SIZ,
		 input 		P_AS_n,
		 input 		P_RW_n,
		 input 		P_RMC_n,
		 input 		P_DS_n,
		 input 		P_ECS_n,
		 input 		P_OCS_n,
		 input 		P_DBEN_n,
		 input 		P_BUS_EN,
		 output 	P_STERM_n,
		 input 		P_STATUS_n,
		 input 		P_REFILL_n,
		 output 	P_BR_n,
		 input 		P_BG_n,
		 output 	P_BGACK_n,
		 /* serial */
		 output 	tx,
		 input 		rx,
		 output 	ttyb_tx,
		 input 		ttyb_rx,
		 /* kbd, mouse */
		 output 	kbd_tx,
		 input 		kbd_rx,
		 output 	mou_tx,
		 input 		mou_rx,
`ifdef SUN3_ETH_WISH7990
		 /* MII eth */
		 output [3:0] 	phy_txd,
		 output 	phy_tx_en,
		 output 	phy_tx_er,
		 input 		phy_tx_clk,
		 input 		phy_col,
		 input [3:0] 	phy_rxd,
		 input 		phy_rx_dv,
		 input 		phy_rx_er,
		 input 		phy_rx_clk,
		 input 		phy_crs,
		 input 		phy_int_n,
		 output 	phy_reset_n,
`endif //  `ifdef SUN3_ETH_WISH7990
`ifdef SUN3_SCSI
		 /* the SCSI disk's block seam */
		 output 	blk_start,
		 output 	blk_we,
		 output [31:0] 	blk_lba,
		 output [7:0] 	blk_buf_rdata,
		 input 		blk_done,
		 input 		blk_err,
		 input 		blk_ready,
		 input [31:0] 	blk_count,
		 input 		blk_buf_we,
		 input [8:0] 	blk_buf_addr,
		 input [7:0] 	blk_buf_wdata,
`endif
		 /* video irq */
		 input 		V_INT,
		 /* leds, debug */
		 output [7:0] 	leds,
		 output 	en_boot,
		 input 		diag_switch,
		 //output [2:0]  berrd,
		 output [7:0] 	todebug,
		 output 	fb_video_en, // EN.VIDEO, to the board's scan-out
		 output 	fpu_sel,     // a coprocessor cycle for the FPU (CpID 1, EN.FPP), to sun3_top
		 /* wishbone */
		 output 	wb_cyc_o,
		 output 	wb_stb_o,
		 output [29:0] 	wb_adr_o,
		 output [31:0] 	wb_dat_o,
		 output [3:0] 	wb_sel_o,
		 output 	wb_we_o,
		 input [31:0] 	wb_dat_i,
		 input 		wb_ack_i
`ifdef SUN3_WB_FIFO
		 ,
		 input 		wb_clk_i,
		 input 		wb_rst_i,
		 // the whole 128-bit line a read brought back, valid with
		 // wb_ack_i; only the cached bridge (SUN3_WB_CACHE) reads it
		 input [127:0] 	wb_line_i
`endif
		 );

   // Byte-wide devices on the 32-bit bus.
`ifdef DEVICE_8BITS_ON_32BITS_BUS
   // extract/expand low-order 8-bits
   function [31:0] EXPAND_8BITS (input [7:0] VAL);
      begin
         EXPAND_8BITS = {VAL, VAL, VAL, VAL};
      end
   endfunction
   function [7:0] EXTRACT_8BITS (input [31:0] X, input [1:0] A);
      begin
         case (A)
   	2'b11: EXTRACT_8BITS = X[ 7: 0];
   	2'b10: EXTRACT_8BITS = X[15: 8];
   	2'b01: EXTRACT_8BITS = X[23:16];
   	2'b00: EXTRACT_8BITS = X[31:24];
         endcase
      end
   endfunction
`else
   // extract/expand high-order 8-bits
   function [31:0] EXPAND_8BITS (input [7:0] VAL);
      begin
         EXPAND_8BITS = {VAL, 24'h000000};
      end
   endfunction
   function [7:0] EXTRACT_8BITS (input [31:0] X, input [1:0] A);
      begin
         EXTRACT_8BITS = X[31:24];
      end
   endfunction
`endif
   
   //assign P_BR_n = 1'b1; // FIXME ? we have nothing doing DMA yet
   //assign P_BGACK_n = 1'b1;


   assign P_STERM_n = 1'b1; // 68k30l has sterm, '020 doesn't
   
   wire 			 EN_DEV;
   wire 			 DISACC;
   
   assign P_HALT_n = 1'b1; // FIXME ?

   // The bus as the system sees it: the CPU's, or the Ethernet DVMA master's
   // while it owns it (muxed below).
   wire [31:0] 			 SUN3_ADR_IN;
   wire [31:0] 			 SUN3_DATA_IN;
   wire [2:0] 			 SUN3_FC;
   wire [1:0] 			 SUN3_SIZ;
   wire 			 SUN3_AS_n;
   wire 			 SUN3_RW_n;
   wire 			 SUN3_DS_n;
   wire 			 MATCH_PROM_BOOT;

   // Every interrupt on this machine is autovectored -- but AVEC means that
   // only in an interrupt acknowledge cycle (CPU space, FC=7, A19-A16=0xF),
   // so it is asserted only there.  Tied low permanently, as it once was, the
   // RD68021 took it as the termination of every bus cycle (it samples AVEC
   // with DSACK), ending each one at S3 before a slow device had seen it.
   assign P_AVEC_n = ~((SUN3_FC == 3'h7) & (SUN3_ADR_IN[19:16] == 4'hF) & ~SUN3_AS_n);

   // layers shortcuts
   wire FC_CTRLLAYER;
   wire FC_CPUCYCLE;
   wire FC_UDATA, FC_UPROG, FC_SDATA, FC_SPROG;
   wire FC_GENERAL;

   /* 0x0: reserved, unused */
   assign FC_UDATA     = (SUN3_FC == 3'h1);
   assign FC_UPROG     = (SUN3_FC == 3'h2);
   assign FC_CTRLLAYER = (SUN3_FC == 3'h3);
   /* 0x4: reserved, unused */
   assign FC_SDATA     = (SUN3_FC == 3'h5);
   assign FC_SPROG     = (SUN3_FC == 3'h6);
   assign FC_CPUCYCLE  = (SUN3_FC == 3'h7);

   // Coprocessor space: CPU space (FC 7), A19-A16 = 2, CpID on A15-A13, the
   // register on A4-A0 (MC68020 UM 7).  The 3/60's FPP is CpID 1, and only
   // while EN.FPP is set (Architecture Manual 4.8).  Every other coprocessor
   // cycle -- another CpID, EN.FPP clear, or no FPU built -- ends promptly
   // with BERR, which on the first CIR access the CPU turns into an F-line
   // trap: that is how an OS finds there is no FPU.  Per Manual 3.2 those
   // errors do not touch the Bus Error register (no BERRCLK) and are not
   // timeouts.  DVMA never runs CPU-space cycles, so SUN3_* is the CPU's.
   wire MATCH_COPRO = FC_CPUCYCLE & (SUN3_ADR_IN[19:16] == 4'h2);
   wire COPRO_BERR  = MATCH_COPRO & ~fpu_sel;   // fpu_sel: below, after EN.FPP
   assign FC_GENERAL   = ~FC_CTRLLAYER & ~FC_CPUCYCLE;

   wire EN_BOOT; // positive logic view of EN_BOOTn
   assign en_boot = EN_BOOT;
   
   // match wire for variable-timing area
   wire 			 MATCH_VME32_32;
`ifdef SUN3_ETH_WISH7990
   wire 			 MATCH_AMDLE;
`endif
`ifdef SUN3_SCSI
   wire 			 MATCH_SCSI;
   wire [31:0] 			 scsi_out;
   wire 			 scsi_ack, scsi_irq;
`endif
   wire 			 MATCH_MEM;
   wire 			 MATCH_FB;
   
   wire [31:0] 			 ethernetdma_addr_out;
   wire [31:0] 			 ethernetdma_data_out;
   wire [2:0] 			 ethernetdma_fc_out;
   wire [1:0] 			 ethernetdma_siz_out;
   wire 			 ethernetdma_as_n_out;
   wire 			 ethernetdma_ds_n_out;
   wire 			 ethernetdma_rw_n_out;
   wire [1:0] 			 ethernetdma_dsack_n;
   wire 			 ethernetdma_br_n_out;
   wire 			 ethernetdma_bg_n;
   wire 			 ethernetdma_bgack_n_out;
   
   
`ifdef SUN3_HAS_DVMA
   // Any DVMA master (the Ethernet's or the SCSI's): both go through the one
   // bridge below, so this is the bus's DVMA owner whoever asked.
   wire 			 ethernet_dma_active = (~ethernetdma_br_n_out & ~ethernetdma_bgack_n_out);
`else
   wire 			 ethernet_dma_active = 1'b0;
   assign 			 ethernetdma_br_n_out = 1'b1;
   assign 			 ethernetdma_bgack_n_out = 1'b1;
`endif

   assign SUN3_ADR_IN  = ethernet_dma_active ? ethernetdma_addr_out : P_ADR_IN;
   assign SUN3_DATA_IN = ethernet_dma_active ? ethernetdma_data_out : P_DATA_IN;
   assign SUN3_FC      = ethernet_dma_active ? ethernetdma_fc_out   : P_FC;
   assign SUN3_SIZ     = ethernet_dma_active ? ethernetdma_siz_out  : P_SIZ;
   assign SUN3_AS_n    = ethernet_dma_active ? ethernetdma_as_n_out : P_AS_n;
   assign SUN3_RW_n    = ethernet_dma_active ? ethernetdma_rw_n_out : P_RW_n;
   assign SUN3_DS_n    = ethernet_dma_active ? ethernetdma_ds_n_out : P_DS_n;
   assign P_BR_n = ethernetdma_br_n_out; // FIXME: multiple DMA sources
   assign ethernetdma_bg_n = P_BG_n; // CHECKME: multiple DMA sources
   assign P_BGACK_n = ethernetdma_bgack_n_out; // FIXME: multiple DMA sources

//`ifndef ETHERNET
   //assign todebug = {~P_RESET_n, ~P_HALT_n, ~SUN3_AS_n, P_RESET_n,
   //		      P_IPL_n[0] & P_IPL_n[1] & P_IPL_n[2], EN_BOOT, MATCH_PROM_BOOT, CLK};
   reg [7:0] 			 rom_ctr;
   always @(negedge CLK)
     begin
	if (sys_reset)
	  begin
	     rom_ctr <= 0;
	  end
	else if (MATCH_PROM_BOOT & ~P_DSACK_n[0] & ~P_DSACK_n[1])
	  begin
	     rom_ctr <= rom_ctr + 1;
	  end
     end
   assign todebug = rom_ctr;
   
//`endif  

   
   // SUN3_AS_n timing
   reg C_S3, C_S5, C_S7, C_S9;
   always @(negedge CLK)
     begin
	if (~SUN3_AS_n)        C_S3 <= 1'b1;
	if (~SUN3_AS_n & C_S3) C_S5 <= 1'b1;
	if (~SUN3_AS_n & C_S5) C_S7 <= 1'b1;
	if (~SUN3_AS_n & C_S7) C_S9 <= 1'b1;
	if ( SUN3_AS_n)
	  begin
	     C_S3 <= 1'b0;
	     C_S5 <= 1'b0;
	     C_S7 <= 1'b0;
	     C_S9 <= 1'b0;
	  end
     end
   reg C_S4r, C_S6r, C_S8r, C_S10r, C_S12r, C_S14r, C_S16r, C_S18r, TIMEOUT;
   always @(posedge CLK)
     begin
	// SUN3_AS_n deasserts on a negedge... so those can last 1/2 cycles past the end of SUN3_AS_n
	if (~SUN3_AS_n & C_S3 ) C_S4r <= 1'b1;
	if (~SUN3_AS_n & C_S4r) C_S6r <= 1'b1;
	if (~SUN3_AS_n & C_S6r) C_S8r <= 1'b1;
	if (~SUN3_AS_n & C_S8r) C_S10r <= 1'b1;
	if (~SUN3_AS_n & C_S10r) C_S12r <= 1'b1;
	if (~SUN3_AS_n & C_S12r) C_S14r <= 1'b1;
	if (~SUN3_AS_n & C_S14r) C_S16r <= 1'b1;
	if (~SUN3_AS_n & C_S16r) C_S18r <= 1'b1;
	if (~SUN3_AS_n & C_S18r & !MATCH_MEM & !MATCH_FB & !MATCH_COPRO // CHECKME: sun3, too soon?
`ifdef SUN3_ETH_WISH7990
	    & !MATCH_AMDLE
`endif
	    ) TIMEOUT <= 1'b1;
	
	if ( SUN3_AS_n)
	  begin
	     C_S4r <= 1'b0;
	     C_S6r <= 1'b0;
	     C_S8r <= 1'b0;
	     C_S10r <= 1'b0;
	     C_S12r <= 1'b0;
	     C_S14r <= 1'b0;
	     C_S16r <= 1'b0;
	     C_S18r <= 1'b0;
	     TIMEOUT <= 1'b0;
	  end
     end
   wire C_S4, C_S6, C_S8, C_S10, C_S12, C_S14, C_S16, C_S18;
   assign C_S4 = C_S4r & ~SUN3_AS_n;
   assign C_S6 = C_S6r & ~SUN3_AS_n;
   assign C_S8 = C_S8r & ~SUN3_AS_n;
   assign C_S10 = C_S10r & ~SUN3_AS_n;
   assign C_S12 = C_S12r & ~SUN3_AS_n;
   assign C_S14 = C_S14r & ~SUN3_AS_n;
   assign C_S16 = C_S16r & ~SUN3_AS_n;
   assign C_S18 = C_S18r & ~SUN3_AS_n;
   
   // match wire for the control/mmu space
   // can match early because they only depend on the SUN3_A address
   wire 			 MATCH_CTX, MATCH_SMAP, MATCH_PMAP;
   wire 			 MATCH_IDPROM, MATCH_SYSEN, MATCH_BERR, MATCH_DIAG, MATCH_UARTBYP, MATCH_CYCTR, MATCH_FLTLOG;
   assign MATCH_IDPROM  = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h0);
   assign MATCH_PMAP    = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h1); // Long
   assign MATCH_SMAP    = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h2);
   assign MATCH_CTX     = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h3);
   assign MATCH_SYSEN   = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h4);
   //assign MATCH_UDVMA   = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h5); // optional (not on 3/60)
   assign MATCH_BERR    = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h6);
   assign MATCH_DIAG    = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h7);
   //assign MATCH_CTAGS   = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h8); // optional
   //assign MATCH_CDATA   = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'h9); // optional
   //assign MATCH_COPS    = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'hA); // optional
   //assign MATCH_BOPS    = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'hB); // optional
   assign MATCH_CYCTR   = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'hC); // custom: 32-bits always-on cycle counter
   assign MATCH_FLTLOG  = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'hD); // custom: the last 32 bus errors (fault_log.v)
   /* 0xC to 0xE: unused */
   assign MATCH_UARTBYP = (FC_CTRLLAYER) & (SUN3_ADR_IN[31:28] == 4'hF);

   assign MATCH_PROM_BOOT  = ((FC_SPROG) & (EN_BOOT)); // at boot (bit from SYSEN): all Supervisor Program are from the PROM

   wire 			 WR;
   assign WR = ~SUN3_DS_n & ~SUN3_AS_n & ~SUN3_RW_n;
   wire 			 RD;
   assign RD = ~SUN3_DS_n & ~SUN3_AS_n &  SUN3_RW_n;

   // MMU & control layers
   wire [7:0] 			 ctx_out;
   wire [7:0] 			 ia_smap2pmap; // fixme: parametrizable
   wire [18:0] 			 ma_pmap2devices; // only 16-bits in e.g. 3/60 // fixme: parametrizable
   wire [7:0] 			 ps_pmap2devices; // fixme: parametrizable
   wire [3:0] 			 mmu_stat_in; 

   wire [31:0] 			 pa_forshow; // more readable as a wave, no functional use
   assign pa_forshow = {ma_pmap2devices, SUN3_ADR_IN[12:0]};			 
   // For use of the MMU: As SUN3_ADR_IN (and FC) are valid from C_S1=>C_S2 and CTX is valid from the last update
   // ia_smap2pmap is valid from C_S3=>C_S4
   // *_pmap2devices are valid from C_S5=>C_S6
   sun3_mmu mmu(.CLK(CLK),
		/* matching */
		.MATCH_CTX(MATCH_CTX),
		.MATCH_SMAP(MATCH_SMAP),
		.MATCH_PMAP_PS(MATCH_PMAP),
		.MATCH_PMAP_MA(MATCH_PMAP),
		.WR(WR),
		.RD(RD),
		/* CPU signals */
		.P_DIN(SUN3_DATA_IN),
		.P_A(SUN3_ADR_IN),
		.P_FC(SUN3_FC),
		/* timing signals */
		.C_S4(C_S4),
		.C_S6(C_S6),
		.C_S8(C_S8),
		/* MMU outputs */
		.ctx_out(ctx_out),
		.ia_smap2pmap(ia_smap2pmap),
		.ma_pmap2devices(ma_pmap2devices),
		.ps_pmap2devices(ps_pmap2devices),
		/* stats */
		.EN_DEV(EN_DEV),
		.DISACC(DISACC),
		.stat_in(mmu_stat_in)
	    );
   
   /* split the 8 protection/status bits by name */
   wire 			 MODIFY, ACCESS, MMU_X, MMU_S, MMU_W, MMU_V;
   wire [1:0] 			 TYPE;
   assign MODIFY  = ps_pmap2devices[0];
   assign ACCESS  = ps_pmap2devices[1];
   assign TYPE[0] = ps_pmap2devices[2];
   assign TYPE[1] = ps_pmap2devices[3];
   assign MMU_X   = ps_pmap2devices[4];
   assign MMU_S   = ps_pmap2devices[5];
   assign MMU_W   = ps_pmap2devices[6];
   assign MMU_V   = ps_pmap2devices[7];
   assign mmu_stat_in[0] = MODIFY | WR;
   assign mmu_stat_in[1] = 1'b1;
   assign mmu_stat_in[2] = TYPE[0]; // IMPROVEME: behavior matches the HW, but we don't need to rewrite TYPE
   assign mmu_stat_in[3] = TYPE[1];
   

   // combinatorial protection check on Page Map output
   wire 			 BERR_P, BERR_V, BERR_T;
   // EN_DEV from 3/60:u102, minus R_ACK
   // normally, EN_DEV is further qualified by TYPE (from MMU) and some PA bits
   // EN_DEV is valid from C_S1=>C_S2 (when SUN3_ADR_IN & FC become valid)
   assign EN_DEV = ((SUN3_ADR_IN[31:28] == 4'h0) & (FC_UPROG)           ) |
		   ((SUN3_ADR_IN[31:28] == 4'h0) & (FC_UDATA | FC_SDATA)) |
		   ((SUN3_ADR_IN[31:28] == 4'hF) & (FC_UPROG)           ) |
		   ((SUN3_ADR_IN[31:28] == 4'hF) & (FC_UDATA | FC_SDATA)) |
		   ((SUN3_ADR_IN[31:28] == 4'h0) & (FC_UPROG | FC_SPROG) & !EN_BOOT) |
		   ((SUN3_ADR_IN[31:28] == 4'hF) & (FC_UPROG | FC_SPROG) & !EN_BOOT);
   // DISACC in 3/60:u232
   // DISACC becomes valid during C_S6, when the MMU signalsoutput signals become valid
   assign DISACC = ((!MMU_V                  & EN_DEV) |                   /* access not valid [also BERR_V] */
		    ( MMU_V & MMU_S          & EN_DEV & !SUN3_FC[2]) |          /* supervisor-only access but not supervisor request (FC2==1 is supervisor) [also BERR_P]*/
		    ( MMU_V         & !MMU_W & EN_DEV            & WR)); /* read-only access but attempting to write [also BERR_P] */
   // BERR.P, BERR.V in 3/60:u232
   assign BERR_V =  (!MMU_V                  & EN_DEV);
   assign BERR_P = (( MMU_V & MMU_S          & EN_DEV & !SUN3_FC[2]) |
		    ( MMU_V         & !MMU_W & EN_DEV            & WR));
   // BERR.T: custom
   assign BERR_T = TIMEOUT;
   
   
   // IDPROM, read-only
   wire [7:0] 			 idprom_out;
   idprom_sun3 idprom(.CLK(CLK),
		      .idx(SUN3_ADR_IN[4:0]),
		      .dout(idprom_out)
		      );

   // Diagnostic register, write-only
   // Cleared by INIT- (sh2 U227).
   gen8bit_reg diag(.CLK(CLK),
		    .din(EXTRACT_8BITS(SUN3_DATA_IN, SUN3_ADR_IN[1:0])),
		    .WR(WR & MATCH_DIAG & C_S4),
		    .dout(leds), // directly to the leds
		    .CLR_n(~sys_reset)
		    );
   
   // Bus Error Register, read-only
   wire [7:0] 			 berr_in;
   wire [7:0] 			 berr_out;
   wire 			 BERRCLK, BERR;
   
   //assign berr_in = {1'b1, 1'b1, FPAENERR, FPABERR, VMEBERR, TIMEOUT, PROTERR, INVALID}; // this is from the architecture manual
   //assign berr_in = {WDOGn, 1'b1, 1'b1, 1'b1, 1'b1, BERR_Tn, BERR_Pn, BERR_Vn}; // this is from the 3/60 schematics
   //assign berr_in = {1'b0, 1'b0, 1'b0, 1'b0, 1'b0, BERR_T, BERR_P, BERR_V}; // we use positive logic // fixme: watchdog?
   assign berr_in = { BERR_V, BERR_P, BERR_T, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0 }; // grr, bit order (timeout is 0x20) // we use positive logic // fixme: watchdog?
   
   gen8bit_reg berr(.CLK(CLK),
		    .din(berr_in),
		    .WR(BERRCLK), // will capture on C_S7=>C_S8
		    .dout(berr_out),
		    .CLR_n(~sys_reset /*1'b1 */) /* FIXME: how is supposed to be initialized ??? */
		    );
   assign BERRCLK	= (C_S6 & (BERR_P | BERR_T | BERR_V)); // FIXME: timing?
   assign BERR	        = (C_S6 & (BERR_P | BERR_T | BERR_V)) // FIXME: timing?
			  | (C_S4 & COPRO_BERR);   // not latched: no BERRCLK
   assign P_BERR_n = ~BERR;

   // System Enable register
   wire [7:0] 			 sys_out;
   gen8bit_reg sys(.CLK(CLK),
		   .din(EXTRACT_8BITS(SUN3_DATA_IN, SUN3_ADR_IN[1:0])),
		   .WR(WR & MATCH_SYSEN & C_S4),
		   .dout(sys_out),
		   .CLR_n(~sys_reset) // reset by INIT- on real HW
		   );
   /* split the 8 system bits by name */
   wire 			 EN_DIAG, EN_FPA, EN_COPY, EN_VIDEO, EN_CACHE, EN_SDVMA, EN_FPP, EN_BOOTn;
   
   assign EN_DIAG  = diag_switch; //sys_out[0];
   assign EN_FPA   = sys_out[1]; // no FPA fitted: stored and read back, nothing more
   assign EN_COPY  = sys_out[2];
   assign EN_VIDEO = sys_out[3];
   assign fb_video_en = EN_VIDEO;
`ifdef SUN3_FPU
   assign fpu_sel   = MATCH_COPRO & (SUN3_ADR_IN[15:13] == 3'd1) & EN_FPP;
`else
   assign fpu_sel   = 1'b0;
`endif
   assign EN_CACHE = sys_out[4];
   assign EN_SDVMA = sys_out[5];
   assign EN_FPP   = sys_out[6];
   assign EN_BOOTn = sys_out[7];
   assign EN_BOOT = ~EN_BOOTn;
   

   // output readable info when we change sysen
`ifndef SYNTHESIS
   always @(sys_out) begin
      $display("System Enable Register updated");
      $display("\tRead back Diag Switch: %x", EN_DIAG);
      $display("\tEnable FPA: %x", EN_FPA);
      $display("\tEnable Copy to Video Mem: %x", EN_COPY);
      $display("\tEnable Video: %x", EN_VIDEO);
      $display("\tEnable External Cache: %x", EN_CACHE);
      $display("\tEnable System DVMA: %x", EN_SDVMA);
      $display("\tEnable FPP: %x", EN_FPP);
      $display("\tBoot State (O => boot, 1 => normal): %x", EN_BOOTn);
   end // always @ (sys_out)
`endif


   
   // custom cycle counter
   wire [31:0] 			 cyctr_out;
   cyctr32bit_reg cyctr(.CLK(CLK),
		      .dout(cyctr_out),
		      .CLR_n(~sys_reset)
		      );

   // The last 32 bus errors, for reading from the PROM monitor (fault_log.v).
   wire [31:0] 			 fltlog_out;
   fault_log fltlog(.CLK(CLK),
		    .RESET_n(~sys_reset),
		    .FAULT(BERRCLK),
		    .ADR(SUN3_ADR_IN),
		    .FC(SUN3_FC),
		    .RW_n(SUN3_RW_n),
		    .SIZ(SUN3_SIZ),
		    .DVMA(ethernet_dma_active),
		    .BER(berr_in),
		    .PTE_PS(ps_pmap2devices),
		    .PTE_MA(ma_pmap2devices),
		    .CYCLES(cyctr_out),
		    .RD_ADR(SUN3_ADR_IN[9:2]),
		    .RD_DATA(fltlog_out));

   // ... and the last 512 bus cycles before a user fetch from page 0 (bus_trace.v):
   // 0xD0001000 status/re-arm, 0xD0002000+ the ring.
   wire [31:0] 			 bustrace_out;
`ifdef SUN3_NO_BUS_TRACE
   assign bustrace_out = 32'h0;
`else
   bus_trace bustrace(.CLK(CLK),
		      .RESET_n(~sys_reset),
		      .AS_n(SUN3_AS_n),
		      .ADR(SUN3_ADR_IN),
		      .FC(SUN3_FC),
		      .RW_n(SUN3_RW_n),
		      .SIZ(SUN3_SIZ),
		      .WDATA(SUN3_DATA_IN),
		      .RDATA(P_DATA_OUT),
		      .DSACK(~P_DSACK_n[0] | ~P_DSACK_n[1]),
		      .BERR(~P_BERR_n),
		      .DVMA(ethernet_dma_active),
		      .CYCLES(cyctr_out),
		      .FREEZE(trace_freeze),
		      .REARM(WR & MATCH_FLTLOG & C_S4 & (SUN3_ADR_IN[13:12] == 2'b01)),
		      .REARM_DATA(SUN3_DATA_IN),
		      .RD_ADR(SUN3_ADR_IN[12:2]),
		      .RD_STATUS(SUN3_ADR_IN[13:12] == 2'b01),
		      .RD_DATA(bustrace_out));
`endif


   // PROM (two access modes: at boot using SUN3_A, or mapped but matched through MA), read-only
   // handled by the two match signals in the bus section, the PROM itself always output whatever is addressed
   wire [31:0] 			 prom_out;
   bootrom32 bootrom(.CLK(CLK),
		     .idx(SUN3_ADR_IN[15:2]),
		     .dout(prom_out)
		     );

   // match wire for devices
   // matching late as we need to be sure the MA is now valid, two clocks after the address is valid
   // that happens on entry in S2 (rising edge), so on that edge IA becomes valid
   // then on entry in S4 MA becomes valid
   wire 			 MATCH_KBDMS, MATCH_SERIAL, MATCH_EEPROM, MATCH_TIMER;
   wire 			 MATCH_MEMERR_CTRL, MATCH_MEMERR_ADDR;
   wire 			 MATCH_IRQREG, MATCH_PROM;
   assign MATCH_KBDMS    = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h0) & C_S6;
   assign MATCH_SERIAL   = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h1) & C_S6;
   assign MATCH_EEPROM   = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h2) & C_S6;
   assign MATCH_TIMER    = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h3) & C_S6;
   assign MATCH_MEMERR_CTRL = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h4) & C_S6 & (SUN3_ADR_IN[2:0] == 3'h0);
   assign MATCH_MEMERR_ADDR = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h4) & C_S6 & (SUN3_ADR_IN[2:0] == 3'h4);
   assign MATCH_IRQREG   = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h5) & C_S6;
   //assign MATCH_I82586   = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h6) & C_S6;
   //assign MATCH_CMAP     = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h7) & C_S6; // color FB only
   
   assign MATCH_PROM     = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h8) & C_S6;
`ifdef SUN3_ETH_WISH7990
   assign MATCH_AMDLE    = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'h9) & C_S6;
`endif
`ifdef SUN3_SCSI
   assign MATCH_SCSI     = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'hA) & C_S6;
`endif
   //assign MATCH_RSVD1    = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'hB) & C_S6;
   //assign MATCH_RSVD2    = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'hC) & C_S6;
   //assign MATCH_RSVD3    = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'hD) & C_S6;
   //assign MATCH_DEP      = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'hE) & C_S6; // uninstalled Data Encryption Processor
   //assign MATCH_ECCREG   = (EN_DEV) & (TYPE == 2'h1) & !DISACC & (ma_pmap2devices[7:4] == 4'hF) & C_S6; // ECC memory only

   wire 			 MATCH_MEMX;
   // "Physically" installed memory: SUN3_MEM_MIB MiB from physical 0.  The
   // pmap gives physical address bits [31:13], i.e. 8 KiB pages, so that is
   // SUN3_MEM_MIB*128 pages.  Anything above it that is still type 0 times out
   // and takes a bus error, which is how the PROM sizes memory.
   assign MATCH_MEM      = (EN_DEV) & (TYPE == 2'h0) & !DISACC & (ma_pmap2devices < (`SUN3_MEM_MIB * 128)) & C_S6;
   
   assign MATCH_MEMX     = (EN_DEV) & (TYPE == 2'h0) & !DISACC & (ma_pmap2devices[18:15] == 4'h0) & C_S6; // addressable, 256 MiB (?) // CHECKME: sun3 behavior

   wire 			 MATCH_FBX;
   assign MATCH_FBX      = (EN_DEV) & (TYPE == 2'h0) & !DISACC & (ma_pmap2devices[18:11] == 8'hFF) & (ma_pmap2devices[10:8] == 3'h0) & C_S6; // architectural: 2 MiB
`ifdef SUN3_FB
   assign MATCH_FB       = (EN_DEV) & (TYPE == 2'h0) & !DISACC & (ma_pmap2devices[18:11] == 8'hFF) & (ma_pmap2devices[10:5] == 6'h00) & C_S6; // BW: 256 KiB
`else
   // No video memory: the PROM's bw2 probe times out.  Not what a real 3/60
   // looks like -- they all have it -- and the monitor is not entirely happy
   // without it (see SUN3_FB in sun3_config.vh).
   assign MATCH_FB       = 1'b0;
`endif
       
   /* VME spaces, no default timing, FYI only */
   /* ... except VME32_32 we use for CSR and temporary SRAM */
   //assign MATCH_VME16_32 = (EN_DEV) & (TYPE == 2'h2) & !DISACC;
   //assign MATCH_VME16_16 = (EN_DEV) & (TYPE == 2'h2) & !DISACC & (ma_pmap2devices[18:11] == 8'hFF));
   //assign MATCH_VME16_08 = (EN_DEV) & (TYPE == 2'h2) & !DISACC & (ma_pmap2devices[18:3] == 16'hFFFF));
   // A 3/60 has no VME bus; anything in the VME spaces times out.
   assign MATCH_VME32_32 = (EN_DEV) & (TYPE == 2'h3) & !DISACC & C_S6;
   //assign MATCH_VME32_16 = (EN_DEV) & (TYPE == 2'h3) & !DISACC & (ma_pmap2devices[18:11] == 8'hFF));
   //assign MATCH_VME32_08 = (EN_DEV) & (TYPE == 2'h3) & !DISACC & (ma_pmap2devices[18:3] == 16'hFFFF));
   /* won't even bother with the FPA */

   wire [7:0] 			 timer_out;
   wire 			 timer_bus_en;
   wire 			 timer_int_n;
   
   // The TOD divides CLK down itself, so it has to know CLK's frequency: the
   // old build left FREQ at its 19.6608 MHz default under a 20 MHz CLK, and
   // time ran 1.7% fast.
 icm7170 #(.FREQ(`SUN3_CPU_HZ)) timerchip(.CLK(CLK),
		   .RESETn(~sys_reset), // no reset on real HW
		   .A(SUN3_ADR_IN[4:0]),
		   .D_IN(EXTRACT_8BITS(SUN3_DATA_IN, SUN3_ADR_IN[1:0])),
		   .D_OUT(timer_out),
		   .D_EN(timer_bus_en),
		   .RD(~MATCH_TIMER | ~RD),
		   .WR(~MATCH_TIMER | ~WR),
		   .CS(1'b0),
		   .INTERRUPT(timer_int_n));

   wire 			 EN_LLBYTE, EN_LUBYTE, EN_ULBYTE, EN_UUBYTE;

   wire [31:0] 			 wishbone_out;
   wire 			 w_ack;
   
   // The memory bridge: synchronous (DSACK waits for the Wishbone answer), or
   // with SUN3_WB_FIFO two dual-clock FIFOs, posted writes and tagged reads,
   // the Wishbone side in the memory controller's clock (sun3_fifo_bridge.v).
   // SUN3_WB_CACHE puts a read cache in front of those FIFOs
   // (sun3_cached_fifo_bridge.v).
   // Same instance name every way: the board constraints name it.
`ifdef SUN3_WB_CACHE
   sun3_cached_fifo_bridge #(.IDX(`SUN3_WB_CACHE_IDX)) wbridge(.CLK(CLK),
				.WB_CLK(wb_clk_i),
				.WB_RESET(wb_rst_i),
				.wb_line_i(wb_line_i),
`elsif SUN3_WB_FIFO
   sun3_fifo_bridge wbridge(.CLK(CLK),
				.WB_CLK(wb_clk_i),
				.WB_RESET(wb_rst_i),
`else
   sun3_wishbone_bridge wbridge(.CLK(CLK),
`endif
				.RESET_n(~sys_reset), // don't reset on CPU-only reset, don't want to loose memory access then
				.P_ADR_IN({ma_pmap2devices[18:0], SUN3_ADR_IN[12:0]}), // full physical
				.P_DATA_IN(SUN3_DATA_IN),
				.P_DATA_OUT(wishbone_out),
				.P_RW_n(SUN3_RW_n),
				.EN_LLBYTE(EN_LLBYTE),
				.EN_LUBYTE(EN_LUBYTE),
				.EN_ULBYTE(EN_ULBYTE),
				.EN_UUBYTE(EN_UUBYTE),
				.MATCH_MEM(MATCH_MEM),
				.MATCH_FB(MATCH_FB),
				.W_ACK(w_ack),
				
				// wishbone
				.wb_cyc_o(wb_cyc_o),
				.wb_stb_o(wb_stb_o),
				.wb_adr_o(wb_adr_o),
				.wb_dat_o(wb_dat_o),
				.wb_sel_o(wb_sel_o),
				.wb_we_o(wb_we_o),
				.wb_dat_i(wb_dat_i),
				.wb_ack_i(wb_ack_i)
				);
   
   assign EN_LLBYTE = ( SUN3_ADR_IN[0] &  SUN3_ADR_IN[1]) | (                SUN3_ADR_IN[1]             &  SUN3_SIZ[1]) | (               ~SUN3_SIZ[0] & ~SUN3_SIZ[1]) | ( SUN3_ADR_IN[0] &                SUN3_SIZ[0] & SUN3_SIZ[1]);
   assign EN_LUBYTE = (~SUN3_ADR_IN[0] &  SUN3_ADR_IN[1]) | ( SUN3_ADR_IN[0] & ~SUN3_ADR_IN[1]             &  SUN3_SIZ[1]) | (~SUN3_ADR_IN[1] & ~SUN3_SIZ[0] & ~SUN3_SIZ[1]) | (               ~SUN3_ADR_IN[1] & SUN3_SIZ[0] & SUN3_SIZ[1]);
   assign EN_ULBYTE = ( SUN3_ADR_IN[0] & ~SUN3_ADR_IN[1]) | (               ~SUN3_ADR_IN[1] & ~SUN3_SIZ[0])             | (~SUN3_ADR_IN[1]             &  SUN3_SIZ[1]);
   assign EN_UUBYTE = (~SUN3_ADR_IN[0] & ~SUN3_ADR_IN[1]);
   
   /* serial port */
   wire [7:0] 			 serial_out;
   wire 			 serial_en;
   wire 			 serial_int_n; // FIXME: DOME
   wire 			 TxDA, TxDA_EN, RxDA;

   assign tx = TxDA;
   assign RxDA = rx;

   // Both SCCs are reset on RESET- (P_RESET_n), the CPU's RESET instruction
   // included, although the production schematic seems to show their RD/WR
   // decode PAL (sh3 U311) taking INIT- only: otherwise the PROM's `k2' after
   // SunOS hangs.  SunOS leaves the console SCC with its interrupts and MIE
   // enabled; after the RESET, self test 9 enables interrupts expecting a soft
   // level 1, takes the SCC's level 6 instead, and loops (diag 0x89).
   // tools/beprobe/sccie.S reproduces it in simulation.
   z8530_scc  #(.SOFT_RESET_EN(1),
		.RR8_CTRL_POP(1),
		.BRG_SRC_A(1),
		.BRG_SRC_B(1),
		.UNIPLUS_BAUD_PATCH_B(0),
		.AUTO_ENABLES_EN(0),
		.RTXC_XTAL_FULLRATE_A(0),
		.RTXC_XTAL_FULLRATE_B(0)
		,.RDWR_RESET_EN(1)
		) serial (// System Interface
			  .clk(CLK),           // CPU/bus clock (register file, interrupts, RR mux)
			  .pclk(clk4m9152),       // Alternative BRG/serializer clock (Zilog "PCLK")
			  .sclk(clk4m9152),          // Primary BRG/serializer clock (e.g. 3.6864 MHz)
			  .reset_n(1'b1),       // Active low reset (async assert)
			  
			  // CPU Interface
			  .cs_n(1'b0),          // Chip select (active low)
			  // RD and WR low together reset the Z8530, on RESET- (the
			  // CPU's RESET instruction too), not just INIT-: see below.
			  .rd_n(((~MATCH_SERIAL & ~MATCH_UARTBYP) | ~RD) & P_RESET_n),          // Read strobe (active low)
			  .wr_n(((~MATCH_SERIAL & ~MATCH_UARTBYP) | ~WR) & P_RESET_n),          // Write strobe (active low)
			  .a_b(SUN3_ADR_IN[2]),           // Channel select: 1=A, 0=B
			  .d_c(SUN3_ADR_IN[1]),           // Data/Control: 1=Data, 0=Control
			  .data_in(EXTRACT_8BITS(SUN3_DATA_IN, SUN3_ADR_IN[1:0])),       // Data input
			  .data_out(serial_out),      // Data output
			  .data_oe(serial_en),       // Data output enable
			  
			  // Interrupt
			  .int_n(serial_int_n),         // Interrupt output (active low)
			  .intack_n(1'b1),      // Interrupt acknowledge
			  
			  // Channel A Serial Interface
			  .rxca(1'b0),          // Receive clock A
			  .txca(1'b0),          // Transmit clock A
			  .rxda(RxDA),          // Receive data A
			  .txda(TxDA),          // Transmit data A
			  .ctsa_n(1'b0),        // Clear to send A (active low)
			  .dcda_n(1'b0),        // Data carrier detect A (active low)
			  .synca_n(1'b0),       // Sync A (async-mode input -> RR0[4], active low)
			  .rtsa_n(),        // Request to send A (active low)
			  .dtra_n(),        // Data terminal ready A (active low)
			  
			  // Channel B Serial Interface
			  .rxcb(1'b0),          // Receive clock B
			  .txcb(1'b0),          // Transmit clock B
			  .rxdb(ttyb_rx),       // Receive data B (ttyb)
			  .txdb(ttyb_tx),       // Transmit data B (ttyb)
			  .ctsb_n(1'b0),        // Clear to send B (active low)
			  .dcdb_n(1'b0),        // Data carrier detect B (active low)
			  .syncb_n(1'b0),       // Sync B (async-mode input -> RR0[4], active low)
			  .rtsb_n(),        // Request to send B (active low)
			  .dtrb_n()         // Data terminal ready B (active low)
			  );
   
   // Keyboard (channel A) and mouse (channel B): a second Z8530, the same
   // model as the console's.  Modem inputs on both are tied low, which is what
   // synthesis made of them when they were left open.
   wire [7:0] 			 kbdms_out;
   wire 			 kbdms_en;
   wire 			 kbdms_int_n;

   z8530_scc  #(.SOFT_RESET_EN(1),
		.RR8_CTRL_POP(1),
		.BRG_SRC_A(1),
		.BRG_SRC_B(1),
		.UNIPLUS_BAUD_PATCH_B(0),
		.AUTO_ENABLES_EN(0),
		.RTXC_XTAL_FULLRATE_A(0),
		.RTXC_XTAL_FULLRATE_B(0)
		,.RDWR_RESET_EN(1)
		) kbdms (.clk(CLK),
			 .pclk(clk4m9152),
			 .sclk(clk4m9152),
			 .reset_n(1'b1),

			 .cs_n(1'b0),
			 .rd_n((~MATCH_KBDMS | ~RD) & P_RESET_n),
			 .wr_n((~MATCH_KBDMS | ~WR) & P_RESET_n),
			 .a_b(SUN3_ADR_IN[2]),
			 .d_c(SUN3_ADR_IN[1]),
			 .data_in(EXTRACT_8BITS(SUN3_DATA_IN, SUN3_ADR_IN[1:0])),
			 .data_out(kbdms_out),
			 .data_oe(kbdms_en),

			 .int_n(kbdms_int_n),
			 .intack_n(1'b1),

			 // Channel A: keyboard
			 .rxca(1'b0), .txca(1'b0),
			 .rxda(kbd_rx),
			 .txda(kbd_tx),
			 .ctsa_n(1'b0), .dcda_n(1'b0), .synca_n(1'b0), .rtsa_n(), .dtra_n(),

			 // Channel B: mouse.  A mouse only talks; the transmit side is
			 // brought out anyway, for a board that wires it to the
			 // connector.
			 .rxcb(1'b0), .txcb(1'b0),
			 .rxdb(mou_rx),
			 .txdb(mou_tx),
			 .ctsb_n(1'b0), .dcdb_n(1'b0), .syncb_n(1'b0), .rtsb_n(), .dtrb_n()
			 );

   wire [7:0] 			 eeprom_out;
   eeprom eeprom(.CLK(CLK),
		 .idx(SUN3_ADR_IN[10:0]),
		 .WR(WR & MATCH_EEPROM),
		 .din(EXTRACT_8BITS(SUN3_DATA_IN, SUN3_ADR_IN[1:0])),
		 .dout(eeprom_out));
   
   
   // mem err crl reg
   // need to return 0 in the NMI handler
   // we can remove the bits in the PROM, but not in the OS
   wire [7:0] 			 memerr_ctrl_out;
   gen8bit_reg memerr_ctrl(.CLK(CLK),
			   .din(EXTRACT_8BITS(SUN3_DATA_IN, SUN3_ADR_IN[1:0])),
			   .WR(WR & MATCH_MEMERR_CTRL),
			   .dout(memerr_ctrl_out),
			   .CLR_n(~sys_reset)
			   );
   // mem err addr reg
   // return 0 on the bus always
   
   // IRQ reg
   wire [7:0] 			 irqreg_out;
   gen8bit_reg irqreg(.CLK(CLK),
		      .din(EXTRACT_8BITS(SUN3_DATA_IN, SUN3_ADR_IN[1:0])),
		      .WR(WR & MATCH_IRQREG),
		      .dout(irqreg_out),
		      .CLR_n(P_RESET_n)
		      );
   wire 	       EN_IRQ7, EN_IRQ6, EN_IRQ5, EN_IRQ4, EN_IRQ3, EN_IRQ2, EN_IRQ1, EN_INT;
   assign EN_IRQ7 = irqreg_out[7];
   assign EN_IRQ6 = irqreg_out[6];
   assign EN_IRQ5 = irqreg_out[5];
   assign EN_IRQ4 = irqreg_out[4];
   assign EN_IRQ3 = irqreg_out[3];
   assign EN_IRQ2 = irqreg_out[2];
   assign EN_IRQ1 = irqreg_out[1];
   assign EN_INT  = irqreg_out[0];

`ifdef SUN3_ETH_WISH7990
   wire [31:0] 	       ethernet_out;
`endif
   
   // Answering the CPU
   // bus muxer. CPU has priority via DATA_EN, otherwise whomever is matched own the bus
   // ... with an implicit priority
   assign P_DATA_OUT = P_DATA_EN         ? SUN3_DATA_IN : // loopback
		       MATCH_CTX       ? EXPAND_8BITS(ctx_out) :
		       MATCH_SMAP      ? EXPAND_8BITS(ia_smap2pmap) :
		       MATCH_PMAP      ? {ps_pmap2devices, 5'h00, ma_pmap2devices} :
		       MATCH_SYSEN     ? EXPAND_8BITS({sys_out[7:1], diag_switch}) :
		       MATCH_BERR      ? EXPAND_8BITS(berr_out) :
		       MATCH_IDPROM    ? EXPAND_8BITS(idprom_out) :
		       MATCH_PROM_BOOT ? prom_out :
		       MATCH_PROM      ? prom_out :
		       MATCH_MEM       ? wishbone_out :
		       MATCH_FB        ? wishbone_out :
		       MATCH_KBDMS     ? EXPAND_8BITS(kbdms_out) :
		       MATCH_SERIAL    ? EXPAND_8BITS(serial_out) :
		       MATCH_UARTBYP   ? EXPAND_8BITS(serial_out) :
		       MATCH_EEPROM    ? EXPAND_8BITS(eeprom_out) :
		       MATCH_MEMERR_CTRL ? EXPAND_8BITS(memerr_ctrl_out) :
		       MATCH_MEMERR_ADDR ? EXPAND_8BITS(8'h00) :
		       MATCH_TIMER     ? EXPAND_8BITS(timer_out) :
		       MATCH_IRQREG    ? EXPAND_8BITS(irqreg_out) :
		       MATCH_CYCTR     ? cyctr_out :
		       MATCH_FLTLOG    ? ((SUN3_ADR_IN[13:12] == 2'b00) ? fltlog_out : bustrace_out) :
`ifdef SUN3_ETH_WISH7990
		       MATCH_AMDLE     ? ethernet_out :
`endif
`ifdef SUN3_SCSI
		       MATCH_SCSI      ? scsi_out :
`endif
		       32'hDEADBEEF;

   // DSACK generator. has knowledge of timings for all devices
   wire 	       DO_ACK;
`ifdef SUN3_ETH_WISH7990
   wire [1:0] 	       ethernet_dsack_n_out;
`endif
   
   // For memory this will need updating if we use "real" (variable-timing) memory
   assign DO_ACK = ( // FIXME: 32 vs 16 vs 8 bits, sun3 (or rewire for eevryone to be 32-bits-like ?)
		     /* reads */
		     ( SUN3_RW_n & C_S4 & (MATCH_CTX | MATCH_IDPROM | MATCH_SYSEN | MATCH_BERR |              MATCH_PROM_BOOT | MATCH_MEMERR_CTRL | MATCH_MEMERR_ADDR)) | // entering S4, quick devices (RO or WR)
		     ( SUN3_RW_n & C_S4 & (MATCH_CYCTR)) | // read-only, 32-bits
		     (             C_S4 & (MATCH_FLTLOG)) | // reads, and writes ignored
		     ( SUN3_RW_n & C_S4 & (MATCH_SMAP)) |  // entering S4, quick devices (CTX is 1 clock but went valid after being written, not affected by SUN3_A)
		     ( SUN3_RW_n & C_S4 & (MATCH_PMAP)) |  // entering S4, physical map needed an extra cycle
		     ( SUN3_RW_n & C_S6 & (MATCH_EEPROM | MATCH_TIMER | MATCH_IRQREG | MATCH_PROM)) | // entering S6, devices going through the MMU
		     ( SUN3_RW_n & C_S4 & (MATCH_UARTBYP)) | // entering S4, FAST serial (4*1/4 clock)		  
		     ( SUN3_RW_n & C_S6 & (MATCH_SERIAL)) | // entering S8, FAST serial (4*1/4 clock)
		     ( SUN3_RW_n & C_S12 & (MATCH_KBDMS)) |  // entering S8, SLOW serial (1/4 clock)
		     ( SUN3_RW_n & w_ack & (MATCH_MEM | MATCH_FB)) | // wishbone
`ifdef SUN3_ETH_WISH7990
		     ( SUN3_RW_n & ~ethernet_dsack_n_out[0] & (MATCH_AMDLE)) | // ethernet (PVC bridge)
`endif
		     /* writes */
		     (~SUN3_RW_n & C_S4 & (MATCH_CTX |                MATCH_SYSEN |              MATCH_DIAG |                   MATCH_MEMERR_CTRL)) | // entering S4, quick devices (WO or WR)
		     (~SUN3_RW_n & C_S4 & (MATCH_SMAP)) |  // entering S4, quick devices (CTX is 1 clock but went valid after being written, not affected by SUN3_A)
		     (~SUN3_RW_n & C_S4 & (MATCH_PMAP)) |  // entering S4, physical map needed an extra cycle
		     (~SUN3_RW_n & C_S6 & (MATCH_EEPROM | MATCH_TIMER | MATCH_IRQREG)) | // entering S6, devices going through the MMU
		     (~SUN3_RW_n & C_S4 & (MATCH_UARTBYP)) | // entering S4, FAST serial (4*1/4 clock)		  
		     (~SUN3_RW_n & C_S6 & (MATCH_SERIAL)) | // entering S8, FAST serial (4*1/4 clock)
		     (~SUN3_RW_n & C_S12 & (MATCH_KBDMS)) | // entering S8, SLOW serial (1/4 clock)
		     (~SUN3_RW_n & w_ack & (MATCH_MEM | MATCH_FB)) | // wishbone
`ifdef SUN3_ETH_WISH7990
		     (~SUN3_RW_n & ~ethernet_dsack_n_out[0] & (MATCH_AMDLE)) | // ethernet (PVC bridge)
`endif
`ifdef SUN3_SCSI
		     (scsi_ack & MATCH_SCSI) | // SCSI board, reads and writes: a clock after it saw the cycle
`endif
		     1'b0);
   
   assign P_DSACK_n[0] = ~(DO_ACK); // we only have 8 and 32 bits for now, so everyone assert [0] (16-bits are [1] only]
`ifdef  DEVICE_8BITS_ON_32BITS_BUS
   assign P_DSACK_n[1] = ~(DO_ACK); // everybody is 32-bits
`else
   assign P_DSACK_n[1] = ~(DO_ACK & (MATCH_PMAP | MATCH_MEMERR_ADDR | MATCH_PROM_BOOT | MATCH_PROM | MATCH_MEMX | MATCH_VME32_32 | MATCH_FBX | MATCH_CYCTR)); // 32-bits devices only
`endif
   
   
   // LEDS
   // as for the real thing, used for debugging (in simulation)
`ifndef SYNTHESIS
   always @(leds) begin
      $display("[%0.3f ms] Leds are now %x", $realtime / 1.0e6, ~leds);
      case (~leds)
	8'hFF:$display(" => L_RESET");
	8'h00:$display(" => L_RUNNING");
	8'h01:$display(" => L_INITIAL");
	8'h02:$display(" => L_USERDOG");
	8'h03:$display(" => L_GOTMEM");
	8'h07:$display(" => L_AFTERDIAG");
	8'h11:$display(" => L_CONTEXT");
	8'h20:$display(" => L_HEARTBEAT");
	8'h21:$display(" => L_SM_CONST");
	8'h22:$display(" => L_SM_ADDR");
	8'h23:$display(" => L_SM_DATA");
	8'h31:$display(" => L_PM_CONST");
	8'h32:$display(" => L_PM_ADDR");
	8'h33:$display(" => L_PM_DATA");
	8'h40:$display(" => L_PROM");
	8'h50:$display(" => L_UART");
	8'h70:$display(" => L_M_MAP");
	8'h71:$display(" => L_M_CONST");
	8'h72:$display(" => L_M_ADDR");
	8'h7F:$display(" => L_PARITY");
	8'h81:$display(" => L_TIMER");
	8'h82:$display(" => L_DES");
	8'hF1:$display(" => L_SETUP_MEM");
	8'hF2:$display(" => L_SETUP_MAP");
	8'hF3:$display(" => L_SETUP_FB");
	8'hF4:$display(" => L_SETUP_KEYB");
	default: $display(" => unknown pattern!!!");
      endcase
      //$flushlog;
   end // always @ (leds)
`endif

   // interrupts
   wire 	       RTC, SCC_IRQ, E_IRQ, PAR_IRQ, S_IRQ;
   assign RTC = ~timer_int_n;
   /* SCC_IRQ is for both Z8530 */
   assign SCC_IRQ = ~(serial_int_n & kbdms_int_n);
   /* Ethernet */
`ifdef SUN3_ETH_WISH7990
   // Driven by whichever MAC is built; already gated by CSR0.INEA, because
   // INEA is a bit of CSR0 and CSR0 is inside the part.
   wire 	       amdle_intr;
   assign E_IRQ = amdle_intr;
`else
   assign E_IRQ = 1'b0;
`endif
   /* no Parity support */
   assign PAR_IRQ = 1'b0;
   /* SCSI: level 2, autovectored */
`ifdef SUN3_SCSI
   assign S_IRQ = scsi_irq;
`else
   assign S_IRQ = 1'b0;
`endif
   
   // The video interrupt (level 4, autovectored: Architecture Manual 5.3.4):
   // the board's vertical sync, in the pixel clock, synchronised here.  The
   // interrupt logic latches it while EN_IRQ4 is set, until software clears
   // that bit, so a level lasting a few lines is enough.
   `SUN3_ASYNC_REG reg [1:0] vint_s = 2'b00;
   always @(posedge CLK) vint_s <= {vint_s[0], V_INT};
   wire V_INT_s = vint_s[1];

   sun3_irq_priority irqenc (.CLK(CLK),
    			     .EN_IRQ7(EN_IRQ7),
			     .EN_IRQ6(EN_IRQ6),
			     .EN_IRQ5(EN_IRQ5),
			     .EN_IRQ4(EN_IRQ4),
			     .EN_IRQ3(EN_IRQ3),
			     .EN_IRQ2(EN_IRQ2),
			     .EN_IRQ1(EN_IRQ1),
			     .EN_INT(EN_INT),
    			     .RTC(RTC),
			     .V_INT(V_INT_s),
			     .SCC_IRQ(SCC_IRQ),
			     .E_IRQ(E_IRQ),
			     .PAR_IRQ(PAR_IRQ),
			     .S_IRQ(S_IRQ),
			     .IPL_n(P_IPL_n));

   
`ifdef SUN3_ETH_WISH7990
   // ---- Wish7990, the C-LANCE ----------------------------------------------
   //
   // The part itself, in CLK - the CPU clock - so that its DVMA is an ordinary
   // cycle on this bus and goes through the MMU like everything else.  That is
   // the whole reason it is here rather than hanging off the SoC's Wishbone
   // fabric at the Migen level: a master over there would reach physical
   // memory, and the driver's DVMA mapping would put the frames in the wrong
   // pages.  Being in CLK also means there is no clock domain crossing to get
   // wrong - both bridges are plain synchronous logic, where the temlib pair
   // above needed a FIFO each way.
   //
   //   wish7990_sun3_regs      the CPU's two 16-bit ports at OBIO 0x120000,
   //                           driving the part's own slave pins
   //   wish7990_dvma_to_020    the part's Wishbone master, as a 68020 bus
   //                           master with BR / BG / BGACK
   //
   // Only MII is wired.  The part does GMII with PHY_DATA_W = 8, but there is
   // no RMII path.
   //
   // POLL_TICKS is 1.6 ms of CLK, which is what the C-LANCE polls its
   // descriptor rings at (p. 30): SUN3_CPU_HZ / 625.  It was a literal 32000,
   // right only at 20 MHz -- off, a driver that waits on the poll rather than
   // writing CSR0.TDMD waits the wrong length of time.
   localparam WISH7990_POLL_TICKS = `SUN3_CPU_HZ / 625;

   wire 	       wish_cs, wish_adr, wish_we, wish_ready;
   wire [15:0] 	       wish_wdata, wish_rdata;
   wire 	       wish_reg_ack;

   wish7990_sun3_regs regs_to_eth (
				   .CLK        (CLK),
				   // The Ethernet's board latch (sh5 U520) is never
				   // reset on a 3/60; INIT- here.
				   .RESET_n    (~sys_reset),
				   .P_ADR_IN   ({ma_pmap2devices[18:0], SUN3_ADR_IN[12:0]}), // full physical
				   .P_DATA_IN  (SUN3_DATA_IN),
				   .P_DATA_OUT (ethernet_out),
				   .P_RW_n     (SUN3_RW_n),
				   .MATCH      (MATCH_AMDLE),
				   .W_ACK      (wish_reg_ack),
				   .cs_o       (wish_cs),
				   .adr_o      (wish_adr),
				   .we_o       (wish_we),
				   .wdata_o    (wish_wdata),
				   .rdata_i    (wish_rdata),
				   .ready_i    (wish_ready)
				   );

   // Both bits: everything in this machine answers as a 32-bit port
   // (DEVICE_8BITS_ON_32BITS_BUS), which is DSACK1 and DSACK0 both low in
   // Table 7-1 of the MC68030 user's manual.
   assign ethernet_dsack_n_out = {~wish_reg_ack, ~wish_reg_ack};

   wire 	       wishm_cyc, wishm_stb, wishm_we, wishm_ack, wishm_err;
   wire [3:0] 	       wishm_sel;
   wire [29:0] 	       wishm_adr;
   wire [31:0] 	       wishm_dat_w, wishm_dat_r;

   wire 	       wish_bswp, wish_acon, wish_bcon;

   wish7990 #(.PHY_DATA_W (4),          // MII
	      .WB_ADDR_W  (30),
	      .WB_DATA_W  (32),
	      .POLL_TICKS (WISH7990_POLL_TICKS)
	      ) ethernet (
				   .clk        (CLK),
				   .rst        (sys_reset),
				   // The part's own RESET pin, on RESET- (sh5
				   // U500 pin 23): the CPU's RESET instruction
				   // stops the chip, as a STOP would.  The rest of
				   // the module (its bus master, MAC) only on
				   // system reset.
				   .reset_i    (~P_RESET_n),
				   .cs_i       (wish_cs),
				   .adr_i      (wish_adr),
				   .we_i       (wish_we),
				   .wdata_i    (wish_wdata),
				   .rdata_o    (wish_rdata),
				   .ready_o    (wish_ready),
				   .intr_o     (amdle_intr),
				   // CSR3 on the pins, for a board that
				   // recreates a real DAL bus.  BSWP is acted
				   // on inside the part by the data engines;
				   // ACON and BCON are carried out inert.
				   .bswp_o     (wish_bswp),
				   .acon_o     (wish_acon),
				   .bcon_o     (wish_bcon),
				   .wbm_cyc_o  (wishm_cyc),
				   .wbm_stb_o  (wishm_stb),
				   .wbm_we_o   (wishm_we),
				   .wbm_sel_o  (wishm_sel),
				   .wbm_adr_o  (wishm_adr),
				   .wbm_dat_o  (wishm_dat_w),
				   .wbm_dat_i  (wishm_dat_r),
				   .wbm_ack_i  (wishm_ack),
				   .wbm_err_i  (wishm_err),
				   .mii_tx_clk (phy_tx_clk),
				   .mii_txd    (phy_txd),
				   .mii_tx_en  (phy_tx_en),
				   .mii_tx_er  (phy_tx_er),
				   .mii_rx_clk (phy_rx_clk),
				   .mii_rxd    (phy_rxd),
				   .mii_rx_dv  (phy_rx_dv),
				   .mii_rx_er  (phy_rx_er),
				   .mii_crs    (phy_crs),
				   .mii_col    (phy_col)
				   );

   // The PHY comes out of reset with the machine.  Nothing in here programs
   // it: the C-LANCE predates MDIO and none of its drivers knows a PHY
   // exists, so it is left to auto-negotiate or to whatever drives MDIO
   // outside this module.
   // No PHY on a 3/60: only the system reset, so a RESET instruction does
   // not drop the link.
   assign phy_reset_n = ~sys_reset;

`endif //  `ifdef SUN3_ETH_WISH7990

`ifdef SUN3_HAS_DVMA
   // ---- DVMA: the bridge onto the 68020 bus, and who gets it ---------------
   //
   // One bridge (wish7990_dvma_to_020: BR/BG/BGACK, 0x0FF00000 + address,
   // supervisor data, through the MMU) and a Wishbone arbiter in front of it:
   // the Ethernet first, then the SCSI, the order the Architecture Manual
   // gives (section 6).  A grant lasts one Wishbone transaction.
   wire 	       eth_cyc, eth_stb, eth_we, eth_ack, eth_err;
   wire [3:0] 	       eth_sel;
   wire [29:0] 	       eth_adr;
   wire [31:0] 	       eth_dat_w, eth_dat_r;
   wire 	       si_cyc, si_we, si_ack, si_err;
   wire [3:0] 	       si_sel;
   wire [29:0] 	       si_adr;
   wire [31:0] 	       si_dat_w, si_dat_r;

   reg 		       dv_busy, dv_si;
   wire 	       dv_cyc, dv_stb, dv_we, dv_ack, dv_err;
   wire [3:0] 	       dv_sel;
   wire [29:0] 	       dv_adr;
   wire [31:0] 	       dv_dat_w, dv_dat_r;

   // The DVMA arbiter is cleared by INIT- only (sh1 U131).
   always @(posedge CLK)
     if (sys_reset)
       begin
	  dv_busy <= 1'b0;
	  dv_si   <= 1'b0;
       end
     else if (~dv_busy)
       begin
	  if (eth_cyc & eth_stb)  begin dv_busy <= 1'b1; dv_si <= 1'b0; end
	  else if (si_cyc)        begin dv_busy <= 1'b1; dv_si <= 1'b1; end
       end
     else if (dv_ack | dv_err)
       dv_busy <= 1'b0;

   assign dv_cyc   = dv_busy & (dv_si ? si_cyc : eth_cyc);
   assign dv_stb   = dv_busy & (dv_si ? si_cyc : eth_stb);
   assign dv_we    = dv_si ? si_we    : eth_we;
   assign dv_sel   = dv_si ? si_sel   : eth_sel;
   assign dv_adr   = dv_si ? si_adr   : eth_adr;
   assign dv_dat_w = dv_si ? si_dat_w : eth_dat_w;
   assign eth_ack  = dv_busy & ~dv_si & dv_ack;
   assign eth_err  = dv_busy & ~dv_si & dv_err;
   assign si_ack   = dv_busy &  dv_si & dv_ack;
   assign si_err   = dv_busy &  dv_si & dv_err;
   assign eth_dat_r = dv_dat_r;
   assign si_dat_r  = dv_dat_r;

`ifdef SUN3_ETH_WISH7990
   assign eth_cyc = wishm_cyc;  assign eth_stb = wishm_stb;  assign eth_we = wishm_we;
   assign eth_sel = wishm_sel;  assign eth_adr = wishm_adr;  assign eth_dat_w = wishm_dat_w;
   assign wishm_ack = eth_ack;  assign wishm_err = eth_err;  assign wishm_dat_r = eth_dat_r;
`else
   assign eth_cyc = 1'b0;  assign eth_stb = 1'b0;  assign eth_we = 1'b0;
   assign eth_sel = 4'h0;  assign eth_adr = 30'h0; assign eth_dat_w = 32'h0;
`endif
`ifndef SUN3_SCSI
   assign si_cyc = 1'b0;  assign si_we = 1'b0;  assign si_sel = 4'h0;
   assign si_adr = 30'h0; assign si_dat_w = 32'h0;
`endif

   wish7990_dvma_to_020 dvma_bridge (
				   .clk         (CLK),
				   .reset_n     (~sys_reset),
				   .wb_cyc_i    (dv_cyc),
				   .wb_stb_i    (dv_stb),
				   .wb_we_i     (dv_we),
				   .wb_sel_i    (dv_sel),
				   .wb_adr_i    (dv_adr),
				   .wb_dat_i    (dv_dat_w),
				   .wb_dat_o    (dv_dat_r),
				   .wb_ack_o    (dv_ack),
				   .wb_err_o    (dv_err),
				   // mc_D_IN is the system's own data mux, so a
				   // DVMA read sees whatever device answered -
				   // which is how the temlib bridge did it too.
				   .mc_A_OUT    (ethernetdma_addr_out),
				   .mc_D_IN     (P_DATA_OUT),
				   .mc_D_OUT    (ethernetdma_data_out),
				   .mc_FC       (ethernetdma_fc_out),
				   .mc_SIZ      (ethernetdma_siz_out),
				   .mc_AS_N_IN  (SUN3_AS_n),
				   .mc_AS_N_OUT (ethernetdma_as_n_out),
				   .mc_DS_N     (ethernetdma_ds_n_out),
				   .mc_RW_N     (ethernetdma_rw_n_out),
				   .mc_DSACK0_N (P_DSACK_n[0]),
				   .mc_DSACK1_N (P_DSACK_n[1]),
				   .mc_BERR_N   (P_BERR_n),
				   .mc_BR_N     (ethernetdma_br_n_out),
				   .mc_BG_N     (ethernetdma_bg_n),
				   .mc_BGACK_N  (ethernetdma_bgack_n_out)
				   );

`endif //  `ifdef SUN3_HAS_DVMA

`ifdef SUN3_SCSI
   // ---- the on-board SCSI (OBIO 0x140000) ------------------------------------
   sun3_si #(.CLK_PERIOD_PS(1000000000 / (`SUN3_CPU_HZ / 1000))) scsi (
       .clk        (CLK),
       // The SCSI board logic (CSR, sh6 U620) is cleared by INIT- only;
       // the 5380 and the UDC are held in reset by its bit 0 from then.
       .rst        (sys_reset),
       .match      (MATCH_SCSI),
       .rw_n       (SUN3_RW_n),
       .adr        (SUN3_ADR_IN[4:0]),
       .wdata      (SUN3_DATA_IN),
       .rdata      (scsi_out),
       .ack        (scsi_ack),
       .irq        (scsi_irq),
       .m_cyc      (si_cyc),
       .m_we       (si_we),
       .m_sel      (si_sel),
       .m_adr      (si_adr),
       .m_dat_o    (si_dat_w),
       .m_dat_i    (si_dat_r),
       .m_ack      (si_ack),
       .m_err      (si_err),
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
       .dma_active    ()
   );
`endif

endmodule // sun2_fpga

