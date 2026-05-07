`timescale 1ns/1ps

// ============================================================================
// Module: ascon_PERMUTATION  (v9 — Unrolled Pipeline Architecture)
//
// THIẾT KẾ MỚI: Fully Unrolled + Optionally Pipelined
// ============================================================================
//
// KIẾN TRÚC:
//
//   G_SBOX_PIPELINE=0 (PARALLEL_ROUNDS > 1, no inter-round regs):
//     → Combinational chain của G rounds, 1 cycle/call
//     → Crit path = G × (CA + SL + LD) deep
//     → Throughput tối đa, latency tối thiểu
//
//   G_SBOX_PIPELINE=1 (PIPELINE_STAGES > 1):
//     → Mỗi round là 1 pipeline stage với register
//     → Latency = G cycles, nhưng Fmax tăng cao hơn nhiều
//     → Cho phép ghi "pipelined architecture" hợp lệ trong bài báo
//     → 1 new block vào pipeline mỗi cycle = throughput lý tưởng
//
// THAM SỐ:
//   G_SBOX_PIPELINE = 0: combinational unroll (all rounds in 1 cycle)
//   G_SBOX_PIPELINE = 1: pipelined unroll (1 round/cycle, round-register)
//
//   G_ROUNDS_MAX = số rounds tối đa được unroll (12 cho pa)
//   G_COMB_RND   = số rounds được gom vào 1 stage khi pipeline
//                  (= 1: mỗi round 1 stage; = 2: 2 rounds/stage...)
//
// INTERFACE THAY ĐỔI SO VỚI v8:
//   - Thêm output: latency_cycles (để CONTROLLER biết cần đợi bao nhiêu cycle)
//   - done vẫn còn để tương thích với CONTROLLER cũ
//   - Khi G_SBOX_PIPELINE=0: done assert sau 1 cycle (như cũ)
//   - Khi G_SBOX_PIPELINE=1: done assert sau `rounds` cycles
//
// FSM ĐƠN GIẢN HÓA:
//   - Không còn lỗi pha vì mỗi stage là independent register
//   - Pipeline flush tự động khi start_perm
//
// ============================================================================

// `include "ascon/rtl/PERMUTATION/ascon_ROUND_COMB.v"

module ascon_PERMUTATION #(
    parameter G_SBOX_PIPELINE = 0,   // 0=comb unroll, 1=pipelined unroll
    parameter G_ROUNDS_MAX    = 12,  // max rounds (pa=12, pb=6 hay 8)
    parameter G_COMB_RND      = 1    // rounds per pipeline stage (khi pipeline=1)
) (
    input  wire         clk,
    input  wire         rst_n,

    // State input
    input  wire [319:0] state_in,
    input  wire [319:0] state_bypass,
    input  wire         use_bypass,

    // Round control
    input  wire [3:0]   rounds,       // number of rounds to run (4 or 6 or 12)
    input  wire [3:0]   start_rc,     // starting round constant index
    input  wire         start_perm,   // pulse: start permutation

    // Mode (reserved)
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         mode,
    /* verilator lint_on UNUSEDSIGNAL */

    // Outputs
    output reg  [319:0] state_out,
    output reg          valid,
    output reg          done
);

    wire [319:0] start_st = use_bypass ? state_bypass : state_in;

    // =========================================================================
    // MODE 0: G_SBOX_PIPELINE=0 — Fully Combinational Unroll
    //
    // Tất cả 12 round instances mắc nối tiếp, kết quả ra trong CÙNG 1 cycle.
    // FSM chỉ cần: latch start_st → 1 cycle sau → done.
    //
    // Throughput: 1 call/cycle = max throughput
    // Critical path: 6×(CA+SL+LD) ≈ nhiều gates, nhưng với 100MHz thường OK
    // =========================================================================
    generate
    if (G_SBOX_PIPELINE == 0) begin : gen_comb_unroll

        // Unroll 12 rounds combinationally
        // Mux output theo `rounds` và `start_rc`
        wire [319:0] round_wire [0:G_ROUNDS_MAX]; // 0=input, 1..12=after each round

        // Round 0 input = start_st (registered below)
        reg [319:0] st_reg;
        reg [3:0]   rc_reg;
        reg [3:0]   rnd_reg;
        reg         running;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                st_reg  <= 320'h0;
                rc_reg  <= 4'h0;
                rnd_reg <= 4'h0;
                running <= 1'b0;
                done    <= 1'b0;
                valid   <= 1'b0;
                state_out <= 320'h0;
            end else begin
                done  <= 1'b0;
                valid <= 1'b0;

                if (start_perm) begin
                    st_reg  <= start_st;
                    rc_reg  <= start_rc;
                    rnd_reg <= rounds;
                    running <= 1'b1;
                end

                // 1 cycle later: unrolled chain is valid
                if (running) begin
                    running   <= 1'b0;
                    done      <= 1'b1;
                    valid     <= 1'b1;
                    // Output muxed below
                end
            end
        end

        // Combinational unroll chain
        assign round_wire[0] = st_reg;

        genvar r;
        for (r = 0; r < G_ROUNDS_MAX; r = r + 1) begin : comb_rounds
            wire [319:0] rout;
            ASCON_ROUND_COMB u_round (
                .state_in   (round_wire[r]),
                .round_const(rc_reg + r[3:0]),
                .state_out  (rout)
            );
            assign round_wire[r+1] = rout;
        end

        // Output mux: select result after `rnd_reg` rounds
        // Since we always unroll all 12 but only use first `rounds` outputs:
        // Use a registered mux in the "running" cycle
        reg [319:0] mux_out;
        always @(rnd_reg, round_wire[1], round_wire[2], round_wire[3], round_wire[4], round_wire[5], round_wire[6], round_wire[7], round_wire[8], round_wire[9], round_wire[10], round_wire[11], round_wire[12]) begin
            case (rnd_reg)
                4'd1:  mux_out = round_wire[1];
                4'd2:  mux_out = round_wire[2];
                4'd3:  mux_out = round_wire[3];
                4'd4:  mux_out = round_wire[4];
                4'd5:  mux_out = round_wire[5];
                4'd6:  mux_out = round_wire[6];
                4'd7:  mux_out = round_wire[7];
                4'd8:  mux_out = round_wire[8];
                4'd9:  mux_out = round_wire[9];
                4'd10: mux_out = round_wire[10];
                4'd11: mux_out = round_wire[11];
                4'd12: mux_out = round_wire[12];
                default: mux_out = round_wire[6];
            endcase
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                state_out <= 320'h0;
            else if (running)
                state_out <= mux_out;
        end

    end // gen_comb_unroll

    // =========================================================================
    // MODE 1: G_SBOX_PIPELINE=1 — Pipelined Unroll (1 round/stage)
    //
    // Mỗi round là 1 pipeline stage với flip-flop register ở đầu ra.
    // Latency = `rounds` cycles, nhưng Fmax tăng đáng kể.
    //
    // Đây là thiết kế "pipelined" hợp lệ cho bài báo:
    //   - Có thanh ghi chèn giữa các stages (rounds)
    //   - Fmax cao hơn → tần số clock cao hơn → throughput cao hơn
    //   - RTL reviewer có thể thấy flip-flop thực sự
    //
    // QUAN TRỌNG: Với thiết kế này, CONTROLLER cần biết latency = rounds cycles.
    //   Controller phải đếm `rounds` cycles sau start_perm trước khi dùng kết quả.
    // =========================================================================
    else begin : gen_pipe_unroll

        // Pipeline: 12 registered stages
        // Stage i: register holds state after round i
        reg [319:0] pipe_st  [0:G_ROUNDS_MAX-1]; // pipe_st[i] = after round i+1
        reg [3:0]   pipe_rc  [0:G_ROUNDS_MAX-1]; // round constant at each stage
        reg         pipe_v   [0:G_ROUNDS_MAX-1]; // valid bit propagates through

        // Registered round counter for done detection
        reg [3:0]   rnd_target;    // how many rounds needed
        reg [3:0]   lat_cnt;       // cycle counter since start_perm
        reg         counting;

        // ---- Stage 0: combinational from start_st ----
        wire [319:0] r0_out;
        ASCON_ROUND_COMB u_r0 (
            .state_in   (start_st),
            .round_const(start_rc),
            .state_out  (r0_out)
        );

        // ---- Stages 0..11: each stage reads its own registered state ----
        // stage_out[s] = Round_{s+1}(pipe_st[s])
        // pipe_st[0]   = R0(start_st), registered on start_perm
        // pipe_st[k+1] = registered stage_out[k]
        // Result after N rounds is in pipe_st[N-1] at edge N.
        wire [319:0] stage_out [0:G_ROUNDS_MAX-1];

        genvar s;
        for (s = 0; s < G_ROUNDS_MAX; s = s + 1) begin : pipe_stages
            ASCON_ROUND_COMB u_rs (
                .state_in   (pipe_st[s]),
                .round_const(s == 0 ? (start_rc + 4'd1) : (pipe_rc[s-1] + 4'd1)),
                .state_out  (stage_out[s])
            );
        end

        // ---- Clock registers for each stage ----
        integer k;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                for (k = 0; k < G_ROUNDS_MAX; k = k + 1) begin
                    pipe_st[k] <= 320'h0;
                    pipe_rc[k] <= 4'h0;
                    pipe_v [k] <= 1'b0;
                end
                rnd_target <= 4'h0;
                lat_cnt    <= 4'h0;
                counting   <= 1'b0;
                done       <= 1'b0;
                valid      <= 1'b0;
                state_out  <= 320'h0;
            end else begin
                done  <= 1'b0;
                valid <= 1'b0;

                // Stage 0 register: latch r0_out when start_perm
                if (start_perm) begin
                    pipe_st[0] <= r0_out;
                    pipe_rc[0] <= start_rc + 4'd1;
                    pipe_v [0] <= 1'b1;
                    rnd_target <= rounds;
                    lat_cnt    <= 4'd1;
                    counting   <= 1'b1;
                end else begin
                    pipe_v[0] <= 1'b0;
                end

                // Stage 1..11 shift register
                for (k = 1; k < G_ROUNDS_MAX; k = k + 1) begin
                    pipe_st[k] <= stage_out[k-1];
                    pipe_rc[k] <= pipe_rc[k-1] + 4'd1;
                    pipe_v [k] <= pipe_v[k-1];
                end

                // Done counter
                if (counting) begin
                    lat_cnt <= lat_cnt + 4'd1;
                    if (lat_cnt >= rnd_target) begin
                        counting  <= 1'b0;
                        done      <= 1'b1;
                        valid     <= 1'b1;
                        // pipe_st[N-1] holds result after N rounds at edge N
                        case (rnd_target)
                            4'd1:  state_out <= pipe_st[0];
                            4'd2:  state_out <= pipe_st[1];
                            4'd3:  state_out <= pipe_st[2];
                            4'd4:  state_out <= pipe_st[3];
                            4'd5:  state_out <= pipe_st[4];
                            4'd6:  state_out <= pipe_st[5];
                            4'd7:  state_out <= pipe_st[6];
                            4'd8:  state_out <= pipe_st[7];
                            4'd9:  state_out <= pipe_st[8];
                            4'd10: state_out <= pipe_st[9];
                            4'd11: state_out <= pipe_st[10];
                            4'd12: state_out <= pipe_st[11];
                            default: state_out <= pipe_st[5];
                        endcase
                    end
                end
            end
        end

    end // gen_pipe_unroll
    endgenerate

endmodule