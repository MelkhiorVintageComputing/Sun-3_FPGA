`timescale 1ns / 1ps

`include "sun3_config.vh"

// The 2 KiB configuration EEPROM (OBIO 0x40000), preloaded with a layout the
// 3/60 PROM accepts.  Offsets are those of the Sun-3 EEPROM layout.
module eeprom(input CLK,
	      input [10:0]     idx,
	      input 	       WR,
	      input [7:0]      din,
	      output reg [7:0] dout
							  );
   
   reg [7:0] sram[0:2047];

   task init;
      integer a;
      begin
         for (a = 0; a < 2048; a = a + 1)
	   begin
	      case (a)
		11'h014: sram[a] <= `SUN3_MEM_MIB; // megabytes of memory installed
		11'h015: sram[a] <= 8'h00; // memory tested
		//11'h016: sram[a] <= 8'h00; // 1152x900
		11'h016: sram[a] <= 8'h20; // 1280x1024
		// 0x17: watchdog action ?
		11'h018: sram[a] <= 8'h12; // boot from eeprom-specified device 
		11'h019: sram[a] <= 8'h73; // boot device (2 bytes)
		11'h01a: sram[a] <= 8'h64;
`ifdef SUN3_FB_CONSOLE
		11'h01f: sram[a] <= 8'h00; // primary terminal (0x00: frame buffer and keyboard)
`else
		11'h01f: sram[a] <= 8'h10; // primary terminal (0x10: serial A)
`endif
		// 0x21: jeyboard click?
		11'h022: sram[a] <= 8'h69; // diag boot (2)
		11'h023: sram[a] <= 8'h65;
		11'h050: sram[a] <= 8'h50;
		11'h051: sram[a] <= 8'h22;
		11'h059: sram[a] <= 8'h25;
		11'h05a: sram[a] <= 8'h80;
		11'h05b: sram[a] <= 8'h12;
		11'h061: sram[a] <= 8'h25;
		11'h062: sram[a] <= 8'h80;
		11'h063: sram[a] <= 8'h12;
		11'h0b8: sram[a] <= 8'h55;
		11'h0b9: sram[a] <= 8'haa;
		11'h70b: sram[a] <= 8'h12;
		default: sram[a] <= 8'h00;
	      endcase
	   end
      end
   endtask
   
   initial
     begin
	dout = $random;
        init;
     end
   
   always @(posedge CLK)
     begin
	if (WR) sram[idx] <= din;
	dout <= sram[idx];
     end

endmodule // smap_sync

