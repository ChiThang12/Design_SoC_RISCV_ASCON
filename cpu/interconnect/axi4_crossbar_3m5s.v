// ============================================================================
// axi4_crossbar_3m5s.v  —  AXI4 Non-blocking Crossbar (3 Master × 5 Slave)
//
// [Fix 3] Mở rộng từ axi4_crossbar_3m4s.v — thêm Slave 4 = CLINT
//
// Module con:
//   axi4_addr_decoder   — decode địa chỉ → slave index (dùng cho AR và AW)
//   axi4_master_mux_3m  — arbitration + mux cho mỗi slave (×5)
//   axi4_decerr_slave   — xử lý địa chỉ không ánh xạ (×3, một cho mỗi master)
//
// Bản đồ địa chỉ:
//   S0: IMEM       0x0000_0000 – 0x0000_FFFF  (mask 0xFFFF_0000)
//   S1: DMEM       0x1000_0000 – 0x1000_FFFF  (mask 0xFFFF_0000)
//   S2: ASCON/DMA  0x2000_0000 – 0x2000_0FFF  (mask 0xFFFF_F000)
//   S3: SoC Ctrl   0x3000_0000 – 0x3000_0FFF  (mask 0xFFFF_F000)
//   S4: CLINT      0x4000_0000 – 0x4000_FFFF  (mask 0xFFFF_0000)  [Fix 3]
//
// Non-blocking: M0, M1, M2 có thể truy cập các slave khác nhau đồng thời.
// Arbitration:  Fixed priority — M0 (ICache) > M1 (DCache) > M2 (DMA).
//
// Lưu ý ID_WIDTH:
//   axi4_master_mux_3m dùng 2 bit cao của ID để tag master index.
//   → Yêu cầu ID_WIDTH >= 3. Với ID_WIDTH=4, còn 2 bit dùng cho transaction ID.
//
// Thay đổi so với 3m4s:
//   - axi4_addr_decoder: thêm S4_BASE / S4_MASK parameter, NUM_SLAVES=5
//   - Thêm S4_AXI_* port (CLINT)
//   - Thêm m{0,1,2}_*_to_s4 steer wires
//   - Array size: [0:5] thay vì [0:4] (index 5 = DECERR)
//   - Thêm mux_s4 instance
//   - R/B OR bus mở rộng thêm _s[5]
// ============================================================================

`include "cpu/interconnect/axi4_addr_decoder.v"
`include "cpu/interconnect/axi4_master_mux_3m.v"
`include "cpu/interconnect/axi4_decerr_slave.v"

module axi4_crossbar_3m5s #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4,   // Phải >= 3 (2 bit tag + ít nhất 1 bit ID)
    parameter STRB_WIDTH = DATA_WIDTH / 8,

    // Địa chỉ base/mask cho từng slave
    parameter [ADDR_WIDTH-1:0] S0_BASE = 32'h0000_0000,
    parameter [ADDR_WIDTH-1:0] S0_MASK = 32'hFFFF_0000,
    parameter [ADDR_WIDTH-1:0] S1_BASE = 32'h1000_0000,
    parameter [ADDR_WIDTH-1:0] S1_MASK = 32'hFFFF_0000,
    parameter [ADDR_WIDTH-1:0] S2_BASE = 32'h2000_0000,
    parameter [ADDR_WIDTH-1:0] S2_MASK = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S3_BASE = 32'h3000_0000,
    parameter [ADDR_WIDTH-1:0] S3_MASK = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S4_BASE = 32'h4000_0000,  // [Fix 3] CLINT
    parameter [ADDR_WIDTH-1:0] S4_MASK = 32'hFFFF_0000
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Master 0 — ICache (chủ yếu đọc)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   M0_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0] M0_AXI_ARADDR,
    input  wire [7:0]            M0_AXI_ARLEN,
    input  wire [2:0]            M0_AXI_ARSIZE,
    input  wire [1:0]            M0_AXI_ARBURST,
    input  wire [2:0]            M0_AXI_ARPROT,
    input  wire                  M0_AXI_ARVALID,
    output wire                  M0_AXI_ARREADY,

    output wire [ID_WIDTH-1:0]   M0_AXI_RID,
    output wire [DATA_WIDTH-1:0] M0_AXI_RDATA,
    output wire [1:0]            M0_AXI_RRESP,
    output wire                  M0_AXI_RLAST,
    output wire                  M0_AXI_RVALID,
    input  wire                  M0_AXI_RREADY,

    input  wire [ID_WIDTH-1:0]   M0_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0] M0_AXI_AWADDR,
    input  wire [7:0]            M0_AXI_AWLEN,
    input  wire [2:0]            M0_AXI_AWSIZE,
    input  wire [1:0]            M0_AXI_AWBURST,
    input  wire [2:0]            M0_AXI_AWPROT,
    input  wire                  M0_AXI_AWVALID,
    output wire                  M0_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0] M0_AXI_WDATA,
    input  wire [STRB_WIDTH-1:0] M0_AXI_WSTRB,
    input  wire                  M0_AXI_WLAST,
    input  wire                  M0_AXI_WVALID,
    output wire                  M0_AXI_WREADY,

    output wire [ID_WIDTH-1:0]   M0_AXI_BID,
    output wire [1:0]            M0_AXI_BRESP,
    output wire                  M0_AXI_BVALID,
    input  wire                  M0_AXI_BREADY,

    // ========================================================================
    // Master 1 — DCache (đọc + ghi)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   M1_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0] M1_AXI_ARADDR,
    input  wire [7:0]            M1_AXI_ARLEN,
    input  wire [2:0]            M1_AXI_ARSIZE,
    input  wire [1:0]            M1_AXI_ARBURST,
    input  wire [2:0]            M1_AXI_ARPROT,
    input  wire                  M1_AXI_ARVALID,
    output wire                  M1_AXI_ARREADY,

    output wire [ID_WIDTH-1:0]   M1_AXI_RID,
    output wire [DATA_WIDTH-1:0] M1_AXI_RDATA,
    output wire [1:0]            M1_AXI_RRESP,
    output wire                  M1_AXI_RLAST,
    output wire                  M1_AXI_RVALID,
    input  wire                  M1_AXI_RREADY,

    input  wire [ID_WIDTH-1:0]   M1_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0] M1_AXI_AWADDR,
    input  wire [7:0]            M1_AXI_AWLEN,
    input  wire [2:0]            M1_AXI_AWSIZE,
    input  wire [1:0]            M1_AXI_AWBURST,
    input  wire [2:0]            M1_AXI_AWPROT,
    input  wire                  M1_AXI_AWVALID,
    output wire                  M1_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0] M1_AXI_WDATA,
    input  wire [STRB_WIDTH-1:0] M1_AXI_WSTRB,
    input  wire                  M1_AXI_WLAST,
    input  wire                  M1_AXI_WVALID,
    output wire                  M1_AXI_WREADY,

    output wire [ID_WIDTH-1:0]   M1_AXI_BID,
    output wire [1:0]            M1_AXI_BRESP,
    output wire                  M1_AXI_BVALID,
    input  wire                  M1_AXI_BREADY,

    // ========================================================================
    // Master 2 — DMA (đọc + ghi, ưu tiên thấp nhất)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   M2_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0] M2_AXI_ARADDR,
    input  wire [7:0]            M2_AXI_ARLEN,
    input  wire [2:0]            M2_AXI_ARSIZE,
    input  wire [1:0]            M2_AXI_ARBURST,
    input  wire [2:0]            M2_AXI_ARPROT,
    input  wire                  M2_AXI_ARVALID,
    output wire                  M2_AXI_ARREADY,

    output wire [ID_WIDTH-1:0]   M2_AXI_RID,
    output wire [DATA_WIDTH-1:0] M2_AXI_RDATA,
    output wire [1:0]            M2_AXI_RRESP,
    output wire                  M2_AXI_RLAST,
    output wire                  M2_AXI_RVALID,
    input  wire                  M2_AXI_RREADY,

    input  wire [ID_WIDTH-1:0]   M2_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0] M2_AXI_AWADDR,
    input  wire [7:0]            M2_AXI_AWLEN,
    input  wire [2:0]            M2_AXI_AWSIZE,
    input  wire [1:0]            M2_AXI_AWBURST,
    input  wire [2:0]            M2_AXI_AWPROT,
    input  wire                  M2_AXI_AWVALID,
    output wire                  M2_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0] M2_AXI_WDATA,
    input  wire [STRB_WIDTH-1:0] M2_AXI_WSTRB,
    input  wire                  M2_AXI_WLAST,
    input  wire                  M2_AXI_WVALID,
    output wire                  M2_AXI_WREADY,

    output wire [ID_WIDTH-1:0]   M2_AXI_BID,
    output wire [1:0]            M2_AXI_BRESP,
    output wire                  M2_AXI_BVALID,
    input  wire                  M2_AXI_BREADY,

    // ========================================================================
    // Slave 0 — IMEM
    // ========================================================================
    output wire [ID_WIDTH-1:0]   S0_AXI_ARID,
    output wire [ADDR_WIDTH-1:0] S0_AXI_ARADDR,
    output wire [7:0]            S0_AXI_ARLEN,
    output wire [2:0]            S0_AXI_ARSIZE,
    output wire [1:0]            S0_AXI_ARBURST,
    output wire [2:0]            S0_AXI_ARPROT,
    output wire                  S0_AXI_ARVALID,
    input  wire                  S0_AXI_ARREADY,

    input  wire [ID_WIDTH-1:0]   S0_AXI_RID,
    input  wire [DATA_WIDTH-1:0] S0_AXI_RDATA,
    input  wire [1:0]            S0_AXI_RRESP,
    input  wire                  S0_AXI_RLAST,
    input  wire                  S0_AXI_RVALID,
    output wire                  S0_AXI_RREADY,

    output wire [ID_WIDTH-1:0]   S0_AXI_AWID,
    output wire [ADDR_WIDTH-1:0] S0_AXI_AWADDR,
    output wire [7:0]            S0_AXI_AWLEN,
    output wire [2:0]            S0_AXI_AWSIZE,
    output wire [1:0]            S0_AXI_AWBURST,
    output wire [2:0]            S0_AXI_AWPROT,
    output wire                  S0_AXI_AWVALID,
    input  wire                  S0_AXI_AWREADY,

    output wire [DATA_WIDTH-1:0] S0_AXI_WDATA,
    output wire [STRB_WIDTH-1:0] S0_AXI_WSTRB,
    output wire                  S0_AXI_WLAST,
    output wire                  S0_AXI_WVALID,
    input  wire                  S0_AXI_WREADY,

    input  wire [ID_WIDTH-1:0]   S0_AXI_BID,
    input  wire [1:0]            S0_AXI_BRESP,
    input  wire                  S0_AXI_BVALID,
    output wire                  S0_AXI_BREADY,

    // ========================================================================
    // Slave 1 — DMEM
    // ========================================================================
    output wire [ID_WIDTH-1:0]   S1_AXI_ARID,
    output wire [ADDR_WIDTH-1:0] S1_AXI_ARADDR,
    output wire [7:0]            S1_AXI_ARLEN,
    output wire [2:0]            S1_AXI_ARSIZE,
    output wire [1:0]            S1_AXI_ARBURST,
    output wire [2:0]            S1_AXI_ARPROT,
    output wire                  S1_AXI_ARVALID,
    input  wire                  S1_AXI_ARREADY,

    input  wire [ID_WIDTH-1:0]   S1_AXI_RID,
    input  wire [DATA_WIDTH-1:0] S1_AXI_RDATA,
    input  wire [1:0]            S1_AXI_RRESP,
    input  wire                  S1_AXI_RLAST,
    input  wire                  S1_AXI_RVALID,
    output wire                  S1_AXI_RREADY,

    output wire [ID_WIDTH-1:0]   S1_AXI_AWID,
    output wire [ADDR_WIDTH-1:0] S1_AXI_AWADDR,
    output wire [7:0]            S1_AXI_AWLEN,
    output wire [2:0]            S1_AXI_AWSIZE,
    output wire [1:0]            S1_AXI_AWBURST,
    output wire [2:0]            S1_AXI_AWPROT,
    output wire                  S1_AXI_AWVALID,
    input  wire                  S1_AXI_AWREADY,

    output wire [DATA_WIDTH-1:0] S1_AXI_WDATA,
    output wire [STRB_WIDTH-1:0] S1_AXI_WSTRB,
    output wire                  S1_AXI_WLAST,
    output wire                  S1_AXI_WVALID,
    input  wire                  S1_AXI_WREADY,

    input  wire [ID_WIDTH-1:0]   S1_AXI_BID,
    input  wire [1:0]            S1_AXI_BRESP,
    input  wire                  S1_AXI_BVALID,
    output wire                  S1_AXI_BREADY,

    // ========================================================================
    // Slave 2 — ASCON / DMA Config
    // ========================================================================
    output wire [ID_WIDTH-1:0]   S2_AXI_ARID,
    output wire [ADDR_WIDTH-1:0] S2_AXI_ARADDR,
    output wire [7:0]            S2_AXI_ARLEN,
    output wire [2:0]            S2_AXI_ARSIZE,
    output wire [1:0]            S2_AXI_ARBURST,
    output wire [2:0]            S2_AXI_ARPROT,
    output wire                  S2_AXI_ARVALID,
    input  wire                  S2_AXI_ARREADY,

    input  wire [ID_WIDTH-1:0]   S2_AXI_RID,
    input  wire [DATA_WIDTH-1:0] S2_AXI_RDATA,
    input  wire [1:0]            S2_AXI_RRESP,
    input  wire                  S2_AXI_RLAST,
    input  wire                  S2_AXI_RVALID,
    output wire                  S2_AXI_RREADY,

    output wire [ID_WIDTH-1:0]   S2_AXI_AWID,
    output wire [ADDR_WIDTH-1:0] S2_AXI_AWADDR,
    output wire [7:0]            S2_AXI_AWLEN,
    output wire [2:0]            S2_AXI_AWSIZE,
    output wire [1:0]            S2_AXI_AWBURST,
    output wire [2:0]            S2_AXI_AWPROT,
    output wire                  S2_AXI_AWVALID,
    input  wire                  S2_AXI_AWREADY,

    output wire [DATA_WIDTH-1:0] S2_AXI_WDATA,
    output wire [STRB_WIDTH-1:0] S2_AXI_WSTRB,
    output wire                  S2_AXI_WLAST,
    output wire                  S2_AXI_WVALID,
    input  wire                  S2_AXI_WREADY,

    input  wire [ID_WIDTH-1:0]   S2_AXI_BID,
    input  wire [1:0]            S2_AXI_BRESP,
    input  wire                  S2_AXI_BVALID,
    output wire                  S2_AXI_BREADY,

    // ========================================================================
    // Slave 3 — SoC Controller
    // ========================================================================
    output wire [ID_WIDTH-1:0]   S3_AXI_ARID,
    output wire [ADDR_WIDTH-1:0] S3_AXI_ARADDR,
    output wire [7:0]            S3_AXI_ARLEN,
    output wire [2:0]            S3_AXI_ARSIZE,
    output wire [1:0]            S3_AXI_ARBURST,
    output wire [2:0]            S3_AXI_ARPROT,
    output wire                  S3_AXI_ARVALID,
    input  wire                  S3_AXI_ARREADY,

    input  wire [ID_WIDTH-1:0]   S3_AXI_RID,
    input  wire [DATA_WIDTH-1:0] S3_AXI_RDATA,
    input  wire [1:0]            S3_AXI_RRESP,
    input  wire                  S3_AXI_RLAST,
    input  wire                  S3_AXI_RVALID,
    output wire                  S3_AXI_RREADY,

    output wire [ID_WIDTH-1:0]   S3_AXI_AWID,
    output wire [ADDR_WIDTH-1:0] S3_AXI_AWADDR,
    output wire [7:0]            S3_AXI_AWLEN,
    output wire [2:0]            S3_AXI_AWSIZE,
    output wire [1:0]            S3_AXI_AWBURST,
    output wire [2:0]            S3_AXI_AWPROT,
    output wire                  S3_AXI_AWVALID,
    input  wire                  S3_AXI_AWREADY,

    output wire [DATA_WIDTH-1:0] S3_AXI_WDATA,
    output wire [STRB_WIDTH-1:0] S3_AXI_WSTRB,
    output wire                  S3_AXI_WLAST,
    output wire                  S3_AXI_WVALID,
    input  wire                  S3_AXI_WREADY,

    input  wire [ID_WIDTH-1:0]   S3_AXI_BID,
    input  wire [1:0]            S3_AXI_BRESP,
    input  wire                  S3_AXI_BVALID,
    output wire                  S3_AXI_BREADY,

    // ========================================================================
    // Slave 4 — CLINT  [Fix 3]
    // ========================================================================
    output wire [ID_WIDTH-1:0]   S4_AXI_ARID,
    output wire [ADDR_WIDTH-1:0] S4_AXI_ARADDR,
    output wire [7:0]            S4_AXI_ARLEN,
    output wire [2:0]            S4_AXI_ARSIZE,
    output wire [1:0]            S4_AXI_ARBURST,
    output wire [2:0]            S4_AXI_ARPROT,
    output wire                  S4_AXI_ARVALID,
    input  wire                  S4_AXI_ARREADY,

    input  wire [ID_WIDTH-1:0]   S4_AXI_RID,
    input  wire [DATA_WIDTH-1:0] S4_AXI_RDATA,
    input  wire [1:0]            S4_AXI_RRESP,
    input  wire                  S4_AXI_RLAST,
    input  wire                  S4_AXI_RVALID,
    output wire                  S4_AXI_RREADY,

    output wire [ID_WIDTH-1:0]   S4_AXI_AWID,
    output wire [ADDR_WIDTH-1:0] S4_AXI_AWADDR,
    output wire [7:0]            S4_AXI_AWLEN,
    output wire [2:0]            S4_AXI_AWSIZE,
    output wire [1:0]            S4_AXI_AWBURST,
    output wire [2:0]            S4_AXI_AWPROT,
    output wire                  S4_AXI_AWVALID,
    input  wire                  S4_AXI_AWREADY,

    output wire [DATA_WIDTH-1:0] S4_AXI_WDATA,
    output wire [STRB_WIDTH-1:0] S4_AXI_WSTRB,
    output wire                  S4_AXI_WLAST,
    output wire                  S4_AXI_WVALID,
    input  wire                  S4_AXI_WREADY,

    input  wire [ID_WIDTH-1:0]   S4_AXI_BID,
    input  wire [1:0]            S4_AXI_BRESP,
    input  wire                  S4_AXI_BVALID,
    output wire                  S4_AXI_BREADY
);

    // ========================================================================
    // Address Decode — M0 (AR + AW)
    // ========================================================================
    wire [2:0] m0_ar_slave_sel, m0_aw_slave_sel;

    axi4_addr_decoder #(
        .NUM_SLAVES(5),
        .S0_BASE(S0_BASE), .S0_MASK(S0_MASK),
        .S1_BASE(S1_BASE), .S1_MASK(S1_MASK),
        .S2_BASE(S2_BASE), .S2_MASK(S2_MASK),
        .S3_BASE(S3_BASE), .S3_MASK(S3_MASK),
        .S4_BASE(S4_BASE), .S4_MASK(S4_MASK)
    ) dec_m0_ar (.addr(M0_AXI_ARADDR), .slave_sel(m0_ar_slave_sel));

    axi4_addr_decoder #(
        .NUM_SLAVES(5),
        .S0_BASE(S0_BASE), .S0_MASK(S0_MASK),
        .S1_BASE(S1_BASE), .S1_MASK(S1_MASK),
        .S2_BASE(S2_BASE), .S2_MASK(S2_MASK),
        .S3_BASE(S3_BASE), .S3_MASK(S3_MASK),
        .S4_BASE(S4_BASE), .S4_MASK(S4_MASK)
    ) dec_m0_aw (.addr(M0_AXI_AWADDR), .slave_sel(m0_aw_slave_sel));

    // ========================================================================
    // Address Decode — M1 (AR + AW)
    // ========================================================================
    wire [2:0] m1_ar_slave_sel, m1_aw_slave_sel;

    axi4_addr_decoder #(
        .NUM_SLAVES(5),
        .S0_BASE(S0_BASE), .S0_MASK(S0_MASK),
        .S1_BASE(S1_BASE), .S1_MASK(S1_MASK),
        .S2_BASE(S2_BASE), .S2_MASK(S2_MASK),
        .S3_BASE(S3_BASE), .S3_MASK(S3_MASK),
        .S4_BASE(S4_BASE), .S4_MASK(S4_MASK)
    ) dec_m1_ar (.addr(M1_AXI_ARADDR), .slave_sel(m1_ar_slave_sel));

    axi4_addr_decoder #(
        .NUM_SLAVES(5),
        .S0_BASE(S0_BASE), .S0_MASK(S0_MASK),
        .S1_BASE(S1_BASE), .S1_MASK(S1_MASK),
        .S2_BASE(S2_BASE), .S2_MASK(S2_MASK),
        .S3_BASE(S3_BASE), .S3_MASK(S3_MASK),
        .S4_BASE(S4_BASE), .S4_MASK(S4_MASK)
    ) dec_m1_aw (.addr(M1_AXI_AWADDR), .slave_sel(m1_aw_slave_sel));

    // ========================================================================
    // Address Decode — M2 / DMA (AR + AW)
    // ========================================================================
    wire [2:0] m2_ar_slave_sel, m2_aw_slave_sel;

    axi4_addr_decoder #(
        .NUM_SLAVES(5),
        .S0_BASE(S0_BASE), .S0_MASK(S0_MASK),
        .S1_BASE(S1_BASE), .S1_MASK(S1_MASK),
        .S2_BASE(S2_BASE), .S2_MASK(S2_MASK),
        .S3_BASE(S3_BASE), .S3_MASK(S3_MASK),
        .S4_BASE(S4_BASE), .S4_MASK(S4_MASK)
    ) dec_m2_ar (.addr(M2_AXI_ARADDR), .slave_sel(m2_ar_slave_sel));

    axi4_addr_decoder #(
        .NUM_SLAVES(5),
        .S0_BASE(S0_BASE), .S0_MASK(S0_MASK),
        .S1_BASE(S1_BASE), .S1_MASK(S1_MASK),
        .S2_BASE(S2_BASE), .S2_MASK(S2_MASK),
        .S3_BASE(S3_BASE), .S3_MASK(S3_MASK),
        .S4_BASE(S4_BASE), .S4_MASK(S4_MASK)
    ) dec_m2_aw (.addr(M2_AXI_AWADDR), .slave_sel(m2_aw_slave_sel));

    // ========================================================================
    // Steer: Master AR/AW → valid per slave
    // index 5 = DECERR
    // ========================================================================

    // M0 AR steered
    wire m0_ar_to_s0  = M0_AXI_ARVALID && (m0_ar_slave_sel == 3'd0);
    wire m0_ar_to_s1  = M0_AXI_ARVALID && (m0_ar_slave_sel == 3'd1);
    wire m0_ar_to_s2  = M0_AXI_ARVALID && (m0_ar_slave_sel == 3'd2);
    wire m0_ar_to_s3  = M0_AXI_ARVALID && (m0_ar_slave_sel == 3'd3);
    wire m0_ar_to_s4  = M0_AXI_ARVALID && (m0_ar_slave_sel == 3'd4);
    wire m0_ar_to_err = M0_AXI_ARVALID && (m0_ar_slave_sel == 3'd5);

    // M0 AW steered
    wire m0_aw_to_s0  = M0_AXI_AWVALID && (m0_aw_slave_sel == 3'd0);
    wire m0_aw_to_s1  = M0_AXI_AWVALID && (m0_aw_slave_sel == 3'd1);
    wire m0_aw_to_s2  = M0_AXI_AWVALID && (m0_aw_slave_sel == 3'd2);
    wire m0_aw_to_s3  = M0_AXI_AWVALID && (m0_aw_slave_sel == 3'd3);
    wire m0_aw_to_s4  = M0_AXI_AWVALID && (m0_aw_slave_sel == 3'd4);
    wire m0_aw_to_err = M0_AXI_AWVALID && (m0_aw_slave_sel == 3'd5);

    // M1 AR steered
    wire m1_ar_to_s0  = M1_AXI_ARVALID && (m1_ar_slave_sel == 3'd0);
    wire m1_ar_to_s1  = M1_AXI_ARVALID && (m1_ar_slave_sel == 3'd1);
    wire m1_ar_to_s2  = M1_AXI_ARVALID && (m1_ar_slave_sel == 3'd2);
    wire m1_ar_to_s3  = M1_AXI_ARVALID && (m1_ar_slave_sel == 3'd3);
    wire m1_ar_to_s4  = M1_AXI_ARVALID && (m1_ar_slave_sel == 3'd4);
    wire m1_ar_to_err = M1_AXI_ARVALID && (m1_ar_slave_sel == 3'd5);

    // M1 AW steered
    wire m1_aw_to_s0  = M1_AXI_AWVALID && (m1_aw_slave_sel == 3'd0);
    wire m1_aw_to_s1  = M1_AXI_AWVALID && (m1_aw_slave_sel == 3'd1);
    wire m1_aw_to_s2  = M1_AXI_AWVALID && (m1_aw_slave_sel == 3'd2);
    wire m1_aw_to_s3  = M1_AXI_AWVALID && (m1_aw_slave_sel == 3'd3);
    wire m1_aw_to_s4  = M1_AXI_AWVALID && (m1_aw_slave_sel == 3'd4);
    wire m1_aw_to_err = M1_AXI_AWVALID && (m1_aw_slave_sel == 3'd5);

    // M2 AR steered
    wire m2_ar_to_s0  = M2_AXI_ARVALID && (m2_ar_slave_sel == 3'd0);
    wire m2_ar_to_s1  = M2_AXI_ARVALID && (m2_ar_slave_sel == 3'd1);
    wire m2_ar_to_s2  = M2_AXI_ARVALID && (m2_ar_slave_sel == 3'd2);
    wire m2_ar_to_s3  = M2_AXI_ARVALID && (m2_ar_slave_sel == 3'd3);
    wire m2_ar_to_s4  = M2_AXI_ARVALID && (m2_ar_slave_sel == 3'd4);
    wire m2_ar_to_err = M2_AXI_ARVALID && (m2_ar_slave_sel == 3'd5);

    // M2 AW steered
    wire m2_aw_to_s0  = M2_AXI_AWVALID && (m2_aw_slave_sel == 3'd0);
    wire m2_aw_to_s1  = M2_AXI_AWVALID && (m2_aw_slave_sel == 3'd1);
    wire m2_aw_to_s2  = M2_AXI_AWVALID && (m2_aw_slave_sel == 3'd2);
    wire m2_aw_to_s3  = M2_AXI_AWVALID && (m2_aw_slave_sel == 3'd3);
    wire m2_aw_to_s4  = M2_AXI_AWVALID && (m2_aw_slave_sel == 3'd4);
    wire m2_aw_to_err = M2_AXI_AWVALID && (m2_aw_slave_sel == 3'd5);

    // ========================================================================
    // ARREADY / AWREADY / WREADY mux back to masters (OR từ slave mux + decerr)
    // index 0-4: real slaves, index 5: decerr
    // ========================================================================
    wire m0_arready_s [0:5], m1_arready_s [0:5], m2_arready_s [0:5];
    wire m0_awready_s [0:5], m1_awready_s [0:5], m2_awready_s [0:5];
    wire m0_wready_s  [0:5], m1_wready_s  [0:5], m2_wready_s  [0:5];

    assign M0_AXI_ARREADY = |{m0_arready_s[5],m0_arready_s[4],m0_arready_s[3],m0_arready_s[2],m0_arready_s[1],m0_arready_s[0]};
    assign M0_AXI_AWREADY = |{m0_awready_s[5],m0_awready_s[4],m0_awready_s[3],m0_awready_s[2],m0_awready_s[1],m0_awready_s[0]};
    assign M0_AXI_WREADY  = |{m0_wready_s[5], m0_wready_s[4], m0_wready_s[3], m0_wready_s[2], m0_wready_s[1], m0_wready_s[0]};

    assign M1_AXI_ARREADY = |{m1_arready_s[5],m1_arready_s[4],m1_arready_s[3],m1_arready_s[2],m1_arready_s[1],m1_arready_s[0]};
    assign M1_AXI_AWREADY = |{m1_awready_s[5],m1_awready_s[4],m1_awready_s[3],m1_awready_s[2],m1_awready_s[1],m1_awready_s[0]};
    assign M1_AXI_WREADY  = |{m1_wready_s[5], m1_wready_s[4], m1_wready_s[3], m1_wready_s[2], m1_wready_s[1], m1_wready_s[0]};

    assign M2_AXI_ARREADY = |{m2_arready_s[5],m2_arready_s[4],m2_arready_s[3],m2_arready_s[2],m2_arready_s[1],m2_arready_s[0]};
    assign M2_AXI_AWREADY = |{m2_awready_s[5],m2_awready_s[4],m2_awready_s[3],m2_awready_s[2],m2_awready_s[1],m2_awready_s[0]};
    assign M2_AXI_WREADY  = |{m2_wready_s[5], m2_wready_s[4], m2_wready_s[3], m2_wready_s[2], m2_wready_s[1], m2_wready_s[0]};

    // ========================================================================
    // R channel — gated OR bus
    // ========================================================================
    wire [ID_WIDTH-1:0]   m0_rid_s   [0:5]; wire [ID_WIDTH-1:0]   m1_rid_s   [0:5]; wire [ID_WIDTH-1:0]   m2_rid_s   [0:5];
    wire [DATA_WIDTH-1:0] m0_rdata_s [0:5]; wire [DATA_WIDTH-1:0] m1_rdata_s [0:5]; wire [DATA_WIDTH-1:0] m2_rdata_s [0:5];
    wire [1:0]            m0_rresp_s [0:5]; wire [1:0]            m1_rresp_s [0:5]; wire [1:0]            m2_rresp_s [0:5];
    wire                  m0_rlast_s [0:5]; wire                  m1_rlast_s [0:5]; wire                  m2_rlast_s [0:5];
    wire                  m0_rvalid_s[0:5]; wire                  m1_rvalid_s[0:5]; wire                  m2_rvalid_s[0:5];

    // M0 R bus
    assign M0_AXI_RID    = ({ID_WIDTH{m0_rvalid_s[0]}} & m0_rid_s[0])    | ({ID_WIDTH{m0_rvalid_s[1]}} & m0_rid_s[1])    | ({ID_WIDTH{m0_rvalid_s[2]}} & m0_rid_s[2])    | ({ID_WIDTH{m0_rvalid_s[3]}} & m0_rid_s[3])    | ({ID_WIDTH{m0_rvalid_s[4]}} & m0_rid_s[4])    | ({ID_WIDTH{m0_rvalid_s[5]}} & m0_rid_s[5]);
    assign M0_AXI_RDATA  = ({DATA_WIDTH{m0_rvalid_s[0]}} & m0_rdata_s[0]) | ({DATA_WIDTH{m0_rvalid_s[1]}} & m0_rdata_s[1]) | ({DATA_WIDTH{m0_rvalid_s[2]}} & m0_rdata_s[2]) | ({DATA_WIDTH{m0_rvalid_s[3]}} & m0_rdata_s[3]) | ({DATA_WIDTH{m0_rvalid_s[4]}} & m0_rdata_s[4]) | ({DATA_WIDTH{m0_rvalid_s[5]}} & m0_rdata_s[5]);
    assign M0_AXI_RRESP  = ({2{m0_rvalid_s[0]}} & m0_rresp_s[0]) | ({2{m0_rvalid_s[1]}} & m0_rresp_s[1]) | ({2{m0_rvalid_s[2]}} & m0_rresp_s[2]) | ({2{m0_rvalid_s[3]}} & m0_rresp_s[3]) | ({2{m0_rvalid_s[4]}} & m0_rresp_s[4]) | ({2{m0_rvalid_s[5]}} & m0_rresp_s[5]);
    assign M0_AXI_RLAST  = (m0_rvalid_s[0] & m0_rlast_s[0]) | (m0_rvalid_s[1] & m0_rlast_s[1]) | (m0_rvalid_s[2] & m0_rlast_s[2]) | (m0_rvalid_s[3] & m0_rlast_s[3]) | (m0_rvalid_s[4] & m0_rlast_s[4]) | (m0_rvalid_s[5] & m0_rlast_s[5]);
    assign M0_AXI_RVALID = m0_rvalid_s[0] | m0_rvalid_s[1] | m0_rvalid_s[2] | m0_rvalid_s[3] | m0_rvalid_s[4] | m0_rvalid_s[5];

    // M1 R bus
    assign M1_AXI_RID    = ({ID_WIDTH{m1_rvalid_s[0]}} & m1_rid_s[0])    | ({ID_WIDTH{m1_rvalid_s[1]}} & m1_rid_s[1])    | ({ID_WIDTH{m1_rvalid_s[2]}} & m1_rid_s[2])    | ({ID_WIDTH{m1_rvalid_s[3]}} & m1_rid_s[3])    | ({ID_WIDTH{m1_rvalid_s[4]}} & m1_rid_s[4])    | ({ID_WIDTH{m1_rvalid_s[5]}} & m1_rid_s[5]);
    assign M1_AXI_RDATA  = ({DATA_WIDTH{m1_rvalid_s[0]}} & m1_rdata_s[0]) | ({DATA_WIDTH{m1_rvalid_s[1]}} & m1_rdata_s[1]) | ({DATA_WIDTH{m1_rvalid_s[2]}} & m1_rdata_s[2]) | ({DATA_WIDTH{m1_rvalid_s[3]}} & m1_rdata_s[3]) | ({DATA_WIDTH{m1_rvalid_s[4]}} & m1_rdata_s[4]) | ({DATA_WIDTH{m1_rvalid_s[5]}} & m1_rdata_s[5]);
    assign M1_AXI_RRESP  = ({2{m1_rvalid_s[0]}} & m1_rresp_s[0]) | ({2{m1_rvalid_s[1]}} & m1_rresp_s[1]) | ({2{m1_rvalid_s[2]}} & m1_rresp_s[2]) | ({2{m1_rvalid_s[3]}} & m1_rresp_s[3]) | ({2{m1_rvalid_s[4]}} & m1_rresp_s[4]) | ({2{m1_rvalid_s[5]}} & m1_rresp_s[5]);
    assign M1_AXI_RLAST  = (m1_rvalid_s[0] & m1_rlast_s[0]) | (m1_rvalid_s[1] & m1_rlast_s[1]) | (m1_rvalid_s[2] & m1_rlast_s[2]) | (m1_rvalid_s[3] & m1_rlast_s[3]) | (m1_rvalid_s[4] & m1_rlast_s[4]) | (m1_rvalid_s[5] & m1_rlast_s[5]);
    assign M1_AXI_RVALID = m1_rvalid_s[0] | m1_rvalid_s[1] | m1_rvalid_s[2] | m1_rvalid_s[3] | m1_rvalid_s[4] | m1_rvalid_s[5];

    // M2 R bus
    assign M2_AXI_RID    = ({ID_WIDTH{m2_rvalid_s[0]}} & m2_rid_s[0])    | ({ID_WIDTH{m2_rvalid_s[1]}} & m2_rid_s[1])    | ({ID_WIDTH{m2_rvalid_s[2]}} & m2_rid_s[2])    | ({ID_WIDTH{m2_rvalid_s[3]}} & m2_rid_s[3])    | ({ID_WIDTH{m2_rvalid_s[4]}} & m2_rid_s[4])    | ({ID_WIDTH{m2_rvalid_s[5]}} & m2_rid_s[5]);
    assign M2_AXI_RDATA  = ({DATA_WIDTH{m2_rvalid_s[0]}} & m2_rdata_s[0]) | ({DATA_WIDTH{m2_rvalid_s[1]}} & m2_rdata_s[1]) | ({DATA_WIDTH{m2_rvalid_s[2]}} & m2_rdata_s[2]) | ({DATA_WIDTH{m2_rvalid_s[3]}} & m2_rdata_s[3]) | ({DATA_WIDTH{m2_rvalid_s[4]}} & m2_rdata_s[4]) | ({DATA_WIDTH{m2_rvalid_s[5]}} & m2_rdata_s[5]);
    assign M2_AXI_RRESP  = ({2{m2_rvalid_s[0]}} & m2_rresp_s[0]) | ({2{m2_rvalid_s[1]}} & m2_rresp_s[1]) | ({2{m2_rvalid_s[2]}} & m2_rresp_s[2]) | ({2{m2_rvalid_s[3]}} & m2_rresp_s[3]) | ({2{m2_rvalid_s[4]}} & m2_rresp_s[4]) | ({2{m2_rvalid_s[5]}} & m2_rresp_s[5]);
    assign M2_AXI_RLAST  = (m2_rvalid_s[0] & m2_rlast_s[0]) | (m2_rvalid_s[1] & m2_rlast_s[1]) | (m2_rvalid_s[2] & m2_rlast_s[2]) | (m2_rvalid_s[3] & m2_rlast_s[3]) | (m2_rvalid_s[4] & m2_rlast_s[4]) | (m2_rvalid_s[5] & m2_rlast_s[5]);
    assign M2_AXI_RVALID = m2_rvalid_s[0] | m2_rvalid_s[1] | m2_rvalid_s[2] | m2_rvalid_s[3] | m2_rvalid_s[4] | m2_rvalid_s[5];

    // B channel
    wire [ID_WIDTH-1:0] m0_bid_s [0:5], m1_bid_s [0:5], m2_bid_s [0:5];
    wire [1:0]          m0_bresp_s[0:5], m1_bresp_s[0:5], m2_bresp_s[0:5];
    wire                m0_bvalid_s[0:5], m1_bvalid_s[0:5], m2_bvalid_s[0:5];

    // M0 B bus
    assign M0_AXI_BID    = ({ID_WIDTH{m0_bvalid_s[0]}} & m0_bid_s[0]) | ({ID_WIDTH{m0_bvalid_s[1]}} & m0_bid_s[1]) | ({ID_WIDTH{m0_bvalid_s[2]}} & m0_bid_s[2]) | ({ID_WIDTH{m0_bvalid_s[3]}} & m0_bid_s[3]) | ({ID_WIDTH{m0_bvalid_s[4]}} & m0_bid_s[4]) | ({ID_WIDTH{m0_bvalid_s[5]}} & m0_bid_s[5]);
    assign M0_AXI_BRESP  = ({2{m0_bvalid_s[0]}} & m0_bresp_s[0]) | ({2{m0_bvalid_s[1]}} & m0_bresp_s[1]) | ({2{m0_bvalid_s[2]}} & m0_bresp_s[2]) | ({2{m0_bvalid_s[3]}} & m0_bresp_s[3]) | ({2{m0_bvalid_s[4]}} & m0_bresp_s[4]) | ({2{m0_bvalid_s[5]}} & m0_bresp_s[5]);
    assign M0_AXI_BVALID = m0_bvalid_s[0] | m0_bvalid_s[1] | m0_bvalid_s[2] | m0_bvalid_s[3] | m0_bvalid_s[4] | m0_bvalid_s[5];

    // M1 B bus
    assign M1_AXI_BID    = ({ID_WIDTH{m1_bvalid_s[0]}} & m1_bid_s[0]) | ({ID_WIDTH{m1_bvalid_s[1]}} & m1_bid_s[1]) | ({ID_WIDTH{m1_bvalid_s[2]}} & m1_bid_s[2]) | ({ID_WIDTH{m1_bvalid_s[3]}} & m1_bid_s[3]) | ({ID_WIDTH{m1_bvalid_s[4]}} & m1_bid_s[4]) | ({ID_WIDTH{m1_bvalid_s[5]}} & m1_bid_s[5]);
    assign M1_AXI_BRESP  = ({2{m1_bvalid_s[0]}} & m1_bresp_s[0]) | ({2{m1_bvalid_s[1]}} & m1_bresp_s[1]) | ({2{m1_bvalid_s[2]}} & m1_bresp_s[2]) | ({2{m1_bvalid_s[3]}} & m1_bresp_s[3]) | ({2{m1_bvalid_s[4]}} & m1_bresp_s[4]) | ({2{m1_bvalid_s[5]}} & m1_bid_s[5]);
    assign M1_AXI_BVALID = m1_bvalid_s[0] | m1_bvalid_s[1] | m1_bvalid_s[2] | m1_bvalid_s[3] | m1_bvalid_s[4] | m1_bvalid_s[5];

    // M2 B bus
    assign M2_AXI_BID    = ({ID_WIDTH{m2_bvalid_s[0]}} & m2_bid_s[0]) | ({ID_WIDTH{m2_bvalid_s[1]}} & m2_bid_s[1]) | ({ID_WIDTH{m2_bvalid_s[2]}} & m2_bid_s[2]) | ({ID_WIDTH{m2_bvalid_s[3]}} & m2_bid_s[3]) | ({ID_WIDTH{m2_bvalid_s[4]}} & m2_bid_s[4]) | ({ID_WIDTH{m2_bvalid_s[5]}} & m2_bid_s[5]);
    assign M2_AXI_BRESP  = ({2{m2_bvalid_s[0]}} & m2_bresp_s[0]) | ({2{m2_bvalid_s[1]}} & m2_bresp_s[1]) | ({2{m2_bvalid_s[2]}} & m2_bresp_s[2]) | ({2{m2_bvalid_s[3]}} & m2_bresp_s[3]) | ({2{m2_bvalid_s[4]}} & m2_bresp_s[4]) | ({2{m2_bvalid_s[5]}} & m2_bresp_s[5]);
    assign M2_AXI_BVALID = m2_bvalid_s[0] | m2_bvalid_s[1] | m2_bvalid_s[2] | m2_bvalid_s[3] | m2_bvalid_s[4] | m2_bvalid_s[5];

    // ========================================================================
    // Slave Mux instances — S0..S4
    // ========================================================================

    // ── Slave 0 mux (IMEM) ──────────────────────────────────────────────────
    axi4_master_mux_3m #(.ID_WIDTH(ID_WIDTH),.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH)) mux_s0 (
        .clk(clk), .rst_n(rst_n),
        .m0_arid(M0_AXI_ARID),   .m0_araddr(M0_AXI_ARADDR), .m0_arlen(M0_AXI_ARLEN),
        .m0_arsize(M0_AXI_ARSIZE),.m0_arburst(M0_AXI_ARBURST),.m0_arprot(M0_AXI_ARPROT),
        .m0_arvalid(m0_ar_to_s0), .m0_arready(m0_arready_s[0]),
        .m0_rid(m0_rid_s[0]),     .m0_rdata(m0_rdata_s[0]),  .m0_rresp(m0_rresp_s[0]),
        .m0_rlast(m0_rlast_s[0]), .m0_rvalid(m0_rvalid_s[0]),.m0_rready(M0_AXI_RREADY),
        .m0_awid(M0_AXI_AWID),   .m0_awaddr(M0_AXI_AWADDR), .m0_awlen(M0_AXI_AWLEN),
        .m0_awsize(M0_AXI_AWSIZE),.m0_awburst(M0_AXI_AWBURST),.m0_awprot(M0_AXI_AWPROT),
        .m0_awvalid(m0_aw_to_s0), .m0_awready(m0_awready_s[0]),
        .m0_wdata(M0_AXI_WDATA),  .m0_wstrb(M0_AXI_WSTRB),  .m0_wlast(M0_AXI_WLAST),
        .m0_wvalid(M0_AXI_WVALID),.m0_wready(m0_wready_s[0]),
        .m0_bid(m0_bid_s[0]),     .m0_bresp(m0_bresp_s[0]),  .m0_bvalid(m0_bvalid_s[0]),
        .m0_bready(M0_AXI_BREADY),
        .m1_arid(M1_AXI_ARID),   .m1_araddr(M1_AXI_ARADDR), .m1_arlen(M1_AXI_ARLEN),
        .m1_arsize(M1_AXI_ARSIZE),.m1_arburst(M1_AXI_ARBURST),.m1_arprot(M1_AXI_ARPROT),
        .m1_arvalid(m1_ar_to_s0), .m1_arready(m1_arready_s[0]),
        .m1_rid(m1_rid_s[0]),     .m1_rdata(m1_rdata_s[0]),  .m1_rresp(m1_rresp_s[0]),
        .m1_rlast(m1_rlast_s[0]), .m1_rvalid(m1_rvalid_s[0]),.m1_rready(M1_AXI_RREADY),
        .m1_awid(M1_AXI_AWID),   .m1_awaddr(M1_AXI_AWADDR), .m1_awlen(M1_AXI_AWLEN),
        .m1_awsize(M1_AXI_AWSIZE),.m1_awburst(M1_AXI_AWBURST),.m1_awprot(M1_AXI_AWPROT),
        .m1_awvalid(m1_aw_to_s0), .m1_awready(m1_awready_s[0]),
        .m1_wdata(M1_AXI_WDATA),  .m1_wstrb(M1_AXI_WSTRB),  .m1_wlast(M1_AXI_WLAST),
        .m1_wvalid(M1_AXI_WVALID),.m1_wready(m1_wready_s[0]),
        .m1_bid(m1_bid_s[0]),     .m1_bresp(m1_bresp_s[0]),  .m1_bvalid(m1_bvalid_s[0]),
        .m1_bready(M1_AXI_BREADY),
        .m2_arid(M2_AXI_ARID),   .m2_araddr(M2_AXI_ARADDR), .m2_arlen(M2_AXI_ARLEN),
        .m2_arsize(M2_AXI_ARSIZE),.m2_arburst(M2_AXI_ARBURST),.m2_arprot(M2_AXI_ARPROT),
        .m2_arvalid(m2_ar_to_s0), .m2_arready(m2_arready_s[0]),
        .m2_rid(m2_rid_s[0]),     .m2_rdata(m2_rdata_s[0]),  .m2_rresp(m2_rresp_s[0]),
        .m2_rlast(m2_rlast_s[0]), .m2_rvalid(m2_rvalid_s[0]),.m2_rready(M2_AXI_RREADY),
        .m2_awid(M2_AXI_AWID),   .m2_awaddr(M2_AXI_AWADDR), .m2_awlen(M2_AXI_AWLEN),
        .m2_awsize(M2_AXI_AWSIZE),.m2_awburst(M2_AXI_AWBURST),.m2_awprot(M2_AXI_AWPROT),
        .m2_awvalid(m2_aw_to_s0), .m2_awready(m2_awready_s[0]),
        .m2_wdata(M2_AXI_WDATA),  .m2_wstrb(M2_AXI_WSTRB),  .m2_wlast(M2_AXI_WLAST),
        .m2_wvalid(M2_AXI_WVALID),.m2_wready(m2_wready_s[0]),
        .m2_bid(m2_bid_s[0]),     .m2_bresp(m2_bresp_s[0]),  .m2_bvalid(m2_bvalid_s[0]),
        .m2_bready(M2_AXI_BREADY),
        .s_arid(S0_AXI_ARID),    .s_araddr(S0_AXI_ARADDR),  .s_arlen(S0_AXI_ARLEN),
        .s_arsize(S0_AXI_ARSIZE),.s_arburst(S0_AXI_ARBURST),.s_arprot(S0_AXI_ARPROT),
        .s_arvalid(S0_AXI_ARVALID),.s_arready(S0_AXI_ARREADY),
        .s_rid(S0_AXI_RID),      .s_rdata(S0_AXI_RDATA),    .s_rresp(S0_AXI_RRESP),
        .s_rlast(S0_AXI_RLAST),  .s_rvalid(S0_AXI_RVALID),  .s_rready(S0_AXI_RREADY),
        .s_awid(S0_AXI_AWID),    .s_awaddr(S0_AXI_AWADDR),  .s_awlen(S0_AXI_AWLEN),
        .s_awsize(S0_AXI_AWSIZE),.s_awburst(S0_AXI_AWBURST),.s_awprot(S0_AXI_AWPROT),
        .s_awvalid(S0_AXI_AWVALID),.s_awready(S0_AXI_AWREADY),
        .s_wdata(S0_AXI_WDATA),  .s_wstrb(S0_AXI_WSTRB),    .s_wlast(S0_AXI_WLAST),
        .s_wvalid(S0_AXI_WVALID),.s_wready(S0_AXI_WREADY),
        .s_bid(S0_AXI_BID),      .s_bresp(S0_AXI_BRESP),    .s_bvalid(S0_AXI_BVALID),
        .s_bready(S0_AXI_BREADY)
    );

    // ── Slave 1 mux (DMEM) ──────────────────────────────────────────────────
    axi4_master_mux_3m #(.ID_WIDTH(ID_WIDTH),.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH)) mux_s1 (
        .clk(clk), .rst_n(rst_n),
        .m0_arid(M0_AXI_ARID),   .m0_araddr(M0_AXI_ARADDR), .m0_arlen(M0_AXI_ARLEN),
        .m0_arsize(M0_AXI_ARSIZE),.m0_arburst(M0_AXI_ARBURST),.m0_arprot(M0_AXI_ARPROT),
        .m0_arvalid(m0_ar_to_s1), .m0_arready(m0_arready_s[1]),
        .m0_rid(m0_rid_s[1]),     .m0_rdata(m0_rdata_s[1]),  .m0_rresp(m0_rresp_s[1]),
        .m0_rlast(m0_rlast_s[1]), .m0_rvalid(m0_rvalid_s[1]),.m0_rready(M0_AXI_RREADY),
        .m0_awid(M0_AXI_AWID),   .m0_awaddr(M0_AXI_AWADDR), .m0_awlen(M0_AXI_AWLEN),
        .m0_awsize(M0_AXI_AWSIZE),.m0_awburst(M0_AXI_AWBURST),.m0_awprot(M0_AXI_AWPROT),
        .m0_awvalid(m0_aw_to_s1), .m0_awready(m0_awready_s[1]),
        .m0_wdata(M0_AXI_WDATA),  .m0_wstrb(M0_AXI_WSTRB),  .m0_wlast(M0_AXI_WLAST),
        .m0_wvalid(M0_AXI_WVALID),.m0_wready(m0_wready_s[1]),
        .m0_bid(m0_bid_s[1]),     .m0_bresp(m0_bresp_s[1]),  .m0_bvalid(m0_bvalid_s[1]),
        .m0_bready(M0_AXI_BREADY),
        .m1_arid(M1_AXI_ARID),   .m1_araddr(M1_AXI_ARADDR), .m1_arlen(M1_AXI_ARLEN),
        .m1_arsize(M1_AXI_ARSIZE),.m1_arburst(M1_AXI_ARBURST),.m1_arprot(M1_AXI_ARPROT),
        .m1_arvalid(m1_ar_to_s1), .m1_arready(m1_arready_s[1]),
        .m1_rid(m1_rid_s[1]),     .m1_rdata(m1_rdata_s[1]),  .m1_rresp(m1_rresp_s[1]),
        .m1_rlast(m1_rlast_s[1]), .m1_rvalid(m1_rvalid_s[1]),.m1_rready(M1_AXI_RREADY),
        .m1_awid(M1_AXI_AWID),   .m1_awaddr(M1_AXI_AWADDR), .m1_awlen(M1_AXI_AWLEN),
        .m1_awsize(M1_AXI_AWSIZE),.m1_awburst(M1_AXI_AWBURST),.m1_awprot(M1_AXI_AWPROT),
        .m1_awvalid(m1_aw_to_s1), .m1_awready(m1_awready_s[1]),
        .m1_wdata(M1_AXI_WDATA),  .m1_wstrb(M1_AXI_WSTRB),  .m1_wlast(M1_AXI_WLAST),
        .m1_wvalid(M1_AXI_WVALID),.m1_wready(m1_wready_s[1]),
        .m1_bid(m1_bid_s[1]),     .m1_bresp(m1_bresp_s[1]),  .m1_bvalid(m1_bvalid_s[1]),
        .m1_bready(M1_AXI_BREADY),
        .m2_arid(M2_AXI_ARID),   .m2_araddr(M2_AXI_ARADDR), .m2_arlen(M2_AXI_ARLEN),
        .m2_arsize(M2_AXI_ARSIZE),.m2_arburst(M2_AXI_ARBURST),.m2_arprot(M2_AXI_ARPROT),
        .m2_arvalid(m2_ar_to_s1), .m2_arready(m2_arready_s[1]),
        .m2_rid(m2_rid_s[1]),     .m2_rdata(m2_rdata_s[1]),  .m2_rresp(m2_rresp_s[1]),
        .m2_rlast(m2_rlast_s[1]), .m2_rvalid(m2_rvalid_s[1]),.m2_rready(M2_AXI_RREADY),
        .m2_awid(M2_AXI_AWID),   .m2_awaddr(M2_AXI_AWADDR), .m2_awlen(M2_AXI_AWLEN),
        .m2_awsize(M2_AXI_AWSIZE),.m2_awburst(M2_AXI_AWBURST),.m2_awprot(M2_AXI_AWPROT),
        .m2_awvalid(m2_aw_to_s1), .m2_awready(m2_awready_s[1]),
        .m2_wdata(M2_AXI_WDATA),  .m2_wstrb(M2_AXI_WSTRB),  .m2_wlast(M2_AXI_WLAST),
        .m2_wvalid(M2_AXI_WVALID),.m2_wready(m2_wready_s[1]),
        .m2_bid(m2_bid_s[1]),     .m2_bresp(m2_bresp_s[1]),  .m2_bvalid(m2_bvalid_s[1]),
        .m2_bready(M2_AXI_BREADY),
        .s_arid(S1_AXI_ARID),    .s_araddr(S1_AXI_ARADDR),  .s_arlen(S1_AXI_ARLEN),
        .s_arsize(S1_AXI_ARSIZE),.s_arburst(S1_AXI_ARBURST),.s_arprot(S1_AXI_ARPROT),
        .s_arvalid(S1_AXI_ARVALID),.s_arready(S1_AXI_ARREADY),
        .s_rid(S1_AXI_RID),      .s_rdata(S1_AXI_RDATA),    .s_rresp(S1_AXI_RRESP),
        .s_rlast(S1_AXI_RLAST),  .s_rvalid(S1_AXI_RVALID),  .s_rready(S1_AXI_RREADY),
        .s_awid(S1_AXI_AWID),    .s_awaddr(S1_AXI_AWADDR),  .s_awlen(S1_AXI_AWLEN),
        .s_awsize(S1_AXI_AWSIZE),.s_awburst(S1_AXI_AWBURST),.s_awprot(S1_AXI_AWPROT),
        .s_awvalid(S1_AXI_AWVALID),.s_awready(S1_AXI_AWREADY),
        .s_wdata(S1_AXI_WDATA),  .s_wstrb(S1_AXI_WSTRB),    .s_wlast(S1_AXI_WLAST),
        .s_wvalid(S1_AXI_WVALID),.s_wready(S1_AXI_WREADY),
        .s_bid(S1_AXI_BID),      .s_bresp(S1_AXI_BRESP),    .s_bvalid(S1_AXI_BVALID),
        .s_bready(S1_AXI_BREADY)
    );

    // ── Slave 2 mux (ASCON) ─────────────────────────────────────────────────
    axi4_master_mux_3m #(.ID_WIDTH(ID_WIDTH),.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH)) mux_s2 (
        .clk(clk), .rst_n(rst_n),
        .m0_arid(M0_AXI_ARID),   .m0_araddr(M0_AXI_ARADDR), .m0_arlen(M0_AXI_ARLEN),
        .m0_arsize(M0_AXI_ARSIZE),.m0_arburst(M0_AXI_ARBURST),.m0_arprot(M0_AXI_ARPROT),
        .m0_arvalid(m0_ar_to_s2), .m0_arready(m0_arready_s[2]),
        .m0_rid(m0_rid_s[2]),     .m0_rdata(m0_rdata_s[2]),  .m0_rresp(m0_rresp_s[2]),
        .m0_rlast(m0_rlast_s[2]), .m0_rvalid(m0_rvalid_s[2]),.m0_rready(M0_AXI_RREADY),
        .m0_awid(M0_AXI_AWID),   .m0_awaddr(M0_AXI_AWADDR), .m0_awlen(M0_AXI_AWLEN),
        .m0_awsize(M0_AXI_AWSIZE),.m0_awburst(M0_AXI_AWBURST),.m0_awprot(M0_AXI_AWPROT),
        .m0_awvalid(m0_aw_to_s2), .m0_awready(m0_awready_s[2]),
        .m0_wdata(M0_AXI_WDATA),  .m0_wstrb(M0_AXI_WSTRB),  .m0_wlast(M0_AXI_WLAST),
        .m0_wvalid(M0_AXI_WVALID),.m0_wready(m0_wready_s[2]),
        .m0_bid(m0_bid_s[2]),     .m0_bresp(m0_bresp_s[2]),  .m0_bvalid(m0_bvalid_s[2]),
        .m0_bready(M0_AXI_BREADY),
        .m1_arid(M1_AXI_ARID),   .m1_araddr(M1_AXI_ARADDR), .m1_arlen(M1_AXI_ARLEN),
        .m1_arsize(M1_AXI_ARSIZE),.m1_arburst(M1_AXI_ARBURST),.m1_arprot(M1_AXI_ARPROT),
        .m1_arvalid(m1_ar_to_s2), .m1_arready(m1_arready_s[2]),
        .m1_rid(m1_rid_s[2]),     .m1_rdata(m1_rdata_s[2]),  .m1_rresp(m1_rresp_s[2]),
        .m1_rlast(m1_rlast_s[2]), .m1_rvalid(m1_rvalid_s[2]),.m1_rready(M1_AXI_RREADY),
        .m1_awid(M1_AXI_AWID),   .m1_awaddr(M1_AXI_AWADDR), .m1_awlen(M1_AXI_AWLEN),
        .m1_awsize(M1_AXI_AWSIZE),.m1_awburst(M1_AXI_AWBURST),.m1_awprot(M1_AXI_AWPROT),
        .m1_awvalid(m1_aw_to_s2), .m1_awready(m1_awready_s[2]),
        .m1_wdata(M1_AXI_WDATA),  .m1_wstrb(M1_AXI_WSTRB),  .m1_wlast(M1_AXI_WLAST),
        .m1_wvalid(M1_AXI_WVALID),.m1_wready(m1_wready_s[2]),
        .m1_bid(m1_bid_s[2]),     .m1_bresp(m1_bresp_s[2]),  .m1_bvalid(m1_bvalid_s[2]),
        .m1_bready(M1_AXI_BREADY),
        .m2_arid(M2_AXI_ARID),   .m2_araddr(M2_AXI_ARADDR), .m2_arlen(M2_AXI_ARLEN),
        .m2_arsize(M2_AXI_ARSIZE),.m2_arburst(M2_AXI_ARBURST),.m2_arprot(M2_AXI_ARPROT),
        .m2_arvalid(m2_ar_to_s2), .m2_arready(m2_arready_s[2]),
        .m2_rid(m2_rid_s[2]),     .m2_rdata(m2_rdata_s[2]),  .m2_rresp(m2_rresp_s[2]),
        .m2_rlast(m2_rlast_s[2]), .m2_rvalid(m2_rvalid_s[2]),.m2_rready(M2_AXI_RREADY),
        .m2_awid(M2_AXI_AWID),   .m2_awaddr(M2_AXI_AWADDR), .m2_awlen(M2_AXI_AWLEN),
        .m2_awsize(M2_AXI_AWSIZE),.m2_awburst(M2_AXI_AWBURST),.m2_awprot(M2_AXI_AWPROT),
        .m2_awvalid(m2_aw_to_s2), .m2_awready(m2_awready_s[2]),
        .m2_wdata(M2_AXI_WDATA),  .m2_wstrb(M2_AXI_WSTRB),  .m2_wlast(M2_AXI_WLAST),
        .m2_wvalid(M2_AXI_WVALID),.m2_wready(m2_wready_s[2]),
        .m2_bid(m2_bid_s[2]),     .m2_bresp(m2_bresp_s[2]),  .m2_bvalid(m2_bvalid_s[2]),
        .m2_bready(M2_AXI_BREADY),
        .s_arid(S2_AXI_ARID),    .s_araddr(S2_AXI_ARADDR),  .s_arlen(S2_AXI_ARLEN),
        .s_arsize(S2_AXI_ARSIZE),.s_arburst(S2_AXI_ARBURST),.s_arprot(S2_AXI_ARPROT),
        .s_arvalid(S2_AXI_ARVALID),.s_arready(S2_AXI_ARREADY),
        .s_rid(S2_AXI_RID),      .s_rdata(S2_AXI_RDATA),    .s_rresp(S2_AXI_RRESP),
        .s_rlast(S2_AXI_RLAST),  .s_rvalid(S2_AXI_RVALID),  .s_rready(S2_AXI_RREADY),
        .s_awid(S2_AXI_AWID),    .s_awaddr(S2_AXI_AWADDR),  .s_awlen(S2_AXI_AWLEN),
        .s_awsize(S2_AXI_AWSIZE),.s_awburst(S2_AXI_AWBURST),.s_awprot(S2_AXI_AWPROT),
        .s_awvalid(S2_AXI_AWVALID),.s_awready(S2_AXI_AWREADY),
        .s_wdata(S2_AXI_WDATA),  .s_wstrb(S2_AXI_WSTRB),    .s_wlast(S2_AXI_WLAST),
        .s_wvalid(S2_AXI_WVALID),.s_wready(S2_AXI_WREADY),
        .s_bid(S2_AXI_BID),      .s_bresp(S2_AXI_BRESP),    .s_bvalid(S2_AXI_BVALID),
        .s_bready(S2_AXI_BREADY)
    );

    // ── Slave 3 mux (SoC Ctrl) ───────────────────────────────────────────────
    axi4_master_mux_3m #(.ID_WIDTH(ID_WIDTH),.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH)) mux_s3 (
        .clk(clk), .rst_n(rst_n),
        .m0_arid(M0_AXI_ARID),   .m0_araddr(M0_AXI_ARADDR), .m0_arlen(M0_AXI_ARLEN),
        .m0_arsize(M0_AXI_ARSIZE),.m0_arburst(M0_AXI_ARBURST),.m0_arprot(M0_AXI_ARPROT),
        .m0_arvalid(m0_ar_to_s3), .m0_arready(m0_arready_s[3]),
        .m0_rid(m0_rid_s[3]),     .m0_rdata(m0_rdata_s[3]),  .m0_rresp(m0_rresp_s[3]),
        .m0_rlast(m0_rlast_s[3]), .m0_rvalid(m0_rvalid_s[3]),.m0_rready(M0_AXI_RREADY),
        .m0_awid(M0_AXI_AWID),   .m0_awaddr(M0_AXI_AWADDR), .m0_awlen(M0_AXI_AWLEN),
        .m0_awsize(M0_AXI_AWSIZE),.m0_awburst(M0_AXI_AWBURST),.m0_awprot(M0_AXI_AWPROT),
        .m0_awvalid(m0_aw_to_s3), .m0_awready(m0_awready_s[3]),
        .m0_wdata(M0_AXI_WDATA),  .m0_wstrb(M0_AXI_WSTRB),  .m0_wlast(M0_AXI_WLAST),
        .m0_wvalid(M0_AXI_WVALID),.m0_wready(m0_wready_s[3]),
        .m0_bid(m0_bid_s[3]),     .m0_bresp(m0_bresp_s[3]),  .m0_bvalid(m0_bvalid_s[3]),
        .m0_bready(M0_AXI_BREADY),
        .m1_arid(M1_AXI_ARID),   .m1_araddr(M1_AXI_ARADDR), .m1_arlen(M1_AXI_ARLEN),
        .m1_arsize(M1_AXI_ARSIZE),.m1_arburst(M1_AXI_ARBURST),.m1_arprot(M1_AXI_ARPROT),
        .m1_arvalid(m1_ar_to_s3), .m1_arready(m1_arready_s[3]),
        .m1_rid(m1_rid_s[3]),     .m1_rdata(m1_rdata_s[3]),  .m1_rresp(m1_rresp_s[3]),
        .m1_rlast(m1_rlast_s[3]), .m1_rvalid(m1_rvalid_s[3]),.m1_rready(M1_AXI_RREADY),
        .m1_awid(M1_AXI_AWID),   .m1_awaddr(M1_AXI_AWADDR), .m1_awlen(M1_AXI_AWLEN),
        .m1_awsize(M1_AXI_AWSIZE),.m1_awburst(M1_AXI_AWBURST),.m1_awprot(M1_AXI_AWPROT),
        .m1_awvalid(m1_aw_to_s3), .m1_awready(m1_awready_s[3]),
        .m1_wdata(M1_AXI_WDATA),  .m1_wstrb(M1_AXI_WSTRB),  .m1_wlast(M1_AXI_WLAST),
        .m1_wvalid(M1_AXI_WVALID),.m1_wready(m1_wready_s[3]),
        .m1_bid(m1_bid_s[3]),     .m1_bresp(m1_bresp_s[3]),  .m1_bvalid(m1_bvalid_s[3]),
        .m1_bready(M1_AXI_BREADY),
        .m2_arid(M2_AXI_ARID),   .m2_araddr(M2_AXI_ARADDR), .m2_arlen(M2_AXI_ARLEN),
        .m2_arsize(M2_AXI_ARSIZE),.m2_arburst(M2_AXI_ARBURST),.m2_arprot(M2_AXI_ARPROT),
        .m2_arvalid(m2_ar_to_s3), .m2_arready(m2_arready_s[3]),
        .m2_rid(m2_rid_s[3]),     .m2_rdata(m2_rdata_s[3]),  .m2_rresp(m2_rresp_s[3]),
        .m2_rlast(m2_rlast_s[3]), .m2_rvalid(m2_rvalid_s[3]),.m2_rready(M2_AXI_RREADY),
        .m2_awid(M2_AXI_AWID),   .m2_awaddr(M2_AXI_AWADDR), .m2_awlen(M2_AXI_AWLEN),
        .m2_awsize(M2_AXI_AWSIZE),.m2_awburst(M2_AXI_AWBURST),.m2_awprot(M2_AXI_AWPROT),
        .m2_awvalid(m2_aw_to_s3), .m2_awready(m2_awready_s[3]),
        .m2_wdata(M2_AXI_WDATA),  .m2_wstrb(M2_AXI_WSTRB),  .m2_wlast(M2_AXI_WLAST),
        .m2_wvalid(M2_AXI_WVALID),.m2_wready(m2_wready_s[3]),
        .m2_bid(m2_bid_s[3]),     .m2_bresp(m2_bresp_s[3]),  .m2_bvalid(m2_bvalid_s[3]),
        .m2_bready(M2_AXI_BREADY),
        .s_arid(S3_AXI_ARID),    .s_araddr(S3_AXI_ARADDR),  .s_arlen(S3_AXI_ARLEN),
        .s_arsize(S3_AXI_ARSIZE),.s_arburst(S3_AXI_ARBURST),.s_arprot(S3_AXI_ARPROT),
        .s_arvalid(S3_AXI_ARVALID),.s_arready(S3_AXI_ARREADY),
        .s_rid(S3_AXI_RID),      .s_rdata(S3_AXI_RDATA),    .s_rresp(S3_AXI_RRESP),
        .s_rlast(S3_AXI_RLAST),  .s_rvalid(S3_AXI_RVALID),  .s_rready(S3_AXI_RREADY),
        .s_awid(S3_AXI_AWID),    .s_awaddr(S3_AXI_AWADDR),  .s_awlen(S3_AXI_AWLEN),
        .s_awsize(S3_AXI_AWSIZE),.s_awburst(S3_AXI_AWBURST),.s_awprot(S3_AXI_AWPROT),
        .s_awvalid(S3_AXI_AWVALID),.s_awready(S3_AXI_AWREADY),
        .s_wdata(S3_AXI_WDATA),  .s_wstrb(S3_AXI_WSTRB),    .s_wlast(S3_AXI_WLAST),
        .s_wvalid(S3_AXI_WVALID),.s_wready(S3_AXI_WREADY),
        .s_bid(S3_AXI_BID),      .s_bresp(S3_AXI_BRESP),    .s_bvalid(S3_AXI_BVALID),
        .s_bready(S3_AXI_BREADY)
    );

    // ── Slave 4 mux (CLINT)  [Fix 3] ─────────────────────────────────────────
    axi4_master_mux_3m #(.ID_WIDTH(ID_WIDTH),.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH)) mux_s4 (
        .clk(clk), .rst_n(rst_n),
        .m0_arid(M0_AXI_ARID),   .m0_araddr(M0_AXI_ARADDR), .m0_arlen(M0_AXI_ARLEN),
        .m0_arsize(M0_AXI_ARSIZE),.m0_arburst(M0_AXI_ARBURST),.m0_arprot(M0_AXI_ARPROT),
        .m0_arvalid(m0_ar_to_s4), .m0_arready(m0_arready_s[4]),
        .m0_rid(m0_rid_s[4]),     .m0_rdata(m0_rdata_s[4]),  .m0_rresp(m0_rresp_s[4]),
        .m0_rlast(m0_rlast_s[4]), .m0_rvalid(m0_rvalid_s[4]),.m0_rready(M0_AXI_RREADY),
        .m0_awid(M0_AXI_AWID),   .m0_awaddr(M0_AXI_AWADDR), .m0_awlen(M0_AXI_AWLEN),
        .m0_awsize(M0_AXI_AWSIZE),.m0_awburst(M0_AXI_AWBURST),.m0_awprot(M0_AXI_AWPROT),
        .m0_awvalid(m0_aw_to_s4), .m0_awready(m0_awready_s[4]),
        .m0_wdata(M0_AXI_WDATA),  .m0_wstrb(M0_AXI_WSTRB),  .m0_wlast(M0_AXI_WLAST),
        .m0_wvalid(M0_AXI_WVALID),.m0_wready(m0_wready_s[4]),
        .m0_bid(m0_bid_s[4]),     .m0_bresp(m0_bresp_s[4]),  .m0_bvalid(m0_bvalid_s[4]),
        .m0_bready(M0_AXI_BREADY),
        .m1_arid(M1_AXI_ARID),   .m1_araddr(M1_AXI_ARADDR), .m1_arlen(M1_AXI_ARLEN),
        .m1_arsize(M1_AXI_ARSIZE),.m1_arburst(M1_AXI_ARBURST),.m1_arprot(M1_AXI_ARPROT),
        .m1_arvalid(m1_ar_to_s4), .m1_arready(m1_arready_s[4]),
        .m1_rid(m1_rid_s[4]),     .m1_rdata(m1_rdata_s[4]),  .m1_rresp(m1_rresp_s[4]),
        .m1_rlast(m1_rlast_s[4]), .m1_rvalid(m1_rvalid_s[4]),.m1_rready(M1_AXI_RREADY),
        .m1_awid(M1_AXI_AWID),   .m1_awaddr(M1_AXI_AWADDR), .m1_awlen(M1_AXI_AWLEN),
        .m1_awsize(M1_AXI_AWSIZE),.m1_awburst(M1_AXI_AWBURST),.m1_awprot(M1_AXI_AWPROT),
        .m1_awvalid(m1_aw_to_s4), .m1_awready(m1_awready_s[4]),
        .m1_wdata(M1_AXI_WDATA),  .m1_wstrb(M1_AXI_WSTRB),  .m1_wlast(M1_AXI_WLAST),
        .m1_wvalid(M1_AXI_WVALID),.m1_wready(m1_wready_s[4]),
        .m1_bid(m1_bid_s[4]),     .m1_bresp(m1_bresp_s[4]),  .m1_bvalid(m1_bvalid_s[4]),
        .m1_bready(M1_AXI_BREADY),
        .m2_arid(M2_AXI_ARID),   .m2_araddr(M2_AXI_ARADDR), .m2_arlen(M2_AXI_ARLEN),
        .m2_arsize(M2_AXI_ARSIZE),.m2_arburst(M2_AXI_ARBURST),.m2_arprot(M2_AXI_ARPROT),
        .m2_arvalid(m2_ar_to_s4), .m2_arready(m2_arready_s[4]),
        .m2_rid(m2_rid_s[4]),     .m2_rdata(m2_rdata_s[4]),  .m2_rresp(m2_rresp_s[4]),
        .m2_rlast(m2_rlast_s[4]), .m2_rvalid(m2_rvalid_s[4]),.m2_rready(M2_AXI_RREADY),
        .m2_awid(M2_AXI_AWID),   .m2_awaddr(M2_AXI_AWADDR), .m2_awlen(M2_AXI_AWLEN),
        .m2_awsize(M2_AXI_AWSIZE),.m2_awburst(M2_AXI_AWBURST),.m2_awprot(M2_AXI_AWPROT),
        .m2_awvalid(m2_aw_to_s4), .m2_awready(m2_awready_s[4]),
        .m2_wdata(M2_AXI_WDATA),  .m2_wstrb(M2_AXI_WSTRB),  .m2_wlast(M2_AXI_WLAST),
        .m2_wvalid(M2_AXI_WVALID),.m2_wready(m2_wready_s[4]),
        .m2_bid(m2_bid_s[4]),     .m2_bresp(m2_bresp_s[4]),  .m2_bvalid(m2_bvalid_s[4]),
        .m2_bready(M2_AXI_BREADY),
        .s_arid(S4_AXI_ARID),    .s_araddr(S4_AXI_ARADDR),  .s_arlen(S4_AXI_ARLEN),
        .s_arsize(S4_AXI_ARSIZE),.s_arburst(S4_AXI_ARBURST),.s_arprot(S4_AXI_ARPROT),
        .s_arvalid(S4_AXI_ARVALID),.s_arready(S4_AXI_ARREADY),
        .s_rid(S4_AXI_RID),      .s_rdata(S4_AXI_RDATA),    .s_rresp(S4_AXI_RRESP),
        .s_rlast(S4_AXI_RLAST),  .s_rvalid(S4_AXI_RVALID),  .s_rready(S4_AXI_RREADY),
        .s_awid(S4_AXI_AWID),    .s_awaddr(S4_AXI_AWADDR),  .s_awlen(S4_AXI_AWLEN),
        .s_awsize(S4_AXI_AWSIZE),.s_awburst(S4_AXI_AWBURST),.s_awprot(S4_AXI_AWPROT),
        .s_awvalid(S4_AXI_AWVALID),.s_awready(S4_AXI_AWREADY),
        .s_wdata(S4_AXI_WDATA),  .s_wstrb(S4_AXI_WSTRB),    .s_wlast(S4_AXI_WLAST),
        .s_wvalid(S4_AXI_WVALID),.s_wready(S4_AXI_WREADY),
        .s_bid(S4_AXI_BID),      .s_bresp(S4_AXI_BRESP),    .s_bvalid(S4_AXI_BVALID),
        .s_bready(S4_AXI_BREADY)
    );

    // ========================================================================
    // DECERR slave — địa chỉ không ánh xạ (index 5)
    // Một instance cho mỗi master — M0, M1, M2
    // ========================================================================

    // ── M0 DECERR ────────────────────────────────────────────────────────────
    axi4_decerr_slave #(.ID_WIDTH(ID_WIDTH),.DATA_WIDTH(DATA_WIDTH)) decerr_m0 (
        .clk(clk), .rst_n(rst_n),
        .s_arid(M0_AXI_ARID),     .s_araddr(M0_AXI_ARADDR), .s_arlen(M0_AXI_ARLEN),
        .s_arvalid(m0_ar_to_err), .s_arready(m0_arready_s[5]),
        .s_rid(m0_rid_s[5]),       .s_rdata(m0_rdata_s[5]),   .s_rresp(m0_rresp_s[5]),
        .s_rlast(m0_rlast_s[5]),   .s_rvalid(m0_rvalid_s[5]), .s_rready(M0_AXI_RREADY),
        .s_awid(M0_AXI_AWID),     .s_awaddr(M0_AXI_AWADDR), .s_awlen(M0_AXI_AWLEN),
        .s_awvalid(m0_aw_to_err), .s_awready(m0_awready_s[5]),
        .s_wlast(M0_AXI_WLAST),   .s_wvalid(M0_AXI_WVALID), .s_wready(m0_wready_s[5]),
        .s_bid(m0_bid_s[5]),       .s_bresp(m0_bresp_s[5]),   .s_bvalid(m0_bvalid_s[5]),
        .s_bready(M0_AXI_BREADY)
    );

    // ── M1 DECERR ────────────────────────────────────────────────────────────
    axi4_decerr_slave #(.ID_WIDTH(ID_WIDTH),.DATA_WIDTH(DATA_WIDTH)) decerr_m1 (
        .clk(clk), .rst_n(rst_n),
        .s_arid(M1_AXI_ARID),     .s_araddr(M1_AXI_ARADDR), .s_arlen(M1_AXI_ARLEN),
        .s_arvalid(m1_ar_to_err), .s_arready(m1_arready_s[5]),
        .s_rid(m1_rid_s[5]),       .s_rdata(m1_rdata_s[5]),   .s_rresp(m1_rresp_s[5]),
        .s_rlast(m1_rlast_s[5]),   .s_rvalid(m1_rvalid_s[5]), .s_rready(M1_AXI_RREADY),
        .s_awid(M1_AXI_AWID),     .s_awaddr(M1_AXI_AWADDR), .s_awlen(M1_AXI_AWLEN),
        .s_awvalid(m1_aw_to_err), .s_awready(m1_awready_s[5]),
        .s_wlast(M1_AXI_WLAST),   .s_wvalid(M1_AXI_WVALID), .s_wready(m1_wready_s[5]),
        .s_bid(m1_bid_s[5]),       .s_bresp(m1_bresp_s[5]),   .s_bvalid(m1_bvalid_s[5]),
        .s_bready(M1_AXI_BREADY)
    );

    // ── M2 DECERR ────────────────────────────────────────────────────────────
    axi4_decerr_slave #(.ID_WIDTH(ID_WIDTH),.DATA_WIDTH(DATA_WIDTH)) decerr_m2 (
        .clk(clk), .rst_n(rst_n),
        .s_arid(M2_AXI_ARID),     .s_araddr(M2_AXI_ARADDR), .s_arlen(M2_AXI_ARLEN),
        .s_arvalid(m2_ar_to_err), .s_arready(m2_arready_s[5]),
        .s_rid(m2_rid_s[5]),       .s_rdata(m2_rdata_s[5]),   .s_rresp(m2_rresp_s[5]),
        .s_rlast(m2_rlast_s[5]),   .s_rvalid(m2_rvalid_s[5]), .s_rready(M2_AXI_RREADY),
        .s_awid(M2_AXI_AWID),     .s_awaddr(M2_AXI_AWADDR), .s_awlen(M2_AXI_AWLEN),
        .s_awvalid(m2_aw_to_err), .s_awready(m2_awready_s[5]),
        .s_wlast(M2_AXI_WLAST),   .s_wvalid(M2_AXI_WVALID), .s_wready(m2_wready_s[5]),
        .s_bid(m2_bid_s[5]),       .s_bresp(m2_bresp_s[5]),   .s_bvalid(m2_bvalid_s[5]),
        .s_bready(M2_AXI_BREADY)
    );

endmodule
// ============================================================================
// END: axi4_crossbar_3m5s.v
// ============================================================================