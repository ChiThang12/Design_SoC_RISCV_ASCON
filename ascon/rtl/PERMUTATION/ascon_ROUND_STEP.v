// ============================================================================
// Module: ascon_ROUND_STEP  (v1 — purely combinational, 1 complete ASCON round)
//
// Mô tả:
//   Thực hiện ĐÚNG 1 vòng lặp ASCON hoàn chỉnh theo thứ tự chuẩn:
//     1. Constant Addition  : XOR round constant vào bit[7:0] của x2
//     2. Substitution Layer : Word-level bit-slice S-box (64-bit wide, 5 words)
//     3. Linear Diffusion   : Rotation XOR cho mỗi trong 5 words
//
//   Module THUẦN TỔ HỢP — không có flip-flop, không có clock/reset.
//   Được thiết kế để instantiate nhiều lần (k=2 trong G_UNROLL=2) tạo thành
//   chuỗi tổ hợp: step1 → mid_state → step2 → next_state.
//
// Interface:
//   state_in  [319:0] : ASCON state đầu vào  {x0,x1,x2,x3,x4} mỗi 64-bit
//   round_rc  [3:0]   : Absolute round index 0..11 để tính round constant
//   state_out [319:0] : ASCON state sau 1 vòng đầy đủ
//
// Slice layout [319:0]:
//   [319:256] = x0,  [255:192] = x1,  [191:128] = x2
//   [127: 64] = x3,  [ 63:  0] = x4
//
// Timing notes (cho synthesis / physical design):
//   Critical path trong 1 ROUND_STEP:
//     RC_ADD (1 XOR) → SBOX (prep XOR → AND → XOR → finalize) → LINEAR_DIFF (XOR+ROT)
//   Với G_UNROLL=2 và G_SBOX_PIPELINE=0: critical path = 2× ROUND_STEP xếp nối tiếp.
//   Với G_UNROLL=2 và G_SBOX_PIPELINE=1: pipeline register được đặt GIỮA step1
//   và step2 (trong ascon_PERMUTATION), cắt critical path còn 1× ROUND_STEP.
//
//   S-box ở đây được triển khai trực tiếp ở word level (64-bit bitwise AND/XOR)
//   thay vì 64 instance 5-bit. Cách này:
//     - Ít port wiring hơn → netlist sạch hơn cho PnR
//     - Synthesis có thể merge XOR trees xuyên qua S-box và Linear Diff
//     - Không tạo 64×3 module instance làm phồng hierarchy
//
// Constant formula (tương đương CONSTANT_ADDITION.v gốc):
//   round_constant[7:0] = 0xF0 - round_rc × 0x0F
//   Ví dụ: rc=0 → 0xF0, rc=1 → 0xE1, rc=2 → 0xD2, ..., rc=11 → 0x4B
//   (8-bit arithmetic để tránh truncation khi rc>1)
// ============================================================================

module ascon_ROUND_STEP (
    input  wire [319:0] state_in,
    input  wire [3:0]   round_rc,
    output wire [319:0] state_out
);

    // ------------------------------------------------------------------
    // Bước 1: Constant Addition
    //   8-bit arithmetic: rc_val = 8'hF0 - ({4'h0,round_rc} * 8'h0F)
    //   XOR vào 8 bit [7:0] của x2 (tức bits [135:128] của state)
    // ------------------------------------------------------------------
    wire [7:0]  rc_val = 8'hF0 - ({4'h0, round_rc} * 8'h0F);

    // Unpack x2, apply constant
    wire [63:0] x2_rc = state_in[191:128] ^ {56'h0, rc_val};

    // ------------------------------------------------------------------
    // Bước 2: Substitution Layer (ASCON 5-bit S-box, bit-slice 64-bit wide)
    //
    // Unpack state words:
    // ------------------------------------------------------------------
    wire [63:0] x0_in = state_in[319:256];
    wire [63:0] x1_in = state_in[255:192];
    wire [63:0] x2_in = x2_rc;
    wire [63:0] x3_in = state_in[127: 64];
    wire [63:0] x4_in = state_in[ 63:  0];

    // --- Phase 1: XOR preparation (bit-parallel trên toàn 64 bit) ---
    //   x0 ^= x4;  x2 ^= x1;  x4 ^= x3  (x1, x3 không đổi)
    wire [63:0] p0 = x0_in ^ x4_in;
    wire [63:0] p1 = x1_in;
    wire [63:0] p2 = x2_in ^ x1_in;
    wire [63:0] p3 = x3_in;
    wire [63:0] p4 = x4_in ^ x3_in;

    // --- Phase 2: AND layer ---
    //   t[i] = (~p[i]) & p[(i+1) mod 5]
    wire [63:0] t0 = (~p0) & p1;
    wire [63:0] t1 = (~p1) & p2;
    wire [63:0] t2 = (~p2) & p3;
    wire [63:0] t3 = (~p3) & p4;
    wire [63:0] t4 = (~p4) & p0;

    // --- Phase 3: XOR layer ---
    //   p[i] ^= t[(i+1) mod 5]
    wire [63:0] q0 = p0 ^ t1;
    wire [63:0] q1 = p1 ^ t2;
    wire [63:0] q2 = p2 ^ t3;
    wire [63:0] q3 = p3 ^ t4;
    wire [63:0] q4 = p4 ^ t0;

    // --- Phase 4: Finalize ---
    //   x0 ^= x4;  x1 ^= x0;  x3 ^= x2;  x2 = ~x2  (x4 không đổi)
    wire [63:0] s0 = q0 ^ q4;
    wire [63:0] s1 = q1 ^ q0;
    wire [63:0] s2 = ~q2;
    wire [63:0] s3 = q3 ^ q2;
    wire [63:0] s4 = q4;

    // ------------------------------------------------------------------
    // Bước 3: Linear Diffusion
    //   Mỗi word xi ^= ROR(xi, a) ^ ROR(xi, b) với (a,b) riêng mỗi word.
    //   ROR(x, n) được triển khai bằng wire concat: {x[n-1:0], x[63:n]}
    //   (chỉ routing wires, zero logic gates — synthesis friendly)
    //
    //   x0: (19, 28) → x0 ^= ROR(x0,19) ^ ROR(x0,28)
    //   x1: (61, 39) → x1 ^= ROR(x1,61) ^ ROR(x1,39)
    //   x2: ( 1,  6) → x2 ^= ROR(x2, 1) ^ ROR(x2, 6)
    //   x3: (10, 17) → x3 ^= ROR(x3,10) ^ ROR(x3,17)
    //   x4: ( 7, 41) → x4 ^= ROR(x4, 7) ^ ROR(x4,41)
    // ------------------------------------------------------------------
    wire [63:0] d0 = s0 ^ {s0[18:0], s0[63:19]} ^ {s0[27:0], s0[63:28]};
    wire [63:0] d1 = s1 ^ {s1[60:0], s1[63:61]} ^ {s1[38:0], s1[63:39]};
    wire [63:0] d2 = s2 ^ {s2[ 0],   s2[63: 1]} ^ {s2[ 5:0], s2[63: 6]};
    wire [63:0] d3 = s3 ^ {s3[ 9:0], s3[63:10]} ^ {s3[16:0], s3[63:17]};
    wire [63:0] d4 = s4 ^ {s4[ 6:0], s4[63: 7]} ^ {s4[40:0], s4[63:41]};

    // ------------------------------------------------------------------
    // Pack output
    // ------------------------------------------------------------------
    assign state_out = {d0, d1, d2, d3, d4};

endmodule