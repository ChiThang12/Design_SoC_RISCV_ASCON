// ============================================================================
// ASCON_STATE_REGISTER Module
// Mô tả: Lưu trữ và quản lý state 320-bit của thuật toán ASCON
// ============================================================================

module ascon_STATE_REG (
    // Clock và Reset
    input  wire         clk,
    input  wire         rst_n,
    
    // Load trạng thái khởi tạo
    input  wire         load_init,
    input  wire [319:0] init_value,
    
    // Cập nhật từ permutation
    input  wire [319:0] permutation_out,
    input  wire         permutation_valid,
    
    // XOR dữ liệu
    input  wire [63:0]  xor_data,
    input  wire [2:0]   xor_position,
    input  wire         xor_enable,
    
    // Output state
    output reg  [319:0] state,
    output wire [63:0]  state_x0,
    output wire [63:0]  state_x1,
    output wire [63:0]  state_x2,
    output wire [63:0]  state_x3,
    output wire [63:0]  state_x4
);

    // ========================================================================
    // Tách state thành 5 words 64-bit
    // ========================================================================
    assign state_x0 = state[319:256];
    assign state_x1 = state[255:192];
    assign state_x2 = state[191:128];
    assign state_x3 = state[127:64];
    assign state_x4 = state[63:0];

    // ========================================================================
    // Logic cập nhật state theo ưu tiên
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 320'h0;
        end
        else begin
            // Ưu tiên 1: Load initial value
            if (load_init) begin
                state <= init_value;
            end
            // Ưu tiên 2: Cập nhật từ permutation
            else if (permutation_valid) begin
                state <= permutation_out;
            end
            // Ưu tiên 3: XOR dữ liệu vào word cụ thể
            else if (xor_enable) begin
                case (xor_position)
                    3'd0: state[319:256] <= state[319:256] ^ xor_data;
                    3'd1: state[255:192] <= state[255:192] ^ xor_data;
                    3'd2: state[191:128] <= state[191:128] ^ xor_data;
                    3'd3: state[127:64]  <= state[127:64]  ^ xor_data;
                    3'd4: state[63:0]    <= state[63:0]    ^ xor_data;
                    default: state <= state; // Giữ nguyên
                endcase
            end
            // Ưu tiên 4: Giữ nguyên state
            else begin
                state <= state;
            end
        end
    end

endmodule