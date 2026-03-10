// ============================================================================
// Module  : ascon_ip_top
// Version : 1.0
//
// Description:
//   Top-level wrapper cho ASCON Crypto Accelerator IP.
//   Tích hợp 3 submodule:
//     - ascon_axi_slave  : AXI4-Lite slave (RISC-V CPU viết config/đọc kết quả)
//     - ascon_CORE       : ASCON crypto engine
//     - ascon_dma        : AXI4-Full master (DMA đọc/ghi DDR tự động)
//
// Topology:
//
//   CPU (AXI4-Lite Master)
//      │  S_AXI_* (32-bit, AXI4-Lite)
//      ▼
//   ┌─────────────────────┐
//   │   ascon_axi_slave   │◄──── irq ────► CPU (interrupt)
//   │   (AXI4-Lite slave) │
//   └──────┬──────────────┘
//          │  core_key, core_nonce, core_data_in,        (config wires)
//          │  core_enc_dec, core_mode, core_data_len,
//          │  core_start, core_soft_rst                  (control pulses)
//          │  ◄── core_busy, core_done,
//          │      core_data_out_valid, core_data_out,
//          │      core_tag_out, core_tag_valid            (status/results)
//          │
//          │  dma_src_addr, dma_dst_addr, dma_length,    (DMA config wires)
//          │  dma_en, dma_start, dma_soft_rst            (DMA control)
//          │  ◄── dma_busy, dma_done, dma_error          (DMA status)
//          │
//          ▼
//   ┌─────────────────────────────────────────────────┐
//   │               ascon_CORE                        │
//   │   (crypto engine: encrypt / decrypt / hash)     │
//   └─────────────────────────────────────────────────┘
//          ▲
//          │  (DMA mode: core_ptext/ctext/tag wires)
//          │
//   ┌──────┴──────────────┐
//   │    ascon_dma        │
//   │  (AXI4-Full master) │
//   └──────┬──────────────┘
//          │  M_AXI_* (64-bit, AXI4-Full)
//          ▼
//   DDR / Memory Crossbar
//
// ─────────────────────────────────────────────────────────────────────────────
// Hai chế độ hoạt động:
//
//   [1] CPU-Direct mode  (dma_en = 0):
//       CPU viết KEY/NONCE/PTEXT vào ascon_axi_slave → ghi CTRL.START →
//       ascon_CORE chạy encrypt → CPU đọc CTEXT/TAG từ slave registers.
//       ascon_dma không hoạt động.
//
//   [2] DMA mode (dma_en = 1):
//       CPU viết KEY/NONCE/DMA_SRC/DMA_DST/DMA_LEN → ghi CTRL.START|DMA_EN →
//       ascon_dma tự fetch plaintext từ DDR → đưa vào ascon_CORE →
//       lấy ctext+tag → ghi ra DDR.
//       CPU chờ interrupt (irq) hoặc poll STATUS.DONE.
//
// ─────────────────────────────────────────────────────────────────────────────
// Port naming:
//   S_AXI_*   : AXI4-Lite slave (từ CPU)
//   M_AXI_*   : AXI4-Full master (tới DDR, từ DMA engine)
//
// Parameters:
//   S_ADDR_WIDTH  : AXI4-Lite slave address width (default 32)
//   S_DATA_WIDTH  : AXI4-Lite slave data width    (default 32)
//   S_ID_WIDTH    : AXI4-Lite slave ID width       (default 4)
//   M_ADDR_WIDTH  : AXI4-Full master address width (default 32)
//   M_DATA_WIDTH  : AXI4-Full master data width    (default 64)
//   M_ID_WIDTH    : AXI4-Full master ID width      (default 4)
// ============================================================================

`include "ascon_accelerator/interface/ascon_axi_slave.v"
`include "ascon_accelerator/rtl/ascon_CORE.v"
`include "ascon_accelerator/dma/rtl/ascon_dma.v"

module ascon_ip_top #(
    // AXI4-Lite Slave parameters
    parameter S_ADDR_WIDTH = 32,
    parameter S_DATA_WIDTH = 32,
    parameter S_ID_WIDTH   = 4,
    // AXI4-Full Master parameters (DMA)
    parameter M_ADDR_WIDTH  = 32,
    parameter M_DATA_WIDTH  = 64,
    parameter M_ID_WIDTH    = 4,
    // DMA FIFO depths
    parameter RD_FIFO_DEPTH = 4,
    parameter WR_FIFO_DEPTH = 8
) (
    input  wire  clk,
    input  wire  rst_n,

    // =========================================================================
    // AXI4-Lite Slave Interface  (from CPU / RISC-V)
    // Base address: 0x2000_0000
    // =========================================================================

    // Write Address Channel
    input  wire [S_ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [S_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire                      S_AXI_AWVALID,
    output wire                      S_AXI_AWREADY,

    // Write Data Channel
    input  wire [S_DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [S_DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                      S_AXI_WVALID,
    output wire                      S_AXI_WREADY,

    // Write Response Channel
    output wire [S_ID_WIDTH-1:0]     S_AXI_BID,
    output wire [1:0]                S_AXI_BRESP,
    output wire                      S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    // Read Address Channel
    input  wire [S_ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [S_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire                      S_AXI_ARVALID,
    output wire                      S_AXI_ARREADY,

    // Read Data Channel
    output wire [S_ID_WIDTH-1:0]     S_AXI_RID,
    output wire [S_DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]                S_AXI_RRESP,
    output wire                      S_AXI_RLAST,
    output wire                      S_AXI_RVALID,
    input  wire                      S_AXI_RREADY,

    // =========================================================================
    // AXI4-Full Master Interface  (to DDR / memory crossbar, from DMA)
    // =========================================================================

    // Write Address Channel
    output wire [M_ID_WIDTH-1:0]       M_AXI_AWID,
    output wire [M_ADDR_WIDTH-1:0]     M_AXI_AWADDR,
    output wire [7:0]                  M_AXI_AWLEN,
    output wire [2:0]                  M_AXI_AWSIZE,
    output wire [1:0]                  M_AXI_AWBURST,
    output wire [3:0]                  M_AXI_AWCACHE,
    output wire [2:0]                  M_AXI_AWPROT,
    output wire                        M_AXI_AWVALID,
    input  wire                        M_AXI_AWREADY,

    // Write Data Channel
    output wire [M_DATA_WIDTH-1:0]     M_AXI_WDATA,
    output wire [M_DATA_WIDTH/8-1:0]   M_AXI_WSTRB,
    output wire                        M_AXI_WLAST,
    output wire                        M_AXI_WVALID,
    input  wire                        M_AXI_WREADY,

    // Write Response Channel
    input  wire [M_ID_WIDTH-1:0]       M_AXI_BID,
    input  wire [1:0]                  M_AXI_BRESP,
    input  wire                        M_AXI_BVALID,
    output wire                        M_AXI_BREADY,

    // Read Address Channel
    output wire [M_ID_WIDTH-1:0]       M_AXI_ARID,
    output wire [M_ADDR_WIDTH-1:0]     M_AXI_ARADDR,
    output wire [7:0]                  M_AXI_ARLEN,
    output wire [2:0]                  M_AXI_ARSIZE,
    output wire [1:0]                  M_AXI_ARBURST,
    output wire [3:0]                  M_AXI_ARCACHE,
    output wire [2:0]                  M_AXI_ARPROT,
    output wire                        M_AXI_ARVALID,
    input  wire                        M_AXI_ARREADY,

    // Read Data Channel
    input  wire [M_ID_WIDTH-1:0]       M_AXI_RID,
    input  wire [M_DATA_WIDTH-1:0]     M_AXI_RDATA,
    input  wire [1:0]                  M_AXI_RRESP,
    input  wire                        M_AXI_RLAST,
    input  wire                        M_AXI_RVALID,
    output wire                        M_AXI_RREADY,

    // =========================================================================
    // Interrupt output (to CPU interrupt controller)
    // =========================================================================
    output wire  irq
);

    // =========================================================================
    // Internal wires: ascon_axi_slave → ascon_CORE
    // =========================================================================

    // Config (static during operation)
    wire [127:0] slave_core_key;
    wire [127:0] slave_core_nonce;
    wire [127:0] slave_core_data_in;   // used in CPU-Direct mode
    wire [6:0]   slave_core_data_len;
    wire         slave_core_enc_dec;
    wire [1:0]   slave_core_mode;

    // Control pulses (1-cycle)
    wire         slave_core_start;
    wire         slave_core_soft_rst;

    // Status from CORE → slave
    wire         core_busy_w;
    wire         core_done_w;
    wire         core_data_out_valid_w;
    wire [127:0] core_data_out_w;
    wire [127:0] core_tag_out_w;
    wire         core_tag_valid_w;

    // =========================================================================
    // Internal wires: ascon_axi_slave → ascon_dma (control)
    // =========================================================================
    wire [31:0]  slave_dma_src_addr;
    wire [31:0]  slave_dma_dst_addr;
    wire [31:0]  slave_dma_length;
    wire         slave_dma_en;
    wire         slave_dma_start;
    wire         slave_dma_soft_rst;

    // Status from DMA → slave
    wire         dma_busy_w;
    wire         dma_done_w;
    wire         dma_error_w;

    // =========================================================================
    // Internal wires: ascon_dma → ascon_CORE (DMA mode data path)
    // =========================================================================
    // DMA pushes plaintext to CORE
    wire [31:0]  dma_core_ptext_0;
    wire [31:0]  dma_core_ptext_1;
    wire         dma_core_data_valid;
    wire         dma_core_data_ready;  // not used by current CORE, tie 1
    wire         dma_core_start;

    // CORE results → DMA captures
    wire [31:0]  core_dma_ctext_0;
    wire [31:0]  core_dma_ctext_1;
    wire [31:0]  core_dma_tag_0;
    wire [31:0]  core_dma_tag_1;
    wire [31:0]  core_dma_tag_2;
    wire [31:0]  core_dma_tag_3;

    // =========================================================================
    // core_start / core_data_in mux:
    //   - CPU-Direct mode (dma_en=0): slave drives core_start and data_in
    //   - DMA mode        (dma_en=1): dma drives core_start and data_in
    // =========================================================================
    wire         core_start_mux   = slave_dma_en ? dma_core_start   : slave_core_start;

    // data_in to CORE:
    //   slave provides {ptext_0, ptext_1, 64'h0} in CPU-Direct mode.
    //   In DMA mode, ascon_dma provides ptext via core_ptext_0/1 wires.
    //   We reconstruct the 128-bit word here.
    wire [127:0] core_data_in_mux = slave_dma_en
        ? {dma_core_ptext_0, dma_core_ptext_1, 64'h0}
        : slave_core_data_in;

    // data_last is always 1 for Phase 1 (single block)
    wire core_data_last = 1'b1;

    // ad_in / ad_valid / ad_last — not exposed in this integration
    // (Phase 1: no associated data)
    wire [127:0] core_ad_in    = 128'h0;
    wire         core_ad_valid = 1'b0;
    wire         core_ad_last  = 1'b1;

    // tag_received — only used for decryption tag check
    // Not exposed at top level in Phase 1; tie to zero
    wire [127:0] core_tag_received = 128'h0;

    // =========================================================================
    // Slice core_data_out for DMA capture
    // =========================================================================
    assign core_dma_ctext_0 = core_data_out_w[127:96];
    assign core_dma_ctext_1 = core_data_out_w[95:64];
    assign core_dma_tag_0   = core_tag_out_w[127:96];
    assign core_dma_tag_1   = core_tag_out_w[95:64];
    assign core_dma_tag_2   = core_tag_out_w[63:32];
    assign core_dma_tag_3   = core_tag_out_w[31:0];

    // DMA data_ready: CORE always ready to accept (no flow control in Phase 1)
    assign dma_core_data_ready = 1'b1;

    // =========================================================================
    // u_slave : ascon_axi_slave
    // =========================================================================
    ascon_axi_slave #(
        .ADDR_WIDTH (S_ADDR_WIDTH),
        .DATA_WIDTH (S_DATA_WIDTH),
        .ID_WIDTH   (S_ID_WIDTH)
    ) u_slave (
        .clk                (clk),
        .rst_n              (rst_n),

        // AXI4-Lite slave ports
        .S_AXI_AWID         (S_AXI_AWID),
        .S_AXI_AWADDR       (S_AXI_AWADDR),
        .S_AXI_AWPROT       (S_AXI_AWPROT),
        .S_AXI_AWVALID      (S_AXI_AWVALID),
        .S_AXI_AWREADY      (S_AXI_AWREADY),

        .S_AXI_WDATA        (S_AXI_WDATA),
        .S_AXI_WSTRB        (S_AXI_WSTRB),
        .S_AXI_WVALID       (S_AXI_WVALID),
        .S_AXI_WREADY       (S_AXI_WREADY),

        .S_AXI_BID          (S_AXI_BID),
        .S_AXI_BRESP        (S_AXI_BRESP),
        .S_AXI_BVALID       (S_AXI_BVALID),
        .S_AXI_BREADY       (S_AXI_BREADY),

        .S_AXI_ARID         (S_AXI_ARID),
        .S_AXI_ARADDR       (S_AXI_ARADDR),
        .S_AXI_ARPROT       (S_AXI_ARPROT),
        .S_AXI_ARVALID      (S_AXI_ARVALID),
        .S_AXI_ARREADY      (S_AXI_ARREADY),

        .S_AXI_RID          (S_AXI_RID),
        .S_AXI_RDATA        (S_AXI_RDATA),
        .S_AXI_RRESP        (S_AXI_RRESP),
        .S_AXI_RLAST        (S_AXI_RLAST),
        .S_AXI_RVALID       (S_AXI_RVALID),
        .S_AXI_RREADY       (S_AXI_RREADY),

        // → ascon_CORE config
        .core_key           (slave_core_key),
        .core_nonce         (slave_core_nonce),
        .core_data_in       (slave_core_data_in),
        .core_data_len      (slave_core_data_len),
        .core_enc_dec       (slave_core_enc_dec),
        .core_mode          (slave_core_mode),
        .core_start         (slave_core_start),
        .core_soft_rst      (slave_core_soft_rst),

        // ← ascon_CORE status
        .core_busy          (core_busy_w),
        .core_done          (core_done_w),
        .core_data_out_valid(core_data_out_valid_w),
        .core_data_out      (core_data_out_w),
        .core_tag_out       (core_tag_out_w),
        .core_tag_valid     (core_tag_valid_w),

        // → ascon_dma config
        .dma_src_addr       (slave_dma_src_addr),
        .dma_dst_addr       (slave_dma_dst_addr),
        .dma_length         (slave_dma_length),
        .dma_en             (slave_dma_en),
        .dma_start          (slave_dma_start),
        .dma_soft_rst       (slave_dma_soft_rst),

        // ← ascon_dma status
        .dma_busy           (dma_busy_w),
        .dma_done           (dma_done_w),
        .dma_error          (dma_error_w),

        // interrupt
        .irq                (irq)
    );

    // =========================================================================
    // u_core : ascon_CORE
    // =========================================================================
    ascon_CORE u_core (
        .clk              (clk),
        .rst_n            (rst_n),

        // start mux: slave (CPU-Direct) or DMA
        .start            (core_start_mux),

        // config always from slave registers
        .mode             (slave_core_mode),
        .enc_dec          (slave_core_enc_dec),
        .key_in           (slave_core_key),
        .nonce_in         (slave_core_nonce),

        // AD — Phase 1: no AD
        .ad_in            (core_ad_in),
        .ad_valid         (core_ad_valid),
        .ad_last          (core_ad_last),

        // data_in mux: slave (CPU-Direct) or DMA
        .data_in          (core_data_in_mux),
        .data_last        (core_data_last),
        .data_len         (slave_core_data_len),

        // tag check — Phase 1: not used
        .tag_received     (core_tag_received),

        // outputs → slave (for readback) and DMA (for write-back)
        .data_out         (core_data_out_w),
        .data_out_valid   (core_data_out_valid_w),
        .tag_out          (core_tag_out_w),
        .tag_valid        (core_tag_valid_w),
        .tag_match        (),    // not used in Phase 1
        .done             (core_done_w),
        .busy             (core_busy_w)
    );

    // =========================================================================
    // u_dma : ascon_dma
    // =========================================================================
    ascon_dma #(
        .ADDR_WIDTH     (M_ADDR_WIDTH),
        .AXI_DATA_WIDTH (M_DATA_WIDTH),
        .AXI_ID_WIDTH   (M_ID_WIDTH),
        .RD_FIFO_DEPTH  (RD_FIFO_DEPTH),
        .WR_FIFO_DEPTH  (WR_FIFO_DEPTH)
    ) u_dma (
        .clk                  (clk),
        .rst_n                (rst_n),

        // Control from slave registers
        .src_addr             (slave_dma_src_addr),
        .dst_addr             (slave_dma_dst_addr),
        .byte_len             (slave_dma_length),
        .burst_len            (8'd0),          // Phase 1: 1-beat burst (ARLEN=0)

        .dma_start            (slave_dma_start),
        .dma_soft_rst         (slave_dma_soft_rst),

        // Status → slave
        .dma_busy             (dma_busy_w),
        .dma_done             (dma_done_w),
        .dma_error            (dma_error_w),

        // Full status (not used at top level in Phase 1)
        .status_rd_done       (),
        .status_wr_done       (),
        .status_rd_error      (),
        .status_wr_error      (),
        .status_fifo_overflow (),
        .dma_err_addr         (),

        // → ascon_CORE (plaintext push)
        .core_ptext_0         (dma_core_ptext_0),
        .core_ptext_1         (dma_core_ptext_1),
        .core_data_valid      (dma_core_data_valid),
        .core_data_ready      (dma_core_data_ready),
        .core_start           (dma_core_start),
        .core_busy            (core_busy_w),
        .core_done            (core_done_w),

        // ← ascon_CORE (ctext + tag capture)
        .core_ctext_0         (core_dma_ctext_0),
        .core_ctext_1         (core_dma_ctext_1),
        .core_tag_0           (core_dma_tag_0),
        .core_tag_1           (core_dma_tag_1),
        .core_tag_2           (core_dma_tag_2),
        .core_tag_3           (core_dma_tag_3),

        // AXI4-Full Master
        .M_AXI_AWID           (M_AXI_AWID),
        .M_AXI_AWADDR         (M_AXI_AWADDR),
        .M_AXI_AWLEN          (M_AXI_AWLEN),
        .M_AXI_AWSIZE         (M_AXI_AWSIZE),
        .M_AXI_AWBURST        (M_AXI_AWBURST),
        .M_AXI_AWCACHE        (M_AXI_AWCACHE),
        .M_AXI_AWPROT         (M_AXI_AWPROT),
        .M_AXI_AWVALID        (M_AXI_AWVALID),
        .M_AXI_AWREADY        (M_AXI_AWREADY),

        .M_AXI_WDATA          (M_AXI_WDATA),
        .M_AXI_WSTRB          (M_AXI_WSTRB),
        .M_AXI_WLAST          (M_AXI_WLAST),
        .M_AXI_WVALID         (M_AXI_WVALID),
        .M_AXI_WREADY         (M_AXI_WREADY),

        .M_AXI_BID            (M_AXI_BID),
        .M_AXI_BRESP          (M_AXI_BRESP),
        .M_AXI_BVALID         (M_AXI_BVALID),
        .M_AXI_BREADY         (M_AXI_BREADY),

        .M_AXI_ARID           (M_AXI_ARID),
        .M_AXI_ARADDR         (M_AXI_ARADDR),
        .M_AXI_ARLEN          (M_AXI_ARLEN),
        .M_AXI_ARSIZE         (M_AXI_ARSIZE),
        .M_AXI_ARBURST        (M_AXI_ARBURST),
        .M_AXI_ARCACHE        (M_AXI_ARCACHE),
        .M_AXI_ARPROT         (M_AXI_ARPROT),
        .M_AXI_ARVALID        (M_AXI_ARVALID),
        .M_AXI_ARREADY        (M_AXI_ARREADY),

        .M_AXI_RID            (M_AXI_RID),
        .M_AXI_RDATA          (M_AXI_RDATA),
        .M_AXI_RRESP          (M_AXI_RRESP),
        .M_AXI_RLAST          (M_AXI_RLAST),
        .M_AXI_RVALID         (M_AXI_RVALID),
        .M_AXI_RREADY         (M_AXI_RREADY)
    );

endmodule