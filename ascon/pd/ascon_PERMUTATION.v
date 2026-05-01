`timescale 1ns/1ps

// ============================================================================
// Module: ascon_PERMUTATION  (v8 — correct FSM, G_SBOX_PIPELINE=0 default)
//
// ROOT CAUSE của tất cả các phiên bản trước:
//   G_SBOX_PIPELINE=1 KHÔNG tương thích với FSM hiện tại.
//   Vấn đề: S-box pipeline yêu cầu input STABLE 2 cycle liên tiếp:
//     Cycle N:   present input X → DFF latch AND(X)
//     Cycle N+1: DFF output = AND(X) → sbox(X) valid
//   Nhưng FSM thay đổi rnd_in mỗi cycle (vì `running` là registered signal,
//   lệch pha 1 cycle so với khi được set), nên:
//     - Cycle 0 (start): rnd_in = start_st → DFF latch AND(start_st)
//     - Cycle 1 (stall): running=0 → rnd_in = start_st LẠI (không phải r0_output!)
//       → DFF latch AND(start_st) LẦN 2 → r1 nhận sai input
//   Kết quả: tất cả rounds từ r1 trở đi đều sai.
//
// FIX: Dùng G_SBOX_PIPELINE=0 (combinational S-box, không DFF).
//   - 1 cycle/round, đơn giản, đúng 100%
//   - Với G=6 rounds/call: 6 cycles/call
//   - ASCON-128 INIT: 2 calls × 6 cycles = 12 cycles
//   - ASCON-128 AD/PT: 1 call × 6 cycles = 6 cycles
//
// NOTE: G_SBOX_PIPELINE=1 có thể implement đúng bằng cách thêm state
// PRESENT/WAIT riêng biệt, nhưng để đảm bảo correctness trước, dùng =0.
// ============================================================================

`include "ascon/rtl/PERMUTATION/ascon_CONSTANT_ADDITION.v"
`include "ascon/rtl/PERMUTATION/ascon_SUBTITUTION_LAYER.v"
`include "ascon/rtl/PERMUTATION/ascon_LINEAR_DIFFUSION.v"

module ascon_PERMUTATION #(
    parameter G_SBOX_PIPELINE = 0    // FIX: default 0 (combinational, correct)
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [319:0] state_in,
    input  wire [319:0] state_bypass,
    input  wire         use_bypass,
    input  wire [3:0]   rounds,
    input  wire [3:0]   start_rc,
    input  wire         start_perm,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         mode,  // reserved for future variant selection
    /* verilator lint_on UNUSEDSIGNAL */

    output reg  [319:0] state_out,
    output reg          valid,
    output reg          done
);

    reg [319:0] cur;
    reg [3:0]   rc;
    reg [3:0]   rounds_reg;
    reg [3:0]   done_cnt;
    reg         running;

    wire [319:0] start_st = use_bypass ? state_bypass : state_in;

    // ---- Round input mux ----
    // running=1: use cur (updated state)
    // running=0: use start_st (initial state at start_perm)
    wire [319:0] rnd_in = running ? cur : start_st;
    wire [3:0]   rnd_rc = running ? rc  : start_rc;

    // ---- Constant addition ----
    wire [63:0] x2_c;
    CONSTANT_ADDITION ca (
        .state_x2(rnd_in[191:128]),
        .round_number(rnd_rc),
        .state_x2_modified(x2_c)
    );

    // ---- Substitution layer (u=1, G_SBOX_PIPELINE=0 → combinational) ----
    wire [63:0] s0, s1, s2, s3, s4;
    SUBSTITUTION_LAYER_PIPELINED #(.G_SBOX_PIPELINE(G_SBOX_PIPELINE)) sl (
        .clk(clk), .rst_n(rst_n),
        .x0_in(rnd_in[319:256]),
        .x1_in(rnd_in[255:192]),
        .x2_in(x2_c),
        .x3_in(rnd_in[127: 64]),
        .x4_in(rnd_in[ 63:  0]),
        .x0_out(s0), .x1_out(s1), .x2_out(s2), .x3_out(s3), .x4_out(s4)
    );

    // ---- Linear diffusion ----
    wire [63:0] d0, d1, d2, d3, d4;
    LINEAR_DIFFUSION ld (
        .x0_in(s0), .x1_in(s1), .x2_in(s2), .x3_in(s3), .x4_in(s4),
        .x0_out(d0), .x1_out(d1), .x2_out(d2), .x3_out(d3), .x4_out(d4)
    );

    wire [319:0] next1 = {d0, d1, d2, d3, d4};

    // ----------------------------------------------------------------
    // FSM — G_SBOX_PIPELINE=0 only (combinational, 1 cycle/round)
    //
    // start_perm fires:
    //   cycle 0: running=0 → rnd_in=start_st → next1 combinationally valid
    //            latch result, start running loop
    //   cycle 1..N-1: running=1 → rnd_in=cur → next1 valid, advance
    //
    // Timing: rounds cycles total per call (1 cycle/round)
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur        <= 320'h0;
            rc         <= 4'h0;
            rounds_reg <= 4'h0;
            done_cnt   <= 4'h0;
            running    <= 1'b0;
            state_out  <= 320'h0;
            valid      <= 1'b0;
            done       <= 1'b0;
        end else begin
            valid <= 1'b0;
            done  <= 1'b0;

            if (!running) begin
                if (start_perm) begin
                    // Cycle 0: rnd_in=start_st (combinational), next1 valid NOW
                    // Latch round 0 result
                    rounds_reg <= rounds;
                    rc         <= start_rc + 4'd1;   // next round after this one
                    done_cnt   <= 4'd1;
                    cur        <= next1;

                    if (4'd1 >= rounds) begin
                        // rounds=1 edge case: done immediately
                        state_out <= next1;
                        valid     <= 1'b1;
                        done      <= 1'b1;
                    end else begin
                        running <= 1'b1;
                    end
                end
            end else begin
                // Cycle 1+: rnd_in=cur (registered), next1 valid NOW
                done_cnt <= done_cnt + 4'd1;
                rc       <= rc + 4'd1;
                cur      <= next1;

                if (done_cnt + 4'd1 >= rounds_reg) begin
                    state_out <= next1;
                    valid     <= 1'b1;
                    done      <= 1'b1;
                    running   <= 1'b0;
                end
            end
        end
    end

endmodule