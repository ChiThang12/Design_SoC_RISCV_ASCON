// ============================================================================
// Module: ascon_PERMUTATION  (v10 — cleanup: bỏ unused mode port)
//
// Thay đổi so với v9:
//   - Xóa input wire mode (Reserved, không có logic nào đọc).
//   - Cập nhật instantiation trong ascon_CORE.v: bỏ .mode(mode_int[0]).
//   - Giữ nguyên hoàn toàn datapath G_UNROLL=2, FSM 4-state, G_SBOX_PIPELINE.
// ============================================================================

`include "ascon/rtl/PERMUTATION/ascon_ROUND_STEP.v"

module ascon_PERMUTATION #(
    parameter G_SBOX_PIPELINE = 0,
    parameter G_UNROLL        = 2
) (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [319:0] state_in,
    input  wire [319:0] state_bypass,
    input  wire         use_bypass,

    input  wire [3:0]   rounds,
    input  wire [3:0]   start_rc,
    input  wire         start_perm,

    output reg  [319:0] state_out,
    output reg          valid,
    output reg          done
);

    localparam [1:0]
        ST_IDLE    = 2'd0,
        ST_RUN     = 2'd1,
        ST_STAGE_0 = 2'd2,
        ST_STAGE_1 = 2'd3;

    reg [1:0] fsm;
    reg [319:0] cur;
    reg [3:0]   rc_cur;
    reg [3:0]   calls_left;

    wire [319:0] start_st = use_bypass ? state_bypass : state_in;

    wire use_start_mux = (fsm == ST_IDLE) & start_perm;
    wire [319:0] rnd_in = use_start_mux ? start_st : cur;
    wire [3:0]   rnd_rc = use_start_mux ? start_rc : rc_cur;

    wire [319:0] mid_state;

    ascon_ROUND_STEP u_step1 (
        .state_in  (rnd_in),
        .round_rc  (rnd_rc),
        .state_out (mid_state)
    );

    wire [319:0] next_state;

    generate
        if (G_SBOX_PIPELINE == 1) begin : gen_pipe_stage

            reg [319:0] mid_state_r;
            reg [3:0]   rc_r;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    mid_state_r <= 320'h0;
                    rc_r        <= 4'h0;
                end else if (fsm == ST_STAGE_0) begin
                    mid_state_r <= mid_state;
                    rc_r        <= rc_cur;
                end
            end

            ascon_ROUND_STEP u_step2 (
                .state_in  (mid_state_r),
                .round_rc  (rc_r + 4'd1),
                .state_out (next_state)
            );

        end else begin : gen_comb_chain

            ascon_ROUND_STEP u_step2 (
                .state_in  (mid_state),
                .round_rc  (rnd_rc + 4'd1),
                .state_out (next_state)
            );

        end
    endgenerate

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

                ST_IDLE: begin
                    if (start_perm) begin
                        /* verilator lint_off CASEINCOMPLETE */
                        if (G_SBOX_PIPELINE == 0) begin
                            cur        <= next_state;
                            rc_cur     <= start_rc + 4'd2;
                            calls_left <= (rounds >> 1) - 4'd1;

                            if ((rounds >> 1) == 4'd1) begin
                                state_out <= next_state;
                                valid     <= 1'b1;
                                done      <= 1'b1;
                            end else begin
                                fsm <= ST_RUN;
                            end

                        end else begin
                            cur        <= start_st;
                            rc_cur     <= start_rc;
                            calls_left <= rounds >> 1;
                            fsm        <= ST_STAGE_0;
                        end
                    end
                end

                ST_RUN: begin
                    cur        <= next_state;
                    rc_cur     <= rc_cur + 4'd2;
                    calls_left <= calls_left - 4'd1;

                    if (calls_left == 4'd1) begin
                        state_out <= next_state;
                        valid     <= 1'b1;
                        done      <= 1'b1;
                        fsm       <= ST_IDLE;
                    end
                end

                ST_STAGE_0: begin
                    fsm <= ST_STAGE_1;
                end

                ST_STAGE_1: begin
                    cur        <= next_state;
                    rc_cur     <= rc_cur + 4'd2;
                    calls_left <= calls_left - 4'd1;

                    if (calls_left == 4'd1) begin
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