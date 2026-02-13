module inst_mem #(
    parameter MEM_SIZE   = 4096,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,

    // Simple Interface
    input  wire [ADDR_WIDTH-1:0] PC,
    output wire [DATA_WIDTH-1:0] Instruction_Code,

    // Burst Read Interface
    input  wire [ADDR_WIDTH-1:0] burst_addr,
    input  wire [7:0]            burst_len,
    input  wire                  burst_req,
    output reg  [DATA_WIDTH-1:0] burst_data,
    output reg                   burst_valid,
    output reg                   burst_last,
    input  wire                  burst_ready
);

    // ========================================================================
    // 1. KHAI BÁO PARAMETER & BIẾN (Đặt trước khi sử dụng)
    // ========================================================================
    localparam BURST_IDLE   = 1'b0;
    localparam BURST_ACTIVE = 1'b1;

    reg  burst_state;
    reg  [ADDR_WIDTH-1:0] current_addr;
    reg  [7:0]            beat_count;
    reg  [7:0]            total_beats;

    wire [DATA_WIDTH-1:0] burst_data_wire; // Chỉ khai báo 1 lần duy nhất ở đây
    wire [9:0] addr_a = PC[11:2];
    wire [9:0] addr_b;
    wire [ADDR_WIDTH-1:0] next_addr;

    // Tín hiệu điều khiển macro (Dùng để sửa lỗi dòng 33 trong ảnh của bạn)
    wire burst_en_logic = (burst_req || burst_state == BURST_ACTIVE);

    // ========================================================================
    // 2. LOGIC COMBINATIONAL
    // ========================================================================
    assign addr_b    = (burst_state == BURST_IDLE) ? burst_addr[11:2] : next_addr[11:2];
    assign next_addr = current_addr + 4;

    // ========================================================================
    // 3. RAM MACRO INSTANCE
    // ========================================================================
    RM_IHPSG13_2P_1024x32_c2_bm_bist u_ram_macro (
        .A_CLK(clk), .A_ADDR(addr_a), .A_MEN(1'b1), .A_REN(1'b1), .A_WEN(1'b0),
        .A_DIN(32'h0), .A_DOUT(Instruction_Code), .A_BM(32'hFFFFFFFF), .A_DLY(1'b0),
        
        .B_CLK(clk), .B_ADDR(addr_b), .B_MEN(burst_en_logic), .B_REN(1'b1), .B_WEN(1'b0),
        .B_DIN(32'h0), .B_DOUT(burst_data_wire), .B_BM(32'hFFFFFFFF), .B_DLY(1'b0),

        // Các chân BIST nối đất/không dùng
        .A_BIST_EN(1'b0), .B_BIST_EN(1'b0), .A_BIST_CLK(1'b0), .B_BIST_CLK(1'b0),
        .A_BIST_ADDR(10'h0), .B_BIST_ADDR(10'h0), .A_BIST_REN(1'b0), .B_BIST_REN(1'b0),
        .A_BIST_WEN(1'b0), .B_BIST_WEN(1'b0), .A_BIST_DIN(32'h0), .B_BIST_DIN(32'h0),
        .A_BIST_MEN(1'b0), .B_BIST_MEN(1'b0), .A_BIST_BM(32'h0), .B_BIST_BM(32'h0)
    );

    // ========================================================================
    // 4. BURST FSM
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            burst_state  <= BURST_IDLE;
            burst_data   <= 32'd0;
            burst_valid  <= 1'b0;
            burst_last   <= 1'b0;
            current_addr <= 32'd0;
            beat_count   <= 8'd0;
            total_beats  <= 8'd0;
        end else begin
            case (burst_state)
                BURST_IDLE: begin
                    if (burst_req) begin
                        current_addr <= burst_addr;
                        beat_count   <= 8'd0;
                        total_beats  <= burst_len;
                        burst_state  <= BURST_ACTIVE;
                        burst_valid  <= 1'b1;
                        burst_last   <= (burst_len == 8'd0);
                        burst_data   <= burst_data_wire;
                    end else begin
                        burst_valid <= 1'b0;
                        burst_last  <= 1'b0;
                    end
                end
                BURST_ACTIVE: begin
                    if (burst_ready && burst_valid) begin
                        if (burst_last) begin
                            burst_state <= BURST_IDLE;
                            burst_valid <= 1'b0;
                            burst_last  <= 1'b0;
                        end else begin
                            beat_count   <= beat_count + 8'd1;
                            current_addr <= next_addr;
                            burst_data   <= burst_data_wire;
                            burst_valid  <= 1'b1;
                            burst_last   <= (beat_count + 8'd1 == total_beats);
                        end
                    end
                end
            endcase
        end
    end
endmodule


