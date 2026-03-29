// ============================================================================
// Module: SUBSTITUTION_LAYER_PIPELINED  (v1)
//
// Mô tả:
//   Áp dụng ASCON_SBOX_PIPELINED song song cho 64 vị trí bit.
//   Truyền tham số G_SBOX_PIPELINE xuống từng S-box instance.
//
//   G_SBOX_PIPELINE=1: thêm 1 cycle latency (stage 1 register)
//   G_SBOX_PIPELINE=0: combinational (tương đương SUBSTITUTION_LAYER gốc)
//
// Thay thế SUBSTITUTION_LAYER trong ascon_PERMUTATION.
// ============================================================================

module SUBSTITUTION_LAYER_PIPELINED #(
    parameter G_SBOX_PIPELINE = 1
) (
    input  wire       clk,
    input  wire       rst_n,

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

            // Bit-slice: lấy bit i từ mỗi word, xếp thành vector 5-bit
            assign in_bits = {x4_in[i], x3_in[i], x2_in[i], x1_in[i], x0_in[i]};

            ASCON_SBOX_PIPELINED #(
                .G_SBOX_PIPELINE(G_SBOX_PIPELINE)
            ) sbox (
                .clk  (clk),
                .rst_n(rst_n),
                .in   (in_bits),
                .out  (out_bits)
            );

            // Gán kết quả trở lại các word output
            assign x0_out[i] = out_bits[0];
            assign x1_out[i] = out_bits[1];
            assign x2_out[i] = out_bits[2];
            assign x3_out[i] = out_bits[3];
            assign x4_out[i] = out_bits[4];
        end
    endgenerate

endmodule