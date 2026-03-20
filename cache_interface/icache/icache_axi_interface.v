`include "cache_interface/icache/icache_defines.vh"

// ============================================================================
// icache_axi_interface — ARLEN=7 (8 beats = 8 words = 1 cache line)
// Thêm AXI4 ID signals để kết nối vào axi4_crossbar
// ============================================================================
module icache_axi_interface #(
    parameter ID_WIDTH = 4
)(
    input wire clk,
    input wire rst_n,

    input wire [31:0]  refill_addr,
    input wire         refill_start,
    output reg         refill_busy,
    output reg         refill_done,

    output reg [31:0]  refill_data,
    output reg [2:0]   refill_word,       // 3 bit: 0-7
    output reg         refill_data_valid,

    output wire [ID_WIDTH-1:0] M_AXI_ARID,
    output wire [31:0]         M_AXI_ARADDR,
    output wire [7:0]          M_AXI_ARLEN,
    output wire [2:0]          M_AXI_ARSIZE,
    output wire [1:0]          M_AXI_ARBURST,
    output wire [2:0]          M_AXI_ARPROT,
    output wire                M_AXI_ARVALID,
    input  wire                M_AXI_ARREADY,

    input  wire [ID_WIDTH-1:0] M_AXI_RID,
    input  wire [31:0]         M_AXI_RDATA,
    input  wire [1:0]          M_AXI_RRESP,
    input  wire                M_AXI_RLAST,
    input  wire                M_AXI_RVALID,
    output wire                M_AXI_RREADY
);
    // ICache luôn dùng ARID = 0 (master 0, ID cố định)
    assign M_AXI_ARID    = {ID_WIDTH{1'b0}};
    assign M_AXI_ARLEN   = 8'd7;
    assign M_AXI_ARSIZE  = 3'b010; // 4 bytes
    assign M_AXI_ARBURST = 2'b01;  // INCR
    assign M_AXI_ARPROT  = 3'b000;

    localparam IDLE = 1'b0;
    localparam R    = 1'b1;

    reg       state;
    reg [2:0] word_counter;

    assign M_AXI_RREADY  = (state == R);
    assign M_AXI_ARVALID = (state == IDLE) && refill_start;
    assign M_AXI_ARADDR  = refill_addr;

    wire ar_handshake = M_AXI_ARVALID && M_AXI_ARREADY;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= IDLE;
            refill_busy       <= 1'b0;
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;
            refill_data       <= 32'h0;
            refill_word       <= 3'h0;
            word_counter      <= 3'h0;
        end else begin
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;

            case (state)
                IDLE: begin
                    word_counter <= 3'h0;
                    if (ar_handshake) begin
                        refill_busy <= 1'b1;
                        state       <= R;
                    end
                end

                R: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        refill_data       <= M_AXI_RDATA;
                        refill_word       <= word_counter;
                        refill_data_valid <= 1'b1;
                        word_counter      <= word_counter + 1;

                        if (M_AXI_RLAST) begin
                            refill_done <= 1'b1;
                            refill_busy <= 1'b0;
                            state       <= IDLE;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule