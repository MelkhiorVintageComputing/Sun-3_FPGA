`timescale 1ns / 1ps

//
// The Sun-3/60's on-board SCSI ("si", OBIO 0x140000): an NCR 5380, an AMD
// Am9516 Universal DMA Controller, and Sun's own packing FIFO between them.
//
// The 5380 is Inputs/Wish5380's (wish5380: sci_regs + sci_bus), with that
// repository's SCSI disk target (scsi_targ) on the bus and its block seam
// brought out, flattened, for the board's storage back end.  What is new here
// is the board logic around the chip, transcribed from Wish5380's QEMU model
// of the same board (cosim/patches/qemu/0004-...-Sun-3-si-onboard-SCSI-board,
// hw/scsi/sun3-si.c), which boots the 3/60 PROMs, NetBSD and SunOS 4.1.1.
// Its comments are the long form of the rules below.
//
// Register block (32 bytes, repeating; NetBSD sireg.h):
//   0x00-0x07  the 5380, one byte apart
//   0x10       udc_data   Am9516 data port (register chosen by udc_addr)
//   0x12       udc_addr   Am9516 register pointer (6 bits)
//   0x14       fifo_data  read-only: the last byte moved, in bits 15:8
//   0x16       fifo_count bytes; reads back as the residual.  A write is
//                         ignored while the bus is in a DATA phase
//   0x18       si_csr     control and status
//   0x08-0x0e, 0x1a-0x1e  VME-only: stored and ignored (the PROM writes
//                         si_iv_am before anything else)
//
// The Am9516, as far as Sun uses it: channel 1, pointers MODE 0x38,
// COMMAND/STATUS 0x2e, chain address 0x26/0x22, COUNT 0x32; commands RESET,
// CIE and START CHAIN.  Start chain fetches a reload word and the registers it
// selects from DVMA memory (Sun: 0x0182 receive / 0x0282 send = current
// address, count, channel mode), then moves the data.  An address high word
// has A23-A16 in its HIGH byte.
//
// Data moves a byte per DVMA cycle, as the QEMU model does, which keeps its
// counters and its leftover-byte behaviour exactly: fifo_count counts bytes,
// the UDC count words (decremented on every even residual), fifo_data holds
// the last byte in 15:8.
//
// Three rules only SunOS enforces (see the model's commit message):
//  * DMA_CONFLICT is never set;
//  * DMA_IP is not raised at terminal count, only on a DVMA bus error with
//    the channel interrupt enabled;
//  * a transfer also ends when the chip stops asking: once it has asked at
//    least once, a lost PHASE MATCH together with the chip's interrupt means
//    the target has moved on (INQUIRY: 56 asked, 36 given).
//
// DVMA goes out as a Wishbone master into sun3_fpga's DVMA bridge
// (wish7990_dvma_to_020), which puts it on the 68020 bus at 0x0FF00000 +
// address, through the MMU, supervisor data.  That bridge maps the byte at
// bus offset k of a longword to Wishbone lane k ^ 1 (it was written for the
// little-endian LANCE); this master uses the same mapping.
//
`include "sun3_attr.vh"

module sun3_si #(
    parameter int CLK_PERIOD_PS = 50000
) (
    input  wire        clk,
    input  wire        rst,          // system reset, active high

    // ---- the CPU's side: an OBIO device --------------------------------
    input  wire        match,        // the cycle is ours (level, whole cycle)
    input  wire        rw_n,
    input  wire [4:0]  adr,
    input  wire [31:0] wdata,        // narrow writes arrive replicated
    output reg  [31:0] rdata,        // replicated on every lane
    output reg         ack,          // one clock
    output wire        irq,          // level 2

    // ---- DVMA: Wishbone master ------------------------------------------
    output reg         m_cyc,
    output reg         m_we,
    output reg  [3:0]  m_sel,
    output reg  [29:0] m_adr,        // word address; [21:0] significant
    output reg  [31:0] m_dat_o,
    input  wire [31:0] m_dat_i,
    input  wire        m_ack,
    input  wire        m_err,

    // ---- the block seam (Inputs/Wish5380 doc/block.md), flattened -------
    output wire        blk_start,
    output wire        blk_we,
    output wire [31:0] blk_lba,
    output wire [7:0]  blk_buf_rdata,
    input  wire        blk_done,
    input  wire        blk_err,
    input  wire        blk_ready,
    input  wire [31:0] blk_count,
    input  wire        blk_buf_we,
    input  wire [8:0]  blk_buf_addr,
    input  wire [7:0]  blk_buf_wdata,

    output wire        dma_active    // for debug
);

   // ------------------------------------------------------------------
   // The chip, the disk and the bus between them
   // ------------------------------------------------------------------
   localparam [15:0] CSR_DMA_ACTIVE = 16'h8000,
                     CSR_BUS_ERR    = 16'h2000,
                     CSR_FIFO_EMPTY = 16'h0400,
                     CSR_SBC_IP     = 16'h0200,
                     CSR_DMA_IP     = 16'h0100,
                     CSR_SEND       = 16'h0008,
                     CSR_INTR_EN    = 16'h0004,
                     CSR_FIFO_RES   = 16'h0002,
                     CSR_SCSI_RES   = 16'h0001,
                     CSR_WRITABLE   = 16'h000F;

   localparam [15:0] SR_CIE = 16'h8000, SR_IP = 16'h2000, SR_CA = 16'h1000,
                     SR_NAC = 16'h0800, SR_TC = 16'h0001;

   reg  [15:0] csr;

   // The chip's port: the CPU's register accesses, or the DMA engine's DACK
   // accesses; between them the address rests on register 5 (Bus and Status),
   // whose PHASE MATCH bit the engine watches.  dat_o is combinational.
   logic       c_stb, c_we, c_dack, c_eop;
   logic [2:0] c_adr;
   logic [7:0] c_wdat, c_rdat;
   logic       chip_drq, chip_irq;

   scsi_t drive_chip, drive_targ, bus;
   blk_req_t breq;
   blk_rsp_t brsp;

   // SCSI_RES (active low) resets the chip and the UDC; it reads 0 after a
   // system reset, so both stay in reset until software lets them go.
   wire chip_rst = rst | ~csr[0];

   wish5380 #(.CLK_PERIOD_PS(CLK_PERIOD_PS)) sbc (
       .clk_i   (clk),
       .rst_i   (chip_rst),
       .stb_i   (c_stb),
       .we_i    (c_we),
       .dack_i  (c_dack),
       .adr_i   (c_adr),
       .dat_i   (c_wdat),
       .dat_o   (c_rdat),
       .eop_i   (c_eop),
       .drq_o   (chip_drq),
       .irq_o   (chip_irq),
       .drive_o (drive_chip),
       .bus_i   (bus)
   );

   scsi_targ #(.CLK_PERIOD_PS(CLK_PERIOD_PS), .TARGET_ID(0),
               .VENDOR("WISH5380"), .PRODUCT("SD CARD 3/60    "),
               .REVISION("0001")) disk (
       .clk_i   (clk),
       .rst_i   (rst),
       .drive_o (drive_targ),
       .bus_i   (bus),
       .blk_o   (breq),
       .blk_i   (brsp)
   );

   scsi_fabric fabric (
       .a_i   (drive_chip),
       .b_i   (drive_targ),
       .c_i   ('0),
       .d_i   ('0),
       .bus_o (bus)
   );

   assign blk_start     = breq.start;
   assign blk_we        = breq.we;
   assign blk_lba       = breq.lba;
   assign blk_buf_rdata = breq.buf_rdata;
   always_comb begin
      brsp.done      = blk_done;
      brsp.err       = blk_err;
      brsp.ready     = blk_ready;
      brsp.count     = blk_count;
      brsp.buf_we    = blk_buf_we;
      brsp.buf_addr  = blk_buf_addr;
      brsp.buf_wdata = blk_buf_wdata;
   end

   // DATA OUT or DATA IN on the bus: MSG and C/D both clear.
   wire in_data_phase = ~bus.msg & ~bus.cd;

   // ------------------------------------------------------------------
   // CPU accesses: one chip strobe per bus cycle, acknowledged a clock later
   // ------------------------------------------------------------------
   reg match_q;
   always_ff @(posedge clk) match_q <= match & ~rst;
   wire cpu_go = match & ~match_q;           // the cycle's first clock here

   // The DMA engine's chip access for this clock (see the engine below).
   logic       e_stb, e_we, e_eop;
   logic [7:0] e_wdat;

   always_comb begin
      if (cpu_go && adr[4:3] == 2'b00) begin
         c_stb = 1'b1; c_we = ~rw_n; c_dack = 1'b0; c_adr = adr[2:0];
         c_wdat = wdata[7:0]; c_eop = 1'b0;
      end else if (e_stb) begin
         c_stb = 1'b1; c_we = e_we; c_dack = 1'b1; c_adr = 3'd0;
         c_wdat = e_wdat; c_eop = e_eop;
      end else begin
         c_stb = 1'b0; c_we = 1'b0; c_dack = 1'b0; c_adr = 3'd5;
         c_wdat = 8'h00; c_eop = 1'b0;
      end
   end
   wire phase_match = c_rdat[3];             // valid when resting on reg 5
   wire resting     = ~c_stb;

   // ------------------------------------------------------------------
   // The board's registers and the Am9516
   // ------------------------------------------------------------------
   reg  [15:0] fifo_count, fifo_data;
   reg  [15:0] vme [0:7];
   reg  [6:0]  udc_ptr;
   reg  [15:0] udc_mode, udc_car_hi, udc_car_lo, udc_count, udc_status;
   reg  [23:0] dma_addr;
   reg         running, saw_drq, start_chain;

   localparam [6:0] UDC_MODE = 7'h38, UDC_CMD = 7'h2e, UDC_CAR_HI = 7'h26,
                    UDC_CAR_LO = 7'h22, UDC_COUNT = 7'h32;

   wire [15:0] csr_rd = (csr & ~CSR_FIFO_EMPTY & ~CSR_SBC_IP)
                      | (running  ? 16'h0 : CSR_FIFO_EMPTY)
                      | (chip_irq ? CSR_SBC_IP : 16'h0);

   reg [15:0] udc_rd;
   always_comb
     case (udc_ptr)
       UDC_CMD:    udc_rd = udc_status;
       UDC_MODE:   udc_rd = udc_mode;
       UDC_CAR_HI: udc_rd = udc_car_hi;
       UDC_CAR_LO: udc_rd = udc_car_lo;
       UDC_COUNT:  udc_rd = udc_count;
       default:    udc_rd = 16'h0000;
     endcase

   // Read data, latched on the cycle's first clock (the chip's is
   // combinational in that clock), replicated on every lane.
   reg [15:0] rd16;
   always_comb
     case (adr[4:1])
       4'h8:    rd16 = udc_rd;                    // 0x10
       4'h9:    rd16 = {9'h0, udc_ptr};           // 0x12
       4'hA:    rd16 = fifo_data;                 // 0x14
       4'hB:    rd16 = fifo_count;                // 0x16
       4'hC:    rd16 = csr_rd;                    // 0x18
       4'h4, 4'h5, 4'h6, 4'h7:                    // 0x08-0x0e
                rd16 = vme[{1'b0, adr[2:1]}];
       4'hD, 4'hE, 4'hF:                          // 0x1a-0x1e
                rd16 = vme[{1'b1, adr[2:1]}];
       default: rd16 = 16'h0000;
     endcase

   always_ff @(posedge clk) begin
      ack <= cpu_go;
      if (cpu_go)
        rdata <= (adr[4:3] == 2'b00) ? {4{c_rdat}} : {2{rd16}};
   end

   // ---- the DMA engine's state, declared here for the register writes ----
   typedef enum logic [3:0] {
      E_IDLE, E_RSEL, E_SCAN, E_WORD, E_RUN, E_MEM_RD, E_CHIP_WR, E_CHIP_RD,
      E_MEM_WR, E_END
   } est_t;
   est_t est;

   wire [15:0] wr16 = wdata[15:0];
   wire        cpu_wr = cpu_go & ~rw_n;

   // From the engine (below): the transfer is over (terminal count, bus
   // error, or the chip stopped asking), the chain fetch failed, a byte moved.
   logic        end_tc, end_err, end_short, chain_err;
   logic        e_byte;
   logic [7:0]  e_byte_val;
   logic        chain_count_ld;
   logic [15:0] chain_count;

   always_ff @(posedge clk) begin
      start_chain <= 1'b0;

      if (cpu_wr) begin
         case (adr[4:1])
           4'h8:                                   // udc_data
             case (udc_ptr)
               UDC_MODE:   udc_mode   <= wr16;
               UDC_CAR_HI: udc_car_hi <= wr16;
               UDC_CAR_LO: udc_car_lo <= wr16;
               UDC_COUNT:  udc_count  <= wr16;
               UDC_CMD:
                 case (wr16[7:0])
                   8'h00: begin                    // RESET
                      udc_mode   <= 16'h0;
                      udc_count  <= 16'h0;
                      udc_status <= SR_CA | SR_NAC;
                      csr        <= csr & ~(CSR_DMA_ACTIVE | CSR_DMA_IP);
                   end
                   8'h32: udc_status <= udc_status | SR_CIE;   // CIE
                   8'hA0: start_chain <= 1'b1;               // START CHAIN
                   default: ;
                 endcase
               default: ;
             endcase
           4'h9: udc_ptr <= wr16[6:0] & 7'h7e;     // bit 1 picks the channel
           4'hB: if (!in_data_phase) fifo_count <= wr16;
           4'hC: begin
              csr <= (csr & ~CSR_WRITABLE) | (wr16 & CSR_WRITABLE);
              if (!wr16[0]) begin                  // SCSI_RES: chip and UDC
                 udc_mode   <= 16'h0;
                 udc_count  <= 16'h0;
                 udc_status <= SR_CA | SR_NAC;
                 csr        <= ((csr & ~CSR_WRITABLE) | (wr16 & CSR_WRITABLE))
                               & ~(CSR_DMA_ACTIVE | CSR_DMA_IP | CSR_BUS_ERR);
              end
              if (!wr16[1]) fifo_data <= 16'h0;    // FIFO_RES
           end
           4'h4, 4'h5, 4'h6, 4'h7: vme[{1'b0, adr[2:1]}] <= wr16;
           4'hD, 4'hE, 4'hF:       vme[{1'b1, adr[2:1]}] <= wr16;
           default: ;
         endcase
      end

      // The engine's effects on the registers.  START CHAIN clears the
      // channel abort reset left and raises DMA ACTIVE at once, as the command
      // write does in the model: a driver may look before the chain is read.
      if (start_chain && est == E_IDLE) begin
         udc_status <= udc_status & ~(SR_TC | SR_NAC | SR_CA);
         csr        <= (csr | CSR_DMA_ACTIVE) & ~(CSR_DMA_IP | CSR_BUS_ERR);
      end
      if (chain_err)
         csr <= (csr | CSR_BUS_ERR) & ~CSR_DMA_ACTIVE;
      if (end_short)
         csr <= csr & ~CSR_DMA_ACTIVE;
      if (end_tc || end_err) begin
         udc_status <= udc_status | SR_TC | SR_NAC
                       | ((end_err && udc_status[15]) ? SR_IP : 16'h0);
         csr <= (csr & ~CSR_DMA_ACTIVE)
                | (end_err ? CSR_BUS_ERR : 16'h0)
                | ((end_err && udc_status[15]) ? CSR_DMA_IP : 16'h0);
      end
      if (e_byte) begin                            // a byte has moved
         fifo_data  <= {e_byte_val, 8'h00};
         fifo_count <= fifo_count - 16'd1;
         if (udc_count != 16'h0 && fifo_count[0])  // new residual even
           udc_count <= udc_count - 16'd1;
      end
      if (chain_count_ld) udc_count <= chain_count;

      if (rst) begin
         csr        <= 16'h0000;
         fifo_count <= 16'h0;
         fifo_data  <= 16'h0;
         udc_ptr    <= 7'h0;
         udc_mode   <= 16'h0;
         udc_car_hi <= 16'h0;
         udc_car_lo <= 16'h0;
         udc_count  <= 16'h0;
         udc_status <= SR_CA | SR_NAC;
      end
   end

   // ------------------------------------------------------------------
   // The DMA engine: chain fetch, then one byte per DVMA cycle
   // ------------------------------------------------------------------
   reg  [23:0] at;              // chain table pointer
   reg  [15:0] rsel;
   reg  [3:0]  bit_i;
   reg         bits_done;
   reg  [1:0]  words_left;
   reg         got_hi;
   reg  [15:0] addr_hi;
   reg  [7:0]  byte_q;
   reg         send;

   // Registers taking two words in the reload scan: current/base ARA and ARB,
   // pattern and mask, channel mode, chain address (Am9516A Figure 12).
   function automatic logic [1:0] nwords(input logic [3:0] i);
      case (i)
        4'd9, 4'd8, 4'd6, 4'd5, 4'd3, 4'd1, 4'd0: nwords = 2'd2;
        default:                                    nwords = 2'd1;
      endcase
   endfunction

   // Bus offset k is Wishbone lane k ^ 1 (see the header).
   function automatic logic [1:0] lane(input logic [1:0] k);
      lane = k ^ 2'b01;
   endfunction

   // A 16-bit read of the word at an even address.
   wire [15:0] m_word = at[1] ? m_dat_i[31:16] : m_dat_i[15:0];
   wire [7:0]  m_byte = m_dat_i[8*lane(dma_addr[1:0]) +: 8];

   task automatic mem_read_word(input logic [23:0] a);
      m_cyc <= 1'b1; m_we <= 1'b0;
      m_adr <= {8'h00, a[23:2]};
      m_sel <= a[1] ? 4'b1100 : 4'b0011;
   endtask

   task automatic mem_byte(input logic we, input logic [23:0] a, input logic [7:0] d);
      m_cyc <= 1'b1; m_we <= we;
      m_adr <= {8'h00, a[23:2]};
      m_sel <= 4'b0001 << lane(a[1:0]);
      m_dat_o <= {4{d}};
   endtask

   // The chip access and the register side effects are combinational in the
   // state, so the chip sees exactly one strobe.  A CPU access to the chip in
   // the same clock wins, and the engine repeats the attempt next clock.
   wire cpu_chip = cpu_go && adr[4:3] == 2'b00;

   always_comb begin
      e_stb = 1'b0; e_we = 1'b0; e_eop = 1'b0; e_wdat = byte_q;
      e_byte = 1'b0; e_byte_val = 8'h00;
      end_tc = 1'b0; end_err = 1'b0; end_short = 1'b0;
      chain_err = 1'b0;
      chain_count_ld = 1'b0; chain_count = m_word;

      case (est)
        E_RSEL, E_WORD:
          if (m_cyc && m_err) chain_err = 1'b1;
        E_CHIP_WR:
          if (!cpu_chip) begin
             e_stb = 1'b1; e_we = 1'b1; e_eop = (fifo_count == 16'd1);
             e_byte = 1'b1; e_byte_val = byte_q;
          end
        E_CHIP_RD:
          if (!cpu_chip) begin
             e_stb = 1'b1; e_we = 1'b0; e_eop = (fifo_count == 16'd1);
          end
        E_MEM_RD, E_MEM_WR:
          if (m_cyc && m_err) end_err = 1'b1;
        E_RUN:
          if (fifo_count == 16'd0) end_tc = 1'b1;
          else if (!chip_drq && resting && saw_drq && !phase_match && chip_irq)
            end_short = 1'b1;
        default: ;
      endcase
      if (est == E_WORD && m_cyc && m_ack && bit_i == 4'd7) chain_count_ld = 1'b1;
      // A receive byte is counted when it reaches memory.
      if (est == E_MEM_WR && m_cyc && m_ack) begin
         e_byte = 1'b1; e_byte_val = byte_q;
      end
   end

   always_ff @(posedge clk) begin
      case (est)
        E_IDLE:
          if (start_chain) begin
             at      <= {udc_car_hi[15:8], udc_car_lo};
             mem_read_word({udc_car_hi[15:8], udc_car_lo});
             running <= 1'b1;
             est     <= E_RSEL;
          end

        E_RSEL:
          if (m_ack || m_err) begin
             m_cyc <= 1'b0;
             if (m_err) begin running <= 1'b0; est <= E_IDLE; end
             else begin
                rsel      <= m_word;
                at        <= at + 24'd2;
                bit_i     <= 4'd9;
                bits_done <= 1'b0;
                got_hi    <= 1'b0;
                est       <= E_SCAN;
             end
          end

        E_SCAN:
          if (bits_done) begin
             send    <= csr[3];
             saw_drq <= 1'b0;
             est     <= E_RUN;
          end else if (rsel[bit_i]) begin
             words_left <= nwords(bit_i);
             mem_read_word(at);
             est <= E_WORD;
          end else if (bit_i == 4'd0) bits_done <= 1'b1;
          else bit_i <= bit_i - 4'd1;

        E_WORD:
          if (m_ack || m_err) begin
             m_cyc <= 1'b0;
             if (m_err) begin running <= 1'b0; est <= E_IDLE; end
             else begin
                at <= at + 24'd2;
                if (bit_i == 4'd9 || bit_i == 4'd8) begin   // current ARA/ARB
                   if (!got_hi) begin addr_hi <= m_word; got_hi <= 1'b1; end
                   else dma_addr <= {addr_hi[15:8], m_word};
                end
                if (words_left == 2'd2) begin
                   words_left <= 2'd1;
                   mem_read_word(at + 24'd2);
                end else begin
                   if (bit_i == 4'd0) bits_done <= 1'b1;
                   else bit_i <= bit_i - 4'd1;
                   est <= E_SCAN;
                end
             end
          end

        E_RUN:
          if (end_tc) begin
             running <= 1'b0; est <= E_IDLE;
          end else if (end_short) begin
             running <= 1'b0; est <= E_IDLE;
          end else if (chip_drq) begin
             saw_drq <= 1'b1;
             if (send) begin
                mem_byte(1'b0, dma_addr, 8'h00);
                est <= E_MEM_RD;
             end else
                est <= E_CHIP_RD;
          end

        E_MEM_RD:                                   // send: memory -> chip
          if (m_ack || m_err) begin
             m_cyc <= 1'b0;
             if (m_err) begin running <= 1'b0; est <= E_IDLE; end
             else begin byte_q <= m_byte; est <= E_CHIP_WR; end
          end

        E_CHIP_WR:
          if (!cpu_chip) begin
             dma_addr <= dma_addr + 24'd1;
             est <= E_RUN;
          end

        E_CHIP_RD:                                  // receive: chip -> memory
          if (!cpu_chip) begin
             byte_q <= c_rdat;
             mem_byte(1'b1, dma_addr, c_rdat);
             est <= E_MEM_WR;
          end

        E_MEM_WR:
          if (m_ack || m_err) begin
             m_cyc <= 1'b0;
             if (m_err) begin running <= 1'b0; est <= E_IDLE; end
             else begin dma_addr <= dma_addr + 24'd1; est <= E_RUN; end
          end

        default: est <= E_IDLE;
      endcase

      // UDC RESET or SCSI_RES abandon any transfer.
      if (cpu_wr && ((adr[4:1] == 4'h8 && udc_ptr == UDC_CMD && wr16[7:0] == 8'h00) ||
                     (adr[4:1] == 4'hC && !wr16[0]))) begin
         est <= E_IDLE; running <= 1'b0; m_cyc <= 1'b0;
      end

      if (rst) begin
         est <= E_IDLE; running <= 1'b0; m_cyc <= 1'b0; m_we <= 1'b0;
         m_sel <= 4'h0; m_adr <= 30'h0; m_dat_o <= 32'h0; saw_drq <= 1'b0;
      end
   end

   assign irq        = csr[2] & (chip_irq | csr[8]);
   assign dma_active = running;

   wire _unused = &{1'b0, wdata[31:16], 1'b0};

endmodule
