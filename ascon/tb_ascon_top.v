// ============================================================================
// Testbench : tb_ascon_ip_top  (v2.0 — 4 bugs fixed)
// Target    : ascon_ip_top.v (v5 — bỏ AXI-Stream, thêm DMA mode)
// Standard  : Verilog-2001, iverilog compatible
//
// ============================================================================
// CHANGELOG v1.0 → v2.0  (4 lỗi cốt lõi đã được sửa)
// ============================================================================
//
// [FIX-1] Memory Map bất đồng bộ (ascon_axi_slave v2.0 map)
// ---------------------------------------------------------
//  Vấn đề: TB v1.0 ghi/đọc sai địa chỉ → mọi test TIMEOUT hoặc trả về rác.
//  Nguyên nhân: TB viết dựa theo slave v1 map, nhưng RTL đã dùng slave v2.0.
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │  REGISTER MAP — ascon_axi_slave v2.0  (base = 0x2000_0000)          │
//  │  Offset  Name         Attr  Mô tả                                   │
//  │  0x000   MODE         R/W   [1:0] mode (00=128,01=128a,10=DMA,11=…) │
//  │  0x004   STATUS       RO    [0]=busy [1]=done [3]=dma_done [2]=dma_b│
//  │  0x008   ENC_DEC      R/W   [0]=0:enc / 1:dec                       │
//  │  0x00C   IRQ_EN       R/W   [0]=done_irq_en                         │
//  │  0x010   KEY_0        R/W   key[127:96]                             │
//  │  0x014   KEY_1        R/W   key[95:64]                              │
//  │  0x018   KEY_2        R/W   key[63:32]                              │
//  │  0x01C   KEY_3        R/W   key[31:0]                               │
//  │  0x020   CTRL         R/W   [0]=START  [1]=SOFT_RST  (write-only)   │
//  │  0x024   NONCE_0      R/W   nonce[127:96]                           │
//  │  0x028   NONCE_1      R/W   nonce[95:64]                            │
//  │  0x02C   NONCE_2      R/W   nonce[63:32]                            │
//  │  0x030   NONCE_3      R/W   nonce[31:0]                             │
//  │  0x034   PT_0         R/W   pt[127:96]                              │
//  │  0x038   PT_1         R/W   pt[95:64]                               │
//  │  0x03C   DATA_LEN     R/W   [6:0] data byte length                  │
//  │  0x040   CTEXT_0      RO    ct[127:96]                              │
//  │  0x044   CTEXT_1      RO    ct[95:64]                               │
//  │  0x048   TAG_0        RO    tag[127:96]                             │
//  │  0x04C   TAG_1        RO    tag[95:64]                              │
//  │  0x050   TAG_2        RO    tag[63:32]                              │
//  │  0x054   TAG_3        RO    tag[31:0]                               │
//  │  0x100   DMA_SRC_ADDR R/W                                           │
//  │  0x104   DMA_DST_ADDR R/W                                           │
//  │  0x108   DMA_BYTE_LEN R/W                                           │
//  │  0x10C   DMA_CTRL     R/W   [0]=START  [1]=SOFT_RST                 │
//  │  0x110   DMA_STATUS   RO    [0]=busy [1]=done [4]=rd_err [5]=wr_err │
//  └──────────────────────────────────────────────────────────────────────┘
//
//  Lỗi cụ thể trong v1.0:
//    - axi_write(32'h000, 32'h1) → ghi vào MODE, không phải START
//      FIX: START nằm ở 0x020 (CTRL[0]=1)
//    - cpu_setup ghi NONCE từ 0x020 → ghi đè CTRL! kích hoạt core sớm
//      FIX: NONCE_0 = 0x024, kế tiếp 0x028, 0x02C, 0x030
//    - DATA_LEN ghi vào 0x05C → không tồn tại
//      FIX: DATA_LEN = 0x03C
//    - MODE ghi vào 0x008 → đây là ENC_DEC, không phải MODE
//      FIX: MODE = 0x000
//    - SOFT_RST ghi 0x000 bit[1]=1 → sai (MODE register), không phải CTRL
//      FIX: SOFT_RST = axi_write(0x020, 32'h2)
//    - IRQ_EN tại 0x00C → đúng, giữ nguyên
//
// [FIX-2] Xóa tàn dư AXI-Stream
// ---------------------------------------------------------
//  Vấn đề: ascon_ip_top v5 đã bỏ hoàn toàn AXI-Stream ports.
//  Nối s_axis_*/m_axis_* vào DUT → lỗi "port mismatch" khi compile.
//  FIX: Xóa khai báo s_axis_*/m_axis_*, task axis_send/axis_recv,
//       capture logic t5_*, và toàn bộ TEST 5 AXI-Stream.
//
// [FIX-3] Thêm DMA Mode test + Dummy Memory Model
// ---------------------------------------------------------
//  Vấn đề: TB v1.0 tie-off toàn bộ M_AXI (AWREADY=1, ARREADY=1 static).
//  Vậy là DMA sẽ:
//    (a) Gửi ARVALID nhưng RVALID không bao giờ đến → FSM treo ở READ phase.
//    (b) Không có kịch bản test nào chạy DMA flow.
//  FIX: Thêm Dummy RAM Model (256 entry × 64-bit) phản hồi đúng AXI4
//       cho cả Read (AR/R) và Write (AW/W/B) trên M_AXI bus.
//       Thêm TEST 5: DMA Encrypt — nạp PT vào RAM, chạy DMA, kiểm tra CT/TAG.
//
// [FIX-4] IRQ Spam Log → Edge Detection
// ---------------------------------------------------------
//  Vấn đề: always @(posedge clk) if (irq) $display(...) → in log LIÊN TỤC
//           mỗi cycle khi irq=1, tràn terminal làm mất debug info.
//  FIX: Bắt sườn lên (posedge irq) dùng irq_prev register.
//       Chỉ in 1 dòng khi irq chuyển 0→1.
//
// ============================================================================
// Compile:
//   iverilog -o tb_top.vvp \
//     ascon/rtl/ascon_INITIALIZATION.v  ascon/rtl/ascon_STATE_REGISTER.v \
//     ascon/rtl/ascon_DATAPATH.v        ascon/rtl/PERMUTATION/ascon_PERMUTATION.v \
//     ascon/rtl/ascon_TAG_GENERATOR.v   ascon/rtl/ascon_TAG_COMPARATOR.v \
//     ascon/rtl/ascon_CONTROLLER.v      ascon/rtl/ascon_CORE.v \
//     ascon/interface/ascon_axi_slave.v \
//     ascon/dma/rtl/sync_fifo.v         ascon/dma/rtl/dma_read_engine.v \
//     ascon/dma/rtl/dma_write_engine.v  ascon/dma/rtl/dma_ctrl_fsm.v \
//     ascon/dma/ascon_dma.v             ascon/ascon_top.v \
//     tb_ascon_ip_top_v2.v
//   vvp tb_top.vvp
//   gtkwave tb_ascon_ip_top.vcd
// ============================================================================

`timescale 1ns/1ps
`include "ascon/ascon_top.v"   // ascon_ip_top và tất cả module con đã được `include trong đó
module tb_ascon_ip_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam S_AW = 32, S_DW = 32, S_IW = 4;
    localparam M_AW = 32, M_DW = 64, M_IW = 4;

    // =========================================================================
    // [FIX-1] Register Map Addresses — ascon_axi_slave v2.0
    //
    // Nguyên tắc đặt tên: ADDR_<tên_thanh_ghi>
    // Giúp code dễ đọc, tránh nhầm địa chỉ khi slave thay đổi map
    // =========================================================================
    localparam ADDR_MODE       = 32'h000;  // R/W  [1:0] mode
    localparam ADDR_STATUS     = 32'h004;  // RO   [0]=busy [1]=done
    localparam ADDR_ENC_DEC    = 32'h008;  // R/W  [0] enc=0 / dec=1
    localparam ADDR_IRQ_EN     = 32'h00C;  // R/W  [0] done_irq_en
    localparam ADDR_KEY_0      = 32'h010;  // R/W  key[127:96]
    localparam ADDR_KEY_1      = 32'h014;  //      key[95:64]
    localparam ADDR_KEY_2      = 32'h018;  //      key[63:32]
    localparam ADDR_KEY_3      = 32'h01C;  //      key[31:0]
    localparam ADDR_CTRL       = 32'h020;  // W    [0]=START [1]=SOFT_RST
    localparam ADDR_NONCE_0    = 32'h024;  // R/W  nonce[127:96]
    localparam ADDR_NONCE_1    = 32'h028;  //      nonce[95:64]
    localparam ADDR_NONCE_2    = 32'h02C;  //      nonce[63:32]
    localparam ADDR_NONCE_3    = 32'h030;  //      nonce[31:0]
    localparam ADDR_PT_0       = 32'h034;  // R/W  pt[127:96]
    localparam ADDR_PT_1       = 32'h038;  //      pt[95:64]
    localparam ADDR_DATA_LEN   = 32'h03C;  // R/W  [6:0] byte length
    localparam ADDR_CTEXT_0    = 32'h040;  // RO   ct[127:96]
    localparam ADDR_CTEXT_1    = 32'h044;  //      ct[95:64]
    localparam ADDR_TAG_0      = 32'h048;  // RO   tag[127:96]
    localparam ADDR_TAG_1      = 32'h04C;  //      tag[95:64]
    localparam ADDR_TAG_2      = 32'h050;  //      tag[63:32]
    localparam ADDR_TAG_3      = 32'h054;  //      tag[31:0]
    localparam ADDR_DMA_SRC    = 32'h100;  // R/W  DMA source address
    localparam ADDR_DMA_DST    = 32'h104;  // R/W  DMA destination address
    localparam ADDR_DMA_LEN    = 32'h108;  // R/W  DMA byte length
    localparam ADDR_DMA_CTRL   = 32'h10C;  // W    [0]=DMA_START [1]=DMA_SOFT_RST
    localparam ADDR_DMA_STATUS = 32'h110;  // RO   [0]=busy [1]=done [4]=rd_err [5]=wr_err

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    reg clk   = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;   // 100 MHz (period = 10 ns)

    // =========================================================================
    // AXI4-Full Slave Interface (TB → DUT)
    // =========================================================================
    reg  [S_IW-1:0]   S_AXI_AWID    = 0;
    reg  [S_AW-1:0]   S_AXI_AWADDR  = 0;
    reg  [7:0]        S_AXI_AWLEN   = 0;
    reg  [2:0]        S_AXI_AWSIZE  = 3'b010;
    reg  [1:0]        S_AXI_AWBURST = 2'b01;
    reg  [2:0]        S_AXI_AWPROT  = 0;
    reg               S_AXI_AWVALID = 0;
    wire              S_AXI_AWREADY;

    reg  [S_DW-1:0]   S_AXI_WDATA   = 0;
    reg  [S_DW/8-1:0] S_AXI_WSTRB   = 4'hF;
    reg               S_AXI_WLAST   = 0;
    reg               S_AXI_WVALID  = 0;
    wire              S_AXI_WREADY;

    wire [S_IW-1:0]   S_AXI_BID;
    wire [1:0]        S_AXI_BRESP;
    wire              S_AXI_BVALID;
    reg               S_AXI_BREADY  = 1;

    reg  [S_IW-1:0]   S_AXI_ARID    = 0;
    reg  [S_AW-1:0]   S_AXI_ARADDR  = 0;
    reg  [7:0]        S_AXI_ARLEN   = 0;
    reg  [2:0]        S_AXI_ARSIZE  = 3'b010;
    reg  [1:0]        S_AXI_ARBURST = 2'b01;
    reg  [2:0]        S_AXI_ARPROT  = 0;
    reg               S_AXI_ARVALID = 0;
    wire              S_AXI_ARREADY;

    wire [S_IW-1:0]   S_AXI_RID;
    wire [S_DW-1:0]   S_AXI_RDATA;
    wire [1:0]        S_AXI_RRESP;
    wire              S_AXI_RLAST;
    wire              S_AXI_RVALID;
    reg               S_AXI_RREADY  = 1;

    // =========================================================================
    // AXI4-Full Master Interface (DUT DMA → TB Dummy RAM)
    //
    // [FIX-2] Không có s_axis_*/m_axis_* nữa — ascon_ip_top v5 đã xóa chúng.
    //
    // [FIX-3] Không tie-off cứng M_AXI_AWREADY/ARREADY=1 nữa.
    //   Lý do: DMA Read Engine chờ RVALID từ memory sau khi handshake AR.
    //   Nếu RVALID không đến, FSM bị treo ở trạng thái READ → TIMEOUT.
    //   Giải pháp: Dummy RAM Model dưới đây xử lý cả AR/R và AW/W/B đúng giao thức.
    // =========================================================================
    wire [M_IW-1:0]   M_AXI_AWID;
    wire [M_AW-1:0]   M_AXI_AWADDR;
    wire [7:0]        M_AXI_AWLEN;
    wire [2:0]        M_AXI_AWSIZE;
    wire [1:0]        M_AXI_AWBURST;
    wire [3:0]        M_AXI_AWCACHE;
    wire [2:0]        M_AXI_AWPROT;
    wire              M_AXI_AWVALID;
    reg               M_AXI_AWREADY = 0;   // Driven by Dummy RAM

    wire [M_DW-1:0]   M_AXI_WDATA;
    wire [M_DW/8-1:0] M_AXI_WSTRB;
    wire              M_AXI_WLAST;
    wire              M_AXI_WVALID;
    reg               M_AXI_WREADY  = 0;   // Driven by Dummy RAM

    reg  [M_IW-1:0]   M_AXI_BID     = 0;
    reg  [1:0]        M_AXI_BRESP   = 0;
    reg               M_AXI_BVALID  = 0;
    wire              M_AXI_BREADY;

    wire [M_IW-1:0]   M_AXI_ARID;
    wire [M_AW-1:0]   M_AXI_ARADDR;
    wire [7:0]        M_AXI_ARLEN;
    wire [2:0]        M_AXI_ARSIZE;
    wire [1:0]        M_AXI_ARBURST;
    wire [3:0]        M_AXI_ARCACHE;
    wire [2:0]        M_AXI_ARPROT;
    wire              M_AXI_ARVALID;
    reg               M_AXI_ARREADY = 0;   // Driven by Dummy RAM

    reg  [M_IW-1:0]   M_AXI_RID     = 0;
    reg  [M_DW-1:0]   M_AXI_RDATA   = 0;
    reg  [1:0]        M_AXI_RRESP   = 0;
    reg               M_AXI_RLAST   = 0;
    reg               M_AXI_RVALID  = 0;
    wire              M_AXI_RREADY;

    // =========================================================================
    // DUT Outputs
    // [FIX-2] Không khai báo s_axis_*/m_axis_* — đã bị xóa trong ascon_top v5
    // =========================================================================
    wire [127:0] o_tag;
    wire         o_tag_valid;
    wire         o_busy;
    wire         irq;

    // =========================================================================
    // DUT Instantiation
    // [FIX-2] Không có s_axis_*/m_axis_* trong port list → compile sẽ pass
    // =========================================================================
    ascon_ip_top #(
        .G_COMB_RND_128 (6),
        .G_COMB_RND_128A(4),
        .G_SBOX_PIPELINE(0),
        .G_DUAL_RATE    (1),
        .G_AXI_DATA_W   (64),
        .S_ADDR_WIDTH   (S_AW),
        .S_DATA_WIDTH   (S_DW),
        .S_ID_WIDTH     (S_IW),
        .M_ADDR_WIDTH   (M_AW),
        .M_DATA_WIDTH   (M_DW),
        .M_ID_WIDTH     (M_IW),
        .RD_FIFO_DEPTH  (4),
        .WR_FIFO_DEPTH  (8)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        // Slave (CPU) interface
        .S_AXI_AWID      (S_AXI_AWID),    .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWLEN     (S_AXI_AWLEN),   .S_AXI_AWSIZE  (S_AXI_AWSIZE),
        .S_AXI_AWBURST   (S_AXI_AWBURST), .S_AXI_AWPROT  (S_AXI_AWPROT),
        .S_AXI_AWVALID   (S_AXI_AWVALID), .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA     (S_AXI_WDATA),   .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WLAST     (S_AXI_WLAST),   .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY    (S_AXI_WREADY),
        .S_AXI_BID       (S_AXI_BID),     .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID    (S_AXI_BVALID),  .S_AXI_BREADY  (S_AXI_BREADY),
        .S_AXI_ARID      (S_AXI_ARID),    .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARLEN     (S_AXI_ARLEN),   .S_AXI_ARSIZE  (S_AXI_ARSIZE),
        .S_AXI_ARBURST   (S_AXI_ARBURST), .S_AXI_ARPROT  (S_AXI_ARPROT),
        .S_AXI_ARVALID   (S_AXI_ARVALID), .S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RID       (S_AXI_RID),     .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP     (S_AXI_RRESP),   .S_AXI_RLAST   (S_AXI_RLAST),
        .S_AXI_RVALID    (S_AXI_RVALID),  .S_AXI_RREADY  (S_AXI_RREADY),
        // Master (DMA) interface
        .M_AXI_AWID      (M_AXI_AWID),    .M_AXI_AWADDR  (M_AXI_AWADDR),
        .M_AXI_AWLEN     (M_AXI_AWLEN),   .M_AXI_AWSIZE  (M_AXI_AWSIZE),
        .M_AXI_AWBURST   (M_AXI_AWBURST), .M_AXI_AWCACHE (M_AXI_AWCACHE),
        .M_AXI_AWPROT    (M_AXI_AWPROT),  .M_AXI_AWVALID (M_AXI_AWVALID),
        .M_AXI_AWREADY   (M_AXI_AWREADY),
        .M_AXI_WDATA     (M_AXI_WDATA),   .M_AXI_WSTRB   (M_AXI_WSTRB),
        .M_AXI_WLAST     (M_AXI_WLAST),   .M_AXI_WVALID  (M_AXI_WVALID),
        .M_AXI_WREADY    (M_AXI_WREADY),
        .M_AXI_BID       (M_AXI_BID),     .M_AXI_BRESP   (M_AXI_BRESP),
        .M_AXI_BVALID    (M_AXI_BVALID),  .M_AXI_BREADY  (M_AXI_BREADY),
        .M_AXI_ARID      (M_AXI_ARID),    .M_AXI_ARADDR  (M_AXI_ARADDR),
        .M_AXI_ARLEN     (M_AXI_ARLEN),   .M_AXI_ARSIZE  (M_AXI_ARSIZE),
        .M_AXI_ARBURST   (M_AXI_ARBURST), .M_AXI_ARCACHE (M_AXI_ARCACHE),
        .M_AXI_ARPROT    (M_AXI_ARPROT),  .M_AXI_ARVALID (M_AXI_ARVALID),
        .M_AXI_ARREADY   (M_AXI_ARREADY),
        .M_AXI_RID       (M_AXI_RID),     .M_AXI_RDATA   (M_AXI_RDATA),
        .M_AXI_RRESP     (M_AXI_RRESP),   .M_AXI_RLAST   (M_AXI_RLAST),
        .M_AXI_RVALID    (M_AXI_RVALID),  .M_AXI_RREADY  (M_AXI_RREADY),
        // Misc
        .o_tag           (o_tag),
        .o_tag_valid     (o_tag_valid),
        .o_busy          (o_busy),
        .irq             (irq)
    );

    // =========================================================================
    // [FIX-3] Dummy Memory Model — AXI4-Full Slave cho M_AXI (DMA)
    //
    // TẠI SAO CẦN: DMA Read Engine gửi ARVALID và chờ RVALID từ memory.
    //   Trong v1.0, M_AXI_ARREADY=1 nhưng M_AXI_RVALID không bao giờ đến.
    //   → dma_read_engine FSM: AR handshake OK → chờ RVALID → treo mãi mãi.
    //   → TIMEOUT trong mọi test có DMA.
    //
    // CẤU TRÚC: RAM 256 entry × 64-bit
    //   Địa chỉ mapping: word_index = addr[10:3]  (64-bit aligned)
    //   Base: 0x1000_0000 → word 0, 0x1000_0008 → word 1, v.v.
    //
    // GIAO THỨC ĐÚng:
    //   Read:  ARVALID+ARREADY → lấy data từ RAM → RVALID+RDATA (next cycle)
    //          → chờ RREADY từ DMA → kết thúc
    //   Write: AWVALID+AWREADY → WVALID+WREADY (ghi từng byte theo WSTRB)
    //          → BVALID+BRESP=OKAY → chờ BREADY → kết thúc
    // =========================================================================
// =========================================================================
    // ---- AXI4-Full Master Responder (Dummy RAM) -----------------------------
    // =========================================================================
    reg [63:0] dummy_ram   [0:255];
    reg [63:0] mem_wr_data [0:15]; // Mảng này để TEST 5 đọc kết quả kiểm tra
    reg [3:0]  mem_wr_idx;         // Con trỏ của mảng mem_wr_data

    // // Các tín hiệu M_AXI cần declare là reg
    // reg              M_AXI_AWREADY, M_AXI_ARREADY;
    // reg              M_AXI_WREADY;
    // reg [M_IW-1:0]   M_AXI_BID;
    // reg [1:0]        M_AXI_BRESP;
    // reg              M_AXI_BVALID;
    // reg [M_IW-1:0]   M_AXI_RID;
    // reg [M_DW-1:0]   M_AXI_RDATA;
    // reg [1:0]        M_AXI_RRESP;
    // reg              M_AXI_RLAST, M_AXI_RVALID;

    // ---- Dummy RAM Read Path ----
    reg [1:0] ram_rd_st;
    localparam RD_IDLE = 2'd0, RD_RESP = 2'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_ARREADY <= 1'b0;
            M_AXI_RVALID  <= 1'b0;
            M_AXI_RDATA   <= 64'h0;
            M_AXI_RLAST   <= 1'b0;
            M_AXI_RRESP   <= 2'b00;
            M_AXI_RID     <= 0;
            ram_rd_st     <= RD_IDLE;
        end else begin
            case (ram_rd_st)
                RD_IDLE: begin
                    M_AXI_ARREADY <= 1'b1;
                    M_AXI_RVALID  <= 1'b0;
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        M_AXI_ARREADY <= 1'b0;
                        // ARADDR[10:3] chuyển địa chỉ byte thành index của mảng 64-bit
                        M_AXI_RDATA   <= dummy_ram[M_AXI_ARADDR[10:3]];
                        M_AXI_RID     <= M_AXI_ARID;
                        M_AXI_RRESP   <= 2'b00;
                        M_AXI_RLAST   <= 1'b1; // Burst 1-beat
                        M_AXI_RVALID  <= 1'b1;
                        ram_rd_st     <= RD_RESP;
                    end
                end
                RD_RESP: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        M_AXI_RVALID  <= 1'b0;
                        M_AXI_RLAST   <= 1'b0;
                        M_AXI_ARREADY <= 1'b1;
                        ram_rd_st     <= RD_IDLE;
                    end
                end
                default: ram_rd_st <= RD_IDLE;
            endcase
        end
    end

    // ---- Dummy RAM Write Path ----
    reg [1:0]        ram_wr_st;
    reg [7:0]        wr_word_idx;
    reg [M_IW-1:0]   wr_id_latch;
    localparam WR_IDLE = 2'd0, WR_DATA = 2'd1, WR_RESP = 2'd2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_AWREADY <= 1'b0;
            M_AXI_WREADY  <= 1'b0;
            M_AXI_BVALID  <= 1'b0;
            M_AXI_BRESP   <= 2'b00;
            M_AXI_BID     <= 0;
            wr_word_idx   <= 0;
            wr_id_latch   <= 0;
            mem_wr_idx    <= 0; // Reset index lưu kết quả
            ram_wr_st     <= WR_IDLE;
        end else begin
            case (ram_wr_st)
                WR_IDLE: begin
                    M_AXI_AWREADY <= 1'b1;
                    M_AXI_BVALID  <= 1'b0;
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWREADY <= 1'b0;
                        wr_word_idx   <= M_AXI_AWADDR[10:3];
                        wr_id_latch   <= M_AXI_AWID;
                        M_AXI_WREADY  <= 1'b1;
                        ram_wr_st     <= WR_DATA;
                    end
                end
                WR_DATA: begin
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        // 1. Ghi vào RAM giả lập theo WSTRB
                        if (M_AXI_WSTRB[0]) dummy_ram[wr_word_idx][7:0]   <= M_AXI_WDATA[7:0];
                        if (M_AXI_WSTRB[1]) dummy_ram[wr_word_idx][15:8]  <= M_AXI_WDATA[15:8];
                        if (M_AXI_WSTRB[2]) dummy_ram[wr_word_idx][23:16] <= M_AXI_WDATA[23:16];
                        if (M_AXI_WSTRB[3]) dummy_ram[wr_word_idx][31:24] <= M_AXI_WDATA[31:24];
                        if (M_AXI_WSTRB[4]) dummy_ram[wr_word_idx][39:32] <= M_AXI_WDATA[39:32];
                        if (M_AXI_WSTRB[5]) dummy_ram[wr_word_idx][47:40] <= M_AXI_WDATA[47:40];
                        if (M_AXI_WSTRB[6]) dummy_ram[wr_word_idx][55:48] <= M_AXI_WDATA[55:48];
                        if (M_AXI_WSTRB[7]) dummy_ram[wr_word_idx][63:56] <= M_AXI_WDATA[63:56];
                        
                        // 2. Chép song song vào mảng testbench để dễ check kết quả
                        mem_wr_data[mem_wr_idx] <= M_AXI_WDATA;
                        mem_wr_idx              <= mem_wr_idx + 1;
                        
                        wr_word_idx <= wr_word_idx + 1;
                        if (M_AXI_WLAST) begin
                            M_AXI_WREADY <= 1'b0;
                            M_AXI_BID    <= wr_id_latch;
                            M_AXI_BRESP  <= 2'b00;
                            M_AXI_BVALID <= 1'b1;
                            ram_wr_st    <= WR_RESP;
                        end
                    end
                end
                WR_RESP: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        M_AXI_BVALID  <= 1'b0;
                        M_AXI_AWREADY <= 1'b1;
                        ram_wr_st     <= WR_IDLE;
                    end
                end
                default: ram_wr_st <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Hierarchical Probes — bắt signal từ bên trong DUT để verify
    // Dùng thay cho chờ register readback để phát hiện lỗi nhanh hơn
    // =========================================================================
    wire [127:0] hw_ct    = dut.core_data_out_w;
    wire         hw_ct_v  = dut.core_data_out_valid_w;
    wire [127:0] hw_tag   = dut.core_tag_out_w;
    wire         hw_tag_v = dut.core_tag_valid_w;
    wire         hw_done  = dut.core_done_w;

    // =========================================================================
    // Capture Registers
    // =========================================================================
    integer pass_count, fail_count;
    integer cyc_start, cyc_total;
    reg [127:0] cap_ct, cap_tag, tag_rd;
    reg [31:0]  axi_rd;

    always @(posedge clk) begin
        if (hw_ct_v)  cap_ct  <= hw_ct;
        if (hw_tag_v) cap_tag <= hw_tag;
    end

    // =========================================================================
    // Test Vectors
    // =========================================================================
    localparam [127:0] TEST_KEY    = 128'h000102030405060708090A0B0C0D0E0F;
    localparam [127:0] TEST_NONCE  = 128'h101112131415161718191A1B1C1D1E1F;
    localparam [127:0] TEST_PT     = 128'h6173636F6E000000_0000000000000000;
    localparam [6:0]   PT_LEN      = 7'd5;
    // Expected results — CPU-Direct (no AD)
    localparam [39:0]  SW_CT_NOAD  = 40'ha9919fa26e;
    localparam [127:0] SW_TAG_NOAD = 128'hf1a4d483f02f1979dad8aef9985b6148;
    // DMA src/dst trong Dummy RAM
    // word_idx = addr[10:3]: 0x1000_0000[10:3]=0, 0x1000_0010[10:3]=2
    localparam [31:0]  DMA_SRC     = 32'h1000_0000;
    localparam [31:0]  DMA_DST     = 32'h1000_0010;

    // =========================================================================
    // [FIX-4] IRQ Edge Monitor
    //
    // Vấn đề v1.0:
    //   always @(posedge clk) if (irq) $display(...)
    //   → irq giữ mức cao (level signal) đến khi phần mềm clear
    //   → $display chạy LIÊN TỤC mỗi 10ns → hàng vạn dòng log
    //   → terminal tràn, debug info quan trọng bị cuộn mất
    //
    // Fix: dùng irq_prev để chỉ in khi có SƯỜN LÊN (0→1)
    // =========================================================================
    reg irq_prev = 0;
    always @(posedge clk) begin
        irq_prev <= irq;
        // Chỉ trigger khi irq đổi 0→1 (sườn lên)
        if (irq && !irq_prev)
            $display("  [%5t] IRQ SƯỜN LÊN 0→1 (chỉ in 1 lần)", $time);
    end

    // Event monitor cho core output (ct_v/tag_v là 1-cycle pulse, không spam)
    always @(posedge clk) begin
        if (hw_ct_v)     $display("  [%5t] core CT valid:  %h", $time, hw_ct);
        if (hw_tag_v)    $display("  [%5t] core TAG valid: %h", $time, hw_tag);
        if (hw_done)     $display("  [%5t] core DONE pulse", $time);
        if (o_tag_valid) $display("  [%5t] o_tag_valid:    %h", $time, o_tag);
    end

    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_ascon_ip_top.vcd");
        $dumpvars(0, tb_ascon_ip_top);
    end

    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #5_000_000;
        $display("[WATCHDOG] 5ms timeout! Simulation hung — kiểm tra FSM deadlock.");
        $finish;
    end

    // =========================================================================
    // BFM Tasks
    // =========================================================================

    // ---- Reset ----
    // Giữ rst_n=0 đủ lâu (8 cycle), deassert đồng bộ với cạnh lên clk
    task do_reset;
        begin
            rst_n         = 0;
            S_AXI_AWVALID = 0;
            S_AXI_WVALID  = 0;
            S_AXI_WLAST   = 0;
            S_AXI_ARVALID = 0;
            S_AXI_BREADY  = 1;
            S_AXI_RREADY  = 1;
            repeat(8) @(posedge clk);
            // Deassert đồng bộ: thay đổi sau cạnh lên → ổn định
            rst_n = 1;
            repeat(3) @(posedge clk);
        end
    endtask

    // ---- AXI Write (1 beat) ----
    // Gửi đồng thời AW và W channel, chờ BVALID, kiểm tra BRESP
task axi_write;
        input [31:0] addr, data;
        integer timeout;
        reg hs_done;
        begin
            timeout = 0; hs_done = 0;
            
            // 1. Kênh Address (AW)
            @(posedge clk);
            S_AXI_AWADDR  <= addr;
            S_AXI_AWVALID <= 1;
            
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_AWREADY && S_AXI_AWVALID) hs_done = 1;
                timeout = timeout + 1;
            end
            S_AXI_AWVALID <= 0;

            // 2. Kênh Data (W)
            hs_done = 0; timeout = 0;
            S_AXI_WDATA  <= data;
            S_AXI_WSTRB  <= 4'hF;
            S_AXI_WLAST  <= 1;
            S_AXI_WVALID <= 1;
            
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_WREADY && S_AXI_WVALID) hs_done = 1;
                timeout = timeout + 1;
            end
            S_AXI_WVALID <= 0;

            // 3. Kênh Response (B)
            hs_done = 0; timeout = 0;
            // (S_AXI_BREADY mặc định đã = 1 ở trên cùng file TB)
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_BVALID && S_AXI_BREADY) hs_done = 1;
                timeout = timeout + 1;
            end
        end
    endtask

    task axi_read;
        input [31:0] addr;
        integer timeout;
        reg hs_done;
        begin
            timeout = 0; hs_done = 0;
            
            // 1. Kênh Address (AR)
            @(posedge clk);
            S_AXI_ARADDR  <= addr;
            S_AXI_ARVALID <= 1;
            
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_ARREADY && S_AXI_ARVALID) hs_done = 1;
                timeout = timeout + 1;
            end
            S_AXI_ARVALID <= 0;

            // 2. Kênh Data (R)
            hs_done = 0; timeout = 0;
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_RVALID && S_AXI_RREADY) begin
                    axi_rd  = S_AXI_RDATA;
                    hs_done = 1;
                end
                timeout = timeout + 1;
            end
        end
    endtask
task axi_burst_write_key;
        input [31:0] addr;
        input [127:0] key_data;
        integer timeout;
        reg hs_done;
        begin
            timeout = 0; hs_done = 0;
            
            // 1. Kênh AW (Kích hoạt Burst 4 beat: AWLEN = 3)
            @(posedge clk);
            S_AXI_AWADDR  <= addr;
            S_AXI_AWLEN   <= 3; 
            S_AXI_AWVALID <= 1;
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_AWREADY && S_AXI_AWVALID) hs_done = 1;
                timeout = timeout + 1;
            end
            S_AXI_AWVALID <= 0;
            S_AXI_AWLEN   <= 0; // Trả về mặc định

            // 2. Kênh W - Lần lượt xả 4 Beats
            // Beat 0
            hs_done = 0; timeout = 0;
            S_AXI_WDATA  <= key_data[127:96];
            S_AXI_WSTRB  <= 4'hF;
            S_AXI_WLAST  <= 0;
            S_AXI_WVALID <= 1;
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_WREADY && S_AXI_WVALID) hs_done = 1;
                timeout = timeout + 1;
            end
            
            // Beat 1
            hs_done = 0; timeout = 0;
            S_AXI_WDATA  <= key_data[95:64];
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_WREADY && S_AXI_WVALID) hs_done = 1;
                timeout = timeout + 1;
            end

            // Beat 2
            hs_done = 0; timeout = 0;
            S_AXI_WDATA  <= key_data[63:32];
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_WREADY && S_AXI_WVALID) hs_done = 1;
                timeout = timeout + 1;
            end

            // Beat 3 (LAST)
            hs_done = 0; timeout = 0;
            S_AXI_WDATA  <= key_data[31:0];
            S_AXI_WLAST  <= 1;
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_WREADY && S_AXI_WVALID) hs_done = 1;
                timeout = timeout + 1;
            end
            S_AXI_WVALID <= 0;
            S_AXI_WLAST  <= 0;

            // 3. Kênh B (Đợi Slave xác nhận)
            hs_done = 0; timeout = 0;
            while (!hs_done && timeout < 100) begin
                @(posedge clk);
                if (S_AXI_BVALID && S_AXI_BREADY) hs_done = 1;
                timeout = timeout + 1;
            end
        end
    endtask
    // ---- Wait core DONE ----
    task wait_done;
        integer t;
        begin
            cyc_start = $time / 10;
            t = 0;
            @(posedge clk);
            while (!hw_done && t < 10000) begin @(posedge clk); t = t + 1; end
            cyc_total = ($time / 10) - cyc_start;
            if (t >= 10000)
                $display("  [FAIL] wait_done: TIMEOUT — core không DONE");
        end
    endtask

 // ---- Wait DMA DONE (poll STATUS register 0x004) ----
    task wait_dma_done;
        integer t;
        reg [31:0] dma_st;
        begin
            t = 0; dma_st = 0;
            repeat(5) @(posedge clk);
            
            // Theo status_word trong slave: Bit [3] là dma_done, Bit [5] là dma_error
            while (!dma_st[3] && t < 20000) begin
                axi_read(32'h004); // SỬ DỤNG ĐỊA CHỈ ADDR_STATUS THAY VÌ ADDR_DMA_STATUS
                dma_st = axi_rd;
                if (dma_st[5]) begin
                    $display("  [FAIL] wait_dma_done: DMA error detected. STATUS=0x%h", dma_st);
                    t = 20000; // Force exit
                end
                t = t + 1;
            end
            if (t >= 20000 && !dma_st[3])
                $display("  [FAIL] wait_dma_done: TIMEOUT");
            else if (dma_st[3])
                $display("  [PASS] wait_dma_done: DMA Done successfully");
        end
    endtask

    // ---- CPU-Direct Setup ----
    //
    // [FIX-1] Bảng so sánh địa chỉ ĐÚNG vs SAI:
    //
    //   Thanh ghi    | v1.0 (SAI)  | v2.0 (ĐÚNG) | Hậu quả của lỗi
    //   -------------|-------------|-------------|------------------------
    //   NONCE_0      | 0x020 (=CTRL!) | 0x024    | Ghi CTRL → START sớm!
    //   PT_0         | 0x030       | 0x034       | Ghi nhầm NONCE_3
    //   DATA_LEN     | 0x05C       | 0x03C       | Không tồn tại → ignored
    //   MODE         | 0x008 (=ENC_DEC!) | 0x000 | Ghi nhầm ENC_DEC reg
    //   START        | 0x000 bit[0]| 0x020 bit[0]| Ghi nhầm MODE register
    //
    task cpu_setup;
        input [127:0] key;
        input [127:0] nonce;
        input [127:0] pt;
        input [6:0]   plen;
        input [1:0]   mode;
        begin
            axi_write(ADDR_KEY_0,   key[127:96]);
            axi_write(ADDR_KEY_1,   key[95:64]);
            axi_write(ADDR_KEY_2,   key[63:32]);
            axi_write(ADDR_KEY_3,   key[31:0]);
            // [FIX-1] NONCE từ 0x024 — KHÔNG phải 0x020 (là CTRL)
            axi_write(ADDR_NONCE_0, nonce[127:96]);
            axi_write(ADDR_NONCE_1, nonce[95:64]);
            axi_write(ADDR_NONCE_2, nonce[63:32]);
            axi_write(ADDR_NONCE_3, nonce[31:0]);
            // [FIX-1] PT từ 0x034
            axi_write(ADDR_PT_0,    pt[127:96]);
            axi_write(ADDR_PT_1,    pt[95:64]);
            // [FIX-1] DATA_LEN tại 0x03C — KHÔNG phải 0x05C
            axi_write(ADDR_DATA_LEN, {25'h0, plen});
            // [FIX-1] MODE tại 0x000 — KHÔNG phải 0x008 (là ENC_DEC)
            axi_write(ADDR_MODE, {30'h0, mode});
        end
    endtask

    // ---- Self-checking helpers ----
    task check1;
        input [255:0] lbl;
        input         got, exp;
        begin
            if (got === exp) begin
                $display("  [PASS] %s = %b", lbl, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s  got=%b  exp=%b", lbl, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check32;
        input [255:0] lbl;
        input [31:0]  got, exp;
        begin
            if (got === exp) begin
                $display("  [PASS] %s = 0x%h", lbl, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s  got=0x%h  exp=0x%h", lbl, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check40;
        input [255:0] lbl;
        input [39:0]  got, exp;
        begin
            if (got === exp) begin
                $display("  [PASS] %s = %h", lbl, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s  got=%h  exp=%h", lbl, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check128;
        input [255:0] lbl;
        input [127:0] got, exp;
        begin
            if (got === exp) begin
                $display("  [PASS] %s = %h", lbl, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s  got=%h  exp=%h", lbl, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    integer t_tmp;
    reg [31:0] rd_val;

    initial begin
        pass_count = 0; fail_count = 0;
        cap_ct = 0; cap_tag = 0;
        cyc_start = 0; cyc_total = 0;

        $display("================================================================");
        $display("  tb_ascon_ip_top v2.0  —  ascon_ip_top v5 (DMA mode, no AXIS)");
        $display("================================================================");
        $display("  KEY   = %h", TEST_KEY);
        $display("  NONCE = %h", TEST_NONCE);
        $display("  PT    = 6173636f6e (ascon, 5B)");
        $display("  EXP CT  (no AD) = %h", SW_CT_NOAD);
        $display("  EXP TAG (no AD) = %h", SW_TAG_NOAD);
        $display("================================================================");

        // =================================================================
        // TEST 1: Reset State
        // TEST: TC_RST_01 + TC_RST_04
        // EXPECT: STATUS=0x00, irq=0 sau khi rst_n=1
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 1: Reset — STATUS và IRQ về default");
        $display("----------------------------------------------------------------");
        do_reset;
        axi_read(ADDR_STATUS);
        $display("  STATUS = 0x%h  (expect 0x00)", axi_rd);
        check1("busy=0 sau reset",    axi_rd[0], 1'b0);
        check1("done=0 sau reset",    axi_rd[1], 1'b0);
        check1("irq=0 sau reset",     irq,        1'b0);
        repeat(2) @(posedge clk);

        // =================================================================
        // TEST 2: CPU-Direct Encryption (ASCON-128, no AD)
        // TEST: TC_AXI_01 (write+readback), functional encrypt
        //
        // [FIX-1] CTRL tại 0x020, ghi 32'h1 để START
        //         Không ghi vào 0x000 (MODE register)
        //
        // EXPECT: CT[127:88]=SW_CT_NOAD, TAG=SW_TAG_NOAD
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 2: CPU-Direct Encrypt (ASCON-128, mode=00)");
        $display("----------------------------------------------------------------");
        do_reset;
        cpu_setup(TEST_KEY, TEST_NONCE, TEST_PT, PT_LEN, 2'b00);
        // [FIX-1] START tại CTRL (0x020), KHÔNG phải 0x000
        axi_write(ADDR_CTRL, 32'h1);
        wait_done;
        $display("  Cycles: %0d", cyc_total);
        check40 ("CT  (5B, CPU-Direct)", cap_ct[127:88], SW_CT_NOAD);
        check128("TAG (CPU-Direct)",     cap_tag,         SW_TAG_NOAD);
        repeat(4) @(posedge clk);

        // =================================================================
        // TEST 3: Register Readback — CT/TAG qua AXI slave registers
        // TEST: TC_AXI_01 (readback verify)
        //
        // Mục đích: Nếu slave lưu kết quả đúng, đọc từ CTEXT_0/TAG_0..3
        // sẽ match với giá trị bắt qua hierarchical probe (cap_ct/cap_tag)
        // EXPECT: CTEXT_0 = cap_ct[127:96], TAG_0..3 = cap_tag
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 3: Register Readback (CTEXT/TAG registers)");
        $display("----------------------------------------------------------------");
        axi_read(ADDR_CTEXT_0);
        check32("CTEXT_0 reg = cap_ct[127:96]", axi_rd, cap_ct[127:96]);
        axi_read(ADDR_CTEXT_1);
        check32("CTEXT_1 reg = cap_ct[95:64]",  axi_rd, cap_ct[95:64]);
        begin : blk_tag_rd
            reg [127:0] tag_from_axi;
            axi_read(ADDR_TAG_0); tag_from_axi[127:96] = axi_rd;
            axi_read(ADDR_TAG_1); tag_from_axi[95:64]  = axi_rd;
            axi_read(ADDR_TAG_2); tag_from_axi[63:32]  = axi_rd;
            axi_read(ADDR_TAG_3); tag_from_axi[31:0]   = axi_rd;
            $display("  TAG (AXI reg) = %h", tag_from_axi);
            $display("  TAG (HW prob) = %h", cap_tag);
            check128("TAG reg match HW probe", tag_from_axi, cap_tag);
        end
        repeat(2) @(posedge clk);

        // =================================================================
        // TEST 4: Soft Reset clears STATUS[done]
        // TEST: TC_RST_02
        //
        // [FIX-1] SOFT_RST tại CTRL[1] → axi_write(ADDR_CTRL=0x020, 32'h2)
        //         Không ghi vào 0x000 (MODE) hay 0x004 (STATUS/RO)
        //
        // EXPECT: done=1 trước → done=0 sau SOFT_RST
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 4: Soft Reset — CTRL[1]=1 clears STATUS[done]");
        $display("----------------------------------------------------------------");
        // Trạng thái hiện tại: done=1 từ TEST 2
        axi_read(ADDR_STATUS);
        $display("  STATUS trước SOFT_RST = 0x%h  (expect bit[1]=1)", axi_rd);
        check1("done=1 trước soft_rst", axi_rd[1], 1'b1);
        // [FIX-1] SOFT_RST = ghi vào CTRL (0x020), bit[1]=1
        axi_write(ADDR_CTRL, 32'h2);
        repeat(4) @(posedge clk);
        axi_read(ADDR_STATUS);
        $display("  STATUS sau  SOFT_RST  = 0x%h  (expect 0x00)", axi_rd);
        check1("done=0 sau soft_rst", axi_rd[1], 1'b0);
        check1("busy=0 sau soft_rst", axi_rd[0], 1'b0);
        repeat(2) @(posedge clk);
        // =================================================================
        // TEST 5: DMA Mode Encryption
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 5: DMA Mode Encryption");
        $display("----------------------------------------------------------------");
        do_reset;
        
        $display("  [DEBUG] Monitoring DMA Internal Signals...");
        $monitor("  [%t] DMA State: %h | Busy: %b | Done Pulse: %b | Error: %b | STATUS Reg: %h", 
                 $time, dut.u_dma.u_ctrl_fsm.state, dut.u_dma.u_ctrl_fsm.dma_busy, dut.u_dma.u_ctrl_fsm.dma_done, dut.u_dma.u_ctrl_fsm.dma_error, axi_rd);
        
        // Bước 1: Nạp PT vào Dummy RAM
        // Bước 1: Nạp PT vào Dummy RAM
        // [SỬA LỖI 1]: Dùng DMA_SRC[10:3] để TB tự động ghi vào đúng ô nhớ mà DMA sẽ đọc.
        // [SỬA LỖI 2]: Đảo vị trí 2 word để khớp với Endianness của RTL (rdata[31:0] là ptext_0).
        dummy_ram[DMA_SRC[10:3]] = {TEST_PT[95:64], TEST_PT[127:96]}; 
        
        $display("  Nạp PT vào dummy_ram[%0d] = %h", DMA_SRC[10:3], dummy_ram[DMA_SRC[10:3]]);

        // Bước 2: KEY/NONCE
        axi_write(ADDR_KEY_0,   TEST_KEY[127:96]);
        axi_write(ADDR_KEY_1,   TEST_KEY[95:64]);
        axi_write(ADDR_KEY_2,   TEST_KEY[63:32]);
        axi_write(ADDR_KEY_3,   TEST_KEY[31:0]);
        axi_write(ADDR_NONCE_0, TEST_NONCE[127:96]);
        axi_write(ADDR_NONCE_1, TEST_NONCE[95:64]);
        axi_write(ADDR_NONCE_2, TEST_NONCE[63:32]);
        axi_write(ADDR_NONCE_3, TEST_NONCE[31:0]);
        axi_write(ADDR_DATA_LEN, {25'h0, PT_LEN});

        // Bước 3: DMA addresses
        axi_write(ADDR_DMA_SRC, DMA_SRC); // Đảm bảo macro DMA_SRC = 32'h100
        axi_write(ADDR_DMA_DST, DMA_DST); // Đảm bảo macro DMA_DST = 32'h200
        axi_write(ADDR_DMA_LEN, 32'h8);

        // Bước 4: MODE = 2'b10 (Không xài DMA_EN ở đây nữa theo RTL mới nhất, nhưng mode 2'b10 là axis_en tùy logic)
        // Lưu ý: slave_dma_en hiện lấy từ bit [2] của ADDR_CTRL, việc ghi ADDR_MODE không bật dma_en.
        axi_write(ADDR_MODE, 32'h0);

        // Bước 5: Ghi vào CTRL (0x020) giá trị 0x5 (bit 2: dma_en=1, bit 0: start=1)
        axi_write(32'h020, 32'h5);
        $display("  DMA_START issued (0x%h ← 0x5)", 32'h020);

        // Bước 6: Poll STATUS (Sửa lại đọc 0x004 và bit 3, 5)
        wait_dma_done;
        axi_read(32'h004); // ADDR_STATUS
        $display("  STATUS final = 0x%h", axi_rd);
        check1("DMA done=1 (Bit 3)",  axi_rd[3], 1'b1);
        check1("DMA error=0 (Bit 5)", axi_rd[5], 1'b0);

        // Bước 7: Kết quả qua hierarchical probe
        $display("  DMA CT  (HW) = %h", cap_ct);
        $display("  DMA TAG (HW) = %h", cap_tag);
        check40 ("DMA CT  = CPU-Direct CT",  cap_ct[127:88], SW_CT_NOAD);
        check128("DMA TAG = CPU-Direct TAG", cap_tag,         SW_TAG_NOAD);
        repeat(4) @(posedge clk);

        // =================================================================
        // TEST 6: IRQ assert khi done (IRQ_EN=1)
        // TEST: TC_IRQ_01, TC_IRQ_03
        //
        // [FIX-4] Nhờ edge detection, IRQ chỉ in 1 dòng log khi 0→1
        //
        // EXPECT: irq=0 trước start → irq=1 sau done → irq=0 sau soft_rst
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 6: IRQ — assert sau done, clear sau soft_rst");
        $display("----------------------------------------------------------------");
        do_reset;
        axi_write(ADDR_IRQ_EN, 32'h1);
        check1("irq=0 trước start",   irq, 1'b0);
        cpu_setup(TEST_KEY, TEST_NONCE, TEST_PT, PT_LEN, 2'b00);
        axi_write(ADDR_CTRL, 32'h1);
        wait_done;
        repeat(3) @(posedge clk);
        check1("irq=1 sau done",      irq, 1'b1);
        axi_write(ADDR_CTRL, 32'h2);  // SOFT_RST
        repeat(4) @(posedge clk);
        check1("irq=0 sau soft_rst",  irq, 1'b0);
        repeat(2) @(posedge clk);

        // =================================================================
        // TEST 7: IRQ masked khi IRQ_EN=0
        // TEST: TC_IRQ_02
        //
        // EXPECT: irq=0 sau done nếu IRQ_EN=0
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 7: IRQ Mask — irq_en=0 ngăn interrupt");
        $display("----------------------------------------------------------------");
        do_reset;
        axi_write(ADDR_IRQ_EN, 32'h0);
        cpu_setup(TEST_KEY, TEST_NONCE, TEST_PT, PT_LEN, 2'b00);
        axi_write(ADDR_CTRL, 32'h1);
        wait_done;
        repeat(3) @(posedge clk);
        check1("irq=0 khi IRQ_EN=0",  irq, 1'b0);
        repeat(2) @(posedge clk);

        // =================================================================
        // TEST 8: AXI ID Tracking (BID==AWID, RID==ARID)
        // TEST: TC_AXI_05
        //
        // Mục đích: Khi nhiều master trên crossbar dùng ID khác nhau,
        // slave phải echo đúng ID trên B và R channel.
        //
        // EXPECT: BID=0xA khi AWID=0xA, RID=0xB khi ARID=0xB
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 8: AXI ID Tracking (BID==AWID, RID==ARID)");
        $display("----------------------------------------------------------------");
        do_reset;
        begin : blk_id
            integer t;
            // Write với AWID=0xA
            @(posedge clk); #1;
            S_AXI_AWID    = 4'hA;
            S_AXI_AWADDR  = ADDR_KEY_0;
            S_AXI_AWLEN   = 8'h00; S_AXI_AWSIZE = 3'b010; S_AXI_AWBURST = 2'b01;
            S_AXI_AWVALID = 1;
            S_AXI_WDATA   = 32'hABCD_EF01;
            S_AXI_WSTRB   = 4'hF; S_AXI_WLAST = 1; S_AXI_WVALID = 1;
            t = 0; @(posedge clk); #1;
            while (!(S_AXI_AWREADY & S_AXI_WREADY) && t < 100) begin @(posedge clk); #1; t=t+1; end
            S_AXI_AWVALID = 0; S_AXI_WVALID = 0; S_AXI_WLAST = 0;
            t = 0; while (!S_AXI_BVALID && t < 100) begin @(posedge clk); t=t+1; end
            $display("  AWID=0xA → BID=0x%h  (expect 0xA)", S_AXI_BID);
            check1("BID==AWID(A)", (S_AXI_BID === 4'hA), 1'b1);
            @(posedge clk); #1;
            // Read với ARID=0xB
            S_AXI_ARID    = 4'hB;
            S_AXI_ARADDR  = ADDR_KEY_0;
            S_AXI_ARLEN   = 8'h00; S_AXI_ARSIZE = 3'b010; S_AXI_ARBURST = 2'b01;
            S_AXI_ARVALID = 1;
            t = 0; @(posedge clk); #1;
            while (!S_AXI_ARREADY && t < 100) begin @(posedge clk); #1; t=t+1; end
            S_AXI_ARVALID = 0;
            t = 0; while (!S_AXI_RVALID && t < 100) begin @(posedge clk); t=t+1; end
            $display("  ARID=0xB → RID=0x%h  (expect 0xB)", S_AXI_RID);
            check1("RID==ARID(B)", (S_AXI_RID === 4'hB), 1'b1);
            @(posedge clk); #1;
        end
        repeat(2) @(posedge clk);

        // =================================================================
        // TEST 9: Back-to-back Write (stress test)
        // TEST: TC_EDGE_01
        //
        // Mục đích: Ghi 4 thanh ghi liên tiếp không có gap giữa các write.
        // Slave phải không bị mất beat, không corrupt thứ tự.
        // EXPECT: readback đúng tất cả 4 giá trị
        // =================================================================
        $display("\n----------------------------------------------------------------");
        $display("  TEST 9: AXI INCR Burst Write (4 KEY registers)");
        $display("----------------------------------------------------------------");
        do_reset;
        
        // Gọi task burst write: Cấp địa chỉ bắt đầu (0x010) và khối data 128-bit
        axi_burst_write_key(32'h010, 128'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0);
        
        // Đọc lại bằng Single Read để verify RTL đã tự động chia data vào đúng địa chỉ chưa
        axi_read(32'h010); check32("KEY_0 readback", axi_rd, 32'hDEAD_BEEF);
        axi_read(32'h014); check32("KEY_1 readback", axi_rd, 32'hCAFE_BABE);
        axi_read(32'h018); check32("KEY_2 readback", axi_rd, 32'h1234_5678);
        axi_read(32'h01C); check32("KEY_3 readback", axi_rd, 32'h9ABC_DEF0);
        repeat(2) @(posedge clk);

        // =================================================================
        // RESULT SUMMARY
        // =================================================================
        $display("\n================================================================");
        $display("  RESULT SUMMARY");
        $display("================================================================");
        $display("  PASSED : %0d", pass_count);
        $display("  FAILED : %0d", fail_count);
        $display("  TOTAL  : %0d", pass_count + fail_count);
        $display("================================================================");
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TEST(S) FAILED — kiểm tra trace ở trên ***", fail_count);
        $display("================================================================");
        $finish;
    end

endmodule