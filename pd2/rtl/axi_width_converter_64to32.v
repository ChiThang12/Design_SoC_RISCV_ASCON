`timescale 1ns/1ps

// ============================================================================
// axi_width_converter_64to32.v  (fixed)
// AXI4 Data Width Converter: 64-bit Master -> 32-bit Slave
// ============================================================================
module axi_width_converter_64to32 #(
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 4,
    parameter M_DATA_WIDTH = 64,
    parameter S_DATA_WIDTH = 32,
    parameter M_STRB_WIDTH = M_DATA_WIDTH / 8,
    parameter S_STRB_WIDTH = S_DATA_WIDTH / 8
)(
    input wire clk,
    input wire rst_n,

    // Master side (64-bit)
    input  wire [ID_WIDTH-1:0]     M_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]   M_AXI_AWADDR,
    input  wire [7:0]              M_AXI_AWLEN,
    input  wire [2:0]              M_AXI_AWSIZE,
    input  wire [1:0]              M_AXI_AWBURST,
    input  wire [3:0]              M_AXI_AWCACHE,
    input  wire [2:0]              M_AXI_AWPROT,
    input  wire                    M_AXI_AWVALID,
    output wire                    M_AXI_AWREADY,

    input  wire [M_DATA_WIDTH-1:0] M_AXI_WDATA,
    input  wire [M_STRB_WIDTH-1:0] M_AXI_WSTRB,
    input  wire                    M_AXI_WLAST,
    input  wire                    M_AXI_WVALID,
    output wire                    M_AXI_WREADY,

    output wire [ID_WIDTH-1:0]     M_AXI_BID,
    output wire [1:0]              M_AXI_BRESP,
    output wire                    M_AXI_BVALID,
    input  wire                    M_AXI_BREADY,

    input  wire [ID_WIDTH-1:0]     M_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   M_AXI_ARADDR,
    input  wire [7:0]              M_AXI_ARLEN,
    input  wire [2:0]              M_AXI_ARSIZE,
    input  wire [1:0]              M_AXI_ARBURST,
    input  wire [3:0]              M_AXI_ARCACHE,
    input  wire [2:0]              M_AXI_ARPROT,
    input  wire                    M_AXI_ARVALID,
    output wire                    M_AXI_ARREADY,

    output wire [ID_WIDTH-1:0]     M_AXI_RID,
    output wire [M_DATA_WIDTH-1:0] M_AXI_RDATA,
    output wire [1:0]              M_AXI_RRESP,
    output wire                    M_AXI_RLAST,
    output wire                    M_AXI_RVALID,
    input  wire                    M_AXI_RREADY,

    // Slave side (32-bit)
    output wire [ID_WIDTH-1:0]     S_AXI_AWID,
    output wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    output wire [7:0]              S_AXI_AWLEN,
    output wire [2:0]              S_AXI_AWSIZE,
    output wire [1:0]              S_AXI_AWBURST,
    output wire [2:0]              S_AXI_AWPROT,
    output wire                    S_AXI_AWVALID,
    input  wire                    S_AXI_AWREADY,

    output wire [S_DATA_WIDTH-1:0] S_AXI_WDATA,
    output wire [S_STRB_WIDTH-1:0] S_AXI_WSTRB,
    output wire                    S_AXI_WLAST,
    output wire                    S_AXI_WVALID,
    input  wire                    S_AXI_WREADY,

    input  wire [ID_WIDTH-1:0]     S_AXI_BID,
    input  wire [1:0]              S_AXI_BRESP,
    input  wire                    S_AXI_BVALID,
    output wire                    S_AXI_BREADY,

    output wire [ID_WIDTH-1:0]     S_AXI_ARID,
    output wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    output wire [7:0]              S_AXI_ARLEN,
    output wire [2:0]              S_AXI_ARSIZE,
    output wire [1:0]              S_AXI_ARBURST,
    output wire [2:0]              S_AXI_ARPROT,
    output wire                    S_AXI_ARVALID,
    input  wire                    S_AXI_ARREADY,

    input  wire [ID_WIDTH-1:0]     S_AXI_RID,
    input  wire [S_DATA_WIDTH-1:0] S_AXI_RDATA,
    input  wire [1:0]              S_AXI_RRESP,
    input  wire                    S_AXI_RLAST,
    input  wire                    S_AXI_RVALID,
    output wire                    S_AXI_RREADY
);

// ============================================================================
// WRITE ADDRESS CHANNEL
// ============================================================================
assign S_AXI_AWID    = M_AXI_AWID;
assign S_AXI_AWADDR  = M_AXI_AWADDR;
assign S_AXI_AWLEN   = {M_AXI_AWLEN[6:0], 1'b1};
assign S_AXI_AWSIZE  = 3'b010;
assign S_AXI_AWBURST = M_AXI_AWBURST;
assign S_AXI_AWPROT  = M_AXI_AWPROT;
assign S_AXI_AWVALID = M_AXI_AWVALID;
assign M_AXI_AWREADY = S_AXI_AWREADY;

// ============================================================================
// WRITE DATA CHANNEL
//
// 3-state FSM:
//   WS_IDLE : chờ master WVALID, latch 64-bit, chuyển sang WS_LOW
//   WS_LOW  : gửi low word [31:0] tới slave, chờ WREADY
//   WS_HIGH : gửi high word [63:32] tới slave, chờ WREADY, về IDLE
// ============================================================================
localparam WS_IDLE = 2'd0,
           WS_LOW  = 2'd1,
           WS_HIGH = 2'd2;

reg [1:0]              ws_state;
reg [M_DATA_WIDTH-1:0] ws_data;
reg [M_STRB_WIDTH-1:0] ws_strb;
reg                    ws_last;

reg                    s_wvalid_r;
reg [S_DATA_WIDTH-1:0] s_wdata_r;
reg [S_STRB_WIDTH-1:0] s_wstrb_r;
reg                    s_wlast_r;

assign S_AXI_WVALID = s_wvalid_r;
assign S_AXI_WDATA  = s_wdata_r;
assign S_AXI_WSTRB  = s_wstrb_r;
assign S_AXI_WLAST  = s_wlast_r;
assign M_AXI_WREADY = (ws_state == WS_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ws_state   <= WS_IDLE;
        ws_data    <= 0;
        ws_strb    <= 0;
        ws_last    <= 0;
        s_wvalid_r <= 0;
        s_wdata_r  <= 0;
        s_wstrb_r  <= 0;
        s_wlast_r  <= 0;
    end else begin
        case (ws_state)
            WS_IDLE: begin
                if (M_AXI_WVALID) begin
                    ws_data    <= M_AXI_WDATA;
                    ws_strb    <= M_AXI_WSTRB;
                    ws_last    <= M_AXI_WLAST;
                    s_wdata_r  <= M_AXI_WDATA[31:0];
                    s_wstrb_r  <= M_AXI_WSTRB[3:0];
                    s_wlast_r  <= 1'b0;
                    s_wvalid_r <= 1'b1;
                    ws_state   <= WS_LOW;
                end
            end
            WS_LOW: begin
                if (S_AXI_WREADY) begin
                    s_wdata_r  <= ws_data[63:32];
                    s_wstrb_r  <= ws_strb[7:4];
                    s_wlast_r  <= ws_last;
                    s_wvalid_r <= 1'b1;
                    ws_state   <= WS_HIGH;
                end
            end
            WS_HIGH: begin
                if (S_AXI_WREADY) begin
                    s_wvalid_r <= 1'b0;
                    s_wlast_r  <= 1'b0;
                    ws_state   <= WS_IDLE;
                end
            end
            default: ws_state <= WS_IDLE;
        endcase
    end
end

// ============================================================================
// WRITE RESPONSE CHANNEL — pass-through
// ============================================================================
assign M_AXI_BID    = S_AXI_BID;
assign M_AXI_BRESP  = S_AXI_BRESP;
assign M_AXI_BVALID = S_AXI_BVALID;
assign S_AXI_BREADY = M_AXI_BREADY;

// ============================================================================
// READ ADDRESS CHANNEL
// ============================================================================
assign S_AXI_ARID    = M_AXI_ARID;
assign S_AXI_ARADDR  = M_AXI_ARADDR;
assign S_AXI_ARLEN   = {M_AXI_ARLEN[6:0], 1'b1};
assign S_AXI_ARSIZE  = 3'b010;
assign S_AXI_ARBURST = M_AXI_ARBURST;
assign S_AXI_ARPROT  = M_AXI_ARPROT;
assign S_AXI_ARVALID = M_AXI_ARVALID;
assign M_AXI_ARREADY = S_AXI_ARREADY;

// ============================================================================
// READ DATA CHANNEL
//
// 3-state FSM:
//   RS_LOW  : chờ slave beat 0 (low word), latch vào rs_low_r
//   RS_HIGH : chờ slave beat 1 (high word), assemble 64-bit, drive master
//   RS_WAIT : giữ master RVALID cho đến khi master RREADY
//
// Toàn bộ output master R đi qua register — không dùng S_AXI_RDATA
// combinational để tránh data thay đổi khi master stall.
// ============================================================================
localparam RS_LOW  = 2'd0,
           RS_HIGH = 2'd1,
           RS_WAIT = 2'd2;

reg [1:0]              rs_state;
reg [S_DATA_WIDTH-1:0] rs_low_r;
reg [1:0]              rs_resp_r;
reg [ID_WIDTH-1:0]     rs_id_r;

reg                    m_rvalid_r;
reg [M_DATA_WIDTH-1:0] m_rdata_r;
reg [1:0]              m_rresp_r;
reg                    m_rlast_r;
reg [ID_WIDTH-1:0]     m_rid_r;

assign M_AXI_RVALID = m_rvalid_r;
assign M_AXI_RDATA  = m_rdata_r;
assign M_AXI_RRESP  = m_rresp_r;
assign M_AXI_RLAST  = m_rlast_r;
assign M_AXI_RID    = m_rid_r;

assign S_AXI_RREADY = (rs_state == RS_LOW) || (rs_state == RS_HIGH);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rs_state   <= RS_LOW;
        rs_low_r   <= 0;
        rs_resp_r  <= 0;
        rs_id_r    <= 0;
        m_rvalid_r <= 0;
        m_rdata_r  <= 0;
        m_rresp_r  <= 0;
        m_rlast_r  <= 0;
        m_rid_r    <= 0;
    end else begin
        case (rs_state)
            RS_LOW: begin
                if (S_AXI_RVALID) begin
                    rs_low_r  <= S_AXI_RDATA;
                    rs_resp_r <= S_AXI_RRESP;
                    rs_id_r   <= S_AXI_RID;
                    rs_state  <= RS_HIGH;
                end
            end
            RS_HIGH: begin
                if (S_AXI_RVALID) begin
                    m_rid_r    <= rs_id_r;
                    m_rdata_r  <= {S_AXI_RDATA, rs_low_r};
                    m_rresp_r  <= rs_resp_r | S_AXI_RRESP;
                    m_rlast_r  <= S_AXI_RLAST;
                    m_rvalid_r <= 1'b1;
                    rs_state   <= RS_WAIT;
                end
            end
            RS_WAIT: begin
                if (M_AXI_RREADY) begin
                    m_rvalid_r <= 1'b0;
                    m_rlast_r  <= 1'b0;
                    rs_state   <= RS_LOW;
                end
            end
            default: rs_state <= RS_LOW;
        endcase
    end
end

endmodule
// ============================================================================
// END
// ============================================================================