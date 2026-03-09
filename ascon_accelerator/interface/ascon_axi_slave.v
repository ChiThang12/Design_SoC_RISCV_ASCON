// ============================================================================
// Module  : ascon_axi_slave
// Project : ASCON Crypto Accelerator IP
// Version : 1.0
//
// Description:
//   AXI4-Lite Slave register interface for the ASCON accelerator IP.
//   Provides CPU access to control, status, key, nonce, plaintext,
//   ciphertext, tag, and DMA configuration registers.
//
// Register Map (base: 0x2000_0000):
//   0x000  CTRL      R/W   [0]=START [1]=SOFT_RST [2]=DMA_EN
//   0x004  STATUS    RO    [0]=BUSY  [1]=DONE [2]=DMA_BUSY [3]=DMA_DONE
//                          [4]=ERROR [5]=DMA_ERROR
//   0x008  MODE      R/W   [0]=ENC_DEC [1]=PERM_MODE
//   0x00C  IRQ_EN    R/W   [0]=DONE_IRQ_EN [1]=DMA_DONE_IRQ_EN [2]=ERROR_IRQ_EN
//   0x010  KEY_0     WO    Key[127:96]
//   0x014  KEY_1     WO    Key[95:64]
//   0x018  KEY_2     WO    Key[63:32]
//   0x01C  KEY_3     WO    Key[31:0]
//   0x020  NONCE_0   WO    Nonce[127:96]
//   0x024  NONCE_1   WO    Nonce[95:64]
//   0x028  NONCE_2   WO    Nonce[63:32]
//   0x02C  NONCE_3   WO    Nonce[31:0]
//   0x030  PTEXT_0   WO    Plaintext[63:32]
//   0x034  PTEXT_1   WO    Plaintext[31:0]
//   0x040  CTEXT_0   RO    Ciphertext[63:32]   (captured on core done)
//   0x044  CTEXT_1   RO    Ciphertext[31:0]
//   0x048  TAG_0     RO    Auth Tag[127:96]
//   0x04C  TAG_1     RO    Auth Tag[95:64]
//   0x050  TAG_2     RO    Auth Tag[63:32]
//   0x054  TAG_3     RO    Auth Tag[31:0]
//   0x100  DMA_SRC   R/W   DMA source address
//   0x104  DMA_DST   R/W   DMA destination address
//   0x108  DMA_LEN   R/W   DMA transfer length (bytes)
//
// Interface to ascon_CORE:
//   - key_in    [127:0] : concatenated from KEY_0..KEY_3
//   - nonce_in  [127:0] : concatenated from NONCE_0..NONCE_3
//   - data_in   [127:0] : {PTEXT_0, PTEXT_1, 64'h0} (zero-padded to 128-bit)
//   - enc_dec          : MODE[0]
//   - start            : pulse from CTRL[0]
//   - soft_rst         : pulse from CTRL[1]
//   data_out, tag_out, done, busy captured from core
//
// AXI4-Lite compliance:
//   - AWREADY / WREADY can be asserted simultaneously (single-cycle accept)
//   - BVALID held until BREADY
//   - RVALID held until RREADY
//   - All write address channels have AWID echoed back as BID
//   - All read  address channels have ARID echoed back as RID
//   - RLAST always 1 (Lite: single-beat only)
//
// Notes:
//   - SOFT_RST clears DONE, DMA_DONE flags but preserves KEY/NONCE/PTEXT registers
//   - Writing to RO registers is silently accepted (OKAY, data discarded)
//   - Writing to WO registers: data captured; reads return 32'h0
//   - START is ignored when BUSY=1
// ============================================================================

module ascon_axi_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // =========================================================================
    // AXI4-Lite Slave Interface
    // =========================================================================

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [2:0]              S_AXI_AWPROT,
    input  wire                    S_AXI_AWVALID,
    output reg                     S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WVALID,
    output reg                     S_AXI_WREADY,

    // Write Response Channel
    output reg  [ID_WIDTH-1:0]     S_AXI_BID,
    output reg  [1:0]              S_AXI_BRESP,
    output reg                     S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

    // Read Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [2:0]              S_AXI_ARPROT,
    input  wire                    S_AXI_ARVALID,
    output reg                     S_AXI_ARREADY,

    // Read Data Channel
    output reg  [ID_WIDTH-1:0]     S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output reg  [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,
    output reg                     S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    // =========================================================================
    // Interface to ascon_CORE
    // =========================================================================

    // Outputs to core
    output wire [127:0]            core_key,       // KEY_0..3 concatenated
    output wire [127:0]            core_nonce,     // NONCE_0..3 concatenated
    output wire [127:0]            core_data_in,   // {PTEXT_0, PTEXT_1, 64'h0}
    output wire [6:0]              core_data_len,  // always 7'd8 (1 block = 8 bytes)
    output wire                    core_enc_dec,   // MODE[0]
    output wire [1:0]              core_mode,      // MODE[1:0]
    output reg                     core_start,     // 1-cycle pulse
    output reg                     core_soft_rst,  // 1-cycle pulse

    // Inputs from core
    input  wire                    core_busy,
    input  wire                    core_done,
    input  wire                    core_data_out_valid,
    input  wire [127:0]            core_data_out,  // ciphertext (lower 64-bit used)
    input  wire [127:0]            core_tag_out,
    input  wire                    core_tag_valid,

    // =========================================================================
    // Interface to ascon_dma
    // =========================================================================

    output wire [31:0]             dma_src_addr,
    output wire [31:0]             dma_dst_addr,
    output wire [31:0]             dma_length,
    output wire                    dma_en,
    output reg                     dma_start,      // 1-cycle pulse
    output reg                     dma_soft_rst,   // 1-cycle pulse

    input  wire                    dma_busy,
    input  wire                    dma_done,
    input  wire                    dma_error,

    // =========================================================================
    // Interrupt Output
    // =========================================================================
    output wire                    irq
);

    // =========================================================================
    // Local address offset parameters (relative to base, bits [11:0])
    // =========================================================================
    localparam [11:0]
        ADDR_CTRL     = 12'h000,
        ADDR_STATUS   = 12'h004,
        ADDR_MODE     = 12'h008,
        ADDR_IRQ_EN   = 12'h00C,
        ADDR_KEY_0    = 12'h010,
        ADDR_KEY_1    = 12'h014,
        ADDR_KEY_2    = 12'h018,
        ADDR_KEY_3    = 12'h01C,
        ADDR_NONCE_0  = 12'h020,
        ADDR_NONCE_1  = 12'h024,
        ADDR_NONCE_2  = 12'h028,
        ADDR_NONCE_3  = 12'h02C,
        ADDR_PTEXT_0  = 12'h030,
        ADDR_PTEXT_1  = 12'h034,
        ADDR_CTEXT_0  = 12'h040,
        ADDR_CTEXT_1  = 12'h044,
        ADDR_TAG_0    = 12'h048,
        ADDR_TAG_1    = 12'h04C,
        ADDR_TAG_2    = 12'h050,
        ADDR_TAG_3    = 12'h054,
        ADDR_DMA_SRC  = 12'h100,
        ADDR_DMA_DST  = 12'h104,
        ADDR_DMA_LEN  = 12'h108;

    // =========================================================================
    // Internal Registers
    // =========================================================================

    // R/W registers
    reg [2:0]  reg_ctrl;       // [2]=DMA_EN [1]=SOFT_RST [0]=START
    reg [1:0]  reg_mode;       // [1]=PERM_MODE [0]=ENC_DEC
    reg [2:0]  reg_irq_en;     // [2]=ERROR_IRQ_EN [1]=DMA_DONE_IRQ_EN [0]=DONE_IRQ_EN

    // WO registers (reads return 0)
    reg [31:0] reg_key_0, reg_key_1, reg_key_2, reg_key_3;
    reg [31:0] reg_nonce_0, reg_nonce_1, reg_nonce_2, reg_nonce_3;
    reg [31:0] reg_ptext_0, reg_ptext_1;

    // RO sticky registers (captured from core)
    reg [31:0] reg_ctext_0, reg_ctext_1;
    reg [31:0] reg_tag_0, reg_tag_1, reg_tag_2, reg_tag_3;

    // DMA configuration registers
    reg [31:0] reg_dma_src, reg_dma_dst, reg_dma_len;

    // Status bits (sticky until SOFT_RST)
    reg        status_done;
    reg        status_dma_done;
    reg        status_error;
    reg        status_dma_error;

    // =========================================================================
    // Write channel — latch address and data independently, fire when both valid
    // =========================================================================

    reg [11:0]     wr_addr_lat;
    reg [ID_WIDTH-1:0] wr_id_lat;
    reg            wr_addr_valid;

    reg [31:0]     wr_data_lat;
    reg [3:0]      wr_strb_lat;
    reg            wr_data_valid;

    wire do_write = wr_addr_valid && wr_data_valid && (!S_AXI_BVALID || S_AXI_BREADY);

    // Accept write address
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_AWREADY  <= 1'b1;
            wr_addr_valid  <= 1'b0;
            wr_addr_lat    <= 12'h0;
            wr_id_lat      <= {ID_WIDTH{1'b0}};
        end else begin
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                wr_addr_lat   <= S_AXI_AWADDR[11:0];
                wr_id_lat     <= S_AXI_AWID;
                wr_addr_valid <= 1'b1;
                S_AXI_AWREADY <= 1'b0;
            end else if (do_write) begin
                wr_addr_valid <= 1'b0;
                S_AXI_AWREADY <= 1'b1;
            end
        end
    end

    // Accept write data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_WREADY  <= 1'b1;
            wr_data_valid <= 1'b0;
            wr_data_lat   <= 32'h0;
            wr_strb_lat   <= 4'h0;
        end else begin
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                wr_data_lat   <= S_AXI_WDATA;
                wr_strb_lat   <= S_AXI_WSTRB;
                wr_data_valid <= 1'b1;
                S_AXI_WREADY  <= 1'b0;
            end else if (do_write) begin
                wr_data_valid <= 1'b0;
                S_AXI_WREADY  <= 1'b1;
            end
        end
    end

    // Write response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_BVALID <= 1'b0;
            S_AXI_BRESP  <= 2'b00;
            S_AXI_BID    <= {ID_WIDTH{1'b0}};
        end else begin
            if (do_write) begin
                S_AXI_BVALID <= 1'b1;
                S_AXI_BRESP  <= 2'b00; // OKAY
                S_AXI_BID    <= wr_id_lat;
            end else if (S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Byte-enable helper: apply WSTRB to a 32-bit register word
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
    // Register Write Logic + core/dma pulse generation
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl    <= 3'h0;
            reg_mode    <= 2'h0;
            reg_irq_en  <= 3'h0;
            reg_key_0   <= 32'h0; reg_key_1 <= 32'h0;
            reg_key_2   <= 32'h0; reg_key_3 <= 32'h0;
            reg_nonce_0 <= 32'h0; reg_nonce_1 <= 32'h0;
            reg_nonce_2 <= 32'h0; reg_nonce_3 <= 32'h0;
            reg_ptext_0 <= 32'h0; reg_ptext_1 <= 32'h0;
            reg_dma_src <= 32'h0;
            reg_dma_dst <= 32'h0;
            reg_dma_len <= 32'h8; // default 8 bytes = 1 block

            core_start   <= 1'b0;
            core_soft_rst <= 1'b0;
            dma_start    <= 1'b0;
            dma_soft_rst <= 1'b0;
        end else begin
            // Default: clear 1-cycle pulses
            core_start    <= 1'b0;
            core_soft_rst <= 1'b0;
            dma_start     <= 1'b0;
            dma_soft_rst  <= 1'b0;

            if (do_write) begin
                case (wr_addr_lat)

                    // ----------------------------------------------------------
                    // CTRL (0x000)
                    // [0] START    — pulse core/dma start if not busy
                    // [1] SOFT_RST — pulse reset
                    // [2] DMA_EN   — sticky bit
                    // ----------------------------------------------------------
                    ADDR_CTRL: begin
                        if (wr_strb_lat[0]) begin
                            // SOFT_RST
                            if (wr_data_lat[1]) begin
                                core_soft_rst <= 1'b1;
                                dma_soft_rst  <= 1'b1;
                                reg_ctrl[1]   <= 1'b0;
                            end
                            // START — only when not busy
                            if (wr_data_lat[0] && !core_busy && !dma_busy) begin
                                core_start <= 1'b1;
                                if (wr_data_lat[2] || reg_ctrl[2])  // DMA_EN can come in same write
                                    dma_start <= 1'b1;
                            end
                            // DMA_EN: latch the bit
                            reg_ctrl[2] <= wr_data_lat[2];
                        end
                    end

                    // ----------------------------------------------------------
                    // MODE (0x008)
                    // ----------------------------------------------------------
                    ADDR_MODE: begin
                        if (wr_strb_lat[0])
                            reg_mode <= wr_data_lat[1:0];
                    end

                    // ----------------------------------------------------------
                    // IRQ_EN (0x00C)
                    // ----------------------------------------------------------
                    ADDR_IRQ_EN: begin
                        if (wr_strb_lat[0])
                            reg_irq_en <= wr_data_lat[2:0];
                    end

                    // ----------------------------------------------------------
                    // KEY registers (WO)
                    // ----------------------------------------------------------
                    ADDR_KEY_0: reg_key_0 <= apply_strb(reg_key_0, wr_data_lat, wr_strb_lat);
                    ADDR_KEY_1: reg_key_1 <= apply_strb(reg_key_1, wr_data_lat, wr_strb_lat);
                    ADDR_KEY_2: reg_key_2 <= apply_strb(reg_key_2, wr_data_lat, wr_strb_lat);
                    ADDR_KEY_3: reg_key_3 <= apply_strb(reg_key_3, wr_data_lat, wr_strb_lat);

                    // ----------------------------------------------------------
                    // NONCE registers (WO)
                    // ----------------------------------------------------------
                    ADDR_NONCE_0: reg_nonce_0 <= apply_strb(reg_nonce_0, wr_data_lat, wr_strb_lat);
                    ADDR_NONCE_1: reg_nonce_1 <= apply_strb(reg_nonce_1, wr_data_lat, wr_strb_lat);
                    ADDR_NONCE_2: reg_nonce_2 <= apply_strb(reg_nonce_2, wr_data_lat, wr_strb_lat);
                    ADDR_NONCE_3: reg_nonce_3 <= apply_strb(reg_nonce_3, wr_data_lat, wr_strb_lat);

                    // ----------------------------------------------------------
                    // PTEXT registers (WO)
                    // ----------------------------------------------------------
                    ADDR_PTEXT_0: reg_ptext_0 <= apply_strb(reg_ptext_0, wr_data_lat, wr_strb_lat);
                    ADDR_PTEXT_1: reg_ptext_1 <= apply_strb(reg_ptext_1, wr_data_lat, wr_strb_lat);

                    // ----------------------------------------------------------
                    // DMA config registers
                    // ----------------------------------------------------------
                    ADDR_DMA_SRC: reg_dma_src <= apply_strb(reg_dma_src, wr_data_lat, wr_strb_lat);
                    ADDR_DMA_DST: reg_dma_dst <= apply_strb(reg_dma_dst, wr_data_lat, wr_strb_lat);
                    ADDR_DMA_LEN: reg_dma_len <= apply_strb(reg_dma_len, wr_data_lat, wr_strb_lat);

                    // RO registers: accept silently (OKAY), ignore data
                    default: ; // CTEXT, TAG, STATUS — writes discarded

                endcase
            end
        end
    end

    // =========================================================================
    // Status register — sticky bits + capture ctext/tag on core done
    // =========================================================================

    wire do_soft_rst = core_soft_rst; // same cycle as write

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_done      <= 1'b0;
            status_dma_done  <= 1'b0;
            status_error     <= 1'b0;
            status_dma_error <= 1'b0;
            reg_ctext_0 <= 32'h0; reg_ctext_1 <= 32'h0;
            reg_tag_0   <= 32'h0; reg_tag_1   <= 32'h0;
            reg_tag_2   <= 32'h0; reg_tag_3   <= 32'h0;
        end else begin
            // SOFT_RST clears sticky done/error flags
            if (do_soft_rst) begin
                status_done      <= 1'b0;
                status_dma_done  <= 1'b0;
                status_error     <= 1'b0;
                status_dma_error <= 1'b0;
            end

            // Capture ciphertext + tag on the cycle core asserts data_out_valid
            if (core_data_out_valid) begin
                reg_ctext_0 <= core_data_out[127:96]; // upper 64-bit of data_out
                reg_ctext_1 <= core_data_out[95:64];
            end

            if (core_tag_valid) begin
                reg_tag_0 <= core_tag_out[127:96];
                reg_tag_1 <= core_tag_out[95:64];
                reg_tag_2 <= core_tag_out[63:32];
                reg_tag_3 <= core_tag_out[31:0];
            end

            // Latch done (sticky)
            if (core_done)
                status_done <= 1'b1;

            // DMA done (sticky)
            if (dma_done)
                status_dma_done <= 1'b1;

            // DMA error (sticky)
            if (dma_error)
                status_dma_error <= 1'b1;
        end
    end

    // STATUS word
    wire [31:0] status_word = {
        26'h0,
        status_dma_error,   // [5]
        status_error,       // [4]
        status_dma_done,    // [3]
        dma_busy,           // [2]
        status_done,        // [1]
        core_busy           // [0]
    };

    // =========================================================================
    // Read Channel
    // =========================================================================

    // Accept read address in one cycle, register for response
    reg [11:0]         rd_addr_lat;
    reg [ID_WIDTH-1:0] rd_id_lat;
    reg                rd_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_ARREADY <= 1'b1;
            rd_pending    <= 1'b0;
            rd_addr_lat   <= 12'h0;
            rd_id_lat     <= {ID_WIDTH{1'b0}};
        end else begin
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                rd_addr_lat   <= S_AXI_ARADDR[11:0];
                rd_id_lat     <= S_AXI_ARID;
                rd_pending    <= 1'b1;
                S_AXI_ARREADY <= 1'b0;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                rd_pending    <= 1'b0;
                S_AXI_ARREADY <= 1'b1;
            end
        end
    end

    // Register read data mux
    reg [31:0] rd_data_mux;

    always @(*) begin
        case (rd_addr_lat)
            ADDR_CTRL:    rd_data_mux = {29'h0, reg_ctrl};
            ADDR_STATUS:  rd_data_mux = status_word;
            ADDR_MODE:    rd_data_mux = {30'h0, reg_mode};
            ADDR_IRQ_EN:  rd_data_mux = {29'h0, reg_irq_en};
            // WO registers return 0
            ADDR_KEY_0,
            ADDR_KEY_1,
            ADDR_KEY_2,
            ADDR_KEY_3:   rd_data_mux = 32'h0;
            ADDR_NONCE_0,
            ADDR_NONCE_1,
            ADDR_NONCE_2,
            ADDR_NONCE_3: rd_data_mux = 32'h0;
            ADDR_PTEXT_0,
            ADDR_PTEXT_1: rd_data_mux = 32'h0;
            // RO result registers
            ADDR_CTEXT_0: rd_data_mux = reg_ctext_0;
            ADDR_CTEXT_1: rd_data_mux = reg_ctext_1;
            ADDR_TAG_0:   rd_data_mux = reg_tag_0;
            ADDR_TAG_1:   rd_data_mux = reg_tag_1;
            ADDR_TAG_2:   rd_data_mux = reg_tag_2;
            ADDR_TAG_3:   rd_data_mux = reg_tag_3;
            // DMA config
            ADDR_DMA_SRC: rd_data_mux = reg_dma_src;
            ADDR_DMA_DST: rd_data_mux = reg_dma_dst;
            ADDR_DMA_LEN: rd_data_mux = reg_dma_len;
            // Unmapped — return 0
            default:      rd_data_mux = 32'h0;
        endcase
    end

    // Drive read response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA  <= 32'h0;
            S_AXI_RRESP  <= 2'b00;
            S_AXI_RID    <= {ID_WIDTH{1'b0}};
        end else begin
            if (rd_pending && !S_AXI_RVALID) begin
                S_AXI_RVALID <= 1'b1;
                S_AXI_RDATA  <= rd_data_mux;
                S_AXI_RRESP  <= 2'b00; // OKAY
                S_AXI_RID    <= rd_id_lat;
            end else if (S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    // RLAST is always 1 for AXI4-Lite (single-beat only)
    assign S_AXI_RLAST = 1'b1;

    // =========================================================================
    // Output assignments to ascon_CORE
    // =========================================================================

    // Key: concatenate 4×32-bit → 128-bit [MSB first]
    assign core_key   = {reg_key_0,   reg_key_1,   reg_key_2,   reg_key_3};
    assign core_nonce = {reg_nonce_0, reg_nonce_1, reg_nonce_2, reg_nonce_3};

    // data_in: {PTEXT_0[63:32], PTEXT_1[31:0], 64'h0} — zero-pad to 128-bit
    // ascon_CORE uses data_in[127:64] as the rate block (x0 ^ plaintext)
    assign core_data_in  = {reg_ptext_0, reg_ptext_1, 64'h0};
    assign core_data_len = 7'd8;   // 1 block = 8 bytes (64-bit rate)
    assign core_enc_dec  = reg_mode[0];
    assign core_mode     = reg_mode;

    // =========================================================================
    // Output assignments to ascon_dma
    // =========================================================================

    assign dma_src_addr = reg_dma_src;
    assign dma_dst_addr = reg_dma_dst;
    assign dma_length   = reg_dma_len;
    assign dma_en       = reg_ctrl[2];

    // =========================================================================
    // Interrupt logic
    // Level-triggered, held until SOFT_RST clears the source flag
    // irq = (DONE & DONE_IRQ_EN) | (DMA_DONE & DMA_DONE_IRQ_EN) | (ERROR & ERROR_IRQ_EN)
    // =========================================================================

    assign irq = (status_done      & reg_irq_en[0]) |
                 (status_dma_done  & reg_irq_en[1]) |
                 (status_error     & reg_irq_en[2]) |
                 (status_dma_error & reg_irq_en[2]);

endmodule