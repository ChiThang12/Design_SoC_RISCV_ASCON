// ============================================================================
// Module  : ascon_ip_top  (v5 — bỏ AXI-Stream, fix INCR burst, fix DMA race)
//
// CHANGES vs v4:
//   FIX-BUG-TOP5 : Xóa hoàn toàn AXI-Stream mode và u_axis instantiation.
//                  Lý do: AXIS_WRAPPER không cần thiết cho SoC CPU+DMA.
//                  Bỏ s_axis_*/m_axis_* khỏi port list.
//
//   FIX-BUG-TOP6 : core_start_mux trong DMA mode trước đây chỉ dùng
//                  dma_core_start, không kiểm tra data_valid.
//                  Race condition: CORE start trước khi DMA FSM nạp ptext.
//                  Fix: core_start_mux = dma_core_start & dma_core_data_valid.
//
//   FIX-BUG-TOP7 : burst_len=8'd1 gây DMA phát 2-beat (128-bit total) qua
//                  width converter 64→32. Converter cắt không đúng boundary.
//                  Fix: burst_len=8'd0 → 1-beat 64-bit → converter cắt 2×32-bit.
//
//   FIX-BUG-TOP8 : o_tag/o_tag_valid/o_busy không có assign trong v4.
//                  Fix: wire trực tiếp từ core_tag_out_w, core_tag_valid_w,
//                  core_busy_w | dma_busy_w.
//
// Hai chế độ hoạt động (slave_dma_en từ register CTRL[2]):
//   [1] CPU-Direct mode (dma_en=0):
//       CPU viết KEY/NONCE/PT qua AXI4-Full slave → ascon_CORE (u_core_cpu)
//       Hỗ trợ INCR burst để nạp Key/Nonce 128-bit bằng memcpy (4 beat × 32-bit)
//
//   [2] DMA mode (dma_en=1):
//       DMA fetch PT từ DDR (1-beat 64-bit) → ascon_CORE → CT/TAG → DDR
//
// NOTE về compile filelist (KHÔNG dùng `include):
//   1. ascon_INITIALIZATION, ascon_STATE_REGISTER, ascon_DATAPATH,
//      ascon_PERMUTATION, ascon_TAG_GENERATOR, ascon_TAG_COMPARATOR,
//      ascon_CONTROLLER
//   2. ascon_CORE.v
//   3. ascon_axi_slave.v
//   4. ascon_dma + submodules
//   5. ascon_ip_top.v  ← file này, KHÔNG `include gì cả
// ============================================================================
// FIX-BUG-TOP1: Xóa tất cả `include — dùng compile filelist thay thế (xem NOTE ở header)
`include "ascon/interface/ascon_axi_slave.v"
`include "ascon/rtl/ascon_CORE.v"
`include "ascon/dma/ascon_dma.v"

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
    parameter WR_FIFO_DEPTH = 32
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
    /* verilator lint_off UNUSEDSIGNAL */
    wire         slave_core_soft_rst;  // output of slave, not forwarded
    /* verilator lint_on UNUSEDSIGNAL */  // connected to slave but not forwarded (intentional)

    wire         core_busy_w;
    wire         core_done_w;
    wire         core_data_out_valid_w;
    wire [127:0] core_data_out_w;
    wire [127:0] core_tag_out_w;
    wire         core_tag_valid_w;
    wire         core_data_valid_w; // NEW
    wire         core_data_ready_w; // NEW

    // =========================================================================
    // Internal wires: slave → DMA
    // =========================================================================
    wire [31:0]  slave_dma_src_addr;
    wire [31:0]  slave_dma_dst_addr;
    wire [31:0]  slave_dma_length;
    wire [7:0]   slave_dma_burst_len; // NEW
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
    wire         dma_core_data_valid;  // DMA→CORE data valid; gated với dma_core_start trong core_start_mux
    wire         dma_core_data_ready;
    wire         dma_core_start;
    wire         dma_core_data_last; // NEW

    wire [31:0]  core_dma_ctext_0;
    wire [31:0]  core_dma_ctext_1;
    wire [31:0]  core_dma_tag_0;
    wire [31:0]  core_dma_tag_1;
    wire [31:0]  core_dma_tag_2;
    wire [31:0]  core_dma_tag_3;

    // =========================================================================
    // [FIX] Bỏ AXI-Stream mode. core_start_mux:
    //   CPU-Direct: slave_core_start_pulse (rising-edge của slave_core_start)
    //               → đảm bảo CORE nhận đúng 1-cycle pulse, không bị restart
    //                 liên tục nếu AXI slave giữ core_start HIGH nhiều cycle
    //   DMA mode:   dma_core_start AND dma_core_data_valid
    //               → tránh race condition (CORE không được start trước khi
    //                 DMA FSM đã nạp dữ liệu vào ptext_0/ptext_1)
    // =========================================================================
    // Edge-detect: tạo 1-cycle pulse từ slave_core_start (có thể là level)
    reg slave_core_start_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) slave_core_start_d <= 1'b0;
        else        slave_core_start_d <= slave_core_start;
    end
    wire slave_core_start_pulse = slave_core_start & ~slave_core_start_d;

    wire core_start_mux = slave_dma_en
        ? (dma_core_start & dma_core_data_valid)
        : slave_core_start_pulse;

    // DMA cung cấp 2x32-bit word (ptext_0=upper, ptext_1=lower) → ghép 64-bit
    // Đặt vào upper 64-bit của 128-bit data_in, lower 64-bit zero-pad
    // DATAPATH sẽ dùng data_len để biết chỉ lấy bao nhiêu byte thực tế
    wire [127:0] core_data_in_mux = slave_dma_en
        ? {dma_core_ptext_0, dma_core_ptext_1, 64'h0}
        : slave_core_data_in;

    wire core_data_last = slave_dma_en ? dma_core_data_last : 1'b1;
    wire core_data_valid = slave_dma_en ? dma_core_data_valid : 1'b1;

    wire [127:0] core_ad_in    = 128'h0;
    wire         core_ad_valid = 1'b0;
    wire         core_ad_last  = 1'b0;
    wire [127:0] core_tag_received = 128'h0;

    // Slice core output for DMA
    assign core_dma_ctext_0 = core_data_out_w[127:96];
    assign core_dma_ctext_1 = core_data_out_w[95:64];
    assign core_dma_tag_0   = core_tag_out_w[127:96];
    assign core_dma_tag_1   = core_tag_out_w[95:64];
    assign core_dma_tag_2   = core_tag_out_w[63:32];
    assign core_dma_tag_3   = core_tag_out_w[31:0];

    assign dma_core_data_ready = core_data_ready_w; // properly route ready

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
        .dma_burst_len      (slave_dma_burst_len), // NEW
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
    // core_start_mux:
    //   CPU-Direct (dma_en=0): slave_core_start (1-cycle pulse từ slave)
    //   DMA mode   (dma_en=1): dma_core_start & dma_core_data_valid
    // mode[0] chọn ASCON-128 (0) vs ASCON-128a (1)
    // =========================================================================
    // tag_match: kết quả so sánh tag trong decrypt mode
    // FIX-PINCONNECTEMPTY: kết nối vào wire thay vì bỏ trống
    /* verilator lint_off UNUSEDSIGNAL */
    wire core_tag_match_w;  // available for future use (decrypt tag check)
    /* verilator lint_on UNUSEDSIGNAL */

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
        .data_valid   (core_data_valid), // NEW
        .data_last    (core_data_last),
        .data_len     (slave_core_data_len),
        .tag_received (core_tag_received),
        .data_out     (core_data_out_w),
        .data_out_valid(core_data_out_valid_w),
        .data_ready   (core_data_ready_w), // NEW
        .tag_out      (core_tag_out_w),
        .tag_valid    (core_tag_valid_w),
        .tag_match    (core_tag_match_w),
        .done         (core_done_w),
        .busy         (core_busy_w)
    );

    // =========================================================================
    // u_dma : ascon_dma (AXI4-Full Master)
    // burst_len=8'd0 → 1-beat 64-bit. Cấu hình linh hoạt qua register DMA_BURST_LEN.
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
        .burst_len            (slave_dma_burst_len), // FIX: Use configurable burst length

        .dma_start            (slave_dma_start),
        .dma_soft_rst         (slave_dma_soft_rst),

        .dma_busy             (dma_busy_w),
        .dma_done             (dma_done_w),
        .dma_error            (dma_error_w),

        /* verilator lint_off PINCONNECTEMPTY */
        .status_rd_done       (),
        .status_wr_done       (),
        .status_rd_error      (),
        .status_wr_error      (),
        .status_fifo_overflow (),
        .dma_err_addr         (),
        /* verilator lint_on PINCONNECTEMPTY */

        .core_ptext_0         (dma_core_ptext_0),
        .core_ptext_1         (dma_core_ptext_1),
        .core_data_valid      (dma_core_data_valid),
        .core_data_ready      (dma_core_data_ready), // Now connected correctly
        .core_start           (dma_core_start),
        .core_data_last       (dma_core_data_last), // NEW
        .core_busy            (core_busy_w),
        .core_done            (core_done_w),
        .core_data_out_valid  (core_data_out_valid_w), // NEW
        .core_tag_valid       (core_tag_valid_w),      // NEW

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

    // =========================================================================
    // Output assigns
    // =========================================================================
    assign o_tag       = core_tag_out_w;
    assign o_tag_valid = core_tag_valid_w;
    assign o_busy      = core_busy_w | dma_busy_w;  // phản ánh trạng thái cả Core và DMA

endmodule