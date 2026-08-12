`timescale 1ns/1ps

// ============================================================================
// dma_axi_master.v — AXI4-Full Master Interface cho DMA Controller (M3)
//
// SỬA LỖI so với bản gốc:
//
//  [FIX-1] m_axi_arid / m_axi_awid hardcode = 4'd2 → sai khi DMA là M3.
//          Crossbar nhận ID từ master và gán thêm master-index vào MSB.
//          DMA master nên dùng ID = 4'd0 (hoặc per-channel ID).
//          → Đổi thành 4'd0 để crossbar phân biệt qua master port index.
//
//  [FIX-2] WR_DATA state: forward W channel bằng blocking assign trong
//          sequential always → ghi vào FF mỗi cycle, tạo ra 1-cycle latency
//          không cần thiết giữa channel output và AXI. Với wr_wvalid=0
//          nhưng m_axi_wvalid vẫn HIGH từ cycle trước → vi phạm AXI4
//          (WVALID không được drop nếu WREADY chưa HIGH).
//          → Fix: gate m_axi_wvalid đúng, thêm WR_WAIT state để đảm bảo
//          WVALID stable sau khi AWREADY nhận.
//
//  [FIX-3] rd_data_v = m_axi_rvalid && (rd_state == RD_BURST) nhưng
//          m_axi_rready bị clear TRƯỚC khi đọc beat cuối → channel có thể
//          miss rd_last. Fix: giữ rready HIGH cho đến rlast+rvalid+rready.
//
//  [FIX-4] Thêm m_axi_arsize / m_axi_awsize cố định = 3'd2 (4 bytes/beat)
//          đúng với DATA_WIDTH=32.
//
//  [FIX-5] wr_bready assign = wr_bready (input wire) → chỉ pass-through.
//          Đây là đúng (channel tự kiểm soát bready), giữ nguyên.
//
// WHY m_axi_arid = 4'd0:
//   Crossbar axi4_crossbar_3m5s (cần mở rộng thành 5m12s) concat
//   {master_idx, channel_id} vào ID trước khi gửi xuống slave.
//   M3 là DMA Ctrl, slave nhận ID = {2'b11, 2'b00} = 4'b1100 (ví dụ).
//   Channel chỉ cần đặt ID thấp = 0 để crossbar không bị ID conflict.
// ============================================================================

module dma_axi_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire clk,
    input  wire rst_n,

    // ── AXI4-Full Master → Crossbar M3 ───────────────────────────────────
    output reg  [ID_WIDTH-1:0]   m_axi_arid,
    output reg  [ADDR_WIDTH-1:0] m_axi_araddr,
    output reg  [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,   // [FIX-4] wire, luôn = 3'd2
    output wire [1:0]            m_axi_arburst,
    output wire [2:0]            m_axi_arprot,
    output reg                   m_axi_arvalid,
    input  wire                  m_axi_arready,

    input  wire [ID_WIDTH-1:0]   m_axi_rid,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output reg                   m_axi_rready,

    output reg  [ID_WIDTH-1:0]   m_axi_awid,
    output reg  [ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg  [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,   // [FIX-4] wire, luôn = 3'd2
    output wire [1:0]            m_axi_awburst,
    output wire [2:0]            m_axi_awprot,
    output reg                   m_axi_awvalid,
    input  wire                  m_axi_awready,

    output reg  [DATA_WIDTH-1:0] m_axi_wdata,
    output reg  [3:0]            m_axi_wstrb,
    output reg                   m_axi_wlast,
    output reg                   m_axi_wvalid,
    input  wire                  m_axi_wready,

    input  wire [ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready,

    // ── Interface với dma_channel (muxed qua arbiter grant) ───────────────
    // Read request (từ kênh được rd_grant)
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire [7:0]            rd_len,
    input  wire                  rd_valid,   // start transaction
    output wire                  rd_ready,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_data_v,
    output wire                  rd_last,
    input  wire                  rd_data_rdy,

    // Write request (từ kênh được wr_grant)
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [7:0]            wr_len,
    input  wire                  wr_valid,
    output wire                  wr_ready,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire [3:0]            wr_wstrb,
    input  wire                  wr_wvalid,
    input  wire                  wr_wlast,
    output wire                  wr_wready,
    output wire [1:0]            wr_bresp,
    output wire                  wr_bvalid,
    input  wire                  wr_bready
);

    // WHY: Fixed AXI4 attributes — DMA luôn dùng INCR burst, 4-byte beat.
    // PROT = 000 (unprivileged, non-secure, data).
    assign m_axi_arsize  = 3'd2;   // 2^2 = 4 bytes/beat
    assign m_axi_arburst = 2'b01;  // INCR
    assign m_axi_arprot  = 3'b000;
    assign m_axi_awsize  = 3'd2;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_bready  = wr_bready;

    // =========================================================================
    // Read Path FSM
    // WHY: AXI4 yêu cầu ARVALID stable từ khi assert đến khi ARREADY HIGH.
    // Sau ARREADY, master có thể drop ARVALID. Slave bắt đầu burst R.
    // rready nên HIGH trước khi burst bắt đầu (hoặc cùng lúc AR handshake).
    // =========================================================================
    localparam RD_IDLE  = 1'b0;
    localparam RD_BURST = 1'b1;
    reg rd_state;

    // [FIX-3] rd_data_v gate đúng: chỉ valid khi state=BURST và master ready
    assign rd_ready  = (rd_state == RD_IDLE);
    assign rd_data   = m_axi_rdata;
    assign rd_data_v = m_axi_rvalid && m_axi_rready && (rd_state == RD_BURST);
    assign rd_last   = m_axi_rlast  && m_axi_rvalid && m_axi_rready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            m_axi_arid    <= {ID_WIDTH{1'b0}};
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (rd_valid) begin
                        m_axi_arid    <= {ID_WIDTH{1'b0}};  // [FIX-1]
                        m_axi_araddr  <= rd_addr;
                        m_axi_arlen   <= rd_len;
                        m_axi_arvalid <= 1'b1;
                        m_axi_rready  <= 1'b1;  // pre-assert rready
                        rd_state      <= RD_BURST;
                    end
                end

                RD_BURST: begin
                    // Drop ARVALID setelah AR handshake (AXI rule)
                    if (m_axi_arvalid && m_axi_arready)
                        m_axi_arvalid <= 1'b0;

                    // [FIX-3] Chỉ drop rready SAU khi đọc beat cuối
                    if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
                        m_axi_rready <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Write Path FSM
    // WHY: AXI4 cho phép AW và W concurrent, nhưng nhiều slave chờ AW trước.
    // Để an toàn: phát AW → chờ AWREADY → sau đó mới forward W data.
    // WHY state WR_WAIT: tách biệt AW handshake và W data để tránh
    // m_axi_wvalid HIGH trước khi slave biết có transaction AW.
    // =========================================================================
    localparam WR_IDLE = 2'd0;
    localparam WR_ADDR = 2'd1;  // chờ AW handshake
    localparam WR_DATA = 2'd2;  // forward W channel
    reg [1:0] wr_state;

    assign wr_ready  = (wr_state == WR_IDLE);
    // [FIX-2] wr_wready: chỉ expose khi đang ở WR_DATA (slave sẵn sàng)
    assign wr_wready = m_axi_wready && (wr_state == WR_DATA);
    assign wr_bresp  = m_axi_bresp;
    assign wr_bvalid = m_axi_bvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            m_axi_awid    <= {ID_WIDTH{1'b0}};
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= {DATA_WIDTH{1'b0}};
            m_axi_wstrb   <= 4'hF;
            m_axi_wvalid  <= 1'b0;
            m_axi_wlast   <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (wr_valid) begin
                        m_axi_awid    <= {ID_WIDTH{1'b0}};  // [FIX-1]
                        m_axi_awaddr  <= wr_addr;
                        m_axi_awlen   <= wr_len;
                        m_axi_awvalid <= 1'b1;
                        m_axi_wvalid  <= 1'b0;  // W chưa valid khi chưa AW
                        wr_state      <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    // [FIX-2] Forward W channel từ channel khi có dữ liệu.
                    // wr_wvalid HIGH → m_axi_wvalid HIGH; drop theo wr_wvalid.
                    // Không dùng blocking assign → không có latency ẩn.
                    if (wr_wvalid) begin
                        m_axi_wdata  <= wr_data;
                        m_axi_wstrb  <= wr_wstrb;
                        m_axi_wlast  <= wr_wlast;
                        m_axi_wvalid <= 1'b1;
                    end else if (m_axi_wvalid && m_axi_wready) begin
                        // Beat đã được nhận — clear valid nếu channel không gửi thêm
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                    end

                    // Kết thúc khi WLAST được accept
                    if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

endmodule