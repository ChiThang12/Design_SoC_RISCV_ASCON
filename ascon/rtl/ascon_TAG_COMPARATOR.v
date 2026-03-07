// ============================================================================
// Module: ASCON_TAG_COMPARATOR
// Mô tả: So sánh generated tag với received tag khi decrypt
//
// Constant-time comparison (tránh timing attack):
//   Tính XOR giữa hai tag, kết quả 0 → match
// ============================================================================

module ASCON_TAG_COMPARATOR (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [127:0] generated_tag,   // từ TAG_GENERATOR
    input  wire [127:0] received_tag,    // tag nhận từ bên ngoài

    // Control
    input  wire         compare_enable,  // pulse: thực hiện so sánh

    // Outputs
    output reg          tag_match,       // 1 = tag hợp lệ
    output reg          tag_valid        // pulse: kết quả hợp lệ
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_match <= 1'b0;
            tag_valid <= 1'b0;
        end else begin
            tag_valid <= 1'b0;

            if (compare_enable) begin
                // Constant-time: check all 128 bits đồng thời
                tag_match <= (generated_tag == received_tag) ? 1'b1 : 1'b0;
                tag_valid <= 1'b1;
            end
        end
    end

endmodule