`timescale 1ns / 1ps

//
// The HDMI pixel clock, and the 5x clock the TMDS serialisers run on.
// From the Sun-2 project's boards/Wukong/hdmi_clkgen.sv, which has the
// history (and the 1080p recipes this machine does not use).
//
// A third MMCM: mmcm_a's VCO (1000 MHz) and mmcm_b's (615.625, carrying the
// SCCs' 4.9152 MHz) cannot make 108 MHz, and there are MMCMs to spare.
//
//     DIVCLK_DIVIDE    1         PFD 50 MHz
//     CLKFBOUT_MULT_F  21.625    VCO 1081.25 MHz
//     CLKOUT0_DIVIDE_F 10        pixel  108.125 MHz  (VESA 108.0 + 0.116 %)
//     CLKOUT1_DIVIDE   2         serial 540.625 MHz
//
// VESA 1280x1024@60, with the 3/60's 1152x900 centred (64 x 62 border).  The
// Sun-2 measured that 742 MHz (1080p60) does not survive in the full design
// and that 540 MHz does on a -2 part.  On a -1 part (the V3) 540.625 MHz is
// above the BUFG's rating and the build needs ALLOW_PW=1 (report_pulse_width);
// whether the picture is sound there is for the monitor to say.
//
// The 5x clock is on a BUFG, out of specification as above, because
// hdl-util's serialiser wants a global clock; a BUFIO/BUFR pair would need a
// different serialiser.
//
module hdmi_clkgen (
    input  wire clk50,          // board oscillator
    input  wire reset,          // active high, asynchronous

    output wire clk_pixel,      // 108.125 MHz
    output wire clk_pixel_x5,   // 540.625 MHz
    output wire locked
);

`ifdef CLKGEN_BEHAVIOURAL

   // The pixel clock is divided from the 5x one, so the 5:1 ratio OSERDESE2's
   // 10:1 DDR mode depends on is exact; two free-running clocks with rounded
   // half-periods would not be.
   localparam realtime X5_HALF = 0.924855;    // 540.625 MHz

   reg pix_r = 1'b0, x5_r = 1'b0, locked_r = 1'b0;
   reg [2:0] div5 = 3'd0;

   always #(X5_HALF) x5_r = ~x5_r;

   always @(x5_r) begin
      if (div5 == 3'd4) begin
         div5  <= 3'd0;
         pix_r <= ~pix_r;
      end else begin
         div5 <= div5 + 3'd1;
      end
   end
   initial begin
      locked_r = 1'b0;
      #6500 locked_r = 1'b1;
   end

   assign clk_pixel    = pix_r;
   assign clk_pixel_x5 = x5_r;
   assign locked       = locked_r & ~reset;

`else

   wire mmcm_fb, mmcm_fb_bufg;
   wire mmcm_pixel, mmcm_x5;

   MMCME2_BASE #(
       .BANDWIDTH         ("OPTIMIZED"),
       .CLKIN1_PERIOD     (20.000),     // 50 MHz
       .DIVCLK_DIVIDE     (1),          // PFD 50 MHz
       .CLKFBOUT_MULT_F   (21.625),     // VCO 1081.25 MHz
       .CLKOUT0_DIVIDE_F  (10.000),     // 108.125 MHz   pixel
       .CLKOUT1_DIVIDE    (2),          // 540.625 MHz   5x, for the serialisers
       .STARTUP_WAIT      ("FALSE")
   ) mmcm_hdmi (
       .CLKIN1   (clk50),
       .CLKFBIN  (mmcm_fb_bufg),
       .CLKFBOUT (mmcm_fb),
       .CLKOUT0  (mmcm_pixel),
       .CLKOUT1  (mmcm_x5),
       .CLKOUT2  (), .CLKOUT3 (), .CLKOUT4 (), .CLKOUT5 (), .CLKOUT6 (),
       .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2B(), .CLKOUT3B(),
       .LOCKED   (locked),
       .PWRDWN   (1'b0),
       .RST      (reset)
   );

   BUFG bufg_fb    (.I(mmcm_fb),    .O(mmcm_fb_bufg));
   BUFG bufg_pixel (.I(mmcm_pixel), .O(clk_pixel));
   BUFG bufg_x5    (.I(mmcm_x5),    .O(clk_pixel_x5));

`endif

endmodule
