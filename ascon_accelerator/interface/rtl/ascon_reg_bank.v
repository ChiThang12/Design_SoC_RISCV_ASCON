// ============================================================================
// Module  : ascon_reg_bank
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_axi_slave
//
// Description:
//   Central register storage for the ASCON accelerator IP.
//   Handles:
//     - Write decode: routes do_write + wr_addr + wr_data to correct register
//     - Read mux: returns register content for given rd_addr (combinational)
//     - Control pulse generation: core_start, core_soft_rst, dma_start, dma_soft_rst
//     - Status capture: latches ctext/tag from core on done signals
//     - Sticky status bits: DONE, DMA_DONE, ERROR, DMA_ERROR
//
// Register Map (offset, relative to IP base 0x2000_0000):
//   0x000  CTRL         R/W  [2]=DMA_EN [1]=SOFT_RST [0]=START
//   0x004  STATUS       RO   [5]=DMA_ERROR [4]=ERROR [3]=DMA_DONE
//                            [2]=DMA_BUSY  [1]=DONE  [0]=BUSY
//   0x008  MODE         R/W  [1]=PERM_MODE [0]=ENC_DEC
//   0x00C  IRQ_EN       R/W  [2]=ERROR_IRQ_EN [1]=DMA_DONE_IRQ_EN [0]=DONE_IRQ_EN
//   0x010-01C KEY_0..3  WO   (reads return 0)
//   0x020-02C NONCE_0..3 WO  (reads return 0)
//   0x030-034 PTEXT_0..1 WO  (reads return 0)
//   0x040-044 CTEXT_0..1 RO  (captured from core on data_out_valid)
//   0x048-054 TAG_0..3   RO  (captured from core on tag_valid)
//   ── DMA registers (spec 05B) ──────────────────────────────────────────────
//   0x100  DMA_SRC_ADDR R/W  Source address (plaintext in DDR)
//   0x104  DMA_DST_ADDR R/W  Destination address (ctext+tag out)
//   0x108  DMA_BYTE_LEN R/W  Bytes to transfer (Phase 1: = 8)
//   0x10C  DMA_CTRL     R/W  [3]=WR_ONLY [2]=RD_ONLY [1]=DMA_SOFT_RST [0]=DMA_START
//   0x110  DMA_STATUS   RO   [6]=FIFO_OVF [5]=WR_ERROR [4]=RD_ERROR
//                            [3]=WR_DONE  [2]=RD_DONE  [1]=DMA_DONE [0]=DMA_BUSY
//   0x114  DMA_BURST_LEN R/W [7:0] AXI burst length (0 = 1 beat)
//   0x118  DMA_ERR_ADDR  RO  Address that caused last AXI error (debug)
// ============================================================================

module ascon_reg_bank #(
    parameter DATA_WIDTH = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ── Write port (from axi_write_channel) ──────────────────────────────────
    input  wire [11:0]             wr_addr,
    input  wire [DATA_WIDTH-1:0]   wr_data,
    input  wire [DATA_WIDTH/8-1:0] wr_strb,
    input  wire                    do_write,

    // ── Read port (to axi_read_channel) ──────────────────────────────────────
    input  wire [11:0]             rd_addr,
    output reg  [DATA_WIDTH-1:0]   rd_data,    // combinational mux

    // ── Control pulses out (1-cycle) ─────────────────────────────────────────
    output reg                     core_start,
    output reg                     core_soft_rst,
    output reg                     dma_start,
    output reg                     dma_soft_rst,

    // ── Register outputs to ascon_CORE ───────────────────────────────────────
    output wire [127:0]            core_key,
    output wire [127:0]            core_nonce,
    output wire [127:0]            core_data_in,
    output wire [6:0]              core_data_len,
    output wire                    core_enc_dec,
    output wire [1:0]              core_mode,

    // ── Status inputs from ascon_CORE ────────────────────────────────────────
    input  wire                    core_busy,
    input  wire                    core_done,
    input  wire                    core_data_out_valid,
    input  wire [127:0]            core_data_out,
    input  wire [127:0]            core_tag_out,
    input  wire                    core_tag_valid,

    // ── Register outputs to ascon_dma ────────────────────────────────────────
    output wire [31:0]             dma_src_addr,
    output wire [31:0]             dma_dst_addr,
    output wire [31:0]             dma_length,
    output wire                    dma_en,
    output wire [7:0]              dma_burst_len,   // DMA_BURST_LEN[7:0] → M_AXI_ARLEN/AWLEN
    output wire                    dma_rd_only,     // DMA_CTRL[2]: skip write phase
    output wire                    dma_wr_only,     // DMA_CTRL[3]: skip read phase

    // ── Status inputs from ascon_dma ─────────────────────────────────────────
    // Aggregate (used by CTRL 0x004 and IRQ)
    input  wire                    dma_busy,
    input  wire                    dma_done,
    input  wire                    dma_error,

    // Detailed DMA status bits — for DMA_STATUS register (0x110)
    input  wire                    dma_status_rd_done,      // [2]
    input  wire                    dma_status_wr_done,      // [3]
    input  wire                    dma_status_rd_error,     // [4]
    input  wire                    dma_status_wr_error,     // [5]
    input  wire                    dma_status_fifo_overflow,// [6]
    // DMA_ERR_ADDR register (0x118) — address that caused AXI error
    input  wire [31:0]             dma_err_addr,

    // =========================================================================
    // Sticky status outputs (to ascon_irq_ctrl)
    // =========================================================================
    output wire                    status_done,
    output wire                    status_dma_done,
    output wire                    status_error,
    output wire                    status_dma_error,

    // ── IRQ_EN bus (to ascon_irq_ctrl) ───────────────────────────────────────
    output wire [2:0]              irq_en_bus
);

    // =========================================================================
    // Address offset localparams
    // =========================================================================
    localparam [11:0]
        ADDR_CTRL         = 12'h000,
        ADDR_STATUS       = 12'h004,
        ADDR_MODE         = 12'h008,
        ADDR_IRQ_EN       = 12'h00C,
        ADDR_KEY_0        = 12'h010,
        ADDR_KEY_1        = 12'h014,
        ADDR_KEY_2        = 12'h018,
        ADDR_KEY_3        = 12'h01C,
        ADDR_NONCE_0      = 12'h020,
        ADDR_NONCE_1      = 12'h024,
        ADDR_NONCE_2      = 12'h028,
        ADDR_NONCE_3      = 12'h02C,
        ADDR_PTEXT_0      = 12'h030,
        ADDR_PTEXT_1      = 12'h034,
        ADDR_CTEXT_0      = 12'h040,
        ADDR_CTEXT_1      = 12'h044,
        ADDR_TAG_0        = 12'h048,
        ADDR_TAG_1        = 12'h04C,
        ADDR_TAG_2        = 12'h050,
        ADDR_TAG_3        = 12'h054,
        ADDR_DMA_SRC      = 12'h100,
        ADDR_DMA_DST      = 12'h104,
        ADDR_DMA_LEN      = 12'h108,
        ADDR_DMA_CTRL     = 12'h10C,   // DMA_CTRL  (spec 05B §4)
        ADDR_DMA_STATUS   = 12'h110,   // DMA_STATUS (RO)
        ADDR_DMA_BURST    = 12'h114,   // DMA_BURST_LEN
        ADDR_DMA_ERR_ADDR = 12'h118;   // DMA_ERR_ADDR (RO)

    // =========================================================================
    // Storage registers
    // =========================================================================

    // R/W control
    reg [1:0]  reg_mode;
    reg [2:0]  reg_irq_en;
    reg        reg_dma_en;

    // WO — key, nonce, plaintext
    reg [31:0] reg_key_0,   reg_key_1,   reg_key_2,   reg_key_3;
    reg [31:0] reg_nonce_0, reg_nonce_1, reg_nonce_2, reg_nonce_3;
    reg [31:0] reg_ptext_0, reg_ptext_1;

    // RO — captured results
    reg [31:0] reg_ctext_0, reg_ctext_1;
    reg [31:0] reg_tag_0,   reg_tag_1,   reg_tag_2,   reg_tag_3;

    // DMA config
    reg [31:0] reg_dma_src, reg_dma_dst, reg_dma_len;
    reg [1:0]  reg_dma_ctrl_mode;  // [1]=WR_ONLY [0]=RD_ONLY  (DMA_CTRL 0x10C [3:2])
    reg [7:0]  reg_dma_burst;      // DMA_BURST_LEN 0x114 [7:0]

    // Sticky status flags
    reg        r_status_done, r_status_dma_done;
    reg        r_status_error, r_status_dma_error;

    assign status_done      = r_status_done;
    assign status_dma_done  = r_status_dma_done;
    assign status_error     = r_status_error;
    assign status_dma_error = r_status_dma_error;

    // =========================================================================
    // Byte-enable helper
    // =========================================================================
    function [31:0] apply_strb;
        input [31:0] old_val;
        input [31:0] new_val;
        input [3:0]  strb;
        begin
            apply_strb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
            apply_strb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
            apply_strb[15: 8] = strb[1] ? new_val[15: 8] : old_val[15: 8];
            apply_strb[ 7: 0] = strb[0] ? new_val[ 7: 0] : old_val[ 7: 0];
        end
    endfunction

    // =========================================================================
    // Write decode + control pulse generation
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_mode    <= 2'h0;
            reg_irq_en  <= 3'h0;
            reg_dma_en  <= 1'b0;
            reg_key_0   <= 32'h0; reg_key_1 <= 32'h0;
            reg_key_2   <= 32'h0; reg_key_3 <= 32'h0;
            reg_nonce_0 <= 32'h0; reg_nonce_1 <= 32'h0;
            reg_nonce_2 <= 32'h0; reg_nonce_3 <= 32'h0;
            reg_ptext_0 <= 32'h0; reg_ptext_1 <= 32'h0;
            reg_dma_src <= 32'h0;
            reg_dma_dst <= 32'h0;
            reg_dma_len <= 32'd8;
            reg_dma_ctrl_mode <= 2'b00;
            reg_dma_burst     <= 8'h00;
            core_start    <= 1'b0;
            core_soft_rst <= 1'b0;
            dma_start     <= 1'b0;
            dma_soft_rst  <= 1'b0;
        end else begin
            // Default: clear 1-cycle pulses every cycle
            core_start    <= 1'b0;
            core_soft_rst <= 1'b0;
            dma_start     <= 1'b0;
            dma_soft_rst  <= 1'b0;

            if (do_write) begin
                case (wr_addr)

                    // ----------------------------------------------------------
                    // CTRL register
                    //   Writing bit[1] SOFT_RST: pulse resets to both core & DMA
                    //   Writing bit[0] START:    pulse start (only if not busy)
                    //   Writing bit[2] DMA_EN:   latched sticky bit
                    // ----------------------------------------------------------
                    ADDR_CTRL: begin
                        if (wr_strb[0]) begin
                            if (wr_data[1]) begin
                                core_soft_rst <= 1'b1;
                                dma_soft_rst  <= 1'b1;
                            end
                            if (wr_data[0] && !core_busy && !dma_busy) begin
                                core_start <= 1'b1;
                                // DMA_EN can come in same write beat or be pre-set
                                if (wr_data[2] || reg_dma_en)
                                    dma_start <= 1'b1;
                            end
                            reg_dma_en <= wr_data[2];
                        end
                    end

                    // ----------------------------------------------------------
                    // MODE register
                    // ----------------------------------------------------------
                    ADDR_MODE: begin
                        if (wr_strb[0])
                            reg_mode <= wr_data[1:0];
                    end

                    // ----------------------------------------------------------
                    // IRQ_EN register
                    // ----------------------------------------------------------
                    ADDR_IRQ_EN: begin
                        if (wr_strb[0])
                            reg_irq_en <= wr_data[2:0];
                    end

                    // ----------------------------------------------------------
                    // Key registers (WO)
                    // ----------------------------------------------------------
                    ADDR_KEY_0: reg_key_0 <= apply_strb(reg_key_0, wr_data, wr_strb);
                    ADDR_KEY_1: reg_key_1 <= apply_strb(reg_key_1, wr_data, wr_strb);
                    ADDR_KEY_2: reg_key_2 <= apply_strb(reg_key_2, wr_data, wr_strb);
                    ADDR_KEY_3: reg_key_3 <= apply_strb(reg_key_3, wr_data, wr_strb);

                    // ----------------------------------------------------------
                    // Nonce registers (WO)
                    // ----------------------------------------------------------
                    ADDR_NONCE_0: reg_nonce_0 <= apply_strb(reg_nonce_0, wr_data, wr_strb);
                    ADDR_NONCE_1: reg_nonce_1 <= apply_strb(reg_nonce_1, wr_data, wr_strb);
                    ADDR_NONCE_2: reg_nonce_2 <= apply_strb(reg_nonce_2, wr_data, wr_strb);
                    ADDR_NONCE_3: reg_nonce_3 <= apply_strb(reg_nonce_3, wr_data, wr_strb);

                    // ----------------------------------------------------------
                    // Plaintext registers (WO)
                    // ----------------------------------------------------------
                    ADDR_PTEXT_0: reg_ptext_0 <= apply_strb(reg_ptext_0, wr_data, wr_strb);
                    ADDR_PTEXT_1: reg_ptext_1 <= apply_strb(reg_ptext_1, wr_data, wr_strb);

                    // ----------------------------------------------------------
                    // DMA config registers (spec 05B §4)
                    // ----------------------------------------------------------
                    ADDR_DMA_SRC: reg_dma_src <= apply_strb(reg_dma_src, wr_data, wr_strb);
                    ADDR_DMA_DST: reg_dma_dst <= apply_strb(reg_dma_dst, wr_data, wr_strb);
                    ADDR_DMA_LEN: reg_dma_len <= apply_strb(reg_dma_len, wr_data, wr_strb);

                    // DMA_CTRL (0x10C)
                    // [0] DMA_START    → pulse dma_start (handled above in ADDR_CTRL logic)
                    //                   NOTE: DMA_START here is the *dedicated* DMA start,
                    //                   separate from main CTRL[0]. Same guard: not if busy.
                    // [1] DMA_SOFT_RST → pulse dma_soft_rst
                    // [2] RD_ONLY      → latched
                    // [3] WR_ONLY      → latched
                    ADDR_DMA_CTRL: begin
                        if (wr_strb[0]) begin
                            if (wr_data[1]) begin
                                dma_soft_rst <= 1'b1;
                            end
                            if (wr_data[0] && !dma_busy) begin
                                dma_start <= 1'b1;
                            end
                            reg_dma_ctrl_mode <= wr_data[3:2];
                        end
                    end

                    // DMA_BURST_LEN (0x114)
                    ADDR_DMA_BURST: begin
                        if (wr_strb[0])
                            reg_dma_burst <= wr_data[7:0];
                    end

                    // DMA_STATUS (0x110), DMA_ERR_ADDR (0x118): RO — writes silently ignored
                    default: ;

                endcase
            end
        end
    end

    // =========================================================================
    // Status capture + sticky bits
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_status_done      <= 1'b0;
            r_status_dma_done  <= 1'b0;
            r_status_error     <= 1'b0;
            r_status_dma_error <= 1'b0;
            reg_ctext_0 <= 32'h0; reg_ctext_1 <= 32'h0;
            reg_tag_0   <= 32'h0; reg_tag_1   <= 32'h0;
            reg_tag_2   <= 32'h0; reg_tag_3   <= 32'h0;
        end else begin
            // SOFT_RST clears sticky flags (preserves key/nonce/ptext)
            if (core_soft_rst) begin
                r_status_done      <= 1'b0;
                r_status_dma_done  <= 1'b0;
                r_status_error     <= 1'b0;
                r_status_dma_error <= 1'b0;
            end

            // Capture ciphertext from core (upper 64-bit of 128-bit data_out)
            if (core_data_out_valid) begin
                reg_ctext_0 <= core_data_out[127:96];
                reg_ctext_1 <= core_data_out[95:64];
            end

            // Capture tag from core
            if (core_tag_valid) begin
                reg_tag_0 <= core_tag_out[127:96];
                reg_tag_1 <= core_tag_out[95:64];
                reg_tag_2 <= core_tag_out[63:32];
                reg_tag_3 <= core_tag_out[31:0];
            end

            // Set sticky done
            if (core_done)  r_status_done      <= 1'b1;
            if (dma_done)   r_status_dma_done  <= 1'b1;
            if (dma_error)  r_status_dma_error <= 1'b1;
        end
    end

    // =========================================================================
    // Read data mux (combinational — axi_read_channel samples on rd_req)
    // =========================================================================
    wire [31:0] status_word = {
        26'h0,
        r_status_dma_error, // [5]
        r_status_error,     // [4]
        r_status_dma_done,  // [3]
        dma_busy,           // [2]
        r_status_done,      // [1]
        core_busy           // [0]
    };

    // DMA_STATUS register (0x110) — sourced live from ascon_dma outputs
    wire [31:0] dma_status_word = {
        25'h0,
        dma_status_fifo_overflow, // [6]
        dma_status_wr_error,      // [5]
        dma_status_rd_error,      // [4]
        dma_status_wr_done,       // [3]
        dma_status_rd_done,       // [2]
        r_status_dma_done,        // [1] sticky DMA_DONE (same as STATUS[3])
        dma_busy                  // [0]
    };

    always @(*) begin
        case (rd_addr)
            ADDR_CTRL:        rd_data = {29'h0, reg_dma_en, 1'b0, 1'b0};
            ADDR_STATUS:      rd_data = status_word;
            ADDR_MODE:        rd_data = {30'h0, reg_mode};
            ADDR_IRQ_EN:      rd_data = {29'h0, reg_irq_en};
            // WO registers — reads return 0
            ADDR_KEY_0,
            ADDR_KEY_1,
            ADDR_KEY_2,
            ADDR_KEY_3,
            ADDR_NONCE_0,
            ADDR_NONCE_1,
            ADDR_NONCE_2,
            ADDR_NONCE_3,
            ADDR_PTEXT_0,
            ADDR_PTEXT_1:     rd_data = 32'h0;
            // RO result registers
            ADDR_CTEXT_0:     rd_data = reg_ctext_0;
            ADDR_CTEXT_1:     rd_data = reg_ctext_1;
            ADDR_TAG_0:       rd_data = reg_tag_0;
            ADDR_TAG_1:       rd_data = reg_tag_1;
            ADDR_TAG_2:       rd_data = reg_tag_2;
            ADDR_TAG_3:       rd_data = reg_tag_3;
            // DMA config registers
            ADDR_DMA_SRC:     rd_data = reg_dma_src;
            ADDR_DMA_DST:     rd_data = reg_dma_dst;
            ADDR_DMA_LEN:     rd_data = reg_dma_len;
            ADDR_DMA_CTRL:    rd_data = {28'h0, reg_dma_ctrl_mode, 1'b0, 1'b0}; // START/RST auto-clear
            ADDR_DMA_STATUS:  rd_data = dma_status_word;
            ADDR_DMA_BURST:   rd_data = {24'h0, reg_dma_burst};
            ADDR_DMA_ERR_ADDR:rd_data = dma_err_addr;   // live from ascon_dma
            // Unmapped
            default:          rd_data = 32'h0;
        endcase
    end

    // =========================================================================
    // Output wires to ascon_CORE
    // =========================================================================
    assign core_key      = {reg_key_0,   reg_key_1,   reg_key_2,   reg_key_3};
    assign core_nonce    = {reg_nonce_0, reg_nonce_1, reg_nonce_2, reg_nonce_3};
    // data_in: {PTEXT_0[63:32], PTEXT_1[31:0], 64'h0} — rate block at [127:64]
    assign core_data_in  = {reg_ptext_0, reg_ptext_1, 64'h0};
    assign core_data_len = 7'd8;
    assign core_enc_dec  = reg_mode[0];
    assign core_mode     = reg_mode;

    // =========================================================================
    // Output wires to ascon_dma
    // =========================================================================
    assign dma_src_addr  = reg_dma_src;
    assign dma_dst_addr  = reg_dma_dst;
    assign dma_length    = reg_dma_len;
    assign dma_en        = reg_dma_en;
    assign dma_burst_len = reg_dma_burst;
    assign dma_rd_only   = reg_dma_ctrl_mode[0];
    assign dma_wr_only   = reg_dma_ctrl_mode[1];

    // =========================================================================
    // IRQ_EN exposed for ascon_irq_ctrl (via parent top)
    // =========================================================================
    assign irq_en_bus = reg_irq_en;

endmodule