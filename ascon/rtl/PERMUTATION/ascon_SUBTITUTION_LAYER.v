// ============================================================================
// Module 3.2: SUBSTITUTION_LAYER
// Mô tả: Áp dụng 5-bit S-box song song cho 64 vị trí bit
// S-box: Chi-nonlinear layer của ASCON
// ============================================================================
`include "ascon_SBOX.v"
module SUBSTITUTION_LAYER (
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

    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : sbox_array
            wire [4:0] in_bits;
            wire [4:0] out_bits;
            
            // Lấy 5 bits tại vị trí i từ mỗi word
            assign in_bits = {x0_in[i], x1_in[i], x2_in[i], x3_in[i], x4_in[i]};
            
            // Áp dụng S-box 5-bit
            ASCON_SBOX sbox (
                .in(in_bits),
                .out(out_bits)
            );
            
            // Gán kết quả trả về các word
            assign x0_out[i] = out_bits[4];
            assign x1_out[i] = out_bits[3];
            assign x2_out[i] = out_bits[2];
            assign x3_out[i] = out_bits[1];
            assign x4_out[i] = out_bits[0];
        end
    endgenerate

endmodule
