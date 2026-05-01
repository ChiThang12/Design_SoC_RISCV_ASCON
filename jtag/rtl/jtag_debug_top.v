`timescale 1ns/1ps

// ============================================================================
// jtag_debug_top.v — JTAG Debug Top
//
// Kết nối:
//   jtag_tap     — TAP state machine (IEEE 1149.1)
//   jtag_dtm     — Debug Transport Module (RISC-V spec)
//   riscv_dm     — Debug Module + System Bus Access
//
// Interface với soc_top:
//   TCK/TMS/TDI/TDO → IO pads (4 dây)
//   M4 AXI4-Full master → Crossbar (System Bus Access)
//   ndmreset → clk_reset_ctrl (non-debug reset)
//   haltreq/resumereq/halted/running ↔ CPU debug port
//
// Lưu ý CDC:
//   TAP chạy ở tck domain (≤ 25 MHz).
//   jtag_dtm có 2-FF synchronizer tck→clk cho DMI request.
//   riscv_dm chạy hoàn toàn trong clk domain (100 MHz).
// ============================================================================

`include "jtag/jtag_tap.v"
`include "jtag/jtag_dtm.v"
`include "jtag/riscv_dm.v"

module jtag_debug_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter ABITS      = 7,
    parameter IDCODE_VAL = 32'hDEAD_0001   // thay bằng JEDEC ID chip thực
)(
    // ── Clock & Reset ─────────────────────────────────────────────────────
    input  wire clk,
    input  wire rst_n,

    // ── JTAG IO pads ──────────────────────────────────────────────────────
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    output wire tdo,          // tri-state controlled bởi tdo_en
    output wire tdo_en,       // HIGH khi Shift-DR/Shift-IR

    // ── CPU Debug Interface ────────────────────────────────────────────────
    output wire ndmreset,     // → clk_reset_ctrl: reset CPU+peripheral, không reset DM
    output wire haltreq,      // → CPU: yêu cầu dừng
    output wire resumereq,    // → CPU: yêu cầu tiếp tục
    input  wire halted,       // ← CPU: đang dừng
    input  wire running,      // ← CPU: đang chạy

    // ── AXI4-Full Master (M4 → Crossbar: System Bus Access) ───────────────
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
    output wire                  M_AXI_BREADY
);

    // ── DMI bus wires ──────────────────────────────────────────────────────
    wire [ABITS-1:0] dmi_addr;
    wire [31:0]      dmi_data_wr;
    wire [1:0]       dmi_op;
    wire             dmi_req_valid;
    wire             dmi_req_ready;

    wire [31:0]      dmi_data_rd;
    wire [1:0]       dmi_rsp_op;
    wire             dmi_rsp_valid;
    wire             dmi_rsp_ready;

    // ── u_dtm: Debug Transport Module ─────────────────────────────────────
    jtag_dtm #(
        .IDCODE_VAL(IDCODE_VAL),
        .ABITS     (ABITS)
    ) u_dtm (
        .tck(tck), .tms(tms), .tdi(tdi),
        .tdo(tdo), .tdo_en(tdo_en),

        .clk(clk), .rst_n(rst_n),

        .dmi_addr      (dmi_addr),
        .dmi_data_wr   (dmi_data_wr),
        .dmi_op        (dmi_op),
        .dmi_req_valid (dmi_req_valid),
        .dmi_req_ready (dmi_req_ready),

        .dmi_data_rd   (dmi_data_rd),
        .dmi_rsp_op    (dmi_rsp_op),
        .dmi_rsp_valid (dmi_rsp_valid),
        .dmi_rsp_ready (dmi_rsp_ready)
    );

    // ── u_dm: Debug Module ─────────────────────────────────────────────────
    riscv_dm #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .ABITS     (ABITS)
    ) u_dm (
        .clk(clk), .rst_n(rst_n),

        .dmi_addr      (dmi_addr),
        .dmi_data_wr   (dmi_data_wr),
        .dmi_op        (dmi_op),
        .dmi_req_valid (dmi_req_valid),
        .dmi_req_ready (dmi_req_ready),

        .dmi_data_rd   (dmi_data_rd),
        .dmi_rsp_op    (dmi_rsp_op),
        .dmi_rsp_valid (dmi_rsp_valid),
        .dmi_rsp_ready (dmi_rsp_ready),

        .ndmreset  (ndmreset),
        .haltreq   (haltreq),
        .resumereq (resumereq),
        .halted    (halted),
        .running   (running),

        .m_axi_arid   (M_AXI_ARID),    .m_axi_araddr  (M_AXI_ARADDR),
        .m_axi_arlen  (M_AXI_ARLEN),   .m_axi_arsize  (M_AXI_ARSIZE),
        .m_axi_arburst(M_AXI_ARBURST), .m_axi_arprot  (M_AXI_ARPROT),
        .m_axi_arvalid(M_AXI_ARVALID), .m_axi_arready (M_AXI_ARREADY),
        .m_axi_rid    (M_AXI_RID),     .m_axi_rdata   (M_AXI_RDATA),
        .m_axi_rresp  (M_AXI_RRESP),   .m_axi_rlast   (M_AXI_RLAST),
        .m_axi_rvalid (M_AXI_RVALID),  .m_axi_rready  (M_AXI_RREADY),
        .m_axi_awid   (M_AXI_AWID),    .m_axi_awaddr  (M_AXI_AWADDR),
        .m_axi_awlen  (M_AXI_AWLEN),   .m_axi_awsize  (M_AXI_AWSIZE),
        .m_axi_awburst(M_AXI_AWBURST), .m_axi_awprot  (M_AXI_AWPROT),
        .m_axi_awvalid(M_AXI_AWVALID), .m_axi_awready (M_AXI_AWREADY),
        .m_axi_wdata  (M_AXI_WDATA),   .m_axi_wstrb   (M_AXI_WSTRB),
        .m_axi_wlast  (M_AXI_WLAST),   .m_axi_wvalid  (M_AXI_WVALID),
        .m_axi_wready (M_AXI_WREADY),
        .m_axi_bid    (M_AXI_BID),     .m_axi_bresp   (M_AXI_BRESP),
        .m_axi_bvalid (M_AXI_BVALID),  .m_axi_bready  (M_AXI_BREADY)
    );

endmodule