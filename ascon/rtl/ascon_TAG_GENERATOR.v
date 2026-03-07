// ============================================================================
// Module: ASCON_TAG_GENERATOR
// Mô tả: Tạo authentication tag từ final state
//
// ASCON-128 finalization:
//   state[191:64] ^= key          (x2 ^= key[127:64], x3 ^= key[63:0])
//   state = PERMUTATION(state, 12)
//   state[127:0] ^= key           (x3 ^= key[127:64], x4 ^= key[63:0])
//   tag = state[127:0]            (x3 || x4)
//
// Module này đọc state sau bước XOR key cuối cùng và xuất tag.
// Việc XOR key và permutation được điều khiển bởi CONTROLLER.
// Module này chỉ capture tag khi generate_tag=1.
// ============================================================================

module ASCON_TAG_GENERATOR (
    input  wire         clk,
    input  wire         rst_n,

    // State hiện tại (sau finalization)
    input  wire [319:0] state,

    // Control
    input  wire         generate_tag,  // pulse: capture tag từ state

    // Output
    output reg  [127:0] tag            // authentication tag = state[127:0]
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag <= 128'd0;
        end else if (generate_tag) begin
            // tag = x3 || x4 = state[127:0]
            tag <= state[127:0];
        end
    end

endmodule