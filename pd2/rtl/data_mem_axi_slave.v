`timescale 1ns/1ps

// `include "memory/data_mem_burst.v"

module data_mem_axi4_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter MEM_SIZE   = 8192
)(
    input wire clk,
    input wire rst_n,

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [7:0]              S_AXI_AWLEN,
    input  wire [2:0]              S_AXI_AWSIZE,
    input  wire [1:0]              S_AXI_AWBURST,
    input  wire [2:0]              S_AXI_AWPROT,
    input  wire                    S_AXI_AWVALID,
    output wire                    S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WLAST,
    input  wire                    S_AXI_WVALID,
    output wire                    S_AXI_WREADY,   // combinational: wr_state == WR_BURST

    // Write Response Channel
    output reg  [ID_WIDTH-1:0]     S_AXI_BID,
    output reg  [1:0]              S_AXI_BRESP,
    output reg                     S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

    // Read Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [7:0]              S_AXI_ARLEN,
    input  wire [2:0]              S_AXI_ARSIZE,
    input  wire [1:0]              S_AXI_ARBURST,
    input  wire [2:0]              S_AXI_ARPROT,
    input  wire                    S_AXI_ARVALID,
    output wire                    S_AXI_ARREADY,

    // Read Data Channel
    output wire [ID_WIDTH-1:0]     S_AXI_RID,
    output wire [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,
    output wire                    S_AXI_RVALID,
    input  wire                    S_AXI_RREADY
);
    localparam [1:0] RESP_OKAY = 2'b00;

    // =========================================================================
    // Read State Machine
    // =========================================================================
    localparam [1:0] RD_IDLE  = 2'b00,
                     RD_BURST = 2'b01;
    reg [1:0] rd_state, rd_next;

    assign S_AXI_ARREADY = (rd_state == RD_IDLE);
    wire   ar_handshake  = S_AXI_ARVALID && S_AXI_ARREADY;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_state <= RD_IDLE;
        else        rd_state <= rd_next;
    end

    always @(*) begin
        rd_next = rd_state;
        case (rd_state)
            RD_IDLE:  if (ar_handshake)                                   rd_next = RD_BURST;
            RD_BURST: if (S_AXI_RVALID && S_AXI_RREADY && S_AXI_RLAST)  rd_next = RD_IDLE;
            default:  rd_next = RD_IDLE;
        endcase
    end

    reg [ADDR_WIDTH-1:0] read_addr;
    reg [ID_WIDTH-1:0]   rd_id_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_addr    <= {ADDR_WIDTH{1'b0}};
            rd_id_latch  <= {ID_WIDTH{1'b0}};
        end else if (ar_handshake) begin
            read_addr   <= S_AXI_ARADDR;
            rd_id_latch <= S_AXI_ARID;
        end
    end

    // burst_rd_req: combinational pulse → 1-cycle latency from AR handshake to RVALID
    wire burst_rd_req;
    assign burst_rd_req = ar_handshake;

    // burst_rd_addr: use S_AXI_ARADDR directly during handshake, registered otherwise
    wire [ADDR_WIDTH-1:0] burst_rd_addr;
    assign burst_rd_addr = ar_handshake ? S_AXI_ARADDR : read_addr;

    // =========================================================================
    // Write State Machine
    // =========================================================================
    localparam [2:0] WR_IDLE  = 3'b000,
                     WR_BURST = 3'b001,
                     WR_RESP  = 3'b010;
    reg [2:0] wr_state, wr_next;

    assign S_AXI_AWREADY = (wr_state == WR_IDLE);
    assign S_AXI_WREADY  = (wr_state == WR_BURST);  // combinational, no 1-cycle delay
    wire   aw_handshake  = S_AXI_AWVALID && S_AXI_AWREADY;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_state <= WR_IDLE;
        else        wr_state <= wr_next;
    end

    always @(*) begin
        wr_next = wr_state;
        case (wr_state)
            WR_IDLE:  if (aw_handshake)                       wr_next = WR_BURST;
            WR_BURST: if (S_AXI_WVALID && S_AXI_WLAST)       wr_next = WR_RESP;
            WR_RESP:  if (S_AXI_BREADY && S_AXI_BVALID)      wr_next = WR_IDLE;
            default:  wr_next = WR_IDLE;
        endcase
    end

    reg [ADDR_WIDTH-1:0] write_addr;
    reg [ID_WIDTH-1:0]   wr_id_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_addr  <= {ADDR_WIDTH{1'b0}};
            wr_id_latch <= {ID_WIDTH{1'b0}};
        end else if (aw_handshake) begin
            write_addr  <= S_AXI_AWADDR;
            wr_id_latch <= S_AXI_AWID;
        end
    end

    // burst_wr_valid: only when WREADY=1 (wr_state==WR_BURST), preventing W before AW
    wire burst_wr_valid = (wr_state == WR_BURST) && S_AXI_WVALID;

    // burst_wr_addr: use write_addr (registered AWADDR). Beat 0 uses write_addr directly;
    // data_mem_burst internally advances wr_current_addr for beats 1+.
    wire [ADDR_WIDTH-1:0] burst_wr_addr = write_addr;

    // Write Response
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

    // =========================================================================
    // Read outputs
    // =========================================================================
    wire [DATA_WIDTH-1:0] burst_rd_data;
    wire                  burst_rd_valid;
    wire                  burst_rd_last;

    assign S_AXI_RID    = rd_id_latch;
    assign S_AXI_RDATA  = burst_rd_data;
    assign S_AXI_RRESP  = RESP_OKAY;
    assign S_AXI_RLAST  = burst_rd_last;
    assign S_AXI_RVALID = burst_rd_valid;

    // =========================================================================
    // Data Memory Instance
    // =========================================================================
    data_mem_burst #(
        .MEM_SIZE  (MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dmem (
        .clk            (clk),
        .rst_n          (rst_n),
        .burst_rd_addr  (burst_rd_addr),
        .burst_rd_len   (S_AXI_ARLEN),
        .burst_rd_req   (burst_rd_req),
        .burst_rd_data  (burst_rd_data),
        .burst_rd_valid (burst_rd_valid),
        .burst_rd_last  (burst_rd_last),
        .burst_rd_ready (S_AXI_RREADY),
        .burst_wr_addr  (burst_wr_addr),
        .burst_wr_data  (S_AXI_WDATA),
        .burst_wr_strb  (S_AXI_WSTRB),
        .burst_wr_valid (burst_wr_valid),
        .burst_wr_ready (),   // always 1 inside data_mem_burst
        .burst_wr_last  (S_AXI_WLAST)
    );

endmodule
