`timescale 1ns/1ps

// ============================================================================
// dma_ctrl.v — DMA Controller Top (M3 + S11)
//
// Kết nối trong SoC:
//   S11 slave (base 0x6001_0000): CPU config DMA qua AXI4-Full
//   M3  master: DMA thực hiện burst mem-to-mem qua AXI4 crossbar
//   irq_out → PLIC[7]: done/error của bất kỳ channel nào
//
// Sub-modules:
//   dma_reg_slave  — AXI4 slave, register file config
//   dma_channel×4  — 4 kênh DMA độc lập, mỗi kênh có line buffer riêng
//   dma_arbiter    — round-robin cho read bus và write bus
//   dma_axi_master — AXI4 master duy nhất giao tiếp với crossbar
//
// SỬA LỖI so với bản gốc:
//
//  [FIX-1] `include đặt trong module → lỗi Verilog-2001. `include phải đặt
//          trước module declaration. Dùng compile filelist thay thế (xem NOTE).
//          → Xóa tất cả `include; dùng external filelist.
//
//  [FIX-2] s_axi_awprot không được pass xuống dma_reg_slave → port mismatch.
//          → Thêm s_axi_awprot và s_axi_arprot vào instance connection.
//
//  [FIX-3] wr_bready và rd_data_rdy trong channel instances được nối vào ()
//          (không connected) → floating input. dma_channel dùng assign
//          wr_bready = 1'b1 và rd_data_rdy = 1'b1 bên trong → output port
//          này không cần nối từ bên ngoài. Giữ nguyên, thêm comment.
//
//  [FIX-4] Đặt lại AXI ID master. Crossbar cần biết M3 (DMA Ctrl) để route.
//          dma_axi_master đặt m_axi_arid/awid = 4'd0 (đã fix trong module đó).
//          Top không cần can thiệp thêm.
//
// NOTE compile filelist (thứ tự quan trọng):
//   1. dma/rtl/dma_axi_master.v
//   2. dma/rtl/dma_arbiter.v
//   3. dma/rtl/dma_channel.v
//   4. dma/rtl/dma_reg_slave.v
//   5. dma/rtl/dma_ctrl.v   ← file này
//
// Kết nối vào soc_top.v:
//   dma_ctrl u_dma_ctrl (
//       .clk       (clk),
//       .rst_n     (fabric_rst_n),
//       .S_AXI_*   (s11_*),   // S11 từ crossbar
//       .M_AXI_*   (m3_*),    // M3 lên crossbar
//       .irq_out   (dma_irq)  // → PLIC[7]
//   );
// ============================================================================
// `include "dma/rtl/dma_reg_slave.v"
// `include "dma/rtl/dma_channel.v"
// `include "dma/rtl/dma_arbiter.v"
// `include "dma/rtl/dma_axi_master.v"
// [FIX-1] Không `include trong file này. Dùng filelist.
module dma_ctrl #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter NUM_CH     = 4
)(
    input  wire clk,
    input  wire rst_n,

    // ── AXI4-Full Slave (S11 ← Crossbar) ─────────────────────────────────
    input  wire [ID_WIDTH-1:0]   S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [7:0]            S_AXI_AWLEN,
    input  wire [2:0]            S_AXI_AWSIZE,
    input  wire [1:0]            S_AXI_AWBURST,
    input  wire [2:0]            S_AXI_AWPROT,   // [FIX-2]
    input  wire                  S_AXI_AWVALID,
    output wire                  S_AXI_AWREADY,
    input  wire [DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [3:0]            S_AXI_WSTRB,
    input  wire                  S_AXI_WLAST,
    input  wire                  S_AXI_WVALID,
    output wire                  S_AXI_WREADY,
    output wire [ID_WIDTH-1:0]   S_AXI_BID,
    output wire [1:0]            S_AXI_BRESP,
    output wire                  S_AXI_BVALID,
    input  wire                  S_AXI_BREADY,
    input  wire [ID_WIDTH-1:0]   S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [7:0]            S_AXI_ARLEN,
    input  wire [2:0]            S_AXI_ARSIZE,
    input  wire [1:0]            S_AXI_ARBURST,
    input  wire [2:0]            S_AXI_ARPROT,   // [FIX-2]
    input  wire                  S_AXI_ARVALID,
    output wire                  S_AXI_ARREADY,
    output wire [ID_WIDTH-1:0]   S_AXI_RID,
    output wire [DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0]            S_AXI_RRESP,
    output wire                  S_AXI_RLAST,
    output wire                  S_AXI_RVALID,
    input  wire                  S_AXI_RREADY,

    // ── AXI4-Full Master (M3 → Crossbar) ─────────────────────────────────
    output wire [ID_WIDTH-1:0]   M_AXI_ARID,
    output wire [ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output wire [7:0]            M_AXI_ARLEN,
    output wire [2:0]            M_AXI_ARSIZE,
    output wire [1:0]            M_AXI_ARBURST,
    output wire [2:0]            M_AXI_ARPROT,
    output wire                  M_AXI_ARVALID,
    input  wire                  M_AXI_ARREADY,
    input  wire [ID_WIDTH-1:0]   M_AXI_RID,
    input  wire [DATA_WIDTH-1:0] M_AXI_RDATA,
    input  wire [1:0]            M_AXI_RRESP,
    input  wire                  M_AXI_RLAST,
    input  wire                  M_AXI_RVALID,
    output wire                  M_AXI_RREADY,
    output wire [ID_WIDTH-1:0]   M_AXI_AWID,
    output wire [ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output wire [7:0]            M_AXI_AWLEN,
    output wire [2:0]            M_AXI_AWSIZE,
    output wire [1:0]            M_AXI_AWBURST,
    output wire [2:0]            M_AXI_AWPROT,
    output wire                  M_AXI_AWVALID,
    input  wire                  M_AXI_AWREADY,
    output wire [DATA_WIDTH-1:0] M_AXI_WDATA,
    output wire [3:0]            M_AXI_WSTRB,
    output wire                  M_AXI_WLAST,
    output wire                  M_AXI_WVALID,
    input  wire                  M_AXI_WREADY,
    input  wire [ID_WIDTH-1:0]   M_AXI_BID,
    input  wire [1:0]            M_AXI_BRESP,
    input  wire                  M_AXI_BVALID,
    output wire                  M_AXI_BREADY,

    // ── IRQ → PLIC ────────────────────────────────────────────────────────
    output wire                  irq_out,
    output wire                  dma_busy_o,

    // ── Peripheral handshake (per-channel) ───────────────────────────────
    // Connect peripheral DMA-request outputs to dma_req[ch].
    // dma_ack[ch] is a 1-cycle pulse after each word transfer.
    input  wire [NUM_CH-1:0]     dma_req,  // from peripherals
    output wire [NUM_CH-1:0]     dma_ack   // to peripherals
);

    // =========================================================================
    // Internal config wires: dma_reg_slave → dma_channel
    // =========================================================================
    wire [ADDR_WIDTH-1:0] ch0_src,  ch1_src,  ch2_src,  ch3_src;
    wire [ADDR_WIDTH-1:0] ch0_dst,  ch1_dst,  ch2_dst,  ch3_dst;
    wire [31:0]           ch0_len,  ch1_len,  ch2_len,  ch3_len;
    wire [1:0]            ch0_mode, ch1_mode, ch2_mode, ch3_mode;
    wire                  ch0_en,   ch1_en,   ch2_en,   ch3_en;
    wire                  ch0_start,ch1_start,ch2_start,ch3_start;

    // Status: dma_channel → dma_reg_slave
    wire [NUM_CH-1:0] ch_done_w;
    wire [NUM_CH-1:0] ch_error_w;
    wire [NUM_CH-1:0] ch_busy_w;

    // Periph ack wires from channels → dma_ack output
    wire [NUM_CH-1:0] ch_periph_ack_w;
    assign dma_ack = ch_periph_ack_w;

    // =========================================================================
    // Arbiter buses
    // WHY: rd bus và wr bus hoàn toàn độc lập → 2 kênh khác nhau có thể
    // đọc và ghi cùng lúc nếu AXI master hỗ trợ outstanding transactions.
    // =========================================================================
    wire [NUM_CH-1:0] rd_req_w, rd_grant_w, rd_rel_w;
    wire [NUM_CH-1:0] wr_req_w, wr_grant_w, wr_rel_w;

    // =========================================================================
    // Channel → Master: read interfaces (flat)
    // =========================================================================
    wire [ADDR_WIDTH-1:0] ch0_rd_addr, ch1_rd_addr, ch2_rd_addr, ch3_rd_addr;
    wire [7:0]            ch0_rd_len,  ch1_rd_len,  ch2_rd_len,  ch3_rd_len;
    wire                  ch0_rd_valid,ch1_rd_valid,ch2_rd_valid,ch3_rd_valid;
    wire                  ch0_rd_ready,ch1_rd_ready,ch2_rd_ready,ch3_rd_ready;
    wire [DATA_WIDTH-1:0] ch0_rd_data, ch1_rd_data, ch2_rd_data, ch3_rd_data;
    wire                  ch0_rd_dv,   ch1_rd_dv,   ch2_rd_dv,   ch3_rd_dv;
    wire                  ch0_rd_last, ch1_rd_last, ch2_rd_last, ch3_rd_last;

    // =========================================================================
    // Channel → Master: write interfaces (flat)
    // =========================================================================
    wire [ADDR_WIDTH-1:0] ch0_wr_addr,   ch1_wr_addr,   ch2_wr_addr,   ch3_wr_addr;
    wire [7:0]            ch0_wr_len,    ch1_wr_len,    ch2_wr_len,    ch3_wr_len;
    wire                  ch0_wr_valid,  ch1_wr_valid,  ch2_wr_valid,  ch3_wr_valid;
    wire                  ch0_wr_ready,  ch1_wr_ready,  ch2_wr_ready,  ch3_wr_ready;
    wire [DATA_WIDTH-1:0] ch0_wr_data,   ch1_wr_data,   ch2_wr_data,   ch3_wr_data;
    wire [3:0]            ch0_wr_wstrb,  ch1_wr_wstrb,  ch2_wr_wstrb,  ch3_wr_wstrb;
    wire                  ch0_wr_wvalid, ch1_wr_wvalid, ch2_wr_wvalid, ch3_wr_wvalid;
    wire                  ch0_wr_wlast,  ch1_wr_wlast,  ch2_wr_wlast,  ch3_wr_wlast;
    wire                  ch0_wr_wready, ch1_wr_wready, ch2_wr_wready, ch3_wr_wready;
    wire [1:0]            ch0_wr_bresp,  ch1_wr_bresp,  ch2_wr_bresp,  ch3_wr_bresp;
    wire                  ch0_wr_bvalid, ch1_wr_bvalid, ch2_wr_bvalid, ch3_wr_bvalid;

    // =========================================================================
    // Muxed master interface (granted channel → axi_master)
    // =========================================================================
    wire [ADDR_WIDTH-1:0] mx_rd_addr;  wire [7:0] mx_rd_len;
    wire                  mx_rd_valid; wire       mx_rd_ready;
    wire [DATA_WIDTH-1:0] mx_rd_data;  wire       mx_rd_dv;
    wire                  mx_rd_last;

    wire [ADDR_WIDTH-1:0] mx_wr_addr;   wire [7:0] mx_wr_len;
    wire                  mx_wr_valid;  wire       mx_wr_ready;
    wire [DATA_WIDTH-1:0] mx_wr_data;   wire [3:0] mx_wr_wstrb;
    wire                  mx_wr_wvalid; wire       mx_wr_wlast;
    wire                  mx_wr_wready; wire [1:0] mx_wr_bresp;
    wire                  mx_wr_bvalid;

    // =========================================================================
    // u_reg_slave — AXI4 slave config
    // =========================================================================
    dma_reg_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),     .NUM_CH(NUM_CH)
    ) u_reg_slave (
        .clk   (clk),
        .rst_n (rst_n),
        .s_axi_awid    (S_AXI_AWID),    .s_axi_awaddr  (S_AXI_AWADDR),
        .s_axi_awlen   (S_AXI_AWLEN),   .s_axi_awsize  (S_AXI_AWSIZE),
        .s_axi_awburst (S_AXI_AWBURST), .s_axi_awprot  (S_AXI_AWPROT),  // [FIX-2]
        .s_axi_awvalid (S_AXI_AWVALID), .s_axi_awready (S_AXI_AWREADY),
        .s_axi_wdata   (S_AXI_WDATA),   .s_axi_wstrb   (S_AXI_WSTRB),
        .s_axi_wlast   (S_AXI_WLAST),   .s_axi_wvalid  (S_AXI_WVALID),
        .s_axi_wready  (S_AXI_WREADY),
        .s_axi_bid     (S_AXI_BID),     .s_axi_bresp   (S_AXI_BRESP),
        .s_axi_bvalid  (S_AXI_BVALID),  .s_axi_bready  (S_AXI_BREADY),
        .s_axi_arid    (S_AXI_ARID),    .s_axi_araddr  (S_AXI_ARADDR),
        .s_axi_arlen   (S_AXI_ARLEN),   .s_axi_arsize  (S_AXI_ARSIZE),
        .s_axi_arburst (S_AXI_ARBURST), .s_axi_arprot  (S_AXI_ARPROT),  // [FIX-2]
        .s_axi_arvalid (S_AXI_ARVALID), .s_axi_arready (S_AXI_ARREADY),
        .s_axi_rid     (S_AXI_RID),     .s_axi_rdata   (S_AXI_RDATA),
        .s_axi_rresp   (S_AXI_RRESP),   .s_axi_rlast   (S_AXI_RLAST),
        .s_axi_rvalid  (S_AXI_RVALID),  .s_axi_rready  (S_AXI_RREADY),
        .ch0_src(ch0_src), .ch0_dst(ch0_dst), .ch0_len(ch0_len),
        .ch0_mode(ch0_mode), .ch0_en(ch0_en), .ch0_start(ch0_start),
        .ch1_src(ch1_src), .ch1_dst(ch1_dst), .ch1_len(ch1_len),
        .ch1_mode(ch1_mode), .ch1_en(ch1_en), .ch1_start(ch1_start),
        .ch2_src(ch2_src), .ch2_dst(ch2_dst), .ch2_len(ch2_len),
        .ch2_mode(ch2_mode), .ch2_en(ch2_en), .ch2_start(ch2_start),
        .ch3_src(ch3_src), .ch3_dst(ch3_dst), .ch3_len(ch3_len),
        .ch3_mode(ch3_mode), .ch3_en(ch3_en), .ch3_start(ch3_start),
        .ch_done (ch_done_w),
        .ch_error(ch_error_w),
        .ch_busy (ch_busy_w),
        .irq_out (irq_out)
    );

    // =========================================================================
    // u_ch0..u_ch3 — DMA Channels
    // WHY: 4 channels độc lập, mỗi cái có line buffer riêng (64 bytes).
    // Một channel hoạt động một lúc trên mỗi bus (read bus / write bus).
    // [FIX-3] wr_bready và rd_data_rdy là outputs từ dma_channel (assign bên trong).
    //         Để () là OK: Verilog cho phép output port không nối.
    // =========================================================================
    dma_channel #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_ch0 (
        .clk(clk), .rst_n(rst_n),
        .cfg_src(ch0_src), .cfg_dst(ch0_dst), .cfg_len(ch0_len),
        .cfg_mode(ch0_mode), .cfg_en(ch0_en), .cfg_start(ch0_start),
        .periph_req(dma_req[0]), .periph_ack(ch_periph_ack_w[0]),
        .done(ch_done_w[0]), .error(ch_error_w[0]), .busy(ch_busy_w[0]),
        .rd_req(rd_req_w[0]), .rd_grant(rd_grant_w[0]), .rd_rel(rd_rel_w[0]),
        .wr_req(wr_req_w[0]), .wr_grant(wr_grant_w[0]), .wr_rel(wr_rel_w[0]),
        .rd_addr(ch0_rd_addr), .rd_len(ch0_rd_len),
        .rd_valid(ch0_rd_valid), .rd_ready(ch0_rd_ready),
        .rd_data(ch0_rd_data), .rd_data_v(ch0_rd_dv), .rd_last(ch0_rd_last),
        .rd_data_rdy(),
        .wr_addr(ch0_wr_addr), .wr_len(ch0_wr_len),
        .wr_valid(ch0_wr_valid), .wr_ready(ch0_wr_ready),
        .wr_data(ch0_wr_data), .wr_wstrb(ch0_wr_wstrb),
        .wr_wvalid(ch0_wr_wvalid), .wr_wlast(ch0_wr_wlast),
        .wr_wready(ch0_wr_wready), .wr_bresp(ch0_wr_bresp),
        .wr_bvalid(ch0_wr_bvalid), .wr_bready()
    );

    dma_channel #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_ch1 (
        .clk(clk), .rst_n(rst_n),
        .cfg_src(ch1_src), .cfg_dst(ch1_dst), .cfg_len(ch1_len),
        .cfg_mode(ch1_mode), .cfg_en(ch1_en), .cfg_start(ch1_start),
        .periph_req(dma_req[1]), .periph_ack(ch_periph_ack_w[1]),
        .done(ch_done_w[1]), .error(ch_error_w[1]), .busy(ch_busy_w[1]),
        .rd_req(rd_req_w[1]), .rd_grant(rd_grant_w[1]), .rd_rel(rd_rel_w[1]),
        .wr_req(wr_req_w[1]), .wr_grant(wr_grant_w[1]), .wr_rel(wr_rel_w[1]),
        .rd_addr(ch1_rd_addr), .rd_len(ch1_rd_len),
        .rd_valid(ch1_rd_valid), .rd_ready(ch1_rd_ready),
        .rd_data(ch1_rd_data), .rd_data_v(ch1_rd_dv), .rd_last(ch1_rd_last),
        .rd_data_rdy(),
        .wr_addr(ch1_wr_addr), .wr_len(ch1_wr_len),
        .wr_valid(ch1_wr_valid), .wr_ready(ch1_wr_ready),
        .wr_data(ch1_wr_data), .wr_wstrb(ch1_wr_wstrb),
        .wr_wvalid(ch1_wr_wvalid), .wr_wlast(ch1_wr_wlast),
        .wr_wready(ch1_wr_wready), .wr_bresp(ch1_wr_bresp),
        .wr_bvalid(ch1_wr_bvalid), .wr_bready()
    );

    dma_channel #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_ch2 (
        .clk(clk), .rst_n(rst_n),
        .cfg_src(ch2_src), .cfg_dst(ch2_dst), .cfg_len(ch2_len),
        .cfg_mode(ch2_mode), .cfg_en(ch2_en), .cfg_start(ch2_start),
        .periph_req(dma_req[2]), .periph_ack(ch_periph_ack_w[2]),
        .done(ch_done_w[2]), .error(ch_error_w[2]), .busy(ch_busy_w[2]),
        .rd_req(rd_req_w[2]), .rd_grant(rd_grant_w[2]), .rd_rel(rd_rel_w[2]),
        .wr_req(wr_req_w[2]), .wr_grant(wr_grant_w[2]), .wr_rel(wr_rel_w[2]),
        .rd_addr(ch2_rd_addr), .rd_len(ch2_rd_len),
        .rd_valid(ch2_rd_valid), .rd_ready(ch2_rd_ready),
        .rd_data(ch2_rd_data), .rd_data_v(ch2_rd_dv), .rd_last(ch2_rd_last),
        .rd_data_rdy(),
        .wr_addr(ch2_wr_addr), .wr_len(ch2_wr_len),
        .wr_valid(ch2_wr_valid), .wr_ready(ch2_wr_ready),
        .wr_data(ch2_wr_data), .wr_wstrb(ch2_wr_wstrb),
        .wr_wvalid(ch2_wr_wvalid), .wr_wlast(ch2_wr_wlast),
        .wr_wready(ch2_wr_wready), .wr_bresp(ch2_wr_bresp),
        .wr_bvalid(ch2_wr_bvalid), .wr_bready()
    );

    dma_channel #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_ch3 (
        .clk(clk), .rst_n(rst_n),
        .cfg_src(ch3_src), .cfg_dst(ch3_dst), .cfg_len(ch3_len),
        .cfg_mode(ch3_mode), .cfg_en(ch3_en), .cfg_start(ch3_start),
        .periph_req(dma_req[3]), .periph_ack(ch_periph_ack_w[3]),
        .done(ch_done_w[3]), .error(ch_error_w[3]), .busy(ch_busy_w[3]),
        .rd_req(rd_req_w[3]), .rd_grant(rd_grant_w[3]), .rd_rel(rd_rel_w[3]),
        .wr_req(wr_req_w[3]), .wr_grant(wr_grant_w[3]), .wr_rel(wr_rel_w[3]),
        .rd_addr(ch3_rd_addr), .rd_len(ch3_rd_len),
        .rd_valid(ch3_rd_valid), .rd_ready(ch3_rd_ready),
        .rd_data(ch3_rd_data), .rd_data_v(ch3_rd_dv), .rd_last(ch3_rd_last),
        .rd_data_rdy(),
        .wr_addr(ch3_wr_addr), .wr_len(ch3_wr_len),
        .wr_valid(ch3_wr_valid), .wr_ready(ch3_wr_ready),
        .wr_data(ch3_wr_data), .wr_wstrb(ch3_wr_wstrb),
        .wr_wvalid(ch3_wr_wvalid), .wr_wlast(ch3_wr_wlast),
        .wr_wready(ch3_wr_wready), .wr_bresp(ch3_wr_bresp),
        .wr_bvalid(ch3_wr_bvalid), .wr_bready()
    );

    assign dma_busy_o = |ch_busy_w;

    // =========================================================================
    // u_arbiter — Round-robin
    // =========================================================================
    dma_arbiter #(.NUM_CH(NUM_CH)) u_arbiter (
        .clk     (clk),     .rst_n   (rst_n),
        .rd_req  (rd_req_w), .rd_grant(rd_grant_w), .rd_rel(rd_rel_w),
        .wr_req  (wr_req_w), .wr_grant(wr_grant_w), .wr_rel(wr_rel_w)
    );

    // =========================================================================
    // Read MUX: channel được rd_grant → axi_master
    // WHY: Chỉ 1 channel được grant tại một thời điểm →
    // priority mux đơn giản là đủ (không xảy ra 2 grant cùng lúc).
    // =========================================================================
    assign mx_rd_addr  = rd_grant_w[0] ? ch0_rd_addr  :
                         rd_grant_w[1] ? ch1_rd_addr  :
                         rd_grant_w[2] ? ch2_rd_addr  : ch3_rd_addr;
    assign mx_rd_len   = rd_grant_w[0] ? ch0_rd_len   :
                         rd_grant_w[1] ? ch1_rd_len   :
                         rd_grant_w[2] ? ch2_rd_len   : ch3_rd_len;
    assign mx_rd_valid = rd_grant_w[0] ? ch0_rd_valid :
                         rd_grant_w[1] ? ch1_rd_valid :
                         rd_grant_w[2] ? ch2_rd_valid :
                         rd_grant_w[3] ? ch3_rd_valid : 1'b0;

    // Read DEMUX: rd_ready / data / dv / last → channel được grant
    assign ch0_rd_ready = rd_grant_w[0] & mx_rd_ready;
    assign ch1_rd_ready = rd_grant_w[1] & mx_rd_ready;
    assign ch2_rd_ready = rd_grant_w[2] & mx_rd_ready;
    assign ch3_rd_ready = rd_grant_w[3] & mx_rd_ready;

    // Data broadcast: channel lọc bằng dv gated
    assign ch0_rd_data = mx_rd_data; assign ch1_rd_data = mx_rd_data;
    assign ch2_rd_data = mx_rd_data; assign ch3_rd_data = mx_rd_data;

    assign ch0_rd_dv   = rd_grant_w[0] & mx_rd_dv;
    assign ch1_rd_dv   = rd_grant_w[1] & mx_rd_dv;
    assign ch2_rd_dv   = rd_grant_w[2] & mx_rd_dv;
    assign ch3_rd_dv   = rd_grant_w[3] & mx_rd_dv;

    assign ch0_rd_last = rd_grant_w[0] & mx_rd_last;
    assign ch1_rd_last = rd_grant_w[1] & mx_rd_last;
    assign ch2_rd_last = rd_grant_w[2] & mx_rd_last;
    assign ch3_rd_last = rd_grant_w[3] & mx_rd_last;

    // =========================================================================
    // Write MUX: channel được wr_grant → axi_master
    // =========================================================================
    assign mx_wr_addr   = wr_grant_w[0] ? ch0_wr_addr   :
                          wr_grant_w[1] ? ch1_wr_addr   :
                          wr_grant_w[2] ? ch2_wr_addr   : ch3_wr_addr;
    assign mx_wr_len    = wr_grant_w[0] ? ch0_wr_len    :
                          wr_grant_w[1] ? ch1_wr_len    :
                          wr_grant_w[2] ? ch2_wr_len    : ch3_wr_len;
    assign mx_wr_valid  = wr_grant_w[0] ? ch0_wr_valid  :
                          wr_grant_w[1] ? ch1_wr_valid  :
                          wr_grant_w[2] ? ch2_wr_valid  :
                          wr_grant_w[3] ? ch3_wr_valid  : 1'b0;
    assign mx_wr_data   = wr_grant_w[0] ? ch0_wr_data   :
                          wr_grant_w[1] ? ch1_wr_data   :
                          wr_grant_w[2] ? ch2_wr_data   : ch3_wr_data;
    assign mx_wr_wstrb  = wr_grant_w[0] ? ch0_wr_wstrb  :
                          wr_grant_w[1] ? ch1_wr_wstrb  :
                          wr_grant_w[2] ? ch2_wr_wstrb  : ch3_wr_wstrb;
    assign mx_wr_wvalid = wr_grant_w[0] ? ch0_wr_wvalid :
                          wr_grant_w[1] ? ch1_wr_wvalid :
                          wr_grant_w[2] ? ch2_wr_wvalid :
                          wr_grant_w[3] ? ch3_wr_wvalid : 1'b0;
    assign mx_wr_wlast  = wr_grant_w[0] ? ch0_wr_wlast  :
                          wr_grant_w[1] ? ch1_wr_wlast  :
                          wr_grant_w[2] ? ch2_wr_wlast  : ch3_wr_wlast;

    // Write DEMUX
    assign ch0_wr_ready  = wr_grant_w[0] & mx_wr_ready;
    assign ch1_wr_ready  = wr_grant_w[1] & mx_wr_ready;
    assign ch2_wr_ready  = wr_grant_w[2] & mx_wr_ready;
    assign ch3_wr_ready  = wr_grant_w[3] & mx_wr_ready;

    assign ch0_wr_wready = wr_grant_w[0] & mx_wr_wready;
    assign ch1_wr_wready = wr_grant_w[1] & mx_wr_wready;
    assign ch2_wr_wready = wr_grant_w[2] & mx_wr_wready;
    assign ch3_wr_wready = wr_grant_w[3] & mx_wr_wready;

    assign ch0_wr_bresp  = mx_wr_bresp; assign ch1_wr_bresp  = mx_wr_bresp;
    assign ch2_wr_bresp  = mx_wr_bresp; assign ch3_wr_bresp  = mx_wr_bresp;

    assign ch0_wr_bvalid = wr_grant_w[0] & mx_wr_bvalid;
    assign ch1_wr_bvalid = wr_grant_w[1] & mx_wr_bvalid;
    assign ch2_wr_bvalid = wr_grant_w[2] & mx_wr_bvalid;
    assign ch3_wr_bvalid = wr_grant_w[3] & mx_wr_bvalid;

    // =========================================================================
    // u_axi_master — AXI4 Master (M3)
    // =========================================================================
    dma_axi_master #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) u_axi_master (
        .clk   (clk),
        .rst_n (rst_n),

        .m_axi_arid    (M_AXI_ARID),    .m_axi_araddr  (M_AXI_ARADDR),
        .m_axi_arlen   (M_AXI_ARLEN),   .m_axi_arsize  (M_AXI_ARSIZE),
        .m_axi_arburst (M_AXI_ARBURST), .m_axi_arprot  (M_AXI_ARPROT),
        .m_axi_arvalid (M_AXI_ARVALID), .m_axi_arready (M_AXI_ARREADY),
        .m_axi_rid     (M_AXI_RID),     .m_axi_rdata   (M_AXI_RDATA),
        .m_axi_rresp   (M_AXI_RRESP),   .m_axi_rlast   (M_AXI_RLAST),
        .m_axi_rvalid  (M_AXI_RVALID),  .m_axi_rready  (M_AXI_RREADY),
        .m_axi_awid    (M_AXI_AWID),    .m_axi_awaddr  (M_AXI_AWADDR),
        .m_axi_awlen   (M_AXI_AWLEN),   .m_axi_awsize  (M_AXI_AWSIZE),
        .m_axi_awburst (M_AXI_AWBURST), .m_axi_awprot  (M_AXI_AWPROT),
        .m_axi_awvalid (M_AXI_AWVALID), .m_axi_awready (M_AXI_AWREADY),
        .m_axi_wdata   (M_AXI_WDATA),   .m_axi_wstrb   (M_AXI_WSTRB),
        .m_axi_wlast   (M_AXI_WLAST),   .m_axi_wvalid  (M_AXI_WVALID),
        .m_axi_wready  (M_AXI_WREADY),
        .m_axi_bid     (M_AXI_BID),     .m_axi_bresp   (M_AXI_BRESP),
        .m_axi_bvalid  (M_AXI_BVALID),  .m_axi_bready  (M_AXI_BREADY),

        .rd_addr    (mx_rd_addr),  .rd_len     (mx_rd_len),
        .rd_valid   (mx_rd_valid), .rd_ready   (mx_rd_ready),
        .rd_data    (mx_rd_data),  .rd_data_v  (mx_rd_dv),
        .rd_last    (mx_rd_last),  .rd_data_rdy(1'b1),

        .wr_addr    (mx_wr_addr),   .wr_len    (mx_wr_len),
        .wr_valid   (mx_wr_valid),  .wr_ready  (mx_wr_ready),
        .wr_data    (mx_wr_data),   .wr_wstrb  (mx_wr_wstrb),
        .wr_wvalid  (mx_wr_wvalid), .wr_wlast  (mx_wr_wlast),
        .wr_wready  (mx_wr_wready), .wr_bresp  (mx_wr_bresp),
        .wr_bvalid  (mx_wr_bvalid), .wr_bready (1'b1)
    );

endmodule
