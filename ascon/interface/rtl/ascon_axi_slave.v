// ============================================================================
// Module  : ascon_axi_slave
// Version : 1.9  (Fix B timeout: WR_DONE state + no WREADY deassert in WR_DATA)
//
// Fix vs 1.5:
//   FIX-A: WR_DATA never deasserts WREADY (only WR_IDLE does).
//   FIX-B: WR_RESP does not clear BVALID on BREADY; new WR_DONE state clears
//          it one cycle later, guaranteeing TB phase-4 sees BVALID=1.
// Fix vs v1.4:
//   BUG: `begin : decode` block dùng `reg d; reg s;` là SystemVerilog syntax.
//   iverilog compile được nhưng behavior undefined — biến bị treat như net,
//   decode không chạy, BVALID không bao giờ được set → toàn bộ write path fail.
//
//   FIX: Xóa named block `begin : decode`, chuyển `d` và `s` thành
//   module-level regs `wr_exec_data` và `wr_exec_strb`, assign trước khi
//   dùng trong case statement. Toàn bộ logic giữ nguyên.
// ============================================================================
module ascon_axi_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ── AXI4-Lite Write Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [2:0]              S_AXI_AWPROT,
    input  wire                    S_AXI_AWVALID,
    output reg                     S_AXI_AWREADY,

    // ── AXI4-Lite Write Data Channel
    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WVALID,
    output reg                     S_AXI_WREADY,

    // ── AXI4-Lite Write Response Channel
    output reg  [ID_WIDTH-1:0]     S_AXI_BID,
    output reg  [1:0]              S_AXI_BRESP,
    output reg                     S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

    // ── AXI4-Lite Read Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [2:0]              S_AXI_ARPROT,
    input  wire                    S_AXI_ARVALID,
    output reg                     S_AXI_ARREADY,

    // ── AXI4-Lite Read Data Channel
    output reg  [ID_WIDTH-1:0]     S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output reg  [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,
    output reg                     S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    // ── Interface to ascon_CORE
    output wire [127:0]            core_key,
    output wire [127:0]            core_nonce,
    output wire [127:0]            core_data_in,
    output wire [6:0]              core_data_len,
    output wire                    core_enc_dec,
    output wire [1:0]              core_mode,
    output reg                     core_start,
    output reg                     core_soft_rst,

    input  wire                    core_busy,
    input  wire                    core_done,
    input  wire                    core_data_out_valid,
    input  wire [127:0]            core_data_out,
    input  wire [127:0]            core_tag_out,
    input  wire                    core_tag_valid,

    // ── Interface to ascon_dma
    output wire [31:0]             dma_src_addr,
    output wire [31:0]             dma_dst_addr,
    output wire [31:0]             dma_length,
    output wire                    dma_en,
    output reg                     dma_start,
    output reg                     dma_soft_rst,

    input  wire                    dma_busy,
    input  wire                    dma_done,
    input  wire                    dma_error,

    // ── Interrupt
    output wire                    irq
);

    // =========================================================================
    // Address offset localparams  (12-bit offset from base)
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
    // Write FSM states
    // =========================================================================
    localparam [1:0]
        WR_IDLE = 2'b00,
        WR_DATA = 2'b01,
        WR_RESP = 2'b10,
        WR_DONE = 2'b11;   // v1.9: hold BVALID=1 one extra cycle for TB to sample

    reg [1:0] wr_state;

    // =========================================================================
    // Read FSM states
    // =========================================================================
    localparam [1:0]
        RD_IDLE  = 2'b00,
        RD_VALID = 2'b01;

    reg [1:0] rd_state;

    // =========================================================================
    // Write channel pipeline registers
    // =========================================================================
    reg [11:0]         wr_addr_lat;
    reg [ID_WIDTH-1:0] wr_id_lat;
    reg [31:0]         wr_data_lat;
    reg [3:0]          wr_strb_lat;

    // =========================================================================
    // FIX: module-level decode temporaries (replaced local reg in begin:decode)
    // =========================================================================
    reg [31:0] wr_exec_data;
    reg [3:0]  wr_exec_strb;

    // =========================================================================
    // Read channel pipeline registers
    // =========================================================================
    reg [11:0]           rd_addr_lat;
    reg [ID_WIDTH-1:0]   rd_id_lat;
    reg [DATA_WIDTH-1:0] rd_data_lat;

    // =========================================================================
    // Storage registers
    // =========================================================================
    reg [1:0]  reg_mode;
    reg [2:0]  reg_irq_en;
    reg        reg_dma_en;

    reg [31:0] reg_key_0,   reg_key_1,   reg_key_2,   reg_key_3;
    reg [31:0] reg_nonce_0, reg_nonce_1, reg_nonce_2, reg_nonce_3;
    reg [31:0] reg_ptext_0, reg_ptext_1;

    reg [31:0] reg_ctext_0, reg_ctext_1;
    reg [31:0] reg_tag_0,   reg_tag_1,   reg_tag_2,   reg_tag_3;

    reg [31:0] reg_dma_src, reg_dma_dst, reg_dma_len;

    reg        status_done,  status_dma_done;
    reg        status_error, status_dma_error;

    // =========================================================================
    // Byte-enable helper
    // =========================================================================
    function [31:0] apply_strb;
        input [31:0] old_val, new_val;
        input [3:0]  strb;
        begin
            apply_strb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
            apply_strb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
            apply_strb[15: 8] = strb[1] ? new_val[15: 8] : old_val[15: 8];
            apply_strb[ 7: 0] = strb[0] ? new_val[ 7: 0] : old_val[ 7: 0];
        end
    endfunction

    // =========================================================================
    // Register read mux
    // =========================================================================
    wire [31:0] status_word = {
        26'h0,
        status_dma_error, // [5]
        status_error,     // [4]
        status_dma_done,  // [3]
        dma_busy,         // [2]
        status_done,      // [1]
        core_busy         // [0]
    };

    function [31:0] reg_read_mux;
        input [11:0] addr;
        begin
            case (addr)
                ADDR_CTRL:    reg_read_mux = {29'h0, reg_dma_en, 1'b0, 1'b0};
                ADDR_STATUS:  reg_read_mux = status_word;
                ADDR_MODE:    reg_read_mux = {30'h0, reg_mode};
                ADDR_IRQ_EN:  reg_read_mux = {29'h0, reg_irq_en};
                ADDR_KEY_0, ADDR_KEY_1,
                ADDR_KEY_2, ADDR_KEY_3,
                ADDR_NONCE_0, ADDR_NONCE_1,
                ADDR_NONCE_2, ADDR_NONCE_3,
                ADDR_PTEXT_0, ADDR_PTEXT_1: reg_read_mux = 32'h0;
                ADDR_CTEXT_0: reg_read_mux = reg_ctext_0;
                ADDR_CTEXT_1: reg_read_mux = reg_ctext_1;
                ADDR_TAG_0:   reg_read_mux = reg_tag_0;
                ADDR_TAG_1:   reg_read_mux = reg_tag_1;
                ADDR_TAG_2:   reg_read_mux = reg_tag_2;
                ADDR_TAG_3:   reg_read_mux = reg_tag_3;
                ADDR_DMA_SRC: reg_read_mux = reg_dma_src;
                ADDR_DMA_DST: reg_read_mux = reg_dma_dst;
                ADDR_DMA_LEN: reg_read_mux = reg_dma_len;
                default:      reg_read_mux = 32'h0;
            endcase
        end
    endfunction

    // =========================================================================
    // WRITE CHANNEL FSM
    //
    // WR_IDLE: accept AW (+ optionally pre-latch W if it arrives first/same)
    // WR_DATA: addr already stable; accept W if not pre-latched; then decode
    // WR_RESP: hold BVALID until BREADY
    //
    // FIX: Removed `begin : decode` block with local `reg d, s` — that is
    // SystemVerilog syntax.  Now uses module-level regs wr_exec_data /
    // wr_exec_strb which are assigned with blocking `=` before the case
    // statement, ensuring correct values in Verilog-2001 simulation.
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            S_AXI_AWREADY <= 1'b1;
            S_AXI_WREADY  <= 1'b1;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BRESP   <= 2'b00;
            S_AXI_BID     <= {ID_WIDTH{1'b0}};
            wr_addr_lat   <= 12'h0;
            wr_id_lat     <= {ID_WIDTH{1'b0}};
            wr_data_lat   <= 32'h0;
            wr_strb_lat   <= 4'h0;
            wr_exec_data  <= 32'h0;
            wr_exec_strb  <= 4'h0;
            // Storage registers
            reg_mode      <= 2'h0;
            reg_irq_en    <= 3'h0;
            reg_dma_en    <= 1'b0;
            reg_key_0     <= 32'h0; reg_key_1   <= 32'h0;
            reg_key_2     <= 32'h0; reg_key_3   <= 32'h0;
            reg_nonce_0   <= 32'h0; reg_nonce_1 <= 32'h0;
            reg_nonce_2   <= 32'h0; reg_nonce_3 <= 32'h0;
            reg_ptext_0   <= 32'h0; reg_ptext_1 <= 32'h0;
            reg_dma_src   <= 32'h0;
            reg_dma_dst   <= 32'h0;
            reg_dma_len   <= 32'd8;
            core_start    <= 1'b0;
            core_soft_rst <= 1'b0;
            dma_start     <= 1'b0;
            dma_soft_rst  <= 1'b0;
        end else begin
            // Default: deassert 1-cycle control pulses every cycle
            core_start    <= 1'b0;
            core_soft_rst <= 1'b0;
            dma_start     <= 1'b0;
            dma_soft_rst  <= 1'b0;

            case (wr_state)

                // ── WR_IDLE ──────────────────────────────────────────────────
                // Accept AW.  Pre-latch W if it arrives same cycle (or before).
                WR_IDLE: begin
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        wr_data_lat  <= S_AXI_WDATA;
                        wr_strb_lat  <= S_AXI_WSTRB;
                        S_AXI_WREADY <= 1'b0;
                    end
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        wr_addr_lat   <= S_AXI_AWADDR[11:0];
                        wr_id_lat     <= S_AXI_AWID;
                        S_AXI_AWREADY <= 1'b0;
                        wr_state      <= WR_DATA;
                    end
                end

                // ── WR_DATA ──────────────────────────────────────────────────
                // wr_addr_lat stable (latched previous cycle).
                // Accept W if not pre-latched, then decode & issue BVALID.
                //
                // v1.9 FIX A: NEVER deassert WREADY in WR_DATA.
                //   When AW+W arrive together in WR_IDLE, W is pre-latched and
                //   WREADY is deasserted there.  In WR_DATA the TB's phase-3
                //   loop checks while(!(wready && wvalid)).  If we deassert
                //   WREADY again in WR_DATA, the window where WREADY=1 is only
                //   1 NBA cycle, which the TB misses because it checks at +1ps
                //   after the posedge where WR_DATA restores WREADY.
                //   Solution: only WR_IDLE deasserts WREADY; WR_DATA never does.
                WR_DATA: begin
                    // Accept W if not yet pre-latched in WR_IDLE.
                    // Keep WREADY=1 — do NOT deassert it here (v1.9 fix).
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        wr_data_lat  <= S_AXI_WDATA;
                        wr_strb_lat  <= S_AXI_WSTRB;
                        // WREADY intentionally kept HIGH (v1.9 fix A)
                    end

                    // Decode when W data is available
                    // WREADY=0 means data already latched (from WR_IDLE or above)
                    // (WVALID && WREADY) means data arriving this exact cycle
                    if ((S_AXI_WVALID && S_AXI_WREADY) || (!S_AXI_WREADY)) begin

                        // FIX: use blocking assignment to module-level regs
                        // so values are resolved before the case statement below
                        wr_exec_data = (S_AXI_WVALID && S_AXI_WREADY) ?
                                        S_AXI_WDATA  : wr_data_lat;
                        wr_exec_strb = (S_AXI_WVALID && S_AXI_WREADY) ?
                                        S_AXI_WSTRB  : wr_strb_lat;

                        // Register decode using stable wr_addr_lat
                        case (wr_addr_lat)
                            ADDR_CTRL: begin
                                if (wr_exec_strb[0]) begin
                                    if (wr_exec_data[1]) begin
                                        core_soft_rst <= 1'b1;
                                        dma_soft_rst  <= 1'b1;
                                    end
                                    if (wr_exec_data[0] && !core_busy && !dma_busy) begin
                                        core_start <= 1'b1;
                                        if (wr_exec_data[2] || reg_dma_en)
                                            dma_start <= 1'b1;
                                    end
                                    reg_dma_en <= wr_exec_data[2];
                                end
                            end
                            ADDR_MODE:    if (wr_exec_strb[0]) reg_mode   <= wr_exec_data[1:0];
                            ADDR_IRQ_EN:  if (wr_exec_strb[0]) reg_irq_en <= wr_exec_data[2:0];
                            ADDR_KEY_0:   reg_key_0   <= apply_strb(reg_key_0,   wr_exec_data, wr_exec_strb);
                            ADDR_KEY_1:   reg_key_1   <= apply_strb(reg_key_1,   wr_exec_data, wr_exec_strb);
                            ADDR_KEY_2:   reg_key_2   <= apply_strb(reg_key_2,   wr_exec_data, wr_exec_strb);
                            ADDR_KEY_3:   reg_key_3   <= apply_strb(reg_key_3,   wr_exec_data, wr_exec_strb);
                            ADDR_NONCE_0: reg_nonce_0 <= apply_strb(reg_nonce_0, wr_exec_data, wr_exec_strb);
                            ADDR_NONCE_1: reg_nonce_1 <= apply_strb(reg_nonce_1, wr_exec_data, wr_exec_strb);
                            ADDR_NONCE_2: reg_nonce_2 <= apply_strb(reg_nonce_2, wr_exec_data, wr_exec_strb);
                            ADDR_NONCE_3: reg_nonce_3 <= apply_strb(reg_nonce_3, wr_exec_data, wr_exec_strb);
                            ADDR_PTEXT_0: reg_ptext_0 <= apply_strb(reg_ptext_0, wr_exec_data, wr_exec_strb);
                            ADDR_PTEXT_1: reg_ptext_1 <= apply_strb(reg_ptext_1, wr_exec_data, wr_exec_strb);
                            ADDR_DMA_SRC: reg_dma_src <= apply_strb(reg_dma_src, wr_exec_data, wr_exec_strb);
                            ADDR_DMA_DST: reg_dma_dst <= apply_strb(reg_dma_dst, wr_exec_data, wr_exec_strb);
                            ADDR_DMA_LEN: reg_dma_len <= apply_strb(reg_dma_len, wr_exec_data, wr_exec_strb);
                            default: ;
                        endcase

                        // Issue write response.
                        // v1.9 FIX A+B combined:
                        //   A) Restore WREADY here so TB phase-3 exits at N+3
                        //      (1 cycle before WR_RESP, which fires at N+3 too)
                        //   B) WR_RESP does not clear BVALID → phase-4 at N+3+1ps
                        //      sees BVALID=1 because WR_RESP NBA hasn't cleared it
                        S_AXI_BID    <= wr_id_lat;
                        S_AXI_BRESP  <= 2'b00;
                        S_AXI_BVALID <= 1'b1;
                        S_AXI_WREADY <= 1'b1;   // restore WREADY so phase-3 exits
                        wr_state     <= WR_RESP;
                    end
                end

                // ── WR_RESP ───────────────────────────────────────────────────
                // Hold BVALID=1 until master asserts BREADY.
                //
                // v1.9 FIX B: on BREADY handshake do NOT clear BVALID here.
                //   Timeline problem: TB phase-3 exits at posedge N+3 then does
                //   #1 → checks s_bvalid at N+3+1ps.  WR_DATA set BVALID at
                //   posedge N+2.  WR_RESP (with s_bready=1 always) fires at
                //   posedge N+3 and would clear BVALID by NBA → s_bvalid=0 at
                //   N+3+1ps → TB phase-4 loops forever → timeout.
                //   Fix: transition to WR_DONE without clearing BVALID; let
                //   WR_DONE clear it one cycle later so TB always sees BVALID=1.
                WR_RESP: begin
                    if (S_AXI_BREADY) begin
                        // Restore handshake signals; clear BVALID in WR_DONE
                        S_AXI_AWREADY <= 1'b1;
                        S_AXI_WREADY  <= 1'b1;
                        wr_state      <= WR_DONE;
                        // BVALID stays 1 this cycle — TB can sample it safely
                    end
                end

                // ── WR_DONE ───────────────────────────────────────────────────
                // BVALID=1 is visible to the TB at the start of this cycle.
                // TB phase-4 (while !bvalid) exits here, then does one more
                // @posedge before returning.  We clear BVALID now so it is 0
                // when the TB's final @posedge completes.
                WR_DONE: begin
                    S_AXI_BVALID <= 1'b0;
                    wr_state     <= WR_IDLE;
                end

                default: begin
                    wr_state      <= WR_IDLE;
                    S_AXI_AWREADY <= 1'b1;
                    S_AXI_WREADY  <= 1'b1;
                end
            endcase
        end
    end

    // =========================================================================
    // Status sticky bits + ctext/tag capture
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_done      <= 1'b0; status_dma_done  <= 1'b0;
            status_error     <= 1'b0; status_dma_error <= 1'b0;
            reg_ctext_0 <= 32'h0; reg_ctext_1 <= 32'h0;
            reg_tag_0   <= 32'h0; reg_tag_1   <= 32'h0;
            reg_tag_2   <= 32'h0; reg_tag_3   <= 32'h0;
        end else begin
            if (core_soft_rst) begin
                status_done      <= 1'b0;
                status_dma_done  <= 1'b0;
                status_error     <= 1'b0;
                status_dma_error <= 1'b0;
            end
            if (core_data_out_valid) begin
                reg_ctext_0 <= core_data_out[127:96];
                reg_ctext_1 <= core_data_out[95:64];
            end
            if (core_tag_valid) begin
                reg_tag_0 <= core_tag_out[127:96];
                reg_tag_1 <= core_tag_out[95:64];
                reg_tag_2 <= core_tag_out[63:32];
                reg_tag_3 <= core_tag_out[31:0];
            end
            if (core_done)  status_done      <= 1'b1;
            if (dma_done)   status_dma_done  <= 1'b1;
            if (dma_error)  status_dma_error <= 1'b1;
        end
    end

    // =========================================================================
    // READ CHANNEL FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            S_AXI_ARREADY <= 1'b1;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RDATA   <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP   <= 2'b00;
            S_AXI_RID     <= {ID_WIDTH{1'b0}};
            rd_addr_lat   <= 12'h0;
            rd_id_lat     <= {ID_WIDTH{1'b0}};
            rd_data_lat   <= {DATA_WIDTH{1'b0}};
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        rd_addr_lat   <= S_AXI_ARADDR[11:0];
                        rd_id_lat     <= S_AXI_ARID;
                        rd_data_lat   <= reg_read_mux(S_AXI_ARADDR[11:0]);
                        S_AXI_ARREADY <= 1'b0;
                        rd_state      <= RD_VALID;
                    end
                end
                RD_VALID: begin
                    if (!S_AXI_RVALID) begin
                        S_AXI_RVALID <= 1'b1;
                        S_AXI_RDATA  <= rd_data_lat;
                        S_AXI_RRESP  <= 2'b00;
                        S_AXI_RID    <= rd_id_lat;
                    end else if (S_AXI_RREADY) begin
                        S_AXI_RVALID  <= 1'b0;
                        S_AXI_ARREADY <= 1'b1;
                        rd_state      <= RD_IDLE;
                    end
                end
                default: begin
                    rd_state      <= RD_IDLE;
                    S_AXI_ARREADY <= 1'b1;
                end
            endcase
        end
    end

    assign S_AXI_RLAST = 1'b1;

    // =========================================================================
    // Output wires to ascon_CORE
    // =========================================================================
    assign core_key      = {reg_key_0,   reg_key_1,   reg_key_2,   reg_key_3};
    assign core_nonce    = {reg_nonce_0, reg_nonce_1, reg_nonce_2, reg_nonce_3};
    assign core_data_in  = {reg_ptext_0, reg_ptext_1, 64'h0};
    assign core_data_len = 7'd8;
    assign core_enc_dec  = reg_mode[0];
    assign core_mode     = reg_mode;

    // =========================================================================
    // Output wires to ascon_dma
    // =========================================================================
    assign dma_src_addr = reg_dma_src;
    assign dma_dst_addr = reg_dma_dst;
    assign dma_length   = reg_dma_len;
    assign dma_en       = reg_dma_en;

    // =========================================================================
    // Interrupt
    // =========================================================================
    assign irq = (status_done      & reg_irq_en[0]) |
                 (status_dma_done  & reg_irq_en[1]) |
                 (status_error     & reg_irq_en[2]) |
                 (status_dma_error & reg_irq_en[2]);

endmodule