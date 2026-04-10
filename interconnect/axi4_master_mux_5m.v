// ============================================================================
// axi4_master_mux_5m.v
// Arbitration + mux cho MỘT slave port — hỗ trợ 5 Master.
//
// Masters:
//   M0 = ICache    (priority 0 — cao nhất)
//   M1 = DCache    (priority 1)
//   M2 = ASCON DMA (priority 2)
//   M3 = DMA Ctrl  (priority 3)
//   M4 = JTAG DM   (priority 4 — thấp nhất)
//
// Quy tắc arbitration (Fixed Priority, no burst cut):
//   - Grant cho master priority cao nhất đang request ở trạng thái IDLE.
//   - Không cắt burst: giữ grant cho đến khi RLAST (read) hoặc B-handshake (write).
//   - M4 (JTAG) chỉ được grant khi M0..M3 đều idle — đảm bảo debug không
//     ảnh hưởng đến real-time pipeline.
//
// ID tagging: 3 bit cao của ID = master index (000=M0 .. 100=M4)
//   → Yêu cầu ID_WIDTH >= 4 (3 tag bits + ≥1 user bit).
//   → Với ID_WIDTH=4: user bits = ID[0], tag = ID[3:1]  ← không dùng vì
//     cần 3 tag bits. Thực tế tag = ID[ID_WIDTH-1:ID_WIDTH-3].
// ============================================================================

module axi4_master_mux_5m #(
    parameter ID_WIDTH   = 4,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Master 0 — ICache
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m0_arid,
    input  wire [ADDR_WIDTH-1:0] m0_araddr,
    input  wire [7:0]            m0_arlen,
    input  wire [2:0]            m0_arsize,
    input  wire [1:0]            m0_arburst,
    input  wire [2:0]            m0_arprot,
    input  wire                  m0_arvalid,
    output wire                  m0_arready,

    output wire [ID_WIDTH-1:0]   m0_rid,
    output wire [DATA_WIDTH-1:0] m0_rdata,
    output wire [1:0]            m0_rresp,
    output wire                  m0_rlast,
    output wire                  m0_rvalid,
    input  wire                  m0_rready,

    input  wire [ID_WIDTH-1:0]   m0_awid,
    input  wire [ADDR_WIDTH-1:0] m0_awaddr,
    input  wire [7:0]            m0_awlen,
    input  wire [2:0]            m0_awsize,
    input  wire [1:0]            m0_awburst,
    input  wire [2:0]            m0_awprot,
    input  wire                  m0_awvalid,
    output wire                  m0_awready,

    input  wire [DATA_WIDTH-1:0] m0_wdata,
    input  wire [STRB_WIDTH-1:0] m0_wstrb,
    input  wire                  m0_wlast,
    input  wire                  m0_wvalid,
    output wire                  m0_wready,

    output wire [ID_WIDTH-1:0]   m0_bid,
    output wire [1:0]            m0_bresp,
    output wire                  m0_bvalid,
    input  wire                  m0_bready,

    // ========================================================================
    // Master 1 — DCache
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m1_arid,
    input  wire [ADDR_WIDTH-1:0] m1_araddr,
    input  wire [7:0]            m1_arlen,
    input  wire [2:0]            m1_arsize,
    input  wire [1:0]            m1_arburst,
    input  wire [2:0]            m1_arprot,
    input  wire                  m1_arvalid,
    output wire                  m1_arready,

    output wire [ID_WIDTH-1:0]   m1_rid,
    output wire [DATA_WIDTH-1:0] m1_rdata,
    output wire [1:0]            m1_rresp,
    output wire                  m1_rlast,
    output wire                  m1_rvalid,
    input  wire                  m1_rready,

    input  wire [ID_WIDTH-1:0]   m1_awid,
    input  wire [ADDR_WIDTH-1:0] m1_awaddr,
    input  wire [7:0]            m1_awlen,
    input  wire [2:0]            m1_awsize,
    input  wire [1:0]            m1_awburst,
    input  wire [2:0]            m1_awprot,
    input  wire                  m1_awvalid,
    output wire                  m1_awready,

    input  wire [DATA_WIDTH-1:0] m1_wdata,
    input  wire [STRB_WIDTH-1:0] m1_wstrb,
    input  wire                  m1_wlast,
    input  wire                  m1_wvalid,
    output wire                  m1_wready,

    output wire [ID_WIDTH-1:0]   m1_bid,
    output wire [1:0]            m1_bresp,
    output wire                  m1_bvalid,
    input  wire                  m1_bready,

    // ========================================================================
    // Master 2 — ASCON DMA (64-bit via width converter → 32-bit)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m2_arid,
    input  wire [ADDR_WIDTH-1:0] m2_araddr,
    input  wire [7:0]            m2_arlen,
    input  wire [2:0]            m2_arsize,
    input  wire [1:0]            m2_arburst,
    input  wire [2:0]            m2_arprot,
    input  wire                  m2_arvalid,
    output wire                  m2_arready,

    output wire [ID_WIDTH-1:0]   m2_rid,
    output wire [DATA_WIDTH-1:0] m2_rdata,
    output wire [1:0]            m2_rresp,
    output wire                  m2_rlast,
    output wire                  m2_rvalid,
    input  wire                  m2_rready,

    input  wire [ID_WIDTH-1:0]   m2_awid,
    input  wire [ADDR_WIDTH-1:0] m2_awaddr,
    input  wire [7:0]            m2_awlen,
    input  wire [2:0]            m2_awsize,
    input  wire [1:0]            m2_awburst,
    input  wire [2:0]            m2_awprot,
    input  wire                  m2_awvalid,
    output wire                  m2_awready,

    input  wire [DATA_WIDTH-1:0] m2_wdata,
    input  wire [STRB_WIDTH-1:0] m2_wstrb,
    input  wire                  m2_wlast,
    input  wire                  m2_wvalid,
    output wire                  m2_wready,

    output wire [ID_WIDTH-1:0]   m2_bid,
    output wire [1:0]            m2_bresp,
    output wire                  m2_bvalid,
    input  wire                  m2_bready,

    // ========================================================================
    // Master 3 — DMA Controller (multi-channel general purpose)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m3_arid,
    input  wire [ADDR_WIDTH-1:0] m3_araddr,
    input  wire [7:0]            m3_arlen,
    input  wire [2:0]            m3_arsize,
    input  wire [1:0]            m3_arburst,
    input  wire [2:0]            m3_arprot,
    input  wire                  m3_arvalid,
    output wire                  m3_arready,

    output wire [ID_WIDTH-1:0]   m3_rid,
    output wire [DATA_WIDTH-1:0] m3_rdata,
    output wire [1:0]            m3_rresp,
    output wire                  m3_rlast,
    output wire                  m3_rvalid,
    input  wire                  m3_rready,

    input  wire [ID_WIDTH-1:0]   m3_awid,
    input  wire [ADDR_WIDTH-1:0] m3_awaddr,
    input  wire [7:0]            m3_awlen,
    input  wire [2:0]            m3_awsize,
    input  wire [1:0]            m3_awburst,
    input  wire [2:0]            m3_awprot,
    input  wire                  m3_awvalid,
    output wire                  m3_awready,

    input  wire [DATA_WIDTH-1:0] m3_wdata,
    input  wire [STRB_WIDTH-1:0] m3_wstrb,
    input  wire                  m3_wlast,
    input  wire                  m3_wvalid,
    output wire                  m3_wready,

    output wire [ID_WIDTH-1:0]   m3_bid,
    output wire [1:0]            m3_bresp,
    output wire                  m3_bvalid,
    input  wire                  m3_bready,

    // ========================================================================
    // Master 4 — JTAG Debug Module (system bus access)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m4_arid,
    input  wire [ADDR_WIDTH-1:0] m4_araddr,
    input  wire [7:0]            m4_arlen,
    input  wire [2:0]            m4_arsize,
    input  wire [1:0]            m4_arburst,
    input  wire [2:0]            m4_arprot,
    input  wire                  m4_arvalid,
    output wire                  m4_arready,

    output wire [ID_WIDTH-1:0]   m4_rid,
    output wire [DATA_WIDTH-1:0] m4_rdata,
    output wire [1:0]            m4_rresp,
    output wire                  m4_rlast,
    output wire                  m4_rvalid,
    input  wire                  m4_rready,

    input  wire [ID_WIDTH-1:0]   m4_awid,
    input  wire [ADDR_WIDTH-1:0] m4_awaddr,
    input  wire [7:0]            m4_awlen,
    input  wire [2:0]            m4_awsize,
    input  wire [1:0]            m4_awburst,
    input  wire [2:0]            m4_awprot,
    input  wire                  m4_awvalid,
    output wire                  m4_awready,

    input  wire [DATA_WIDTH-1:0] m4_wdata,
    input  wire [STRB_WIDTH-1:0] m4_wstrb,
    input  wire                  m4_wlast,
    input  wire                  m4_wvalid,
    output wire                  m4_wready,

    output wire [ID_WIDTH-1:0]   m4_bid,
    output wire [1:0]            m4_bresp,
    output wire                  m4_bvalid,
    input  wire                  m4_bready,

    // ========================================================================
    // Slave Port
    // ========================================================================
    output wire [ID_WIDTH-1:0]   s_arid,
    output wire [ADDR_WIDTH-1:0] s_araddr,
    output wire [7:0]            s_arlen,
    output wire [2:0]            s_arsize,
    output wire [1:0]            s_arburst,
    output wire [2:0]            s_arprot,
    output wire                  s_arvalid,
    input  wire                  s_arready,

    input  wire [ID_WIDTH-1:0]   s_rid,
    input  wire [DATA_WIDTH-1:0] s_rdata,
    input  wire [1:0]            s_rresp,
    input  wire                  s_rlast,
    input  wire                  s_rvalid,
    output wire                  s_rready,

    output wire [ID_WIDTH-1:0]   s_awid,
    output wire [ADDR_WIDTH-1:0] s_awaddr,
    output wire [7:0]            s_awlen,
    output wire [2:0]            s_awsize,
    output wire [1:0]            s_awburst,
    output wire [2:0]            s_awprot,
    output wire                  s_awvalid,
    input  wire                  s_awready,

    output wire [DATA_WIDTH-1:0] s_wdata,
    output wire [STRB_WIDTH-1:0] s_wstrb,
    output wire                  s_wlast,
    output wire                  s_wvalid,
    input  wire                  s_wready,

    input  wire [ID_WIDTH-1:0]   s_bid,
    input  wire [1:0]            s_bresp,
    input  wire                  s_bvalid,
    output wire                  s_bready
);

    // ========================================================================
    // ID Tag constants — 3 bits → supports 8 masters (5 used)
    // ========================================================================
    localparam [2:0] TAG_M0 = 3'b000;
    localparam [2:0] TAG_M1 = 3'b001;
    localparam [2:0] TAG_M2 = 3'b010;
    localparam [2:0] TAG_M3 = 3'b011;
    localparam [2:0] TAG_M4 = 3'b100;

    // ========================================================================
    // Read Arbitration FSM — Fixed Priority M0 > M1 > M2 > M3 > M4
    // No burst cut: hold grant until RLAST
    // ========================================================================
    localparam [2:0] RD_IDLE = 3'd0,
                     RD_M0   = 3'd1,
                     RD_M1   = 3'd2,
                     RD_M2   = 3'd3,
                     RD_M3   = 3'd4,
                     RD_M4   = 3'd5;

    reg [2:0] rd_arb;

    // Next-state combinational helper
    function [2:0] rd_next_winner;
        input m0v, m1v, m2v, m3v, m4v;
        begin
            if      (m0v) rd_next_winner = RD_M0;
            else if (m1v) rd_next_winner = RD_M1;
            else if (m2v) rd_next_winner = RD_M2;
            else if (m3v) rd_next_winner = RD_M3;
            else if (m4v) rd_next_winner = RD_M4;
            else          rd_next_winner = RD_IDLE;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_arb <= RD_IDLE;
        end else begin
            case (rd_arb)
                RD_IDLE: rd_arb <= rd_next_winner(m0_arvalid, m1_arvalid,
                                                   m2_arvalid, m3_arvalid, m4_arvalid);
                RD_M0: if (s_rvalid && m0_rready && s_rlast)
                           rd_arb <= rd_next_winner(m0_arvalid, m1_arvalid,
                                                    m2_arvalid, m3_arvalid, m4_arvalid);
                RD_M1: if (s_rvalid && m1_rready && s_rlast)
                           rd_arb <= rd_next_winner(m0_arvalid, m1_arvalid,
                                                    m2_arvalid, m3_arvalid, m4_arvalid);
                RD_M2: if (s_rvalid && m2_rready && s_rlast)
                           rd_arb <= rd_next_winner(m0_arvalid, m1_arvalid,
                                                    m2_arvalid, m3_arvalid, m4_arvalid);
                RD_M3: if (s_rvalid && m3_rready && s_rlast)
                           rd_arb <= rd_next_winner(m0_arvalid, m1_arvalid,
                                                    m2_arvalid, m3_arvalid, m4_arvalid);
                RD_M4: if (s_rvalid && m4_rready && s_rlast)
                           rd_arb <= rd_next_winner(m0_arvalid, m1_arvalid,
                                                    m2_arvalid, m3_arvalid, m4_arvalid);
                default: rd_arb <= RD_IDLE;
            endcase
        end
    end

    wire rd_grant_m0 = (rd_arb == RD_M0) ||
                       (rd_arb == RD_IDLE && m0_arvalid);
    wire rd_grant_m1 = (rd_arb == RD_M1) ||
                       (rd_arb == RD_IDLE && !m0_arvalid && m1_arvalid);
    wire rd_grant_m2 = (rd_arb == RD_M2) ||
                       (rd_arb == RD_IDLE && !m0_arvalid && !m1_arvalid && m2_arvalid);
    wire rd_grant_m3 = (rd_arb == RD_M3) ||
                       (rd_arb == RD_IDLE && !m0_arvalid && !m1_arvalid &&
                        !m2_arvalid && m3_arvalid);
    wire rd_grant_m4 = (rd_arb == RD_M4) ||
                       (rd_arb == RD_IDLE && !m0_arvalid && !m1_arvalid &&
                        !m2_arvalid && !m3_arvalid && m4_arvalid);

    // ========================================================================
    // Write Arbitration FSM — Fixed Priority M0 > M1 > M2 > M3 > M4
    // No burst cut: hold grant until B-handshake
    // ========================================================================
    localparam [2:0] WR_IDLE = 3'd0,
                     WR_M0   = 3'd1,
                     WR_M1   = 3'd2,
                     WR_M2   = 3'd3,
                     WR_M3   = 3'd4,
                     WR_M4   = 3'd5;

    reg [2:0] wr_arb;

    function [2:0] wr_next_winner;
        input m0v, m1v, m2v, m3v, m4v;
        begin
            if      (m0v) wr_next_winner = WR_M0;
            else if (m1v) wr_next_winner = WR_M1;
            else if (m2v) wr_next_winner = WR_M2;
            else if (m3v) wr_next_winner = WR_M3;
            else if (m4v) wr_next_winner = WR_M4;
            else          wr_next_winner = WR_IDLE;
        end
    endfunction

    // Helper: which master's bready to check
    wire cur_bready = (wr_arb == WR_M0) ? m0_bready :
                      (wr_arb == WR_M1) ? m1_bready :
                      (wr_arb == WR_M2) ? m2_bready :
                      (wr_arb == WR_M3) ? m3_bready : m4_bready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_arb <= WR_IDLE;
        end else begin
            case (wr_arb)
                WR_IDLE: wr_arb <= wr_next_winner(m0_awvalid, m1_awvalid,
                                                   m2_awvalid, m3_awvalid, m4_awvalid);
                WR_M0: if (s_bvalid && m0_bready)
                           wr_arb <= wr_next_winner(m0_awvalid, m1_awvalid,
                                                    m2_awvalid, m3_awvalid, m4_awvalid);
                WR_M1: if (s_bvalid && m1_bready)
                           wr_arb <= wr_next_winner(m0_awvalid, m1_awvalid,
                                                    m2_awvalid, m3_awvalid, m4_awvalid);
                WR_M2: if (s_bvalid && m2_bready)
                           wr_arb <= wr_next_winner(m0_awvalid, m1_awvalid,
                                                    m2_awvalid, m3_awvalid, m4_awvalid);
                WR_M3: if (s_bvalid && m3_bready)
                           wr_arb <= wr_next_winner(m0_awvalid, m1_awvalid,
                                                    m2_awvalid, m3_awvalid, m4_awvalid);
                WR_M4: if (s_bvalid && m4_bready)
                           wr_arb <= wr_next_winner(m0_awvalid, m1_awvalid,
                                                    m2_awvalid, m3_awvalid, m4_awvalid);
                default: wr_arb <= WR_IDLE;
            endcase
        end
    end

    wire wr_grant_m0 = (wr_arb == WR_M0) ||
                       (wr_arb == WR_IDLE && m0_awvalid);
    wire wr_grant_m1 = (wr_arb == WR_M1) ||
                       (wr_arb == WR_IDLE && !m0_awvalid && m1_awvalid);
    wire wr_grant_m2 = (wr_arb == WR_M2) ||
                       (wr_arb == WR_IDLE && !m0_awvalid && !m1_awvalid && m2_awvalid);
    wire wr_grant_m3 = (wr_arb == WR_M3) ||
                       (wr_arb == WR_IDLE && !m0_awvalid && !m1_awvalid &&
                        !m2_awvalid && m3_awvalid);
    wire wr_grant_m4 = (wr_arb == WR_M4) ||
                       (wr_arb == WR_IDLE && !m0_awvalid && !m1_awvalid &&
                        !m2_awvalid && !m3_awvalid && m4_awvalid);

    // ========================================================================
    // AR Channel Mux → Slave
    // ========================================================================
    assign s_arvalid = rd_grant_m0 ? m0_arvalid :
                       rd_grant_m1 ? m1_arvalid :
                       rd_grant_m2 ? m2_arvalid :
                       rd_grant_m3 ? m3_arvalid :
                       rd_grant_m4 ? m4_arvalid : 1'b0;

    assign s_araddr  = rd_grant_m0 ? m0_araddr :
                       rd_grant_m1 ? m1_araddr :
                       rd_grant_m2 ? m2_araddr :
                       rd_grant_m3 ? m3_araddr : m4_araddr;

    assign s_arlen   = rd_grant_m0 ? m0_arlen :
                       rd_grant_m1 ? m1_arlen :
                       rd_grant_m2 ? m2_arlen :
                       rd_grant_m3 ? m3_arlen : m4_arlen;

    assign s_arsize  = rd_grant_m0 ? m0_arsize :
                       rd_grant_m1 ? m1_arsize :
                       rd_grant_m2 ? m2_arsize :
                       rd_grant_m3 ? m3_arsize : m4_arsize;

    assign s_arburst = rd_grant_m0 ? m0_arburst :
                       rd_grant_m1 ? m1_arburst :
                       rd_grant_m2 ? m2_arburst :
                       rd_grant_m3 ? m3_arburst : m4_arburst;

    assign s_arprot  = rd_grant_m0 ? m0_arprot :
                       rd_grant_m1 ? m1_arprot :
                       rd_grant_m2 ? m2_arprot :
                       rd_grant_m3 ? m3_arprot : m4_arprot;

    // ID tagging: top 3 bits = master index
    assign s_arid = rd_grant_m0 ? {TAG_M0, m0_arid[ID_WIDTH-4:0]} :
                    rd_grant_m1 ? {TAG_M1, m1_arid[ID_WIDTH-4:0]} :
                    rd_grant_m2 ? {TAG_M2, m2_arid[ID_WIDTH-4:0]} :
                    rd_grant_m3 ? {TAG_M3, m3_arid[ID_WIDTH-4:0]} :
                                  {TAG_M4, m4_arid[ID_WIDTH-4:0]};

    assign m0_arready = rd_grant_m0 ? s_arready : 1'b0;
    assign m1_arready = rd_grant_m1 ? s_arready : 1'b0;
    assign m2_arready = rd_grant_m2 ? s_arready : 1'b0;
    assign m3_arready = rd_grant_m3 ? s_arready : 1'b0;
    assign m4_arready = rd_grant_m4 ? s_arready : 1'b0;

    // ========================================================================
    // R Channel Demux ← Slave (top 3 bits of RID = master index)
    // ========================================================================
    wire [2:0] rd_resp_tag = s_rid[ID_WIDTH-1:ID_WIDTH-3];

    wire rd_resp_to_m0 = (rd_resp_tag == TAG_M0);
    wire rd_resp_to_m1 = (rd_resp_tag == TAG_M1);
    wire rd_resp_to_m2 = (rd_resp_tag == TAG_M2);
    wire rd_resp_to_m3 = (rd_resp_tag == TAG_M3);
    wire rd_resp_to_m4 = (rd_resp_tag == TAG_M4);

    // Strip tag bits when returning to master
    wire [ID_WIDTH-4:0] s_rid_user = s_rid[ID_WIDTH-4:0];
    assign m0_rid = {{3{1'b0}}, s_rid_user};
    assign m1_rid = {{3{1'b0}}, s_rid_user};
    assign m2_rid = {{3{1'b0}}, s_rid_user};
    assign m3_rid = {{3{1'b0}}, s_rid_user};
    assign m4_rid = {{3{1'b0}}, s_rid_user};

    assign m0_rdata  = s_rdata;
    assign m1_rdata  = s_rdata;
    assign m2_rdata  = s_rdata;
    assign m3_rdata  = s_rdata;
    assign m4_rdata  = s_rdata;

    assign m0_rresp  = s_rresp;
    assign m1_rresp  = s_rresp;
    assign m2_rresp  = s_rresp;
    assign m3_rresp  = s_rresp;
    assign m4_rresp  = s_rresp;

    assign m0_rlast  = s_rlast && rd_resp_to_m0;
    assign m1_rlast  = s_rlast && rd_resp_to_m1;
    assign m2_rlast  = s_rlast && rd_resp_to_m2;
    assign m3_rlast  = s_rlast && rd_resp_to_m3;
    assign m4_rlast  = s_rlast && rd_resp_to_m4;

    assign m0_rvalid = s_rvalid && rd_resp_to_m0;
    assign m1_rvalid = s_rvalid && rd_resp_to_m1;
    assign m2_rvalid = s_rvalid && rd_resp_to_m2;
    assign m3_rvalid = s_rvalid && rd_resp_to_m3;
    assign m4_rvalid = s_rvalid && rd_resp_to_m4;

    assign s_rready  = rd_resp_to_m0 ? m0_rready :
                       rd_resp_to_m1 ? m1_rready :
                       rd_resp_to_m2 ? m2_rready :
                       rd_resp_to_m3 ? m3_rready :
                       rd_resp_to_m4 ? m4_rready : 1'b0;

    // ========================================================================
    // AW Channel Mux → Slave
    // ========================================================================
    assign s_awvalid = wr_grant_m0 ? m0_awvalid :
                       wr_grant_m1 ? m1_awvalid :
                       wr_grant_m2 ? m2_awvalid :
                       wr_grant_m3 ? m3_awvalid :
                       wr_grant_m4 ? m4_awvalid : 1'b0;

    assign s_awaddr  = wr_grant_m0 ? m0_awaddr :
                       wr_grant_m1 ? m1_awaddr :
                       wr_grant_m2 ? m2_awaddr :
                       wr_grant_m3 ? m3_awaddr : m4_awaddr;

    assign s_awlen   = wr_grant_m0 ? m0_awlen :
                       wr_grant_m1 ? m1_awlen :
                       wr_grant_m2 ? m2_awlen :
                       wr_grant_m3 ? m3_awlen : m4_awlen;

    assign s_awsize  = wr_grant_m0 ? m0_awsize :
                       wr_grant_m1 ? m1_awsize :
                       wr_grant_m2 ? m2_awsize :
                       wr_grant_m3 ? m3_awsize : m4_awsize;

    assign s_awburst = wr_grant_m0 ? m0_awburst :
                       wr_grant_m1 ? m1_awburst :
                       wr_grant_m2 ? m2_awburst :
                       wr_grant_m3 ? m3_awburst : m4_awburst;

    assign s_awprot  = wr_grant_m0 ? m0_awprot :
                       wr_grant_m1 ? m1_awprot :
                       wr_grant_m2 ? m2_awprot :
                       wr_grant_m3 ? m3_awprot : m4_awprot;

    assign s_awid    = wr_grant_m0 ? {TAG_M0, m0_awid[ID_WIDTH-4:0]} :
                       wr_grant_m1 ? {TAG_M1, m1_awid[ID_WIDTH-4:0]} :
                       wr_grant_m2 ? {TAG_M2, m2_awid[ID_WIDTH-4:0]} :
                       wr_grant_m3 ? {TAG_M3, m3_awid[ID_WIDTH-4:0]} :
                                     {TAG_M4, m4_awid[ID_WIDTH-4:0]};

    assign m0_awready = wr_grant_m0 ? s_awready : 1'b0;
    assign m1_awready = wr_grant_m1 ? s_awready : 1'b0;
    assign m2_awready = wr_grant_m2 ? s_awready : 1'b0;
    assign m3_awready = wr_grant_m3 ? s_awready : 1'b0;
    assign m4_awready = wr_grant_m4 ? s_awready : 1'b0;

    // ========================================================================
    // W Channel Mux → Slave
    // ========================================================================
    assign s_wdata  = wr_grant_m0 ? m0_wdata :
                      wr_grant_m1 ? m1_wdata :
                      wr_grant_m2 ? m2_wdata :
                      wr_grant_m3 ? m3_wdata : m4_wdata;

    assign s_wstrb  = wr_grant_m0 ? m0_wstrb :
                      wr_grant_m1 ? m1_wstrb :
                      wr_grant_m2 ? m2_wstrb :
                      wr_grant_m3 ? m3_wstrb : m4_wstrb;

    assign s_wlast  = wr_grant_m0 ? m0_wlast :
                      wr_grant_m1 ? m1_wlast :
                      wr_grant_m2 ? m2_wlast :
                      wr_grant_m3 ? m3_wlast : m4_wlast;

    assign s_wvalid = wr_grant_m0 ? m0_wvalid :
                      wr_grant_m1 ? m1_wvalid :
                      wr_grant_m2 ? m2_wvalid :
                      wr_grant_m3 ? m3_wvalid :
                      wr_grant_m4 ? m4_wvalid : 1'b0;

    assign m0_wready = wr_grant_m0 ? s_wready : 1'b0;
    assign m1_wready = wr_grant_m1 ? s_wready : 1'b0;
    assign m2_wready = wr_grant_m2 ? s_wready : 1'b0;
    assign m3_wready = wr_grant_m3 ? s_wready : 1'b0;
    assign m4_wready = wr_grant_m4 ? s_wready : 1'b0;

    // ========================================================================
    // B Channel Demux ← Slave
    // ========================================================================
    wire [2:0] wr_resp_tag = s_bid[ID_WIDTH-1:ID_WIDTH-3];

    wire wr_resp_to_m0 = (wr_resp_tag == TAG_M0);
    wire wr_resp_to_m1 = (wr_resp_tag == TAG_M1);
    wire wr_resp_to_m2 = (wr_resp_tag == TAG_M2);
    wire wr_resp_to_m3 = (wr_resp_tag == TAG_M3);
    wire wr_resp_to_m4 = (wr_resp_tag == TAG_M4);

    wire [ID_WIDTH-4:0] s_bid_user = s_bid[ID_WIDTH-4:0];
    assign m0_bid = {{3{1'b0}}, s_bid_user};
    assign m1_bid = {{3{1'b0}}, s_bid_user};
    assign m2_bid = {{3{1'b0}}, s_bid_user};
    assign m3_bid = {{3{1'b0}}, s_bid_user};
    assign m4_bid = {{3{1'b0}}, s_bid_user};

    assign m0_bresp  = s_bresp;
    assign m1_bresp  = s_bresp;
    assign m2_bresp  = s_bresp;
    assign m3_bresp  = s_bresp;
    assign m4_bresp  = s_bresp;

    assign m0_bvalid = s_bvalid && wr_resp_to_m0;
    assign m1_bvalid = s_bvalid && wr_resp_to_m1;
    assign m2_bvalid = s_bvalid && wr_resp_to_m2;
    assign m3_bvalid = s_bvalid && wr_resp_to_m3;
    assign m4_bvalid = s_bvalid && wr_resp_to_m4;

    assign s_bready  = wr_resp_to_m0 ? m0_bready :
                       wr_resp_to_m1 ? m1_bready :
                       wr_resp_to_m2 ? m2_bready :
                       wr_resp_to_m3 ? m3_bready :
                       wr_resp_to_m4 ? m4_bready : 1'b0;

endmodule