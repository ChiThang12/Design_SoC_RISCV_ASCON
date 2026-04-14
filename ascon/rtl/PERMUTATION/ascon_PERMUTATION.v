// ============================================================================
// Module: ascon_PERMUTATION  (v9 — G_UNROLL=2, FSM verified)
//
// Thay đổi chính so với v8:
//   1. Thêm tham số G_UNROLL=2: mỗi "call" xử lý 2 rounds bằng chuỗi
//      2× ascon_ROUND_STEP tổ hợp.
//   2. Tổng calls = rounds / G_UNROLL (rounds phải là bội số của 2).
//   3. Loại bỏ biến `running`. Thay bằng FSM 3-state rõ ràng:
//        ST_IDLE    (2'd0): chờ start_perm
//        ST_RUN     (2'd1): G_SBOX_PIPELINE=0 — chạy liên tục 1 cycle/call
//        ST_STAGE_0 (2'd2): G_SBOX_PIPELINE=1 — latch step1→mid_state_r
//        ST_STAGE_1 (2'd3): G_SBOX_PIPELINE=1 — latch step2→cur
//   4. Biến rc_cur: round constant cho step1 của call HIỆN TẠI.
//      step2 dùng rc_cur+1. Tăng rc_cur+=2 sau mỗi call hoàn thành.
//
// DATAPATH:
//
//   rnd_in ─────► [ROUND_STEP #1: rc_cur  ] ──► mid_state
//                                                    │
//                         ┌──────────────────────────┘
//                         │  (G_SBOX_PIPELINE=1: mid_state_r ← DFF)
//                         ▼
//                 [ROUND_STEP #2: rc_cur+1] ──► next_state ──► cur
//
// FSM TIMING (G_SBOX_PIPELINE=0, rounds=6, calls=3):
//   C0 (IDLE+start): rnd_in=start_st → next_state → cur; calls_left=2; fsm→RUN
//   C1 (RUN):        rnd_in=cur → next_state → cur; calls_left=1; (done ở C2)
//   C2 (RUN):        rnd_in=cur → next_state → cur; calls_left=0; done=1; fsm→IDLE
//   Latency: rounds/2 cycles = 3 cycles ✓
//
// FSM TIMING (G_SBOX_PIPELINE=1, rounds=12, calls=6):
//   C0  (IDLE+start): cur←start_st; rc_cur←0; calls_left←6; fsm→STAGE_0
//   C1  (STAGE_0):    rnd_in=cur; step1→mid_state_r; fsm→STAGE_1
//   C2  (STAGE_1):    step2(mid_state_r,1)→cur; rc+=2; calls_left=5; fsm→STAGE_0
//   C3  (STAGE_0):    rnd_in=cur; step1→mid_state_r; fsm→STAGE_1
//   C4  (STAGE_1):    step2(mid_state_r,3)→cur; rc+=2; calls_left=4; fsm→STAGE_0
//   ...
//   C12 (STAGE_1):    step2(mid_state_r,11)→cur; calls_left=1; done=1; fsm→IDLE
//   Latency: 1 + 6×2 = 13 cycles ✓
//
// INTERFACE: Giữ nguyên so với v8 — ascon_CORE.v KHÔNG cần thay đổi.
//   rounds   : Tổng rounds (12/8/6). Phải là bội số của 2.
//   start_rc : Round constant index của round đầu tiên.
//   Tất cả cổng khác giữ nguyên.
//
// TIMING CHO SYNTHESIS/PD:
//   G_SBOX_PIPELINE=0:
//     Critical path qua cả 2 ROUND_STEP xếp nối tiếp.
//     Nếu timing vi phạm: enable retiming (compile_ultra -retime) để synthesis
//     tự insert pipeline stage tại wire mid_state (320-bit inter-stage point).
//     Hoặc chuyển sang G_SBOX_PIPELINE=1.
//
//   G_SBOX_PIPELINE=1:
//     Pipeline register 320-bit tại mid_state_r giữa step1 và step2.
//     Critical path ≈ 1× ROUND_STEP (RC_ADD + SBOX + LINEAR_DIFF).
//     Throughput: 1 round/cycle (tương đương v8 nhưng cần 2 cycle/call).
//     Fmax ~2× so với G_SBOX_PIPELINE=0 với G_UNROLL=2.
// ============================================================================

`include "ascon/rtl/PERMUTATION/ascon_ROUND_STEP.v"

module ascon_PERMUTATION #(
    parameter G_SBOX_PIPELINE = 0,
    parameter G_UNROLL        = 2    // Cố định = 2. Tham số giữ để document ý định.
) (
    input  wire         clk,
    input  wire         rst_n,

    // State input
    input  wire [319:0] state_in,
    input  wire [319:0] state_bypass,
    input  wire         use_bypass,     // 1: dùng state_bypass, 0: dùng state_in

    // Permutation configuration
    input  wire [3:0]   rounds,         // Tổng rounds cần chạy (12, 8, hoặc 6)
    input  wire [3:0]   start_rc,       // Absolute round constant index bắt đầu
    input  wire         start_perm,     // Pulse 1 cycle để bắt đầu

    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         mode,           // Reserved
    /* verilator lint_on UNUSEDSIGNAL */

    // Outputs
    output reg  [319:0] state_out,
    output reg          valid,
    output reg          done
);

    // ----------------------------------------------------------------
    // FSM state encoding
    // ----------------------------------------------------------------
    localparam [1:0]
        ST_IDLE    = 2'd0,
        ST_RUN     = 2'd1,   // G_SBOX_PIPELINE=0: active, 1 cycle/call
        ST_STAGE_0 = 2'd2,   // G_SBOX_PIPELINE=1: step1 compute, latch mid
        ST_STAGE_1 = 2'd3;   // G_SBOX_PIPELINE=1: step2 compute, latch result

    reg [1:0] fsm;

    // ----------------------------------------------------------------
    // Datapath registers
    // ----------------------------------------------------------------
    reg [319:0] cur;          // Intermediate state (output của call trước)
    reg [3:0]   rc_cur;       // Round constant cho step1 của call HIỆN TẠI
    reg [3:0]   calls_left;   // Số calls chưa xử lý (sau call đầu tại IDLE)

    // ----------------------------------------------------------------
    // Input state mux
    // ----------------------------------------------------------------
    wire [319:0] start_st = use_bypass ? state_bypass : state_in;

    // ----------------------------------------------------------------
    // Combinational input mux cho ROUND_STEP chain
    //
    // Khi IDLE+start_perm: dùng start_st (chưa có cur valid)
    // Khi RUN / STAGE_0:   dùng cur (đã latch từ call trước)
    //
    // QUAN TRỌNG timing: tín hiệu này là combinational path vào ROUND_STEP.
    // Synthesis tool có thể minimize fanout tại mux output (320-bit).
    // ----------------------------------------------------------------
    wire use_start_mux = (fsm == ST_IDLE) & start_perm;

    wire [319:0] rnd_in  = use_start_mux ? start_st : cur;
    wire [3:0]   rnd_rc  = use_start_mux ? start_rc : rc_cur;

    // ----------------------------------------------------------------
    // ROUND_STEP #1 (step1): tính output sau 1 round đầu
    // ----------------------------------------------------------------
    wire [319:0] mid_state;

    ascon_ROUND_STEP u_step1 (
        .state_in  (rnd_in),
        .round_rc  (rnd_rc),
        .state_out (mid_state)
    );

    // ----------------------------------------------------------------
    // ROUND_STEP #2 (step2): tính output sau round thứ 2
    //
    // G_SBOX_PIPELINE=0: nhận mid_state trực tiếp (chuỗi tổ hợp)
    // G_SBOX_PIPELINE=1: nhận mid_state_r (registered — pipeline cut point)
    //   mid_state_r được latch khi fsm=ST_STAGE_0
    //   rc_r lưu rc_cur của STAGE_0 để step2 dùng rc_r+1 đúng chu kỳ
    // ----------------------------------------------------------------
    wire [319:0] next_state;

    generate
        if (G_SBOX_PIPELINE == 1) begin : gen_pipe_stage

            reg [319:0] mid_state_r;
            reg [3:0]   rc_r;

            // Latch mid_state khi đang ở STAGE_0
            // (step1 đang tính từ cur hoặc start_st qua mux)
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    mid_state_r <= 320'h0;
                    rc_r        <= 4'h0;
                end else if (fsm == ST_STAGE_0) begin
                    mid_state_r <= mid_state;
                    rc_r        <= rc_cur;   // Latch rc_cur hiện tại (không tăng ở STAGE_0)
                end
            end

            ascon_ROUND_STEP u_step2 (
                .state_in  (mid_state_r),
                .round_rc  (rc_r + 4'd1),
                .state_out (next_state)
            );

        end else begin : gen_comb_chain

            // Combinational chain: step2 nhận ngay từ step1
            ascon_ROUND_STEP u_step2 (
                .state_in  (mid_state),
                .round_rc  (rnd_rc + 4'd1),
                .state_out (next_state)
            );

        end
    endgenerate

    // ----------------------------------------------------------------
    // FSM + Register updates
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm        <= ST_IDLE;
            cur        <= 320'h0;
            rc_cur     <= 4'h0;
            calls_left <= 4'h0;
            state_out  <= 320'h0;
            valid      <= 1'b0;
            done       <= 1'b0;
        end else begin
            valid <= 1'b0;
            done  <= 1'b0;

            case (fsm)

                // --------------------------------------------------------
                // ST_IDLE
                // --------------------------------------------------------
                ST_IDLE: begin
                    if (start_perm) begin
                        /* verilator lint_off CASEINCOMPLETE */
                        if (G_SBOX_PIPELINE == 0) begin
                            // ----------------------------------------
                            // COMB mode:
                            //   rnd_in=start_st (via use_start_mux=1, comb)
                            //   next_state valid combinationally RIGHT NOW
                            //   Latch kết quả call pertama.
                            // ----------------------------------------
                            cur        <= next_state;
                            rc_cur     <= start_rc + 4'd2;
                            // calls = rounds>>1; đã thực hiện 1 call → còn (rounds>>1)-1
                            calls_left <= (rounds >> 1) - 4'd1;

                            if ((rounds >> 1) == 4'd1) begin
                                // Chỉ 1 call tổng → done ngay
                                state_out <= next_state;
                                valid     <= 1'b1;
                                done      <= 1'b1;
                                // fsm giữ ST_IDLE
                            end else begin
                                fsm <= ST_RUN;
                            end

                        end else begin
                            // ----------------------------------------
                            // PIPELINE mode:
                            //   Pre-load cur = start_st để STAGE_0 dùng
                            //   qua rnd_in mux (use_start_mux=0 ở STAGE_0)
                            // ----------------------------------------
                            cur        <= start_st;
                            rc_cur     <= start_rc;    // Không tăng ở đây
                            calls_left <= rounds >> 1; // Tổng calls, chưa trừ
                            fsm        <= ST_STAGE_0;
                        end
                    end
                end

                // --------------------------------------------------------
                // ST_RUN (G_SBOX_PIPELINE=0 only)
                //
                // Invariant đầu vào: cur = kết quả call trước, rc_cur valid,
                //                    calls_left = số calls còn lại (>= 1)
                // rnd_in = cur (use_start_mux=0, fsm≠IDLE) ✓
                // next_state = tổ hợp valid ✓
                // --------------------------------------------------------
                ST_RUN: begin
                    cur        <= next_state;
                    rc_cur     <= rc_cur + 4'd2;
                    calls_left <= calls_left - 4'd1;

                    if (calls_left == 4'd1) begin
                        // calls_left CŨ = 1 → đây là call cuối
                        state_out <= next_state;
                        valid     <= 1'b1;
                        done      <= 1'b1;
                        fsm       <= ST_IDLE;
                    end
                    // else: tiếp tục ST_RUN
                end

                // --------------------------------------------------------
                // ST_STAGE_0 (G_SBOX_PIPELINE=1 only)
                //
                // Invariant: cur = state đầu vào cho call này (start_st hoặc
                //            kết quả call trước đã latch ở STAGE_1)
                //            rc_cur = round constant đúng cho call này
                //
                // Action: rnd_in=cur (mux) → step1 tính → mid_state_r latch
                //         (latch xảy ra trong gen_pipe_stage always block)
                // Không update cur/rc_cur/calls_left ở đây.
                // --------------------------------------------------------
                ST_STAGE_0: begin
                    // Chỉ advance FSM; mid_state_r latch trong gen_pipe_stage
                    fsm <= ST_STAGE_1;
                end

                // --------------------------------------------------------
                // ST_STAGE_1 (G_SBOX_PIPELINE=1 only)
                //
                // Invariant: mid_state_r = step1 output từ STAGE_0
                //            rc_r = rc_cur yang dilatched di STAGE_0
                //
                // Action: step2(mid_state_r, rc_r+1) → next_state (comb valid)
                //         Latch next_state, advance rc_cur, decrement calls_left
                // --------------------------------------------------------
                ST_STAGE_1: begin
                    cur        <= next_state;
                    rc_cur     <= rc_cur + 4'd2;
                    calls_left <= calls_left - 4'd1;

                    if (calls_left == 4'd1) begin
                        // calls_left CŨ = 1 → call cuối
                        state_out <= next_state;
                        valid     <= 1'b1;
                        done      <= 1'b1;
                        fsm       <= ST_IDLE;
                    end else begin
                        fsm <= ST_STAGE_0;
                    end
                end

                default: fsm <= ST_IDLE;

            endcase
        end
    end

endmodule