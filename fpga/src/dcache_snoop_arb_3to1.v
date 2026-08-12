`timescale 1ns/1ps

module dcache_snoop_arb_3to1 #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [ADDR_WIDTH-1:0] req0_addr,
    input  wire [1:0]            req0_cmd,
    input  wire [1:0]            req0_mask,
    input  wire                  req0_valid,
    output wire                  req0_ready,
    output wire                  req0_resp_valid,
    output wire                  req0_resp_hit,
    output wire [DATA_WIDTH-1:0] req0_resp_data,

    input  wire [ADDR_WIDTH-1:0] req1_addr,
    input  wire [1:0]            req1_cmd,
    input  wire [1:0]            req1_mask,
    input  wire                  req1_valid,
    output wire                  req1_ready,
    output wire                  req1_resp_valid,
    output wire                  req1_resp_hit,
    output wire [DATA_WIDTH-1:0] req1_resp_data,

    input  wire [ADDR_WIDTH-1:0] req2_addr,
    input  wire [1:0]            req2_cmd,
    input  wire [1:0]            req2_mask,
    input  wire                  req2_valid,
    output wire                  req2_ready,
    output wire                  req2_resp_valid,
    output wire                  req2_resp_hit,
    output wire [DATA_WIDTH-1:0] req2_resp_data,

    output wire [ADDR_WIDTH-1:0] up_addr,
    output wire [1:0]            up_cmd,
    output wire [1:0]            up_mask,
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
    reg [1:0]  last_grant_r;

    reg  [1:0] grant_owner_w;
    reg        grant_valid_w;

    localparam [1:0]
        LAST_REQ2 = OWN_REQ2;

    always @(*) begin
        grant_owner_w = OWN_REQ0;
        grant_valid_w = 1'b0;

        case (last_grant_r)
            OWN_REQ0: begin
                if (req1_valid) begin
                    grant_owner_w = OWN_REQ1;
                    grant_valid_w = 1'b1;
                end else if (req2_valid) begin
                    grant_owner_w = OWN_REQ2;
                    grant_valid_w = 1'b1;
                end else if (req0_valid) begin
                    grant_owner_w = OWN_REQ0;
                    grant_valid_w = 1'b1;
                end
            end

            OWN_REQ1: begin
                if (req2_valid) begin
                    grant_owner_w = OWN_REQ2;
                    grant_valid_w = 1'b1;
                end else if (req0_valid) begin
                    grant_owner_w = OWN_REQ0;
                    grant_valid_w = 1'b1;
                end else if (req1_valid) begin
                    grant_owner_w = OWN_REQ1;
                    grant_valid_w = 1'b1;
                end
            end

            default: begin
                if (req0_valid) begin
                    grant_owner_w = OWN_REQ0;
                    grant_valid_w = 1'b1;
                end else if (req1_valid) begin
                    grant_owner_w = OWN_REQ1;
                    grant_valid_w = 1'b1;
                end else if (req2_valid) begin
                    grant_owner_w = OWN_REQ2;
                    grant_valid_w = 1'b1;
                end
            end
        endcase
    end

    assign up_valid = !wait_resp_r && grant_valid_w;
    assign up_addr  = (grant_owner_w == OWN_REQ0) ? req0_addr :
                      (grant_owner_w == OWN_REQ1) ? req1_addr : req2_addr;
    assign up_cmd   = (grant_owner_w == OWN_REQ0) ? req0_cmd  :
                      (grant_owner_w == OWN_REQ1) ? req1_cmd  : req2_cmd;
    assign up_mask  = (grant_owner_w == OWN_REQ0) ? req0_mask :
                      (grant_owner_w == OWN_REQ1) ? req1_mask : req2_mask;

    assign req0_ready = !wait_resp_r && grant_valid_w && (grant_owner_w == OWN_REQ0) && up_ready;
    assign req1_ready = !wait_resp_r && grant_valid_w && (grant_owner_w == OWN_REQ1) && up_ready;
    assign req2_ready = !wait_resp_r && grant_valid_w && (grant_owner_w == OWN_REQ2) && up_ready;

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
            last_grant_r <= LAST_REQ2;
        end else begin
            if (!wait_resp_r && up_valid && up_ready) begin
                wait_resp_r <= 1'b1;
                owner_r     <= grant_owner_w;
                last_grant_r <= grant_owner_w;
            end else if (wait_resp_r && up_resp_valid) begin
                wait_resp_r <= 1'b0;
            end
        end
    end

endmodule
