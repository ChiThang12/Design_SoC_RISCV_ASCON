// ============================================================================
// axi4_master_mux_3m.v
// Arbitration + mux cho MỘT slave port — hỗ trợ 3 Master (M0, M1, M2).
//
// Thay thế axi4_master_mux.v (2 master) để dùng với crossbar 3×4.
//
// Thứ tự ưu tiên: M0 (ICache) > M1 (DCache) > M2 (DMA)
//   - M0 có priority cao nhất (không bao giờ bị chặn trong IDLE)
//   - M2 (DMA) có priority thấp nhất (chỉ được grant khi M0 và M1 idle)
//   - Không cắt burst: giữ grant cho đến khi RLAST / B-handshake
//
// ID tagging: 2 bit cao của ID = master index (00=M0, 01=M1, 10=M2)
//   → Yêu cầu ID_WIDTH >= 3.
// ============================================================================

module axi4_master_mux_3m #(
    parameter ID_WIDTH   = 4,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Master 0 — Read (AR/R)
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

    // Master 0 — Write (AW/W/B)
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
    // Master 1 — Read (AR/R)
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

    // Master 1 — Write (AW/W/B)
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
    // Master 2 — Read (AR/R)  [DMA]
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

    // Master 2 — Write (AW/W/B)  [DMA]
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
    // Slave Port (output to actual slave)
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
    // Read Arbitration FSM — Fixed priority M0 > M1 > M2
    // Không cắt burst: giữ grant cho đến RLAST
    // ========================================================================
    localparam [2:0] RD_ARB_IDLE = 3'd0,
                     RD_ARB_M0   = 3'd1,
                     RD_ARB_M1   = 3'd2,
                     RD_ARB_M2   = 3'd3;

    reg [2:0] rd_arb;
    reg       rd_burst_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_arb         <= RD_ARB_IDLE;
            rd_burst_active <= 1'b0;
        end else begin
            case (rd_arb)
                RD_ARB_IDLE: begin
                    if      (m0_arvalid) rd_arb <= RD_ARB_M0;
                    else if (m1_arvalid) rd_arb <= RD_ARB_M1;
                    else if (m2_arvalid) rd_arb <= RD_ARB_M2;
                end

                RD_ARB_M0: begin
                    if (!rd_burst_active && m0_arvalid && s_arready) begin
                        rd_burst_active <= 1'b1;
                    end else if (rd_burst_active && s_rvalid && s_rlast && m0_rready) begin
                        rd_burst_active <= 1'b0;
                        if      (m0_arvalid) rd_arb <= RD_ARB_M0;
                        else if (m1_arvalid) rd_arb <= RD_ARB_M1;
                        else if (m2_arvalid) rd_arb <= RD_ARB_M2;
                        else                 rd_arb <= RD_ARB_IDLE;
                    end
                end

                RD_ARB_M1: begin
                    if (!rd_burst_active && m1_arvalid && s_arready) begin
                        rd_burst_active <= 1'b1;
                    end else if (rd_burst_active && s_rvalid && s_rlast && m1_rready) begin
                        rd_burst_active <= 1'b0;
                        if      (m0_arvalid) rd_arb <= RD_ARB_M0;
                        else if (m1_arvalid) rd_arb <= RD_ARB_M1;
                        else if (m2_arvalid) rd_arb <= RD_ARB_M2;
                        else                 rd_arb <= RD_ARB_IDLE;
                    end
                end

                RD_ARB_M2: begin
                    if (!rd_burst_active && m2_arvalid && s_arready) begin
                        rd_burst_active <= 1'b1;
                    end else if (rd_burst_active && s_rvalid && s_rlast && m2_rready) begin
                        rd_burst_active <= 1'b0;
                        if      (m0_arvalid) rd_arb <= RD_ARB_M0;
                        else if (m1_arvalid) rd_arb <= RD_ARB_M1;
                        else if (m2_arvalid) rd_arb <= RD_ARB_M2;
                        else                 rd_arb <= RD_ARB_IDLE;
                    end
                end

                default: rd_arb <= RD_ARB_IDLE;
            endcase
        end
    end

    // Combinational grant
    wire rd_grant_m0 = (rd_arb == RD_ARB_M0) ||
                       (rd_arb == RD_ARB_IDLE && m0_arvalid);
    wire rd_grant_m1 = (rd_arb == RD_ARB_M1) ||
                       (rd_arb == RD_ARB_IDLE && !m0_arvalid && m1_arvalid);
    wire rd_grant_m2 = (rd_arb == RD_ARB_M2) ||
                       (rd_arb == RD_ARB_IDLE && !m0_arvalid && !m1_arvalid && m2_arvalid);

    // ========================================================================
    // Write Arbitration FSM — Fixed priority M0 > M1 > M2
    // Kết thúc khi B-handshake hoàn tất
    // ========================================================================
    localparam [2:0] WR_ARB_IDLE = 3'd0,
                     WR_ARB_M0   = 3'd1,
                     WR_ARB_M1   = 3'd2,
                     WR_ARB_M2   = 3'd3;

    reg [2:0] wr_arb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_arb <= WR_ARB_IDLE;
        end else begin
            case (wr_arb)
                WR_ARB_IDLE: begin
                    if      (m0_awvalid) wr_arb <= WR_ARB_M0;
                    else if (m1_awvalid) wr_arb <= WR_ARB_M1;
                    else if (m2_awvalid) wr_arb <= WR_ARB_M2;
                end

                WR_ARB_M0: begin
                    if (s_bvalid && m0_bready) begin
                        if      (m0_awvalid) wr_arb <= WR_ARB_M0;
                        else if (m1_awvalid) wr_arb <= WR_ARB_M1;
                        else if (m2_awvalid) wr_arb <= WR_ARB_M2;
                        else                 wr_arb <= WR_ARB_IDLE;
                    end
                end

                WR_ARB_M1: begin
                    if (s_bvalid && m1_bready) begin
                        if      (m0_awvalid) wr_arb <= WR_ARB_M0;
                        else if (m1_awvalid) wr_arb <= WR_ARB_M1;
                        else if (m2_awvalid) wr_arb <= WR_ARB_M2;
                        else                 wr_arb <= WR_ARB_IDLE;
                    end
                end

                WR_ARB_M2: begin
                    if (s_bvalid && m2_bready) begin
                        if      (m0_awvalid) wr_arb <= WR_ARB_M0;
                        else if (m1_awvalid) wr_arb <= WR_ARB_M1;
                        else if (m2_awvalid) wr_arb <= WR_ARB_M2;
                        else                 wr_arb <= WR_ARB_IDLE;
                    end
                end

                default: wr_arb <= WR_ARB_IDLE;
            endcase
        end
    end

    wire wr_grant_m0 = (wr_arb == WR_ARB_M0) ||
                       (wr_arb == WR_ARB_IDLE && m0_awvalid);
    wire wr_grant_m1 = (wr_arb == WR_ARB_M1) ||
                       (wr_arb == WR_ARB_IDLE && !m0_awvalid && m1_awvalid);
    wire wr_grant_m2 = (wr_arb == WR_ARB_M2) ||
                       (wr_arb == WR_ARB_IDLE && !m0_awvalid && !m1_awvalid && m2_awvalid);

    // ========================================================================
    // ID Tagging: 2 bit cao = master index (00=M0, 01=M1, 10=M2)
    // Yêu cầu ID_WIDTH >= 3.
    // ========================================================================
    localparam TAG_M0 = 2'b00;
    localparam TAG_M1 = 2'b01;
    localparam TAG_M2 = 2'b10;

    // ========================================================================
    // AR Channel Mux → Slave
    // ========================================================================
    assign s_arvalid = rd_grant_m0 ? m0_arvalid :
                       rd_grant_m1 ? m1_arvalid :
                       rd_grant_m2 ? m2_arvalid : 1'b0;

    assign s_araddr  = rd_grant_m0 ? m0_araddr  :
                       rd_grant_m1 ? m1_araddr   : m2_araddr;
    assign s_arlen   = rd_grant_m0 ? m0_arlen   :
                       rd_grant_m1 ? m1_arlen    : m2_arlen;
    assign s_arsize  = rd_grant_m0 ? m0_arsize  :
                       rd_grant_m1 ? m1_arsize   : m2_arsize;
    assign s_arburst = rd_grant_m0 ? m0_arburst :
                       rd_grant_m1 ? m1_arburst  : m2_arburst;
    assign s_arprot  = rd_grant_m0 ? m0_arprot  :
                       rd_grant_m1 ? m1_arprot   : m2_arprot;

    // ID tagging: 2 bit cao ghi master index, các bit thấp từ master
    assign s_arid = rd_grant_m0 ? {TAG_M0, m0_arid[ID_WIDTH-3:0]} :
                    rd_grant_m1 ? {TAG_M1, m1_arid[ID_WIDTH-3:0]} :
                                  {TAG_M2, m2_arid[ID_WIDTH-3:0]};

    assign m0_arready = rd_grant_m0 ? s_arready : 1'b0;
    assign m1_arready = rd_grant_m1 ? s_arready : 1'b0;
    assign m2_arready = rd_grant_m2 ? s_arready : 1'b0;

    // ========================================================================
    // R Channel Demux ← Slave (dựa vào 2 bit cao của RID)
    // ========================================================================
    wire [1:0] rd_resp_tag = s_rid[ID_WIDTH-1:ID_WIDTH-2];

    wire rd_resp_to_m0 = (rd_resp_tag == TAG_M0);
    wire rd_resp_to_m1 = (rd_resp_tag == TAG_M1);
    wire rd_resp_to_m2 = (rd_resp_tag == TAG_M2);

    // Strip tag bits khi trả về master
    assign m0_rid   = {2'b00, s_rid[ID_WIDTH-3:0]};
    assign m1_rid   = {2'b00, s_rid[ID_WIDTH-3:0]};
    assign m2_rid   = {2'b00, s_rid[ID_WIDTH-3:0]};

    assign m0_rdata  = s_rdata;
    assign m1_rdata  = s_rdata;
    assign m2_rdata  = s_rdata;
    assign m0_rresp  = s_rresp;
    assign m1_rresp  = s_rresp;
    assign m2_rresp  = s_rresp;

    // Gate RLAST bằng rd_resp_to_mX — tránh leak burst sang master khác
    assign m0_rlast  = s_rlast && rd_resp_to_m0;
    assign m1_rlast  = s_rlast && rd_resp_to_m1;
    assign m2_rlast  = s_rlast && rd_resp_to_m2;

    assign m0_rvalid = s_rvalid && rd_resp_to_m0;
    assign m1_rvalid = s_rvalid && rd_resp_to_m1;
    assign m2_rvalid = s_rvalid && rd_resp_to_m2;

    assign s_rready  = rd_resp_to_m0 ? m0_rready :
                       rd_resp_to_m1 ? m1_rready :
                       rd_resp_to_m2 ? m2_rready : 1'b0;

    // ========================================================================
    // AW Channel Mux → Slave
    // ========================================================================
    assign s_awvalid = wr_grant_m0 ? m0_awvalid :
                       wr_grant_m1 ? m1_awvalid :
                       wr_grant_m2 ? m2_awvalid : 1'b0;

    assign s_awaddr  = wr_grant_m0 ? m0_awaddr  :
                       wr_grant_m1 ? m1_awaddr   : m2_awaddr;
    assign s_awlen   = wr_grant_m0 ? m0_awlen   :
                       wr_grant_m1 ? m1_awlen    : m2_awlen;
    assign s_awsize  = wr_grant_m0 ? m0_awsize  :
                       wr_grant_m1 ? m1_awsize   : m2_awsize;
    assign s_awburst = wr_grant_m0 ? m0_awburst :
                       wr_grant_m1 ? m1_awburst  : m2_awburst;
    assign s_awprot  = wr_grant_m0 ? m0_awprot  :
                       wr_grant_m1 ? m1_awprot   : m2_awprot;
    assign s_awid    = wr_grant_m0 ? {TAG_M0, m0_awid[ID_WIDTH-3:0]} :
                       wr_grant_m1 ? {TAG_M1, m1_awid[ID_WIDTH-3:0]} :
                                     {TAG_M2, m2_awid[ID_WIDTH-3:0]};

    assign m0_awready = wr_grant_m0 ? s_awready : 1'b0;
    assign m1_awready = wr_grant_m1 ? s_awready : 1'b0;
    assign m2_awready = wr_grant_m2 ? s_awready : 1'b0;

    // ========================================================================
    // W Channel Mux → Slave
    // ========================================================================
    assign s_wdata  = wr_grant_m0 ? m0_wdata  :
                      wr_grant_m1 ? m1_wdata   : m2_wdata;
    assign s_wstrb  = wr_grant_m0 ? m0_wstrb  :
                      wr_grant_m1 ? m1_wstrb   : m2_wstrb;
    assign s_wlast  = wr_grant_m0 ? m0_wlast  :
                      wr_grant_m1 ? m1_wlast   : m2_wlast;
    assign s_wvalid = wr_grant_m0 ? m0_wvalid :
                      wr_grant_m1 ? m1_wvalid  :
                      wr_grant_m2 ? m2_wvalid  : 1'b0;

    assign m0_wready = wr_grant_m0 ? s_wready : 1'b0;
    assign m1_wready = wr_grant_m1 ? s_wready : 1'b0;
    assign m2_wready = wr_grant_m2 ? s_wready : 1'b0;

    // ========================================================================
    // B Channel Demux ← Slave
    // ========================================================================
    wire [1:0] wr_resp_tag = s_bid[ID_WIDTH-1:ID_WIDTH-2];

    wire wr_resp_to_m0 = (wr_resp_tag == TAG_M0);
    wire wr_resp_to_m1 = (wr_resp_tag == TAG_M1);
    wire wr_resp_to_m2 = (wr_resp_tag == TAG_M2);

    assign m0_bid   = {2'b00, s_bid[ID_WIDTH-3:0]};
    assign m1_bid   = {2'b00, s_bid[ID_WIDTH-3:0]};
    assign m2_bid   = {2'b00, s_bid[ID_WIDTH-3:0]};
    assign m0_bresp  = s_bresp;
    assign m1_bresp  = s_bresp;
    assign m2_bresp  = s_bresp;

    assign m0_bvalid = s_bvalid && wr_resp_to_m0;
    assign m1_bvalid = s_bvalid && wr_resp_to_m1;
    assign m2_bvalid = s_bvalid && wr_resp_to_m2;

    assign s_bready  = wr_resp_to_m0 ? m0_bready :
                       wr_resp_to_m1 ? m1_bready :
                       wr_resp_to_m2 ? m2_bready : 1'b0;

endmodule