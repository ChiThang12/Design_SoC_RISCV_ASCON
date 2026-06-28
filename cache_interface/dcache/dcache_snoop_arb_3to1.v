`timescale 1ns/1ps

module dcache_snoop_arb_3to1 #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [ADDR_WIDTH-1:0] req0_addr,
    input  wire [1:0]            req0_cmd,
    input  wire                  req0_valid,
    output wire                  req0_ready,
    output wire                  req0_resp_valid,
    output wire                  req0_resp_hit,
    output wire [DATA_WIDTH-1:0] req0_resp_data,

    input  wire [ADDR_WIDTH-1:0] req1_addr,
    input  wire [1:0]            req1_cmd,
    input  wire                  req1_valid,
    output wire                  req1_ready,
    output wire                  req1_resp_valid,
    output wire                  req1_resp_hit,
    output wire [DATA_WIDTH-1:0] req1_resp_data,

    input  wire [ADDR_WIDTH-1:0] req2_addr,
    input  wire [1:0]            req2_cmd,
    input  wire                  req2_valid,
    output wire                  req2_ready,
    output wire                  req2_resp_valid,
    output wire                  req2_resp_hit,
    output wire [DATA_WIDTH-1:0] req2_resp_data,

    output wire [ADDR_WIDTH-1:0] up_addr,
    output wire [1:0]            up_cmd,
    output wire                  up_valid,
    input  wire                  up_ready,
    input  wire                  up_resp_valid,
    input  wire                  up_resp_hit,
    input  wire [DATA_WIDTH-1:0] up_resp_data
);

    localparam [1:0]
        OWN_REQ0 = 2'd0,
        OWN_REQ1 = 2'd1,
        OWN_REQ2 = 2'd2;

    reg        wait_resp_r;
    reg [1:0]  owner_r;

    wire pick0 = req0_valid;
    wire pick1 = !req0_valid && req1_valid;
    wire pick2 = !req0_valid && !req1_valid && req2_valid;

    assign up_valid = !wait_resp_r && (pick0 || pick1 || pick2);
    assign up_addr  = pick0 ? req0_addr :
                      pick1 ? req1_addr : req2_addr;
    assign up_cmd   = pick0 ? req0_cmd  :
                      pick1 ? req1_cmd  : req2_cmd;

    assign req0_ready = !wait_resp_r && pick0 && up_ready;
    assign req1_ready = !wait_resp_r && pick1 && up_ready;
    assign req2_ready = !wait_resp_r && pick2 && up_ready;

    assign req0_resp_valid = wait_resp_r && (owner_r == OWN_REQ0) && up_resp_valid;
    assign req1_resp_valid = wait_resp_r && (owner_r == OWN_REQ1) && up_resp_valid;
    assign req2_resp_valid = wait_resp_r && (owner_r == OWN_REQ2) && up_resp_valid;

    assign req0_resp_hit  = up_resp_hit;
    assign req1_resp_hit  = up_resp_hit;
    assign req2_resp_hit  = up_resp_hit;
    assign req0_resp_data = up_resp_data;
    assign req1_resp_data = up_resp_data;
    assign req2_resp_data = up_resp_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wait_resp_r <= 1'b0;
            owner_r     <= OWN_REQ0;
        end else begin
            if (!wait_resp_r && up_valid && up_ready) begin
                wait_resp_r <= 1'b1;
                if (pick1)
                    owner_r <= OWN_REQ1;
                else if (pick2)
                    owner_r <= OWN_REQ2;
                else
                    owner_r <= OWN_REQ0;
            end else if (wait_resp_r && up_resp_valid) begin
                wait_resp_r <= 1'b0;
            end
        end
    end

endmodule
