// ============================================================================
// Module 3.3: LINEAR_DIFFUSION
// Mô tả: Linear diffusion layer với rotation cụ thể cho mỗi word
// ============================================================================

module LINEAR_DIFFUSION (
    input  wire [63:0] x0_in,
    input  wire [63:0] x1_in,
    input  wire [63:0] x2_in,
    input  wire [63:0] x3_in,
    input  wire [63:0] x4_in,
    
    output wire [63:0] x0_out,
    output wire [63:0] x1_out,
    output wire [63:0] x2_out,
    output wire [63:0] x3_out,
    output wire [63:0] x4_out
);

    // Function for right rotation
    function [63:0] ROR;
        input [63:0] value;
        input integer n;
        begin
            ROR = (value >> n) | (value << (64 - n));
        end
    endfunction

    // x0 ^= ROR(x0, 19) ^ ROR(x0, 28)
    assign x0_out = x0_in ^ ROR(x0_in, 19) ^ ROR(x0_in, 28);
    
    // x1 ^= ROR(x1, 61) ^ ROR(x1, 39)
    assign x1_out = x1_in ^ ROR(x1_in, 61) ^ ROR(x1_in, 39);
    
    // x2 ^= ROR(x2, 1) ^ ROR(x2, 6)
    assign x2_out = x2_in ^ ROR(x2_in, 1) ^ ROR(x2_in, 6);
    
    // x3 ^= ROR(x3, 10) ^ ROR(x3, 17)
    assign x3_out = x3_in ^ ROR(x3_in, 10) ^ ROR(x3_in, 17);
    
    // x4 ^= ROR(x4, 7) ^ ROR(x4, 41)
    assign x4_out = x4_in ^ ROR(x4_in, 7) ^ ROR(x4_in, 41);

endmodule