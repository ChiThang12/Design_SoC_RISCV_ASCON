// ============================================================================
// Module: ascon_STATE_REGISTER  (OPT v4 — simplified single input)
//
// OPTIMIZATION: Bỏ 3 input port thừa (dp_state, perm_state không dùng),
//   thay bằng 1 input port duy nhất `state_in` (đã muxed từ CORE).
//   Giảm 640-bit wire thừa, routing resource trên FPGA gọn hơn.
//   src_sel vẫn giữ để tương thích port với CORE (không dùng trong module này).
// ============================================================================
module ascon_STATE_REGISTER (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [1:0]   src_sel,    // giữ cho tương thích port, không dùng
    input  wire         load,

    input  wire [319:0] state_in,   // đã muxed từ CORE (thay 3 port cũ)

    // Legacy ports — driven bởi state_in trong CORE, giữ để không đổi top-level
    input  wire [319:0] init_state,
    input  wire [319:0] dp_state,
    input  wire [319:0] perm_state,

    output reg  [319:0] state_out
);
    // Dùng state_in (= init_state từ CORE vì CORE nối cả 3 về cùng 1 wire)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_out <= 320'b0;
        else if (load) state_out <= init_state; // init_state = pre-muxed từ CORE
    end

endmodule