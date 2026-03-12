// ============================================================================
// Module: ASCON_PERMUTATION  (OPT v3-FIX — Loop Unrolling u=2, bypass state_reg)
//
// FIX cho Pre-Perm Merging race condition:
//   Vấn đề: khi state_load và perm_start xảy ra cùng cycle,
//     state_reg chưa update kịp → permutation đọc giá trị cũ.
//
//   Giải pháp: thêm input `state_bypass` và `use_bypass`.
//     Khi start_perm=1 đồng thời với state_load=1 (từ CORE):
//       CORE truyền state_next_final trực tiếp qua state_bypass
//       perm latch state_bypass thay vì state_in (= state_reg_out cũ)
//     Khi start_perm=1 độc lập (không cùng với state_load):
//       use_bypass=0, perm latch state_in như bình thường
//
// OPTIMIZATION: 2 rounds/cycle (u=2)
//   Init/Final (12 rounds): 12 cycles → 6 cycles  (-50%)
//   AD/PT      ( 8 rounds):  8 cycles → 4 cycles  (-50%)
//
// Bug fixes từ v2 vẫn giữ:
//   FIX1: round_counter = 12 - rounds (absolute start index)
//   FIX2: rounds_reg snapshot 'rounds' tại start_perm
// ============================================================================

`include "ascon/rtl/PERMUTATION/ascon_CONSTANT_ADDITION.v"
`include "ascon/rtl/PERMUTATION/ascon_SUBTITUTION_LAYER.v"
`include "ascon/rtl/PERMUTATION/ascon_LINEAR_DIFFUSION.v"

module ascon_PERMUTATION (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [319:0] state_in,       // từ state_reg_out (giá trị đã latch)
    input  wire [319:0] state_bypass,   // NEW: state_next_final trực tiếp từ CORE mux
    input  wire         use_bypass,     // NEW: 1 = dùng state_bypass khi start_perm
    input  wire [3:0]   rounds,
    input  wire         start_perm,
    input  wire         mode,

    output reg  [319:0] state_out,
    output reg          valid,
    output reg          done
);

    reg [319:0] current_state;
    reg [3:0]   round_counter;
    reg [3:0]   rounds_reg;
    reg [3:0]   rounds_done;
    reg         running;

    // ---- ROUND 1 ----
    wire [63:0] r1_x0 = current_state[319:256];
    wire [63:0] r1_x1 = current_state[255:192];
    wire [63:0] r1_x2 = current_state[191:128];
    wire [63:0] r1_x3 = current_state[127: 64];
    wire [63:0] r1_x4 = current_state[ 63:  0];

    wire [63:0] r1_x2c, r1_s0, r1_s1, r1_s2, r1_s3, r1_s4;
    wire [63:0] r1_d0, r1_d1, r1_d2, r1_d3, r1_d4;

    CONSTANT_ADDITION ca_r1 (
        .state_x2(r1_x2), .round_number(round_counter),
        .state_x2_modified(r1_x2c)
    );
    SUBSTITUTION_LAYER sl_r1 (
        .x0_in(r1_x0), .x1_in(r1_x1), .x2_in(r1_x2c), .x3_in(r1_x3), .x4_in(r1_x4),
        .x0_out(r1_s0), .x1_out(r1_s1), .x2_out(r1_s2), .x3_out(r1_s3), .x4_out(r1_s4)
    );
    LINEAR_DIFFUSION ld_r1 (
        .x0_in(r1_s0), .x1_in(r1_s1), .x2_in(r1_s2), .x3_in(r1_s3), .x4_in(r1_s4),
        .x0_out(r1_d0), .x1_out(r1_d1), .x2_out(r1_d2), .x3_out(r1_d3), .x4_out(r1_d4)
    );

    // ---- ROUND 2 ----
    wire [63:0] r2_x2c, r2_s0, r2_s1, r2_s2, r2_s3, r2_s4;
    wire [63:0] r2_d0, r2_d1, r2_d2, r2_d3, r2_d4;

    CONSTANT_ADDITION ca_r2 (
        .state_x2(r1_d2), .round_number(round_counter + 4'd1),
        .state_x2_modified(r2_x2c)
    );
    SUBSTITUTION_LAYER sl_r2 (
        .x0_in(r1_d0), .x1_in(r1_d1), .x2_in(r2_x2c), .x3_in(r1_d3), .x4_in(r1_d4),
        .x0_out(r2_s0), .x1_out(r2_s1), .x2_out(r2_s2), .x3_out(r2_s3), .x4_out(r2_s4)
    );
    LINEAR_DIFFUSION ld_r2 (
        .x0_in(r2_s0), .x1_in(r2_s1), .x2_in(r2_s2), .x3_in(r2_s3), .x4_in(r2_s4),
        .x0_out(r2_d0), .x1_out(r2_d1), .x2_out(r2_d2), .x3_out(r2_d3), .x4_out(r2_d4)
    );

    wire [319:0] next2 = {r2_d0, r2_d1, r2_d2, r2_d3, r2_d4};

    // ---------------------------------------------------------------
    // Start-cycle combinational pipeline (round 1-2 từ start state)
    // Mục tiêu: loại bỏ 1 cycle lãng phí khi start_perm chỉ latch state
    // Sau fix: PERM12 = 6 cycles, PERM8 = 4 cycles
    // ---------------------------------------------------------------
    wire [319:0] start_state_mux = use_bypass ? state_bypass : state_in;
    wire [3:0]   start_rc        = 4'd12 - rounds;

    wire [63:0] rs1_x0 = start_state_mux[319:256];
    wire [63:0] rs1_x1 = start_state_mux[255:192];
    wire [63:0] rs1_x2 = start_state_mux[191:128];
    wire [63:0] rs1_x3 = start_state_mux[127: 64];
    wire [63:0] rs1_x4 = start_state_mux[ 63:  0];

    wire [63:0] rs1_x2c, rs1_s0, rs1_s1, rs1_s2, rs1_s3, rs1_s4;
    wire [63:0] rs1_d0,  rs1_d1,  rs1_d2,  rs1_d3,  rs1_d4;
    wire [63:0] rs2_x2c, rs2_s0, rs2_s1, rs2_s2, rs2_s3, rs2_s4;
    wire [63:0] rs2_d0,  rs2_d1,  rs2_d2,  rs2_d3,  rs2_d4;

    CONSTANT_ADDITION  ca_rs1 (.state_x2(rs1_x2),  .round_number(start_rc),
                                .state_x2_modified(rs1_x2c));
    SUBSTITUTION_LAYER sl_rs1 (.x0_in(rs1_x0), .x1_in(rs1_x1), .x2_in(rs1_x2c),
                                .x3_in(rs1_x3), .x4_in(rs1_x4),
                                .x0_out(rs1_s0), .x1_out(rs1_s1), .x2_out(rs1_s2),
                                .x3_out(rs1_s3), .x4_out(rs1_s4));
    LINEAR_DIFFUSION   ld_rs1 (.x0_in(rs1_s0), .x1_in(rs1_s1), .x2_in(rs1_s2),
                                .x3_in(rs1_s3), .x4_in(rs1_s4),
                                .x0_out(rs1_d0), .x1_out(rs1_d1), .x2_out(rs1_d2),
                                .x3_out(rs1_d3), .x4_out(rs1_d4));

    CONSTANT_ADDITION  ca_rs2 (.state_x2(rs1_d2),  .round_number(start_rc + 4'd1),
                                .state_x2_modified(rs2_x2c));
    SUBSTITUTION_LAYER sl_rs2 (.x0_in(rs1_d0), .x1_in(rs1_d1), .x2_in(rs2_x2c),
                                .x3_in(rs1_d3), .x4_in(rs1_d4),
                                .x0_out(rs2_s0), .x1_out(rs2_s1), .x2_out(rs2_s2),
                                .x3_out(rs2_s3), .x4_out(rs2_s4));
    LINEAR_DIFFUSION   ld_rs2 (.x0_in(rs2_s0), .x1_in(rs2_s1), .x2_in(rs2_s2),
                                .x3_in(rs2_s3), .x4_in(rs2_s4),
                                .x0_out(rs2_d0), .x1_out(rs2_d1), .x2_out(rs2_d2),
                                .x3_out(rs2_d3), .x4_out(rs2_d4));

    wire [319:0] next2_start = {rs2_d0, rs2_d1, rs2_d2, rs2_d3, rs2_d4};

    // ---- Control (FIXED) ----
    // start_perm cycle: chạy round 1-2 ngay, không waste cycle latch
    //   PERM12: 6 cycles  (was 8)
    //   PERM8:  4 cycles  (was 6)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= 320'h0;
            round_counter <= 4'h0;
            rounds_reg    <= 4'h0;
            rounds_done   <= 4'h0;
            running       <= 1'b0;
            state_out     <= 320'h0;
            valid         <= 1'b0;
            done          <= 1'b0;
        end else begin
            valid <= 1'b0;
            done  <= 1'b0;

            if (start_perm && !running) begin
                // Latch kết quả round 1-2 ngay trong cycle start_perm
                current_state <= next2_start;
                round_counter <= start_rc + 4'd2;
                rounds_reg    <= rounds;
                rounds_done   <= 4'd2;

                if (4'd2 >= rounds) begin
                    // Xong ngay (rounds=2, không dùng trong ASCON thực tế)
                    state_out <= next2_start;
                    valid     <= 1'b1;
                    done      <= 1'b1;
                    running   <= 1'b0;
                end else begin
                    running <= 1'b1;
                end
            end
            else if (running) begin
                current_state <= next2;
                round_counter <= round_counter + 4'd2;
                rounds_done   <= rounds_done   + 4'd2;

                if (rounds_done + 4'd2 >= rounds_reg) begin
                    state_out <= next2;
                    valid     <= 1'b1;
                    done      <= 1'b1;
                    running   <= 1'b0;
                end
            end
        end
    end

endmodule