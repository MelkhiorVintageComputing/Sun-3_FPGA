`timescale 1ns / 1ps

`include "sun3_config.vh"
`include "sun3_attr.vh"

// The 2 KiB configuration EEPROM (OBIO 0x40000), preloaded with a layout the
// 3/60 PROM accepts.  Offsets are those of the Sun-3 EEPROM layout.
module eeprom(input CLK,
	      input [10:0]     idx,
	      input 	       WR,
	      input [7:0]      din,
	      output reg [7:0] dout
							  );
   
   // Preloaded contents, as plain blocking assignments in one initial block:
   // the form both Vivado and Quartus turn into an initialised block RAM.
   `SUN3_RAM_BLOCK reg [7:0] sram[0:2047];

   integer a;
   initial
     begin
`ifdef SUN3_SIM
	dout = $random;
`endif
	for (a = 0; a < 2048; a = a + 1) sram[a] = 8'h00;
	sram[11'h014] = `SUN3_MEM_MIB; // megabytes of memory installed
	sram[11'h015] = 8'h00; // memory tested
	sram[11'h016] = 8'h20; // 1280x1024 (0x00: 1152x900)
	// 0x17: watchdog action ?
	sram[11'h018] = 8'h12; // boot from eeprom-specified device
	sram[11'h019] = 8'h73; // boot device (2 bytes)
	sram[11'h01a] = 8'h64;
`ifdef SUN3_FB_CONSOLE
	sram[11'h01f] = 8'h00; // primary terminal (0x00: frame buffer and keyboard)
`else
	sram[11'h01f] = 8'h10; // primary terminal (0x10: serial A)
`endif
	// 0x21: keyboard click?
	sram[11'h022] = 8'h69; // diag boot (2)
	sram[11'h023] = 8'h65;
	sram[11'h050] = 8'h50;
	sram[11'h051] = 8'h22;
	sram[11'h059] = 8'h25;
	sram[11'h05a] = 8'h80;
	sram[11'h05b] = 8'h12;
	sram[11'h061] = 8'h25;
	sram[11'h062] = 8'h80;
	sram[11'h063] = 8'h12;
	sram[11'h0b8] = 8'h55;
	sram[11'h0b9] = 8'haa;
	sram[11'h70b] = 8'h12;
     end

   always @(posedge CLK)
     begin
	if (WR) sram[idx] <= din;
	dout <= sram[idx];
     end

endmodule // eeprom

