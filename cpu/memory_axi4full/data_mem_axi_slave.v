// ============================================================================
// data_mem_axi4_slave.v - Data Memory AXI4 Full Slave (FIXED)
// ============================================================================
// FIXES:
// - S_AXI_ARREADY, S_AXI_AWREADY đổi từ reg thành wire (vì gán assign)
// - Giữ nguyên logic combinational để đảm bảo handshake ngay lập tức
// ============================================================================

`include "cpu/memory_axi4full/data_mem_burst.v"

module data_mem_axi4_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter MEM_SIZE   = 8192
)(
    input wire clk,
    input wire rst_n,

    // Write Address Channel
    input wire [ID_WIDTH-1:0]     S_AXI_AWID,
    input wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input wire [7:0]              S_AXI_AWLEN,
    input wire [2:0]              S_AXI_AWSIZE,
    input wire [1:0]              S_AXI_AWBURST,
    input wire [2:0]              S_AXI_AWPROT,
    input wire                    S_AXI_AWVALID,
    output wire                   S_AXI_AWREADY,  // Changed from reg to wire

    // Write Data Channel
    input wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input wire                    S_AXI_WLAST,
    input wire                    S_AXI_WVALID,
    output reg                    S_AXI_WREADY,

    // Write Response Channel
    output reg  [ID_WIDTH-1:0]    S_AXI_BID,
    output reg  [1:0]             S_AXI_BRESP,
    output reg                    S_AXI_BVALID,
    input wire                    S_AXI_BREADY,

    // Read Address Channel
    input wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input wire [7:0]              S_AXI_ARLEN,
    input wire [2:0]              S_AXI_ARSIZE,
    input wire [1:0]              S_AXI_ARBURST,
    input wire [2:0]              S_AXI_ARPROT,
    input wire                    S_AXI_ARVALID,
    output wire                   S_AXI_ARREADY,  // Changed from reg to wire

    // Read Data Channel
    output wire [ID_WIDTH-1:0]    S_AXI_RID,
    output wire [DATA_WIDTH-1:0]  S_AXI_RDATA,
    output wire [1:0]             S_AXI_RRESP,
    output wire                   S_AXI_RLAST,
    output wire                   S_AXI_RVALID,
    input wire                    S_AXI_RREADY
);

    localparam [1:0] RESP_OKAY = 2'b00;

    reg [ID_WIDTH-1:0] wr_id_latch;
    reg [ID_WIDTH-1:0] rd_id_latch;

    // ========================================================================
    // Read State Machine
    // ========================================================================
    localparam [1:0] RD_IDLE  = 2'b00,
                     RD_BURST = 2'b01;

    reg [1:0] rd_state, rd_next;

    // ========================================================================
    // Write State Machine
    // ========================================================================
    localparam [2:0] WR_IDLE  = 3'b000,
                     WR_BURST = 3'b001,
                     WR_RESP  = 3'b010;

    reg [2:0] wr_state, wr_next;

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0]  rd_burst_length;
    reg [2:0]  rd_burst_size;
    reg [1:0]  rd_burst_type;

    reg [ADDR_WIDTH-1:0] write_addr;
    reg [7:0]  wr_burst_length;
    reg [2:0]  wr_burst_size;
    reg [1:0]  wr_burst_type;
    reg [7:0]  wr_beat_count;

    // ========================================================================
    // Burst interfaces
    // ========================================================================
    wire [ADDR_WIDTH-1:0] burst_rd_addr;
    wire [7:0]  burst_rd_len;
    reg         burst_rd_req;
    wire [DATA_WIDTH-1:0] burst_rd_data;
    wire        burst_rd_valid;
    wire        burst_rd_last;
    wire        burst_rd_ready;

    wire [ADDR_WIDTH-1:0] burst_wr_addr;
    wire [7:0]  burst_wr_len;
    wire [DATA_WIDTH-1:0] burst_wr_data;
    wire [3:0]  burst_wr_strb;
    wire        burst_wr_valid;
    wire        burst_wr_ready;
    wire        burst_wr_last;

    // Read interface wiring
    assign burst_rd_addr  = read_addr;
    assign burst_rd_len   = rd_burst_length;
    assign burst_rd_ready = S_AXI_RREADY;

    // [FIX-CRIT-1] burst_wr_addr: dùng S_AXI_AWADDR trực tiếp tại cycle AW handshake
    wire aw_handshake = S_AXI_AWVALID && S_AXI_AWREADY;
    wire [ADDR_WIDTH-1:0] wr_awaddr_mux;
    assign wr_awaddr_mux = aw_handshake ? S_AXI_AWADDR : write_addr;

    assign burst_wr_addr  = wr_awaddr_mux;
    assign burst_wr_len   = wr_burst_length;
    assign burst_wr_data  = S_AXI_WDATA;
    assign burst_wr_strb  = S_AXI_WSTRB;
    assign burst_wr_last  = S_AXI_WLAST;

    // [FIX-BUG5] dùng wr_next để detect AW handshake cycle
    assign burst_wr_valid = ((wr_state == WR_BURST) || (wr_next == WR_BURST)) && S_AXI_WVALID;

    // Read outputs
    assign S_AXI_RID    = rd_id_latch;
    assign S_AXI_RDATA  = burst_rd_data;
    assign S_AXI_RRESP  = RESP_OKAY;
    assign S_AXI_RLAST  = burst_rd_last;
    assign S_AXI_RVALID = burst_rd_valid;

    // Simple interface (unused)
    wire [ADDR_WIDTH-1:0] simple_addr     = 32'h0;
    wire [DATA_WIDTH-1:0] simple_wdata    = 32'h0;
    wire                  simple_memwrite = 1'b0;
    wire                  simple_memread  = 1'b0;
    wire [1:0]            simple_byte_size = 2'b10;
    wire                  simple_sign_ext  = 1'b0;
    wire [DATA_WIDTH-1:0] simple_rdata;

    // ========================================================================
    // Data Memory Instance
    // ========================================================================
    data_mem_burst #(
        .MEM_SIZE  (MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dmem (
        .clk            (clk),
        .rst_n          (rst_n),
        .address        (simple_addr),
        .write_data     (simple_wdata),
        .memwrite       (simple_memwrite),
        .memread        (simple_memread),
        .byte_size      (simple_byte_size),
        .sign_ext       (simple_sign_ext),
        .read_data      (simple_rdata),
        .burst_rd_addr  (burst_rd_addr),
        .burst_rd_len   (burst_rd_len),
        .burst_rd_req   (burst_rd_req),
        .burst_rd_data  (burst_rd_data),
        .burst_rd_valid (burst_rd_valid),
        .burst_rd_last  (burst_rd_last),
        .burst_rd_ready (burst_rd_ready),
        .burst_wr_addr  (burst_wr_addr),
        .burst_wr_len   (burst_wr_len),
        .burst_wr_data  (burst_wr_data),
        .burst_wr_strb  (burst_wr_strb),
        .burst_wr_valid (burst_wr_valid),
        .burst_wr_ready (burst_wr_ready),
        .burst_wr_last  (burst_wr_last)
    );

    // ========================================================================
    // Read State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_state <= RD_IDLE;
        else        rd_state <= rd_next;
    end

    always @(*) begin
        rd_next = rd_state;
        case (rd_state)
            RD_IDLE:  if (S_AXI_ARVALID && S_AXI_ARREADY)               rd_next = RD_BURST;
            RD_BURST: if (S_AXI_RVALID && S_AXI_RREADY && S_AXI_RLAST)  rd_next = RD_IDLE;
            default:  rd_next = RD_IDLE;
        endcase
    end

    // ARREADY là combinational (phụ thuộc trạng thái)
    assign S_AXI_ARREADY = (rd_state == RD_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_addr        <= {ADDR_WIDTH{1'b0}};
            rd_burst_length  <= 8'd0;
            rd_burst_size    <= 3'd0;
            rd_burst_type    <= 2'd0;
            burst_rd_req     <= 1'b0;
            rd_id_latch      <= {ID_WIDTH{1'b0}};
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    burst_rd_req  <= 1'b0;
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin  // handshake
                        read_addr       <= S_AXI_ARADDR;
                        rd_burst_length <= S_AXI_ARLEN;
                        rd_burst_size   <= S_AXI_ARSIZE;
                        rd_burst_type   <= S_AXI_ARBURST;
                        rd_id_latch     <= S_AXI_ARID;
                        burst_rd_req    <= 1'b1;  // pulse 1 cycle
                    end
                end
                RD_BURST: begin
                    burst_rd_req  <= 1'b0;
                end
                default: begin
                    burst_rd_req  <= 1'b0;
                end
            endcase
        end
    end

    // ========================================================================
    // Write State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_state <= WR_IDLE;
        else        wr_state <= wr_next;
    end

    always @(*) begin
        wr_next = wr_state;
        case (wr_state)
            WR_IDLE:  if (S_AXI_AWVALID && S_AXI_AWREADY)  wr_next = WR_BURST;
            WR_BURST: if (S_AXI_WVALID  && S_AXI_WLAST)    wr_next = WR_RESP;
            WR_RESP:  if (S_AXI_BREADY  && S_AXI_BVALID)   wr_next = WR_IDLE;
            default:  wr_next = WR_IDLE;
        endcase
    end

    // AWREADY là combinational
    assign S_AXI_AWREADY = (wr_state == WR_IDLE);

    // Write Address Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_addr       <= {ADDR_WIDTH{1'b0}};
            wr_burst_length  <= 8'd0;
            wr_burst_size    <= 3'd0;
            wr_burst_type    <= 2'd0;
            wr_id_latch      <= {ID_WIDTH{1'b0}};
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        write_addr      <= S_AXI_AWADDR;
                        wr_burst_length <= S_AXI_AWLEN;
                        wr_burst_size   <= S_AXI_AWSIZE;
                        wr_burst_type   <= S_AXI_AWBURST;
                        wr_id_latch     <= S_AXI_AWID;
                    end
                end
                default: ;
            endcase
        end
    end

    // Write Data Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_WREADY  <= 1'b0;
            wr_beat_count <= 8'd0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (S_AXI_AWVALID && S_AXI_AWREADY)
                        S_AXI_WREADY <= 1'b1;
                    else
                        S_AXI_WREADY <= 1'b0;
                    wr_beat_count <= 8'd0;
                end
                WR_BURST: begin
                    S_AXI_WREADY <= burst_wr_ready;
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        if (!S_AXI_WLAST)
                            wr_beat_count <= wr_beat_count + 1'b1;
                        else
                            wr_beat_count <= 8'd0;
                    end
                end
                default: begin
                    S_AXI_WREADY  <= 1'b0;
                    wr_beat_count <= 8'd0;
                end
            endcase
        end
    end

    // Write Response Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_BRESP  <= RESP_OKAY;
            S_AXI_BVALID <= 1'b0;
            S_AXI_BID    <= {ID_WIDTH{1'b0}};
        end else begin
            case (wr_state)
                WR_BURST: begin
                    if (S_AXI_WVALID && S_AXI_WREADY && S_AXI_WLAST) begin
                        S_AXI_BRESP  <= RESP_OKAY;
                        S_AXI_BVALID <= 1'b1;
                        S_AXI_BID    <= wr_id_latch;
                    end
                end
                WR_RESP: begin
                    if (S_AXI_BREADY && S_AXI_BVALID)
                        S_AXI_BVALID <= 1'b0;
                end
                default: S_AXI_BVALID <= 1'b0;
            endcase
        end
    end

always @(posedge clk) begin
    if (S_AXI_ARVALID && S_AXI_ARREADY)
        $display("[DMEM AXI] Read  burst: addr=0x%h len=%0d @ %0t",
                 S_AXI_ARADDR, S_AXI_ARLEN+1, $time);

    if (S_AXI_RVALID && S_AXI_RREADY)
        $display("[DMEM AXI] Read  data:  data=0x%h last=%b @ %0t",
                 S_AXI_RDATA, S_AXI_RLAST, $time);

    if (S_AXI_AWVALID && S_AXI_AWREADY)
        $display("[DMEM AXI] Write burst: addr=0x%h len=%0d @ %0t",
                 S_AXI_AWADDR, S_AXI_AWLEN+1, $time);

    if (S_AXI_WVALID && S_AXI_WREADY)
        $display("[DMEM AXI] Write data:  data=0x%h strb=%b last=%b @ %0t",
                 S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WLAST, $time);
end

endmodule