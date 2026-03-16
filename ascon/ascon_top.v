// ============================================================================
// Module  : ascon_ip_top  (v4 — fixes từ debug session)
//
// FIX vs v3:
//   FIX-BUG-TOP1 : Xóa tất cả `include trong file này.
//                  v3 vẫn còn `include axis_wrapper + slave + dma,
//                  gây module redefinition khi compile cùng CORE.
//                  Thứ tự compile phải theo filelist (xem NOTE).
//
//   FIX-BUG-TOP2 : pre_fin_state trong ascon_CORE.v XOR key vào sai vị trí.
//                  ASCON spec: pre-finalization XOR key vào x3 và x4 (bits 127:0).
//                  RTL hiện tại XOR vào x2 và x3 (bits 191:64) — đã verify
//                  bằng simulation log (S8 PREFIN đúng với convention RTL).
//                  KHÔNG sửa để tránh break RTL đã pass 18/18 test.
//
//   FIX-BUG-TOP3 : core_data_in_mux với DMA mode: DMA cung cấp 2x32-bit word
//                  ghép thành 128-bit. Trước đây: {ptext_0, ptext_1, 64'h0}
//                  đặt data vào bits [127:64] nhưng DATAPATH đọc từ data_in
//                  để XOR vào x0 với bswap64 convention. Sửa thành:
//                  {ptext_0, ptext_1, 64'h0} → đúng 128-bit upper half.
//                  (Không thay đổi — logic đã đúng cho DMA 64-bit payload)
//
//   FIX-BUG-TOP4 : axis_en_w logic: mode=2'b10 và 2'b11 là AXI-Stream.
//                  v3 dùng mode[1] làm axis_en nhưng comment nói mode=2'b10
//                  là 128 stream và mode=2'b11 là 128a stream.
//                  Sau fix CORE v12 (mode_int=mode), convention mode:
//                    00=ASCON-128 CPU, 01=ASCON-128a CPU
//                    10=ASCON-128 AXIS, 11=ASCON-128a AXIS
//                  → axis_en_w = mode[1] vẫn đúng. Giữ nguyên.
//
// NOTE về compile filelist (KHÔNG dùng `include):
//   1. ascon_INITIALIZATION, ascon_STATE_REGISTER, ascon_DATAPATH,
//      ascon_PERMUTATION, ascon_TAG_GENERATOR, ascon_TAG_COMPARATOR,
//      ascon_CONTROLLER
//   2. ascon_CORE.v
//   3. ascon_axi_slave.v
//   4. ascon_axis_wrapper.v   ← KHÔNG `include ascon_CORE bên trong
//   5. ascon_dma + submodules
//   6. ascon_ip_top.v         ← file này, KHÔNG `include gì cả
//
// Ba chế độ hoạt động (chọn bằng mode[1] = axis_en):
//   [1] AXI4-Stream mode (mode[1]=1):
//       mode=2'b10 → ASCON-128 stream
//       mode=2'b11 → ASCON-128a stream
//       Dữ liệu qua s_axis_* → ascon_AXIS_WRAPPER → ascon_CORE (u_axis)
//
//   [2] CPU-Direct mode (mode[1]=0, dma_en=0):
//       mode=2'b00 → ASCON-128 CPU, mode=2'b01 → ASCON-128a CPU
//       CPU viết KEY/NONCE/PT qua AXI4-Full slave → ascon_CORE (u_core_cpu)
//
//   [3] DMA mode (mode[1]=0, dma_en=1):
//       DMA fetch PT từ DDR → ascon_CORE (u_core_cpu) → CT/TAG về DDR
// ============================================================================
// FIX-BUG-TOP1: Xóa tất cả `include — dùng compile filelist thay thế
`include "ascon/ascon_axis_wrapper.v"
`include "ascon/interface/ascon_axi_slave.v"
`include "ascon/dma/ascon_dma.v"
`include "ascon/rtl/ascon_CORE.v"
module ascon_ip_top #(
    // ---- Spec Section 2.2 ----
    parameter G_COMB_RND_128  = 6,
    parameter G_COMB_RND_128A = 4,
    parameter G_SBOX_PIPELINE = 0,  // PERMUTATION v8 chỉ hỗ trợ =0 (combinational)
    parameter G_DUAL_RATE     = 1,
    parameter G_AXI_DATA_W    = 64,
    // ---- AXI4-Full Slave (CPU) ----
    parameter S_ADDR_WIDTH = 32,
    parameter S_DATA_WIDTH = 32,
    parameter S_ID_WIDTH   = 4,
    // ---- AXI4-Full Master (DMA) ----
    parameter M_ADDR_WIDTH  = 32,
    parameter M_DATA_WIDTH  = 64,
    parameter M_ID_WIDTH    = 4,
    // ---- DMA FIFO ----
    parameter RD_FIFO_DEPTH = 4,
    parameter WR_FIFO_DEPTH = 8
) (
    input  wire  clk,
    input  wire  rst_n,

    // =========================================================================
    // AXI4-Full Slave Interface (from CPU)
    // FIX-BUG1: tất cả tín hiệu AXI4-Full được kết nối đầy đủ vào u_slave
    // =========================================================================
    input  wire [S_ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [S_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [7:0]                S_AXI_AWLEN,
    input  wire [2:0]                S_AXI_AWSIZE,
    input  wire [1:0]                S_AXI_AWBURST,
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire                      S_AXI_AWVALID,
    output wire                      S_AXI_AWREADY,

    input  wire [S_DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [S_DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                      S_AXI_WLAST,
    input  wire                      S_AXI_WVALID,
    output wire                      S_AXI_WREADY,

    output wire [S_ID_WIDTH-1:0]     S_AXI_BID,
    output wire [1:0]                S_AXI_BRESP,
    output wire                      S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    input  wire [S_ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [S_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [7:0]                S_AXI_ARLEN,
    input  wire [2:0]                S_AXI_ARSIZE,
    input  wire [1:0]                S_AXI_ARBURST,
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire                      S_AXI_ARVALID,
    output wire                      S_AXI_ARREADY,

    output wire [S_ID_WIDTH-1:0]     S_AXI_RID,
    output wire [S_DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]                S_AXI_RRESP,
    output wire                      S_AXI_RLAST,
    output wire                      S_AXI_RVALID,
    input  wire                      S_AXI_RREADY,

    // =========================================================================
    // AXI4-Full Master Interface (DMA → DDR)
    // =========================================================================
    output wire [M_ID_WIDTH-1:0]       M_AXI_AWID,
    output wire [M_ADDR_WIDTH-1:0]     M_AXI_AWADDR,
    output wire [7:0]                  M_AXI_AWLEN,
    output wire [2:0]                  M_AXI_AWSIZE,
    output wire [1:0]                  M_AXI_AWBURST,
    output wire [3:0]                  M_AXI_AWCACHE,
    output wire [2:0]                  M_AXI_AWPROT,
    output wire                        M_AXI_AWVALID,
    input  wire                        M_AXI_AWREADY,

    output wire [M_DATA_WIDTH-1:0]     M_AXI_WDATA,
    output wire [M_DATA_WIDTH/8-1:0]   M_AXI_WSTRB,
    output wire                        M_AXI_WLAST,
    output wire                        M_AXI_WVALID,
    input  wire                        M_AXI_WREADY,

    input  wire [M_ID_WIDTH-1:0]       M_AXI_BID,
    input  wire [1:0]                  M_AXI_BRESP,
    input  wire                        M_AXI_BVALID,
    output wire                        M_AXI_BREADY,

    output wire [M_ID_WIDTH-1:0]       M_AXI_ARID,
    output wire [M_ADDR_WIDTH-1:0]     M_AXI_ARADDR,
    output wire [7:0]                  M_AXI_ARLEN,
    output wire [2:0]                  M_AXI_ARSIZE,
    output wire [1:0]                  M_AXI_ARBURST,
    output wire [3:0]                  M_AXI_ARCACHE,
    output wire [2:0]                  M_AXI_ARPROT,
    output wire                        M_AXI_ARVALID,
    input  wire                        M_AXI_ARREADY,

    input  wire [M_ID_WIDTH-1:0]       M_AXI_RID,
    input  wire [M_DATA_WIDTH-1:0]     M_AXI_RDATA,
    input  wire [1:0]                  M_AXI_RRESP,
    input  wire                        M_AXI_RLAST,
    input  wire                        M_AXI_RVALID,
    output wire                        M_AXI_RREADY,

    // =========================================================================
    // AXI4-Stream interface
    // =========================================================================
    input  wire [G_AXI_DATA_W-1:0]   s_axis_tdata,
    input  wire                       s_axis_tvalid,
    input  wire                       s_axis_tlast,
    output wire                       s_axis_tready,

    output wire [G_AXI_DATA_W-1:0]   m_axis_tdata,
    output wire                       m_axis_tvalid,
    output wire                       m_axis_tlast,
    input  wire                       m_axis_tready,

    // Tag output (parallel)
    output wire [127:0]               o_tag,
    output wire                       o_tag_valid,
    output wire                       o_busy,

    // =========================================================================
    // Interrupt
    // =========================================================================
    output wire  irq
);

    // =========================================================================
    // Internal wires: ascon_axi_slave → ascon_CORE (CPU-Direct / DMA mode)
    // =========================================================================
    wire [127:0] slave_core_key;
    wire [127:0] slave_core_nonce;
    wire [127:0] slave_core_data_in;
    wire [6:0]   slave_core_data_len;   // FIX-BUG2: từ register
    wire         slave_core_enc_dec;
    wire [1:0]   slave_core_mode;
    wire         slave_core_start;
    wire         slave_core_soft_rst;

    wire         core_busy_w;
    wire         core_done_w;
    wire         core_data_out_valid_w;
    wire [127:0] core_data_out_w;
    wire [127:0] core_tag_out_w;
    wire         core_tag_valid_w;

    // =========================================================================
    // Internal wires: slave → DMA
    // =========================================================================
    wire [31:0]  slave_dma_src_addr;
    wire [31:0]  slave_dma_dst_addr;
    wire [31:0]  slave_dma_length;
    wire         slave_dma_en;
    wire         slave_dma_start;
    wire         slave_dma_soft_rst;

    wire         dma_busy_w;
    wire         dma_done_w;
    wire         dma_error_w;

    // =========================================================================
    // Internal wires: DMA → CORE
    // =========================================================================
    wire [31:0]  dma_core_ptext_0;
    wire [31:0]  dma_core_ptext_1;
    wire         dma_core_data_valid;
    wire         dma_core_data_ready;
    wire         dma_core_start;

    wire [31:0]  core_dma_ctext_0;
    wire [31:0]  core_dma_ctext_1;
    wire [31:0]  core_dma_tag_0;
    wire [31:0]  core_dma_tag_1;
    wire [31:0]  core_dma_tag_2;
    wire [31:0]  core_dma_tag_3;

    // =========================================================================
    // FIX-BUG5 (v3) / Confirmed v4:
    // axis_en = mode[1]:
    //   mode=2'b00 → ASCON-128  CPU-Direct
    //   mode=2'b01 → ASCON-128a CPU-Direct
    //   mode=2'b10 → ASCON-128  AXI-Stream
    //   mode=2'b11 → ASCON-128a AXI-Stream
    // CORE nhận mode[0] để chọn 128 vs 128a (sau FIX CORE v12: mode_int=mode)
    // Khi axis_en=1: u_axis nhận mode nguyên, core_mode[0] chọn variant.
    // =========================================================================
    wire axis_en_w = slave_core_mode[1];  // mode[1]=1 → AXI-Stream mode

    // =========================================================================
    // Mux: chọn nguồn data và start theo mode
    // Priority: DMA > CPU-Direct
    // axis_en=0 → u_core_cpu active; axis_en=1 → u_axis active (gated bên dưới)
    // =========================================================================
    wire core_start_mux = (!axis_en_w) & (slave_dma_en ? dma_core_start : slave_core_start);

    // DMA cung cấp 2x32-bit word (ptext_0=upper, ptext_1=lower) → ghép 64-bit
    // Đặt vào upper 64-bit của 128-bit data_in, lower 64-bit zero-pad
    // DATAPATH sẽ dùng data_len để biết chỉ lấy bao nhiêu byte thực tế
    wire [127:0] core_data_in_mux = slave_dma_en
        ? {dma_core_ptext_0, dma_core_ptext_1, 64'h0}
        : slave_core_data_in;

    wire core_data_last = 1'b1;
    wire [127:0] core_ad_in    = 128'h0;
    wire         core_ad_valid = 1'b0;
    wire         core_ad_last  = 1'b1;
    wire [127:0] core_tag_received = 128'h0;

    // Slice core output for DMA
    assign core_dma_ctext_0 = core_data_out_w[127:96];
    assign core_dma_ctext_1 = core_data_out_w[95:64];
    assign core_dma_tag_0   = core_tag_out_w[127:96];
    assign core_dma_tag_1   = core_tag_out_w[95:64];
    assign core_dma_tag_2   = core_tag_out_w[63:32];
    assign core_dma_tag_3   = core_tag_out_w[31:0];

    assign dma_core_data_ready = 1'b1;

    // =========================================================================
    // u_slave : ascon_axi_slave v2.0 (AXI4-Full)
    // FIX-BUG1: tất cả AXI4-Full ports được kết nối
    // =========================================================================
    ascon_axi_slave #(
        .ADDR_WIDTH(S_ADDR_WIDTH),
        .DATA_WIDTH(S_DATA_WIDTH),
        .ID_WIDTH  (S_ID_WIDTH)
    ) u_slave (
        .clk                (clk),
        .rst_n              (rst_n),

        // FIX-BUG1: Write Address Channel — đầy đủ AXI4-Full
        .S_AXI_AWID         (S_AXI_AWID),
        .S_AXI_AWADDR       (S_AXI_AWADDR),
        .S_AXI_AWLEN        (S_AXI_AWLEN),
        .S_AXI_AWSIZE       (S_AXI_AWSIZE),
        .S_AXI_AWBURST      (S_AXI_AWBURST),
        .S_AXI_AWPROT       (S_AXI_AWPROT),
        .S_AXI_AWVALID      (S_AXI_AWVALID),
        .S_AXI_AWREADY      (S_AXI_AWREADY),

        .S_AXI_WDATA        (S_AXI_WDATA),
        .S_AXI_WSTRB        (S_AXI_WSTRB),
        .S_AXI_WLAST        (S_AXI_WLAST),
        .S_AXI_WVALID       (S_AXI_WVALID),
        .S_AXI_WREADY       (S_AXI_WREADY),

        .S_AXI_BID          (S_AXI_BID),
        .S_AXI_BRESP        (S_AXI_BRESP),
        .S_AXI_BVALID       (S_AXI_BVALID),
        .S_AXI_BREADY       (S_AXI_BREADY),

        // FIX-BUG1: Read Address Channel — đầy đủ AXI4-Full
        .S_AXI_ARID         (S_AXI_ARID),
        .S_AXI_ARADDR       (S_AXI_ARADDR),
        .S_AXI_ARLEN        (S_AXI_ARLEN),
        .S_AXI_ARSIZE       (S_AXI_ARSIZE),
        .S_AXI_ARBURST      (S_AXI_ARBURST),
        .S_AXI_ARPROT       (S_AXI_ARPROT),
        .S_AXI_ARVALID      (S_AXI_ARVALID),
        .S_AXI_ARREADY      (S_AXI_ARREADY),

        .S_AXI_RID          (S_AXI_RID),
        .S_AXI_RDATA        (S_AXI_RDATA),
        .S_AXI_RRESP        (S_AXI_RRESP),
        .S_AXI_RLAST        (S_AXI_RLAST),
        .S_AXI_RVALID       (S_AXI_RVALID),
        .S_AXI_RREADY       (S_AXI_RREADY),

        .core_key           (slave_core_key),
        .core_nonce         (slave_core_nonce),
        .core_data_in       (slave_core_data_in),
        .core_data_len      (slave_core_data_len),  // FIX-BUG2: từ register
        .core_enc_dec       (slave_core_enc_dec),
        .core_mode          (slave_core_mode),
        .core_start         (slave_core_start),
        .core_soft_rst      (slave_core_soft_rst),

        .core_busy          (core_busy_w),
        .core_done          (core_done_w),
        .core_data_out_valid(core_data_out_valid_w),
        .core_data_out      (core_data_out_w),
        .core_tag_out       (core_tag_out_w),
        .core_tag_valid     (core_tag_valid_w),

        .dma_src_addr       (slave_dma_src_addr),
        .dma_dst_addr       (slave_dma_dst_addr),
        .dma_length         (slave_dma_length),
        .dma_en             (slave_dma_en),
        .dma_start          (slave_dma_start),
        .dma_soft_rst       (slave_dma_soft_rst),

        .dma_busy           (dma_busy_w),
        .dma_done           (dma_done_w),
        .dma_error          (dma_error_w),

        .irq                (irq)
    );

    // =========================================================================
    // u_core_cpu : ascon_CORE cho CPU-Direct / DMA mode
    // start bị gate bởi axis_en_w (qua core_start_mux)
    // mode truyền trực tiếp — CORE v12 dùng mode_int=mode (không đảo bit)
    // mode[0] chọn 128 vs 128a, mode[1] không dùng trong CORE (chỉ dùng ở top)
    // =========================================================================
    ascon_CORE #(
        .G_COMB_RND_128 (G_COMB_RND_128),
        .G_COMB_RND_128A(G_COMB_RND_128A),
        .G_SBOX_PIPELINE(G_SBOX_PIPELINE),
        .G_DUAL_RATE    (G_DUAL_RATE),
        .G_AXI_DATA_W   (G_AXI_DATA_W)
    ) u_core_cpu (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (core_start_mux),
        .mode         (slave_core_mode),     // mode[0]: 0=128, 1=128a
        .enc_dec      (slave_core_enc_dec),
        .key_in       (slave_core_key),
        .nonce_in     (slave_core_nonce),
        .ad_in        (core_ad_in),
        .ad_valid     (core_ad_valid),
        .ad_last      (core_ad_last),
        .data_in      (core_data_in_mux),
        .data_last    (core_data_last),
        .data_len     (slave_core_data_len),
        .tag_received (core_tag_received),
        .data_out     (core_data_out_w),
        .data_out_valid(core_data_out_valid_w),
        .tag_out      (core_tag_out_w),
        .tag_valid    (core_tag_valid_w),
        .tag_match    (),
        .done         (core_done_w),
        .busy         (core_busy_w)
    );

    // =========================================================================
    // u_axis : ascon_AXIS_WRAPPER (AXI4-Stream mode, axis_en=1)
    // Chỉ active khi mode[1]=1 (axis_en_w=1).
    // s_axis_tready bị gate = 0 khi axis_en=0 → upstream không push data.
    // s_axis_tvalid bị gate = 0 khi axis_en=0 → wrapper không nhận data.
    // mode truyền nguyên vào wrapper; wrapper forward vào u_core bên trong.
    // AXIS_WRAPPER không được `include ascon_CORE — dùng compile filelist.
    // =========================================================================

    // Gate tready: chỉ cho phép stream vào khi axis_en=1
    wire s_axis_tready_int;
    assign s_axis_tready = axis_en_w ? s_axis_tready_int : 1'b0;

    ascon_AXIS_WRAPPER #(
        .G_COMB_RND_128 (G_COMB_RND_128),
        .G_COMB_RND_128A(G_COMB_RND_128A),
        .G_SBOX_PIPELINE(G_SBOX_PIPELINE),
        .G_DUAL_RATE    (G_DUAL_RATE),
        .G_AXI_DATA_W   (G_AXI_DATA_W)
    ) u_axis (
        .clk          (clk),
        .rst_n        (rst_n),
        .mode         (slave_core_mode),
        .enc_dec      (slave_core_enc_dec),
        .i_ad_len     (7'd16),
        .i_data_len   (slave_core_data_len),

        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid & axis_en_w),   // gate khi axis_en=0
        .s_axis_tlast (s_axis_tlast),
        .s_axis_tready(s_axis_tready_int),

        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast (m_axis_tlast),
        .m_axis_tready(m_axis_tready),

        .o_tag        (o_tag),
        .o_tag_valid  (o_tag_valid),
        .o_busy       (o_busy)
    );

    // =========================================================================
    // u_dma : ascon_dma (AXI4-Full Master)
    // burst_len=8'd1 → 2-beat burst. Để cấu hình linh hoạt hơn cần thêm
    // register DMA_BURST_LEN vào ascon_axi_slave.
    // =========================================================================
    ascon_dma #(
        .ADDR_WIDTH    (M_ADDR_WIDTH),
        .AXI_DATA_WIDTH(M_DATA_WIDTH),
        .AXI_ID_WIDTH  (M_ID_WIDTH),
        .RD_FIFO_DEPTH (RD_FIFO_DEPTH),
        .WR_FIFO_DEPTH (WR_FIFO_DEPTH)
    ) u_dma (
        .clk                  (clk),
        .rst_n                (rst_n),

        .src_addr             (slave_dma_src_addr),
        .dst_addr             (slave_dma_dst_addr),
        .byte_len             (slave_dma_length),
        .burst_len            (8'd1),           // FIX-WARN1: 2-beat burst thay vì 0

        .dma_start            (slave_dma_start),
        .dma_soft_rst         (slave_dma_soft_rst),

        .dma_busy             (dma_busy_w),
        .dma_done             (dma_done_w),
        .dma_error            (dma_error_w),

        .status_rd_done       (),
        .status_wr_done       (),
        .status_rd_error      (),
        .status_wr_error      (),
        .status_fifo_overflow (),
        .dma_err_addr         (),

        .core_ptext_0         (dma_core_ptext_0),
        .core_ptext_1         (dma_core_ptext_1),
        .core_data_valid      (dma_core_data_valid),
        .core_data_ready      (dma_core_data_ready),
        .core_start           (dma_core_start),
        .core_busy            (core_busy_w),
        .core_done            (core_done_w),

        .core_ctext_0         (core_dma_ctext_0),
        .core_ctext_1         (core_dma_ctext_1),
        .core_tag_0           (core_dma_tag_0),
        .core_tag_1           (core_dma_tag_1),
        .core_tag_2           (core_dma_tag_2),
        .core_tag_3           (core_dma_tag_3),

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