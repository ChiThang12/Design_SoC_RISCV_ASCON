`timescale 1ns/1ps

// ============================================================================
// Module: ASCON_SBOX_PIPELINED  (v1 — 2-stage pipeline S-box)
//
// Mô tả:
//   Thực hiện ASCON 5-bit S-box với tùy chọn pipeline register giữa
//   AND-layer (stage 1) và XOR-layer (stage 2).
//
//   G_SBOX_PIPELINE=1 (default):
//     Stage 1 (cycle N):   tính AND-layer → lưu t0_r..t4_r, x0_r..x4_r vào DFF
//     Stage 2 (cycle N+1): tính XOR-layer dùng giá trị đã register → output
//     Critical path: giảm ~50% (chỉ AND hoặc chỉ XOR mỗi half-cycle)
//     Latency: +1 cycle mỗi S-box call
//
//   G_SBOX_PIPELINE=0:
//     Combinational hoàn toàn (tương đương ASCON_SBOX gốc)
//     Không thêm DFF, không thêm latency
//
// Input/Output:
//   in[4:0]  = {x4[i], x3[i], x2[i], x1[i], x0[i]} tại bit position i
//   out[4:0] = {y4[i], y3[i], y2[i], y1[i], y0[i]}
//
// Lưu ý:
//   Module này thay thế ASCON_SBOX trong SUBSTITUTION_LAYER.
//   Khi G_SBOX_PIPELINE=1, SUBSTITUTION_LAYER thêm 1 cycle latency.
//   ascon_PERMUTATION phải tính vòng đầu ngay tại start_perm cycle,
//   nên 1 cycle overhead không ảnh hưởng throughput (đã xử lý trong
//   start_perm combinational path của PERMUTATION).
// ============================================================================
module ASCON_SBOX_PIPELINED #(
    parameter G_SBOX_PIPELINE = 1    // 1=pipeline, 0=combinational
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire       clk,    // reserved for pipelined variant (G_SBOX_PIPELINE=1)
    input  wire       rst_n,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [4:0] in,
    output reg  [4:0] out
);

    // ------------------------------------------------------------------
    // Stage 0: XOR preparation (combinational, shared cả 2 mode)
    // ------------------------------------------------------------------
    wire [4:0] x_prep;
    assign x_prep[0] = in[0] ^ in[4];   // x0 ^= x4
    assign x_prep[1] = in[1];           // x1 unchanged
    assign x_prep[2] = in[2] ^ in[1];   // x2 ^= x1
    assign x_prep[3] = in[3];           // x3 unchanged
    assign x_prep[4] = in[4] ^ in[3];   // x4 ^= x3

    // ------------------------------------------------------------------
    // AND layer (combinational từ x_prep)
    // t[i] = (~x_prep[i]) & x_prep[(i+1)%5]
    // ------------------------------------------------------------------
    wire [4:0] t_and;
    assign t_and[0] = (~x_prep[0]) & x_prep[1];
    assign t_and[1] = (~x_prep[1]) & x_prep[2];
    assign t_and[2] = (~x_prep[2]) & x_prep[3];
    assign t_and[3] = (~x_prep[3]) & x_prep[4];
    assign t_and[4] = (~x_prep[4]) & x_prep[0];

    generate
        if (G_SBOX_PIPELINE == 1) begin : gen_pipelined

            // ----------------------------------------------------------
            // Stage 1 register: lưu x_prep và t_and sau 1 cycle
            // ----------------------------------------------------------
            reg [4:0] x_prep_r;
            reg [4:0] t_and_r;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    x_prep_r <= 5'b0;
                    t_and_r  <= 5'b0;
                end else begin
                    x_prep_r <= x_prep;
                    t_and_r  <= t_and;
                end
            end

            // ----------------------------------------------------------
            // Stage 2: XOR layer (combinational, dùng registered values)
            // x[i] ^= t[(i+1)%5]
            // ----------------------------------------------------------
            wire [4:0] x_xor;
            assign x_xor[0] = x_prep_r[0] ^ t_and_r[1];
            assign x_xor[1] = x_prep_r[1] ^ t_and_r[2];
            assign x_xor[2] = x_prep_r[2] ^ t_and_r[3];
            assign x_xor[3] = x_prep_r[3] ^ t_and_r[4];
            assign x_xor[4] = x_prep_r[4] ^ t_and_r[0];

            // Final XOR adjustments (combinational)
            // x1 ^= x0; x0 ^= x4; x3 ^= x2; x2 = ~x2
            always @(*) begin
                out[1] = x_xor[1] ^ x_xor[0];   // x1 ^= x0
                out[0] = x_xor[0] ^ x_xor[4];   // x0 ^= x4
                out[3] = x_xor[3] ^ x_xor[2];   // x3 ^= x2
                out[2] = ~x_xor[2];              // x2 = ~x2
                out[4] = x_xor[4];               // x4 unchanged
            end

        end else begin : gen_combinational

            // ----------------------------------------------------------
            // Combinational path (không pipeline, G_SBOX_PIPELINE=0)
            // Tương đương ASCON_SBOX gốc
            // ----------------------------------------------------------
            wire [4:0] x_xor;
            assign x_xor[0] = x_prep[0] ^ t_and[1];
            assign x_xor[1] = x_prep[1] ^ t_and[2];
            assign x_xor[2] = x_prep[2] ^ t_and[3];
            assign x_xor[3] = x_prep[3] ^ t_and[4];
            assign x_xor[4] = x_prep[4] ^ t_and[0];

            always @(*) begin
                out[1] = x_xor[1] ^ x_xor[0];
                out[0] = x_xor[0] ^ x_xor[4];
                out[3] = x_xor[3] ^ x_xor[2];
                out[2] = ~x_xor[2];
                out[4] = x_xor[4];
            end

        end
    endgenerate

endmodule