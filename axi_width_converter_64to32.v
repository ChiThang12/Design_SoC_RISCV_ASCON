// ============================================================================
// axi_width_converter_64to32.v
// AXI4 Data Width Converter: 64-bit Master → 32-bit Slave
//
// Chuyển đổi giao tiếp từ AXI4 master 64-bit (ASCON DMA) sang
// AXI4 slave 32-bit (crossbar).
//
// Nguyên lý hoạt động:
//   WRITE path (64→32):
//     - Mỗi beat 64-bit từ master được tách thành 2 beat 32-bit tới slave.
//     - Beat thấp (WDATA[31:0])  → slave beat 0
//     - Beat cao (WDATA[63:32]) → slave beat 1
//     - AWLEN được nhân đôi: slave_AWLEN = 2*(master_AWLEN+1) - 1
//     - AWSIZE được đặt cố định = 3'b010 (4 bytes)
//     - WLAST chỉ assert tại beat 32-bit cuối cùng của burst
//
//   READ path (32→64):
//     - 2 beat 32-bit từ slave được ghép thành 1 beat 64-bit cho master.
//     - Beat lẻ  (slave beat 0) → RDATA[31:0]
//     - Beat chẵn (slave beat 1) → RDATA[63:32]
//     - ARLEN được nhân đôi tương tự
//     - RLAST chỉ assert với master khi đã nhận đủ 2 beat slave
//
//   BURST chỉ hỗ trợ INCR (AXBURST=2'b01).
//   ID, PROT, CACHE được pass-through.
//
// Parameters:
//   ADDR_WIDTH  : địa chỉ (default 32)
//   ID_WIDTH    : ID width (default 4)
//   M_DATA_WIDTH: data width phía master — phải = 64 (default 64)
//   S_DATA_WIDTH: data width phía slave  — phải = 32 (default 32)
// ============================================================================

module axi_width_converter_64to32 #(
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 4,
    parameter M_DATA_WIDTH = 64,   // Master side (ASCON DMA)
    parameter S_DATA_WIDTH = 32,   // Slave  side (Crossbar)
    parameter M_STRB_WIDTH = M_DATA_WIDTH / 8,  // 8
    parameter S_STRB_WIDTH = S_DATA_WIDTH / 8   // 4
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Master side (64-bit) — kết nối với ASCON M_AXI
    // ========================================================================

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]    M_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]  M_AXI_AWADDR,
    input  wire [7:0]             M_AXI_AWLEN,
    input  wire [2:0]             M_AXI_AWSIZE,
    input  wire [1:0]             M_AXI_AWBURST,
    input  wire [3:0]             M_AXI_AWCACHE,
    input  wire [2:0]             M_AXI_AWPROT,
    input  wire                   M_AXI_AWVALID,
    output wire                   M_AXI_AWREADY,

    // Write Data Channel
    input  wire [M_DATA_WIDTH-1:0] M_AXI_WDATA,
    input  wire [M_STRB_WIDTH-1:0] M_AXI_WSTRB,
    input  wire                    M_AXI_WLAST,
    input  wire                    M_AXI_WVALID,
    output wire                    M_AXI_WREADY,

    // Write Response Channel
    output wire [ID_WIDTH-1:0]    M_AXI_BID,
    output wire [1:0]             M_AXI_BRESP,
    output wire                   M_AXI_BVALID,
    input  wire                   M_AXI_BREADY,

    // Read Address Channel
    input  wire [ID_WIDTH-1:0]    M_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]  M_AXI_ARADDR,
    input  wire [7:0]             M_AXI_ARLEN,
    input  wire [2:0]             M_AXI_ARSIZE,
    input  wire [1:0]             M_AXI_ARBURST,
    input  wire [3:0]             M_AXI_ARCACHE,
    input  wire [2:0]             M_AXI_ARPROT,
    input  wire                   M_AXI_ARVALID,
    output wire                   M_AXI_ARREADY,

    // Read Data Channel
    output wire [ID_WIDTH-1:0]    M_AXI_RID,
    output wire [M_DATA_WIDTH-1:0] M_AXI_RDATA,
    output wire [1:0]             M_AXI_RRESP,
    output wire                   M_AXI_RLAST,
    output wire                   M_AXI_RVALID,
    input  wire                   M_AXI_RREADY,

    // ========================================================================
    // Slave side (32-bit) — kết nối với Crossbar M2
    // ========================================================================

    // Write Address Channel
    output wire [ID_WIDTH-1:0]    S_AXI_AWID,
    output wire [ADDR_WIDTH-1:0]  S_AXI_AWADDR,
    output wire [7:0]             S_AXI_AWLEN,
    output wire [2:0]             S_AXI_AWSIZE,
    output wire [1:0]             S_AXI_AWBURST,
    output wire [2:0]             S_AXI_AWPROT,
    output wire                   S_AXI_AWVALID,
    input  wire                   S_AXI_AWREADY,

    // Write Data Channel
    output wire [S_DATA_WIDTH-1:0] S_AXI_WDATA,
    output wire [S_STRB_WIDTH-1:0] S_AXI_WSTRB,
    output wire                    S_AXI_WLAST,
    output wire                    S_AXI_WVALID,
    input  wire                    S_AXI_WREADY,

    // Write Response Channel
    input  wire [ID_WIDTH-1:0]    S_AXI_BID,
    input  wire [1:0]             S_AXI_BRESP,
    input  wire                   S_AXI_BVALID,
    output wire                   S_AXI_BREADY,

    // Read Address Channel
    output wire [ID_WIDTH-1:0]    S_AXI_ARID,
    output wire [ADDR_WIDTH-1:0]  S_AXI_ARADDR,
    output wire [7:0]             S_AXI_ARLEN,
    output wire [2:0]             S_AXI_ARSIZE,
    output wire [1:0]             S_AXI_ARBURST,
    output wire [2:0]             S_AXI_ARPROT,
    output wire                   S_AXI_ARVALID,
    input  wire                   S_AXI_ARREADY,

    // Read Data Channel
    input  wire [ID_WIDTH-1:0]    S_AXI_RID,
    input  wire [S_DATA_WIDTH-1:0] S_AXI_RDATA,
    input  wire [1:0]             S_AXI_RRESP,
    input  wire                   S_AXI_RLAST,
    input  wire                   S_AXI_RVALID,
    output wire                   S_AXI_RREADY
);

    // ========================================================================
    // WRITE ADDRESS CHANNEL
    // Nhân đôi AWLEN: 1 beat 64-bit = 2 beat 32-bit
    // AWSIZE cố định = 3'b010 (4 bytes = 32-bit)
    // ========================================================================
    assign S_AXI_AWID    = M_AXI_AWID;
    assign S_AXI_AWADDR  = M_AXI_AWADDR;
    assign S_AXI_AWLEN   = {M_AXI_AWLEN[6:0], 1'b1};  // (AWLEN+1)*2 - 1
    assign S_AXI_AWSIZE  = 3'b010;                      // 4 bytes
    assign S_AXI_AWBURST = M_AXI_AWBURST;
    assign S_AXI_AWPROT  = M_AXI_AWPROT;
    assign S_AXI_AWVALID = M_AXI_AWVALID;
    assign M_AXI_AWREADY = S_AXI_AWREADY;

    // ========================================================================
    // WRITE DATA CHANNEL
    // Mỗi beat 64-bit → 2 beat 32-bit (low word trước, high word sau)
    // ========================================================================
    reg wr_beat_sel;   // 0 = đang gửi low word, 1 = đang gửi high word
    reg [M_DATA_WIDTH-1:0] wr_data_latch;
    reg [M_STRB_WIDTH-1:0] wr_strb_latch;
    reg                    wr_last_latch;
    reg                    wr_data_valid;

    // State: 0 = chờ beat 64-bit từ master, 1 = đang gửi high word
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_beat_sel   <= 1'b0;
            wr_data_latch <= {M_DATA_WIDTH{1'b0}};
            wr_strb_latch <= {M_STRB_WIDTH{1'b0}};
            wr_last_latch <= 1'b0;
            wr_data_valid <= 1'b0;
        end else begin
            if (wr_beat_sel == 1'b0) begin
                // Gửi low word — latch toàn bộ beat từ master
                if (M_AXI_WVALID && S_AXI_WREADY) begin
                    wr_data_latch <= M_AXI_WDATA;
                    wr_strb_latch <= M_AXI_WSTRB;
                    wr_last_latch <= M_AXI_WLAST;
                    wr_beat_sel   <= 1'b1;
                    wr_data_valid <= 1'b1;
                end
            end else begin
                // Gửi high word — xong thì trở về chờ beat tiếp theo
                if (S_AXI_WREADY) begin
                    wr_beat_sel   <= 1'b0;
                    wr_data_valid <= 1'b0;
                end
            end
        end
    end

    // Low word: lấy trực tiếp từ master (beat 0)
    // High word: lấy từ latch (beat 1)
    assign S_AXI_WDATA  = (wr_beat_sel == 1'b0)
                            ? M_AXI_WDATA[S_DATA_WIDTH-1:0]
                            : wr_data_latch[M_DATA_WIDTH-1:S_DATA_WIDTH];

    assign S_AXI_WSTRB  = (wr_beat_sel == 1'b0)
                            ? M_AXI_WSTRB[S_STRB_WIDTH-1:0]
                            : wr_strb_latch[M_STRB_WIDTH-1:S_STRB_WIDTH];

    // WLAST: chỉ assert ở beat high word cuối cùng của burst
    assign S_AXI_WLAST  = (wr_beat_sel == 1'b1) && wr_last_latch;

    // WVALID:
    //   beat 0 (low): valid khi master valid
    //   beat 1 (high): valid khi latch đã có data
    assign S_AXI_WVALID = (wr_beat_sel == 1'b0) ? M_AXI_WVALID
                                                 : wr_data_valid;

    // Master WREADY: chỉ báo ready khi đang ở beat 0 (low word)
    // Beat 1 (high word) dùng latch, master không cần gửi thêm
    assign M_AXI_WREADY = (wr_beat_sel == 1'b0) && S_AXI_WREADY;

    // ========================================================================
    // WRITE RESPONSE CHANNEL — pass-through
    // ========================================================================
    assign M_AXI_BID    = S_AXI_BID;
    assign M_AXI_BRESP  = S_AXI_BRESP;
    assign M_AXI_BVALID = S_AXI_BVALID;
    assign S_AXI_BREADY = M_AXI_BREADY;

    // ========================================================================
    // READ ADDRESS CHANNEL
    // Nhân đôi ARLEN tương tự AWLEN
    // ========================================================================
    assign S_AXI_ARID    = M_AXI_ARID;
    assign S_AXI_ARADDR  = M_AXI_ARADDR;
    assign S_AXI_ARLEN   = {M_AXI_ARLEN[6:0], 1'b1};  // (ARLEN+1)*2 - 1
    assign S_AXI_ARSIZE  = 3'b010;                      // 4 bytes
    assign S_AXI_ARBURST = M_AXI_ARBURST;
    assign S_AXI_ARPROT  = M_AXI_ARPROT;
    assign S_AXI_ARVALID = M_AXI_ARVALID;
    assign M_AXI_ARREADY = S_AXI_ARREADY;

    // ========================================================================
    // READ DATA CHANNEL
    // Ghép 2 beat 32-bit → 1 beat 64-bit cho master
    // ========================================================================
    reg                    rd_beat_sel;  // 0 = nhận low word, 1 = nhận high word
    reg [S_DATA_WIDTH-1:0] rd_low_latch; // lưu low word
    reg [1:0]              rd_resp_latch;
    reg [ID_WIDTH-1:0]     rd_id_latch;
    reg                    rd_data_valid; // beat 64-bit đã sẵn sàng
    reg                    rd_last_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_beat_sel   <= 1'b0;
            rd_low_latch  <= {S_DATA_WIDTH{1'b0}};
            rd_resp_latch <= 2'b00;
            rd_id_latch   <= {ID_WIDTH{1'b0}};
            rd_data_valid <= 1'b0;
            rd_last_latch <= 1'b0;
        end else begin
            if (rd_beat_sel == 1'b0) begin
                // Nhận low word từ slave
                if (S_AXI_RVALID && S_AXI_RREADY) begin
                    rd_low_latch  <= S_AXI_RDATA;
                    rd_resp_latch <= S_AXI_RRESP;
                    rd_id_latch   <= S_AXI_RID;
                    rd_beat_sel   <= 1'b1;
                end
            end else begin
                // Nhận high word từ slave — sau đó present beat 64-bit cho master
                if (S_AXI_RVALID) begin
                    rd_last_latch <= S_AXI_RLAST;
                    rd_data_valid <= 1'b1;
                    rd_beat_sel   <= 1'b0;
                end
                // Master đã nhận → clear valid
                if (rd_data_valid && M_AXI_RREADY) begin
                    rd_data_valid <= 1'b0;
                end
            end
        end
    end

    // Slave RREADY:
    //   beat 0: sẵn sàng nhận low word bất cứ lúc nào
    //   beat 1: sẵn sàng nhận high word khi chưa có data đang chờ master
    assign S_AXI_RREADY = (rd_beat_sel == 1'b0) ? 1'b1
                                                 : ~rd_data_valid;

    // Master R channel
    assign M_AXI_RID    = rd_id_latch;
    assign M_AXI_RDATA  = {S_AXI_RDATA, rd_low_latch};  // [63:32]=high, [31:0]=low
    assign M_AXI_RRESP  = rd_resp_latch | S_AXI_RRESP;  // propagate worst response
    assign M_AXI_RLAST  = rd_last_latch;
    assign M_AXI_RVALID = rd_data_valid;

endmodule