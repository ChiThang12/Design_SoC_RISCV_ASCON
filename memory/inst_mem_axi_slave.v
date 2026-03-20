// ============================================================================
// inst_mem_axi_slave.v - AXI4 Full Slave (v5 - fixes)
// ============================================================================
// FIXES:
//
// [FIX-CRIT-3] AWREADY delay 1 cycle:
//   Gốc: S_AXI_AWREADY <= 1'b1 khi detect AWVALID (sequential → delay 1 cycle)
//   → Master fire-and-forget sẽ miss handshake.
//   Fix: S_AXI_AWREADY = combinational, HIGH khi wr_state == WR_IDLE.
//   Tương tự cách S_AXI_ARREADY đã làm (combinational assign).
//   SLVERR response vẫn đúng: AWREADY lên ngay, data được drain, BRESP=SLVERR.
//
// [FIX-WR-DATA-DRAIN] Khi AWREADY combinational, WREADY phải sẵn sàng ngay
//   cycle WR_DATA (không cần pre-assert trong WR_IDLE nữa).
//   Đơn giản hóa: WREADY = 1'b1 trong WR_DATA state.
//
// Các tính năng khác giữ nguyên từ v4.
// ============================================================================

`include "memory/inst_mem.v"

module inst_mem_axi_slave #(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter ID_WIDTH      = 4,
    parameter MEM_SIZE      = 4096,
    parameter MEM_INIT_FILE = "memory/program.hex"
)(
    input wire clk,
    input wire rst_n,

    // Write channels (read-only memory → always SLVERR)
    input  wire [ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [7:0]              S_AXI_AWLEN,
    input  wire [2:0]              S_AXI_AWSIZE,
    input  wire [1:0]              S_AXI_AWBURST,
    input  wire [2:0]              S_AXI_AWPROT,
    input  wire                    S_AXI_AWVALID,
    output wire                    S_AXI_AWREADY,  // [FIX-CRIT-3] combinational

    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WLAST,
    input  wire                    S_AXI_WVALID,
    output wire                    S_AXI_WREADY,   // [FIX] combinational trong WR_DATA

    output reg  [ID_WIDTH-1:0]     S_AXI_BID,
    output reg  [1:0]              S_AXI_BRESP,
    output reg                     S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

    // Read channels
    input  wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [7:0]              S_AXI_ARLEN,
    input  wire [2:0]              S_AXI_ARSIZE,
    input  wire [1:0]              S_AXI_ARBURST,
    input  wire [2:0]              S_AXI_ARPROT,
    input  wire                    S_AXI_ARVALID,
    output wire                    S_AXI_ARREADY,  // combinational (giữ nguyên)

    output wire [ID_WIDTH-1:0]     S_AXI_RID,
    output wire [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,
    output wire                    S_AXI_RVALID,
    input  wire                    S_AXI_RREADY
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // =========================================================================
    // Read State Machine
    // =========================================================================
    localparam RD_IDLE  = 1'b0;
    localparam RD_BURST = 1'b1;
    reg rd_state;

    assign S_AXI_ARREADY = (rd_state == RD_IDLE);
    wire ar_handshake    = S_AXI_ARVALID && S_AXI_ARREADY;
    wire burst_req       = ar_handshake;

    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0]            burst_len_r;
    reg [ID_WIDTH-1:0]   rid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_addr   <= {ADDR_WIDTH{1'b0}};
            burst_len_r <= 8'd0;
            rid_r       <= {ID_WIDTH{1'b0}};
        end else if (ar_handshake) begin
            read_addr   <= S_AXI_ARADDR;
            burst_len_r <= S_AXI_ARLEN;
            rid_r       <= S_AXI_ARID;
        end
    end

    assign S_AXI_RID = ar_handshake ? S_AXI_ARID : rid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_state <= RD_IDLE;
        else case (rd_state)
            RD_IDLE:  if (ar_handshake)                                  rd_state <= RD_BURST;
            RD_BURST: if (S_AXI_RVALID && S_AXI_RREADY && S_AXI_RLAST) rd_state <= RD_IDLE;
            default:  rd_state <= RD_IDLE;
        endcase
    end

    wire [ADDR_WIDTH-1:0] burst_addr = ar_handshake ? S_AXI_ARADDR : read_addr;
    wire [7:0]            burst_len  = ar_handshake ? S_AXI_ARLEN  : burst_len_r;

    wire [DATA_WIDTH-1:0] burst_data;
    wire                  burst_valid;
    wire                  burst_last;
    wire [DATA_WIDTH-1:0] simple_inst;

    inst_mem #(
        .MEM_SIZE      (MEM_SIZE),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .MEM_INIT_FILE (MEM_INIT_FILE)
    ) imem (
        .clk              (clk),
        .rst_n            (rst_n),
        .PC               (burst_addr),
        .Instruction_Code (simple_inst),
        .burst_addr       (burst_addr),
        .burst_len        (burst_len),
        .burst_req        (burst_req),
        .burst_data       (burst_data),
        .burst_valid      (burst_valid),
        .burst_last       (burst_last),
        .burst_ready      (S_AXI_RREADY)
    );

    assign S_AXI_RDATA  = burst_data;
    assign S_AXI_RRESP  = RESP_OKAY;
    assign S_AXI_RLAST  = burst_last;
    assign S_AXI_RVALID = burst_valid;

    // =========================================================================
    // Write channels — always SLVERR
    // [FIX-CRIT-3] Dùng combinational AWREADY/WREADY
    // =========================================================================
    localparam [1:0] WR_IDLE = 2'b00,
                     WR_DATA = 2'b01,
                     WR_RESP = 2'b10;
    reg [1:0]        wr_state;
    reg [ID_WIDTH-1:0] bid_r;

    // [FIX-CRIT-3] AWREADY combinational: HIGH khi WR_IDLE
    assign S_AXI_AWREADY = (wr_state == WR_IDLE);

    // [FIX] WREADY combinational: HIGH khi WR_DATA
    assign S_AXI_WREADY  = (wr_state == WR_DATA);

    wire aw_handshake = S_AXI_AWVALID && S_AXI_AWREADY;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state     <= WR_IDLE;
            S_AXI_BID    <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP  <= RESP_SLVERR;
            S_AXI_BVALID <= 1'b0;
            bid_r        <= {ID_WIDTH{1'b0}};
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (aw_handshake) begin
                        bid_r    <= S_AXI_AWID;
                        wr_state <= WR_DATA;
                    end
                end
                WR_DATA: begin
                    // WREADY = combinational (see assign above)
                    if (S_AXI_WVALID && S_AXI_WLAST) begin
                        S_AXI_BID    <= bid_r;
                        S_AXI_BRESP  <= RESP_SLVERR;
                        S_AXI_BVALID <= 1'b1;
                        wr_state     <= WR_RESP;
                    end
                end
                WR_RESP: begin
                    if (S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Debug
    // =========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (ar_handshake)
            $display("[IMEM] Burst start: addr=0x%h len=%0d id=0x%h @ %0t",
                     S_AXI_ARADDR, S_AXI_ARLEN+1, S_AXI_ARID, $time);
        if (S_AXI_RVALID && S_AXI_RREADY)
            $display("[IMEM] Beat: data=0x%h last=%b rid=0x%h @ %0t",
                     S_AXI_RDATA, S_AXI_RLAST, S_AXI_RID, $time);
        if (aw_handshake)
            $display("[IMEM] Write attempt (SLVERR): addr=0x%h @ %0t",
                     S_AXI_AWADDR, $time);
    end
    `endif

endmodule