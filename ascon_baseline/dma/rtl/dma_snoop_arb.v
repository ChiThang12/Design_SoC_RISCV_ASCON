`timescale 1ns/1ps

module dma_snoop_arb #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH = 64
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        dma_soft_rst,

    input  wire                        rd_req_valid,
    input  wire [1:0]                  rd_req_cmd,
    input  wire [ADDR_WIDTH-1:0]       rd_req_addr,
    output wire                        rd_req_ready,
    output wire                        rd_resp_valid,
    output wire                        rd_resp_hit,
    output wire [AXI_DATA_WIDTH-1:0]   rd_resp_data,

    input  wire                        wr_req_valid,
    input  wire [1:0]                  wr_req_cmd,
    input  wire [ADDR_WIDTH-1:0]       wr_req_addr,
    output wire                        wr_req_ready,
    output wire                        wr_resp_valid,
    output wire                        wr_resp_hit,
    output wire [AXI_DATA_WIDTH-1:0]   wr_resp_data,

    output wire [ADDR_WIDTH-1:0]       DC_SNOOP_ADDR,
    output wire [1:0]                  DC_SNOOP_CMD,
    output wire                        DC_SNOOP_REQ_VALID,
    input  wire                        DC_SNOOP_REQ_READY,
    input  wire                        DC_SNOOP_RESP_VALID,
    input  wire                        DC_SNOOP_RESP_HIT,
    input  wire [AXI_DATA_WIDTH-1:0]   DC_SNOOP_RESP_DATA
);

    wire pick_rd = rd_req_valid;
    wire pick_wr = !rd_req_valid && wr_req_valid;

    reg  wait_resp;
    reg  owner_wr;

    assign DC_SNOOP_REQ_VALID = !wait_resp && (pick_rd || pick_wr);
    assign DC_SNOOP_CMD       = pick_rd ? rd_req_cmd : wr_req_cmd;
    assign DC_SNOOP_ADDR      = pick_rd ? rd_req_addr : wr_req_addr;

    assign rd_req_ready = !wait_resp && pick_rd && DC_SNOOP_REQ_READY;
    assign wr_req_ready = !wait_resp && pick_wr && DC_SNOOP_REQ_READY;
    assign rd_resp_valid = wait_resp && !owner_wr && DC_SNOOP_RESP_VALID;
    assign wr_resp_valid = wait_resp &&  owner_wr && DC_SNOOP_RESP_VALID;
    assign rd_resp_hit   = DC_SNOOP_RESP_HIT;
    assign wr_resp_hit   = DC_SNOOP_RESP_HIT;
    assign rd_resp_data  = DC_SNOOP_RESP_DATA;
    assign wr_resp_data  = DC_SNOOP_RESP_DATA;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wait_resp <= 1'b0;
            owner_wr  <= 1'b0;
        end else if (dma_soft_rst) begin
            wait_resp <= 1'b0;
            owner_wr  <= 1'b0;
        end else begin
            if (!wait_resp && DC_SNOOP_REQ_VALID && DC_SNOOP_REQ_READY) begin
                wait_resp <= 1'b1;
                owner_wr  <= pick_wr;
            end else if (wait_resp && DC_SNOOP_RESP_VALID) begin
                wait_resp <= 1'b0;
            end
        end
    end

endmodule
