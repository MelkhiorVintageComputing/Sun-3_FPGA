module sun3_mmu #(parameter CTX_VALID_BITS=3,
		  SMAP_IDX_WIDTH=14, /* 7188 SRAM */
		  SMAP_OUTPUT_BITS=8,
		  PMAP_IDX_WIDTH=12, /* 2168 SRAM */
		  PMAP_MA_OUTPUT_BITS=19,
		  PMAP_PS_OUTPUT_BITS=8)
   (input CLK,
    /* matching */
    input 			     MATCH_CTX,
    input 			     MATCH_SMAP,
    input 			     MATCH_PMAP_PS,
    input 			     MATCH_PMAP_MA,
    input 			     WR,
    input 			     RD,
    /* CPU signals */
    input [31:0] 		     P_DIN,
    input [31:0] 		     P_A,
    input [2:0] 		     P_FC, 
    /* timing signals */
    input 			     C_S4,
    input 			     C_S6,
    input 			     C_S8,
    /* MMU outputs */
    output [7:0] 		     ctx_out,
    output [SMAP_OUTPUT_BITS-1:0]    ia_smap2pmap,
    output [PMAP_MA_OUTPUT_BITS-1:0] ma_pmap2devices,
    output [PMAP_PS_OUTPUT_BITS-1:0] ps_pmap2devices,
    /* stats */
    input 			     EN_DEV,
    input 			     DISACC,
    input [3:0] 		     stat_in
);

   localparam PAGE_IDX_BITS=13;
   localparam SEG_IDX_BITS=4;
   localparam STAT_BITS=4;
   
   

   wire [CTX_VALID_BITS-1:0] 				    cx_ctx2smap; /* cx_ctx2smap is purely internal, ctx_out is the variant visible to the CPU */
   
   // Context register
   ctx_reg_sun3 #(.VALID_BITS(CTX_VALID_BITS)) ctx(.CLK(CLK),
						   .din(P_DIN[31:24]),
						   .WR(WR & MATCH_CTX & C_S4),
						   .dout(ctx_out), // 8-bits output (3 lsb used)
						   .cx(cx_ctx2smap) // 3-bits output 
						   );
   
   // Segment Map
   smap_sram #(.DATA_WIDTH(SMAP_OUTPUT_BITS), .IDX_WIDTH(SMAP_IDX_WIDTH)) smap(.CLK(CLK),
		  .idx({P_A[16+(SMAP_IDX_WIDTH-CTX_VALID_BITS):17],cx_ctx2smap}),
		  .WR(WR & MATCH_SMAP & C_S4),
		  .ia_in(P_DIN[31:32-SMAP_OUTPUT_BITS]),
		  .ia_out(ia_smap2pmap) // X-bits outputs: index in the PMap
		  );
   // Page Map (except status bit)
   pmap_sram #(.MA_DATA_WIDTH(PMAP_MA_OUTPUT_BITS), .PS_DATA_WIDTH(PMAP_PS_OUTPUT_BITS - STAT_BITS), .IDX_WIDTH(PMAP_IDX_WIDTH)) pmap(.CLK(CLK),
		  .idx({ia_smap2pmap,P_A[PAGE_IDX_BITS+SEG_IDX_BITS-1:PAGE_IDX_BITS]}),
		  .WR_ma(WR & MATCH_PMAP_MA & C_S4),
		  .WR_ps(WR & MATCH_PMAP_PS & C_S4),
		  .ma_in(P_DIN[PMAP_MA_OUTPUT_BITS-1:0]),
		  .ps_in(P_DIN[31:32-(PMAP_PS_OUTPUT_BITS  - STAT_BITS)]),
		  .ma_out(ma_pmap2devices), // Y-bits output #1: physical address bits
		  .ps_out(ps_pmap2devices[PMAP_PS_OUTPUT_BITS-1:STAT_BITS])  // 4-bits output #2: protection bits
		  );

   wire 						    update_stat;
   assign update_stat = C_S4 & !C_S6 & EN_DEV & !DISACC; // so valid during the C_S5 to C_S6 CLK posedge, alongside all other output signals
      
   // Page Map (status bit)
   // Need a separate SRAM as it is written to when memory/devices are accessed...
   sram_sync  #(.DATA_WIDTH(STAT_BITS), .IDX_WIDTH(PMAP_IDX_WIDTH)) stat_pmap (.CLK(CLK),
									       .idx({ia_smap2pmap,P_A[PAGE_IDX_BITS+SEG_IDX_BITS-1:PAGE_IDX_BITS]}),
									       .WR((WR & MATCH_PMAP_PS & C_S4) | (update_stat)),
									       .din((P_DIN[31-PMAP_PS_OUTPUT_BITS+STAT_BITS:32-PMAP_PS_OUTPUT_BITS] & {STAT_BITS{~update_stat}}) | (stat_in & {STAT_BITS{update_stat}})),
									       .dout(ps_pmap2devices[STAT_BITS-1:0]) // 4-bits output #2: status bits
									       );  
endmodule // sun3_mmu

