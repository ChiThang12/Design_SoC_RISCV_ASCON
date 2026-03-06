// ============================================================================
// axi4_master_mux.v
// Arbitration + mux cho MỘT slave port.
// Nhận request từ 2 master (M0 ưu tiên cao hơn M1), forward tới slave.
// Xử lý ID tagging: bit[ID_WIDTH-1] = master index.
//
// Instantiate 4 lần trong axi4_crossbar — một cho mỗi slave.
// Non-blocking: mỗi slave mux hoạt động độc lập → M0 truy cập S0,
// M1 truy cập S1 đồng thời mà không chặn nhau.
// ============================================================================

module axi4_master_mux #(
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

    // ========================================================================
    // Master 0 — Write (AW/W/B) — ICache: luôn tie off, nhưng vẫn phải nhận
    // ========================================================================
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

    // ========================================================================
    // Master 1 — Write (AW/W/B)
    // ========================================================================
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
    // Read Arbitration FSM
    // Fixed priority: M0 > M1
    // Không cắt burst: giữ grant cho đến khi RLAST
    // ========================================================================
    localparam [1:0] RD_ARB_IDLE = 2'd0,
                     RD_ARB_M0   = 2'd1,
                     RD_ARB_M1   = 2'd2;

    reg [1:0] rd_arb;
    reg       rd_burst_active; // đang trong burst, không cho arbiter chạy

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_arb         <= RD_ARB_IDLE;
            rd_burst_active <= 1'b0;
        end else begin
            case (rd_arb)
                RD_ARB_IDLE: begin
                    if (m0_arvalid)
                        rd_arb <= RD_ARB_M0;
                    else if (m1_arvalid)
                        rd_arb <= RD_ARB_M1;
                end

                RD_ARB_M0: begin
                    // FIX 2: if/else if — không thể set+clear cùng 1 posedge
                    // BUG CŨ: 2 if riêng biệt → 1-beat burst (ARLEN=0):
                    //   AR handshake + RLAST xuất hiện cùng cycle
                    //   → set rd_burst_active=1, rồi ngay lập tức clear=0 (last assign wins)
                    //   → rd_burst_active=0 ngay sau → burst 8-beat tiếp theo bị confused
                    if (!rd_burst_active && m0_arvalid && s_arready) begin
                        rd_burst_active <= 1'b1;
                    end else if (rd_burst_active && s_rvalid && s_rlast && m0_rready) begin
                        rd_burst_active <= 1'b0;
                        if (m0_arvalid)
                            rd_arb <= RD_ARB_M0;
                        else if (m1_arvalid)
                            rd_arb <= RD_ARB_M1;
                        else
                            rd_arb <= RD_ARB_IDLE;
                    end
                end

                RD_ARB_M1: begin
                    if (!rd_burst_active && m1_arvalid && s_arready) begin
                        rd_burst_active <= 1'b1;
                    end else if (rd_burst_active && s_rvalid && s_rlast && m1_rready) begin
                        rd_burst_active <= 1'b0;
                        if (m0_arvalid)
                            rd_arb <= RD_ARB_M0;
                        else if (m1_arvalid)
                            rd_arb <= RD_ARB_M1;
                        else
                            rd_arb <= RD_ARB_IDLE;
                    end
                end

                default: rd_arb <= RD_ARB_IDLE;
            endcase
        end
    end

    wire rd_grant_m0 = (rd_arb == RD_ARB_M0) || (rd_arb == RD_ARB_IDLE && m0_arvalid);
    wire rd_grant_m1 = (rd_arb == RD_ARB_M1) || (rd_arb == RD_ARB_IDLE && !m0_arvalid && m1_arvalid);

    // ========================================================================
    // Write Arbitration FSM (tương tự, fixed priority M0 > M1)
    // ========================================================================
    localparam [1:0] WR_ARB_IDLE = 2'd0,
                     WR_ARB_M0   = 2'd1,
                     WR_ARB_M1   = 2'd2;

    reg [1:0] wr_arb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_arb <= WR_ARB_IDLE;
        end else begin
            case (wr_arb)
                WR_ARB_IDLE: begin
                    if (m0_awvalid)
                        wr_arb <= WR_ARB_M0;
                    else if (m1_awvalid)
                        wr_arb <= WR_ARB_M1;
                end

                WR_ARB_M0: begin
                    // B handshake → giao dịch kết thúc
                    if (s_bvalid && m0_bready) begin
                        if (m0_awvalid)
                            wr_arb <= WR_ARB_M0;
                        else if (m1_awvalid)
                            wr_arb <= WR_ARB_M1;
                        else
                            wr_arb <= WR_ARB_IDLE;
                    end
                end

                WR_ARB_M1: begin
                    if (s_bvalid && m1_bready) begin
                        if (m0_awvalid)
                            wr_arb <= WR_ARB_M0;
                        else if (m1_awvalid)
                            wr_arb <= WR_ARB_M1;
                        else
                            wr_arb <= WR_ARB_IDLE;
                    end
                end

                default: wr_arb <= WR_ARB_IDLE;
            endcase
        end
    end

    wire wr_grant_m0 = (wr_arb == WR_ARB_M0) || (wr_arb == WR_ARB_IDLE && m0_awvalid);
    wire wr_grant_m1 = (wr_arb == WR_ARB_M1) || (wr_arb == WR_ARB_IDLE && !m0_awvalid && m1_awvalid);

    // ========================================================================
    // AR Channel Mux → Slave (với ID tagging)
    // Bit[ID_WIDTH-1] = master index (0=M0, 1=M1)
    // ========================================================================
    assign s_arvalid = rd_grant_m0 ? m0_arvalid :
                       rd_grant_m1 ? m1_arvalid : 1'b0;

    assign s_araddr  = rd_grant_m0 ? m0_araddr : m1_araddr;
    assign s_arlen   = rd_grant_m0 ? m0_arlen  : m1_arlen;
    assign s_arsize  = rd_grant_m0 ? m0_arsize : m1_arsize;
    assign s_arburst = rd_grant_m0 ? m0_arburst: m1_arburst;
    assign s_arprot  = rd_grant_m0 ? m0_arprot : m1_arprot;

    // ID tagging: gán bit cao nhất = master index
    assign s_arid    = rd_grant_m0 ? {1'b0, m0_arid[ID_WIDTH-2:0]} :
                                     {1'b1, m1_arid[ID_WIDTH-2:0]};

    assign m0_arready = rd_grant_m0 ? s_arready : 1'b0;
    assign m1_arready = rd_grant_m1 ? s_arready : 1'b0;

    // ========================================================================
    // R Channel Demux ← Slave (dựa vào bit cao của RID)
    // ========================================================================
    wire rd_resp_to_m0 = (s_rid[ID_WIDTH-1] == 1'b0);
    wire rd_resp_to_m1 = (s_rid[ID_WIDTH-1] == 1'b1);

    // Strip master tag bit khi trả về master
    assign m0_rid    = {1'b0, s_rid[ID_WIDTH-2:0]};
    assign m1_rid    = {1'b0, s_rid[ID_WIDTH-2:0]};

    assign m0_rdata  = s_rdata;
    assign m1_rdata  = s_rdata;
    assign m0_rresp  = s_rresp;
    assign m1_rresp  = s_rresp;
    // FIX 1: gate RLAST bằng rd_resp_to_mX — tránh leak sang master không được serve
    // Nếu không gate: khi mux_s1 đang idle, m0_rlast_s[1]=s_rlast=1 rác
    // OR bus ở crossbar bắt được → M0_AXI_RLAST=1 dù burst chưa xong
    assign m0_rlast  = s_rlast && rd_resp_to_m0;
    assign m1_rlast  = s_rlast && rd_resp_to_m1;

    assign m0_rvalid = s_rvalid && rd_resp_to_m0;
    assign m1_rvalid = s_rvalid && rd_resp_to_m1;

    assign s_rready  = rd_resp_to_m0 ? m0_rready :
                       rd_resp_to_m1 ? m1_rready : 1'b0;

    // ========================================================================
    // AW Channel Mux → Slave (với ID tagging)
    // ========================================================================
    assign s_awvalid = wr_grant_m0 ? m0_awvalid :
                       wr_grant_m1 ? m1_awvalid : 1'b0;

    assign s_awaddr  = wr_grant_m0 ? m0_awaddr : m1_awaddr;
    assign s_awlen   = wr_grant_m0 ? m0_awlen  : m1_awlen;
    assign s_awsize  = wr_grant_m0 ? m0_awsize : m1_awsize;
    assign s_awburst = wr_grant_m0 ? m0_awburst: m1_awburst;
    assign s_awprot  = wr_grant_m0 ? m0_awprot : m1_awprot;
    assign s_awid    = wr_grant_m0 ? {1'b0, m0_awid[ID_WIDTH-2:0]} :
                                     {1'b1, m1_awid[ID_WIDTH-2:0]};

    assign m0_awready = wr_grant_m0 ? s_awready : 1'b0;
    assign m1_awready = wr_grant_m1 ? s_awready : 1'b0;

    // ========================================================================
    // W Channel Mux → Slave
    // ========================================================================
    assign s_wdata  = wr_grant_m0 ? m0_wdata : m1_wdata;
    assign s_wstrb  = wr_grant_m0 ? m0_wstrb : m1_wstrb;
    assign s_wlast  = wr_grant_m0 ? m0_wlast : m1_wlast;
    assign s_wvalid = wr_grant_m0 ? m0_wvalid :
                      wr_grant_m1 ? m1_wvalid : 1'b0;

    assign m0_wready = wr_grant_m0 ? s_wready : 1'b0;
    assign m1_wready = wr_grant_m1 ? s_wready : 1'b0;

    // ========================================================================
    // B Channel Demux ← Slave
    // ========================================================================
    wire wr_resp_to_m0 = (s_bid[ID_WIDTH-1] == 1'b0);
    wire wr_resp_to_m1 = (s_bid[ID_WIDTH-1] == 1'b1);

    assign m0_bid    = {1'b0, s_bid[ID_WIDTH-2:0]};
    assign m1_bid    = {1'b0, s_bid[ID_WIDTH-2:0]};
    assign m0_bresp  = s_bresp;
    assign m1_bresp  = s_bresp;

    assign m0_bvalid = s_bvalid && wr_resp_to_m0;
    assign m1_bvalid = s_bvalid && wr_resp_to_m1;

    assign s_bready  = wr_resp_to_m0 ? m0_bready :
                       wr_resp_to_m1 ? m1_bready : 1'b0;

endmodule