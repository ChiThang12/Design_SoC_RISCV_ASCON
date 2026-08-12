`timescale 1ns/1ps

module dcache_snoop_bus_2way #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [ADDR_WIDTH-1:0] up_snoop_addr,
    input  wire [1:0]            up_snoop_cmd,
    input  wire [1:0]            up_snoop_mask,
    input  wire                  up_snoop_req_valid,
    output wire                  up_snoop_req_ready,
    output reg                   up_snoop_resp_valid,
    output reg                   up_snoop_resp_hit,
    output reg  [DATA_WIDTH-1:0] up_snoop_resp_data,

    output wire [ADDR_WIDTH-1:0] dc0_snoop_addr,
    output wire [1:0]            dc0_snoop_cmd,
    output wire                  dc0_snoop_req_valid,
    input  wire                  dc0_snoop_req_ready,
    input  wire                  dc0_snoop_resp_valid,
    input  wire                  dc0_snoop_resp_hit,
    input  wire [DATA_WIDTH-1:0] dc0_snoop_resp_data,

    output wire [ADDR_WIDTH-1:0] dc1_snoop_addr,
    output wire [1:0]            dc1_snoop_cmd,
    output wire                  dc1_snoop_req_valid,
    input  wire                  dc1_snoop_req_ready,
    input  wire                  dc1_snoop_resp_valid,
    input  wire                  dc1_snoop_resp_hit,
    input  wire [DATA_WIDTH-1:0] dc1_snoop_resp_data
);

    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_REQ  = 2'd1,
        ST_RESP = 2'd2;

    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] snoop_addr_r;
    reg [1:0]            snoop_cmd_r;
    reg                  dc0_sent_r;
    reg                  dc1_sent_r;
    reg                  dc0_wait_resp_r;
    reg                  dc1_wait_resp_r;
    reg                  dc0_hit_r;
    reg                  dc1_hit_r;
    reg [DATA_WIDTH-1:0] dc0_data_r;
    reg [DATA_WIDTH-1:0] dc1_data_r;
    reg                  warn_collision_r;

    assign up_snoop_req_ready = (state == ST_IDLE);

    assign dc0_snoop_addr      = snoop_addr_r;
    assign dc0_snoop_cmd       = snoop_cmd_r;
    assign dc0_snoop_req_valid = (state == ST_REQ) && up_snoop_mask[0] && !dc0_sent_r;

    assign dc1_snoop_addr      = snoop_addr_r;
    assign dc1_snoop_cmd       = snoop_cmd_r;
    assign dc1_snoop_req_valid = (state == ST_REQ) && up_snoop_mask[1] && !dc1_sent_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            snoop_addr_r       <= {ADDR_WIDTH{1'b0}};
            snoop_cmd_r        <= 2'b00;
            dc0_sent_r         <= 1'b0;
            dc1_sent_r         <= 1'b0;
            dc0_wait_resp_r    <= 1'b0;
            dc1_wait_resp_r    <= 1'b0;
            dc0_hit_r          <= 1'b0;
            dc1_hit_r          <= 1'b0;
            dc0_data_r         <= {DATA_WIDTH{1'b0}};
            dc1_data_r         <= {DATA_WIDTH{1'b0}};
            warn_collision_r   <= 1'b0;
            up_snoop_resp_valid <= 1'b0;
            up_snoop_resp_hit   <= 1'b0;
            up_snoop_resp_data  <= {DATA_WIDTH{1'b0}};
        end else begin
            up_snoop_resp_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (up_snoop_req_valid) begin
                        snoop_addr_r    <= up_snoop_addr;
                        snoop_cmd_r     <= up_snoop_cmd;
                        dc0_sent_r      <= !up_snoop_mask[0];
                        dc1_sent_r      <= !up_snoop_mask[1];
                        dc0_wait_resp_r <= 1'b0;
                        dc1_wait_resp_r <= 1'b0;
                        dc0_hit_r       <= 1'b0;
                        dc1_hit_r       <= 1'b0;
                        dc0_data_r      <= {DATA_WIDTH{1'b0}};
                        dc1_data_r      <= {DATA_WIDTH{1'b0}};
                        warn_collision_r<= 1'b0;
                        state           <= ST_REQ;
                    end
                end

                ST_REQ: begin
                    if (dc0_wait_resp_r && dc0_snoop_resp_valid) begin
                        dc0_wait_resp_r <= 1'b0;
                        dc0_hit_r       <= dc0_snoop_resp_hit;
                        dc0_data_r      <= dc0_snoop_resp_data;
                    end

                    if (dc1_wait_resp_r && dc1_snoop_resp_valid) begin
                        dc1_wait_resp_r <= 1'b0;
                        dc1_hit_r       <= dc1_snoop_resp_hit;
                        dc1_data_r      <= dc1_snoop_resp_data;
                    end

                    if (!dc0_sent_r && dc0_snoop_req_ready) begin
                        dc0_sent_r      <= 1'b1;
                        dc0_wait_resp_r <= 1'b1;
                    end

                    if (!dc1_sent_r && dc1_snoop_req_ready) begin
                        dc1_sent_r      <= 1'b1;
                        dc1_wait_resp_r <= 1'b1;
                    end

                    if ((dc0_sent_r || dc0_snoop_req_ready) &&
                        (dc1_sent_r || dc1_snoop_req_ready)) begin
                        state <= ST_RESP;
                    end
                end

                ST_RESP: begin
                    if (dc0_wait_resp_r && dc0_snoop_resp_valid) begin
                        dc0_wait_resp_r <= 1'b0;
                        dc0_hit_r       <= dc0_snoop_resp_hit;
                        dc0_data_r      <= dc0_snoop_resp_data;
                    end

                    if (dc1_wait_resp_r && dc1_snoop_resp_valid) begin
                        dc1_wait_resp_r <= 1'b0;
                        dc1_hit_r       <= dc1_snoop_resp_hit;
                        dc1_data_r      <= dc1_snoop_resp_data;
                    end

                    if ((!dc0_wait_resp_r || dc0_snoop_resp_valid) &&
                        (!dc1_wait_resp_r || dc1_snoop_resp_valid)) begin
                        if ((dc0_wait_resp_r ? dc0_snoop_resp_hit : dc0_hit_r) &&
                            (dc1_wait_resp_r ? dc1_snoop_resp_hit : dc1_hit_r) &&
                            ((dc0_wait_resp_r ? dc0_snoop_resp_data : dc0_data_r) !=
                             (dc1_wait_resp_r ? dc1_snoop_resp_data : dc1_data_r)) &&
                            !warn_collision_r) begin
                            warn_collision_r <= 1'b1;
                            $display("[WARN] dcache_snoop_bus_2way: conflicting data returned by both caches for addr=%08x cmd=%0d",
                                     snoop_addr_r, snoop_cmd_r);
                        end
                        up_snoop_resp_valid <= 1'b1;
                        up_snoop_resp_hit   <= (dc0_wait_resp_r ? dc0_snoop_resp_hit : dc0_hit_r) |
                                               (dc1_wait_resp_r ? dc1_snoop_resp_hit : dc1_hit_r);
                        up_snoop_resp_data  <= (dc0_wait_resp_r ? dc0_snoop_resp_hit : dc0_hit_r) ?
                                               (dc0_wait_resp_r ? dc0_snoop_resp_data : dc0_data_r) :
                                               ((dc1_wait_resp_r ? dc1_snoop_resp_hit : dc1_hit_r) ?
                                                (dc1_wait_resp_r ? dc1_snoop_resp_data : dc1_data_r) :
                                                {DATA_WIDTH{1'b0}});
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
