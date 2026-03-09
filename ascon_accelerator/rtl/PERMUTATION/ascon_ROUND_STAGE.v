// ============================================================
// Module: ascon_ROUND_STAGE
//
// One fully combinational Ascon round:
//   1. Constant Addition  — XOR round constant into x2
//   2. Substitution Layer — 64 parallel 5-bit S-boxes (reuses ASCON_SBOX)
//   3. Linear Diffusion   — rotation-based mixing per word
//
// No clock, no registers — purely combinational.
// Instantiate N times (via generate) to build a pipelined permutation.
//
// round_idx : absolute round index (0..11)
//   p12 → starts at 0
//   p8  → starts at 4
//   p6  → starts at 6
// ============================================================
`include "ascon_accelerator/rtl/PERMUTATION/ascon_SBOX.v"

module ascon_ROUND_STAGE (
    input  wire [319:0] state_in,
    input  wire [3:0]   round_idx,
    output wire [319:0] state_out
);

    // ---- Unpack state words ----
    wire [63:0] x0 = state_in[319:256];
    wire [63:0] x1 = state_in[255:192];
    wire [63:0] x2 = state_in[191:128];
    wire [63:0] x3 = state_in[127: 64];
    wire [63:0] x4 = state_in[ 63:  0];

    // ----------------------------------------------------------------
    // 1. Constant Addition
    //    round_constant = 0xF0 - round_idx * 0x0F
    // ----------------------------------------------------------------
    wire [7:0]  rc    = 8'hF0 - ({4'h0, round_idx} * 8'h0F);
    wire [63:0] x2_rc = x2 ^ {56'h0, rc};

    // ----------------------------------------------------------------
    // 2. Substitution Layer — 64 parallel ASCON_SBOX instances
    //    in_bits = { x4[i], x3[i], x2[i], x1[i], x0[i] }
    // ----------------------------------------------------------------
    wire [63:0] x0_s, x1_s, x2_s, x3_s, x4_s;

    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : sbox_array
            wire [4:0] sb_in  = {x4[i], x3[i], x2_rc[i], x1[i], x0[i]};
            wire [4:0] sb_out;

            ASCON_SBOX u_sbox (
                .in  (sb_in),
                .out (sb_out)
            );

            assign x0_s[i] = sb_out[0];
            assign x1_s[i] = sb_out[1];
            assign x2_s[i] = sb_out[2];
            assign x3_s[i] = sb_out[3];
            assign x4_s[i] = sb_out[4];
        end
    endgenerate

    // ----------------------------------------------------------------
    // 3. Linear Diffusion
    //    xi ^= ROR(xi, a) ^ ROR(xi, b)
    //    ROR(x, n) in Verilog: { x[n-1:0], x[63:n] }
    //
    //    x0: a=19, b=28
    //    x1: a=61, b=39
    //    x2: a= 1, b= 6
    //    x3: a=10, b=17
    //    x4: a= 7, b=41
    // ----------------------------------------------------------------
    wire [63:0] x0_d = x0_s ^ {x0_s[18: 0], x0_s[63:19]}
                             ^ {x0_s[27: 0], x0_s[63:28]};

    wire [63:0] x1_d = x1_s ^ {x1_s[60: 0], x1_s[63:61]}
                             ^ {x1_s[38: 0], x1_s[63:39]};

    wire [63:0] x2_d = x2_s ^ {x2_s[ 0],    x2_s[63: 1]}
                             ^ {x2_s[ 5: 0], x2_s[63: 6]};

    wire [63:0] x3_d = x3_s ^ {x3_s[ 9: 0], x3_s[63:10]}
                             ^ {x3_s[16: 0], x3_s[63:17]};

    wire [63:0] x4_d = x4_s ^ {x4_s[ 6: 0], x4_s[63: 7]}
                             ^ {x4_s[40: 0], x4_s[63:41]};

    // ---- Pack output ----
    assign state_out = {x0_d, x1_d, x2_d, x3_d, x4_d};

endmodule