`timescale 1ns/1ps

// ============================================================================
// Module: ascon_CONTROLLER  (v14 — fix: mode decode align với convention mới)
//
// FIX vs v13:
//   BUG: GCD parameters dùng mode[0]==1 cho ASCON-128 (convention ngược).
//        Nguyên nhân: CORE v11 đảo mode_int[0] trước khi truyền vào CONTROLLER,
//        nên CONTROLLER phải check ngược. Sau khi CORE v12 bỏ đảo, CONTROLLER
//        cần decode lại đúng chiều.
//
//   FIX: mode[0]==0 → ASCON-128  (G=6, calls_pa=2, calls_pb=1)
//        mode[0]==1 → ASCON-128a (G=4, calls_pa=3, calls_pb=2)
// ============================================================================
module ascon_CONTROLLER #(
    parameter G_COMB_RND_128  = 6,
    parameter G_COMB_RND_128A = 4,
    /* verilator lint_off UNUSEDPARAM */
    parameter G_SBOX_PIPELINE = 0
    /* verilator lint_on UNUSEDPARAM */
) (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         start,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [1:0]   mode,   // mode[1] unused (only mode[0] decoded)
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire         enc_dec,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [127:0] key_in,
    input  wire [127:0] nonce_in,
    input  wire [127:0] ad_in,
    input  wire         ad_valid,
    input  wire         ad_last,
    input  wire [127:0] data_in,
    input  wire         data_last,
    input  wire [6:0]   data_len,
    input  wire [127:0] tag_received,
    /* verilator lint_on UNUSEDSIGNAL */

    output reg          data_out_valid,
    output reg          done,
    output reg          busy,

    output reg          load_key,
    output reg          load_nonce,
    output reg          init_start,

    output reg  [1:0]   state_src_sel,
    output reg          state_load,

    output reg          dp_pad_enable,
    output reg  [1:0]   dp_block_sel,
    output reg          dp_enc_dec,

    output reg  [3:0]   perm_rounds,
    output reg  [3:0]   perm_start_rc,
    output reg          perm_start,

    output reg          gen_tag,
    output reg          compare_tag,

    output reg          do_post_init_key_xor,
    output reg          do_pre_fin_key_xor,
    output reg          do_dom_sep,

    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         init_done,  // reserved for future pipeline use
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire         perm_done,
    input  wire         tag_gen_valid,
    input  wire         tag_cmp_done,
    input  wire         extra_pad_block_needed
);

    // ----------------------------------------------------------------
    // GCD parameters
    // ----------------------------------------------------------------
    // mode[0]=0 → ASCON-128  (G=6, pa=12→2 calls, pb=6→1 call)
    // mode[0]=1 → ASCON-128a (G=4, pa=12→3 calls, pb=8→2 calls)
    wire [3:0] G =
        (mode[0] == 1'b0) ? G_COMB_RND_128[3:0] : G_COMB_RND_128A[3:0];

    wire [3:0] calls_pa =
        (mode[0] == 1'b0) ? 4'd2 : 4'd3;

    wire [3:0] calls_pb =
        (mode[0] == 1'b0) ? 4'd1 : 4'd2;

    wire [3:0] pb_offset =
        (mode[0] == 1'b0) ? 4'd6 : 4'd4;

    wire [3:0] rc_pa = (calls_pa - cnt) * G;
    wire [3:0] rc_pb = pb_offset + (calls_pb - cnt) * G;

    // ----------------------------------------------------------------
    // State encoding
    // ----------------------------------------------------------------
    localparam [5:0]
        S_IDLE              = 6'd0,
        S_LOAD_KEY          = 6'd1,
        S_LOAD_NONCE        = 6'd2,
        S_INIT_TRIG         = 6'd3,
        S_INIT_LOAD         = 6'd33,
        S_INIT_START        = 6'd4,
        S_INIT_WAIT         = 6'd5,
        S_INIT_OUT          = 6'd6,
        S_POST_INIT         = 6'd7,
        S_DOM_SEP           = 6'd8,
        S_AD_LOAD           = 6'd9,
        S_AD_START          = 6'd10,
        S_AD_WAIT           = 6'd11,
        S_AD_OUT            = 6'd12,
        S_AD_PAD_LOAD       = 6'd13,
        S_AD_PAD_START      = 6'd14,
        S_AD_PAD_WAIT       = 6'd15,
        S_AD_PAD_OUT        = 6'd16,
        S_DATA_LOAD         = 6'd17,
        S_DATA_START        = 6'd18,
        S_DATA_WAIT         = 6'd19,
        S_DATA_OUT          = 6'd20,
        S_DATA_PAD_LOAD     = 6'd21,
        S_FINAL_SETUP       = 6'd25,
        S_FINAL_START       = 6'd26,
        S_FINAL_WAIT        = 6'd27,
        S_FINAL_OUT         = 6'd28,
        S_GEN_TAG           = 6'd29,
        S_WAIT_TAG          = 6'd30,
        S_CMP_TAG           = 6'd31,
        S_DONE              = 6'd32;

    reg [5:0] state;
    reg [3:0] cnt;
    reg       ad_last_r;
    reg       data_last_r;
    reg       extra_pad_r;

    // ----------------------------------------------------------------
    // Sequential FSM
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            cnt         <= 4'd0;
            ad_last_r   <= 1'b0;
            data_last_r <= 1'b0;
            extra_pad_r <= 1'b0;
        end else begin
            case (state)

                S_IDLE:
                    if (start) state <= S_LOAD_KEY;

                S_LOAD_KEY:   state <= S_LOAD_NONCE;
                S_LOAD_NONCE: state <= S_INIT_TRIG;
                S_INIT_TRIG:  state <= S_INIT_LOAD;

                S_INIT_LOAD: begin
                    cnt   <= calls_pa;
                    state <= S_INIT_START;
                end

                S_INIT_START: state <= S_INIT_WAIT;

                S_INIT_WAIT:
                    if (perm_done) state <= S_INIT_OUT;

                S_INIT_OUT: begin
                    cnt <= cnt - 4'd1;
                    if (cnt == 4'd1) state <= S_POST_INIT;
                    else             state <= S_INIT_START;
                end

                S_POST_INIT:
                    state <= ad_valid ? S_AD_LOAD : S_DOM_SEP;

                S_DOM_SEP:
                    state <= S_DATA_LOAD;

                // ---- AD ----
                S_AD_LOAD: begin
                    ad_last_r   <= ad_last;
                    extra_pad_r <= extra_pad_block_needed;
                    cnt         <= calls_pb;
                    state       <= S_AD_START;
                end

                S_AD_START: state <= S_AD_WAIT;

                S_AD_WAIT:
                    if (perm_done) state <= S_AD_OUT;

                S_AD_OUT: begin
                    cnt <= cnt - 4'd1;
                    if (cnt > 4'd1)
                        state <= S_AD_START;
                    else if (ad_last_r & extra_pad_r)
                        state <= S_AD_PAD_LOAD;
                    else if (ad_last_r)
                        state <= S_DOM_SEP;
                    else
                        state <= S_AD_LOAD;
                end

                S_AD_PAD_LOAD: begin
                    cnt   <= calls_pb;
                    state <= S_AD_PAD_START;
                end

                S_AD_PAD_START: state <= S_AD_PAD_WAIT;

                S_AD_PAD_WAIT:
                    if (perm_done) state <= S_AD_PAD_OUT;

                S_AD_PAD_OUT: begin
                    cnt <= cnt - 4'd1;
                    if (cnt > 4'd1) state <= S_AD_PAD_START;
                    else            state <= S_DOM_SEP;
                end

                // ---- Data ----
                // FIX 1: last block → skip p^b, go directly to finalization
                S_DATA_LOAD: begin
                    data_last_r <= data_last;
                    extra_pad_r <= extra_pad_block_needed;
                    cnt         <= calls_pb;
                    if (data_last & ~extra_pad_block_needed)
                        state <= S_FINAL_SETUP;  // FIX: skip perm for last block
                    else
                        state <= S_DATA_START;
                end

                S_DATA_START: state <= S_DATA_WAIT;

                S_DATA_WAIT:
                    if (perm_done) state <= S_DATA_OUT;

                S_DATA_OUT: begin
                    cnt <= cnt - 4'd1;
                    if (cnt > 4'd1)
                        state <= S_DATA_START;
                    else if (data_last_r & extra_pad_r)
                        state <= S_DATA_PAD_LOAD;
                    else if (data_last_r)
                        state <= S_FINAL_SETUP;
                    else
                        state <= S_DATA_LOAD;
                end

                // FIX 2: pad block is always last → skip perm, go to finalization
                S_DATA_PAD_LOAD: begin
                    state <= S_FINAL_SETUP;   // FIX: no perm after pad block
                end

                // ---- FINAL ----
                S_FINAL_SETUP: begin
                    cnt   <= calls_pa;
                    state <= S_FINAL_START;
                end

                S_FINAL_START: state <= S_FINAL_WAIT;

                S_FINAL_WAIT:
                    if (perm_done) state <= S_FINAL_OUT;

                S_FINAL_OUT: begin
                    cnt <= cnt - 4'd1;
                    if (cnt == 4'd1) state <= S_GEN_TAG;
                    else             state <= S_FINAL_START;
                end

                S_GEN_TAG:  state <= S_WAIT_TAG;

                S_WAIT_TAG:
                    if (tag_gen_valid)
                        state <= enc_dec ? S_CMP_TAG : S_DONE;

                S_CMP_TAG:
                    if (tag_cmp_done) state <= S_DONE;

                S_DONE:  state <= S_IDLE;
                default: state <= S_IDLE;

            endcase
        end
    end

    // ----------------------------------------------------------------
    // Combinational outputs
    // ----------------------------------------------------------------
    always @(*) begin
        load_key             = 1'b0;
        load_nonce           = 1'b0;
        init_start           = 1'b0;
        state_src_sel        = 2'b10;
        state_load           = 1'b0;
        dp_pad_enable        = 1'b0;
        dp_block_sel         = 2'b00;
        dp_enc_dec           = enc_dec;
        perm_rounds          = G;
        perm_start_rc        = 4'd0;
        perm_start           = 1'b0;
        gen_tag              = 1'b0;
        compare_tag          = 1'b0;
        data_out_valid       = 1'b0;
        do_post_init_key_xor = 1'b0;
        do_pre_fin_key_xor   = 1'b0;
        do_dom_sep           = 1'b0;
        done                 = 1'b0;
        busy                 = 1'b1;

        case (state)
            S_IDLE:       busy = 1'b0;
            S_LOAD_KEY:   load_key = 1'b1;
            S_LOAD_NONCE: load_nonce = 1'b1;
            S_INIT_TRIG:  init_start = 1'b1;

            S_INIT_LOAD: begin
                state_src_sel = 2'b00;
                state_load    = 1'b1;
            end

            S_INIT_START: begin
                perm_rounds   = G;
                perm_start_rc = rc_pa;
                perm_start    = 1'b1;
            end

            S_INIT_OUT: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
            end

            S_POST_INIT: begin
                do_post_init_key_xor = 1'b1;
                state_src_sel        = 2'b10;
                state_load           = 1'b1;
            end

            S_DOM_SEP: begin
                do_dom_sep    = 1'b1;
                state_src_sel = 2'b10;
                state_load    = 1'b1;
            end

            S_AD_LOAD: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b00;
                dp_pad_enable = ad_last & ~extra_pad_block_needed;
                state_load    = 1'b1;
            end

            S_AD_START: begin
                perm_rounds   = G;
                perm_start_rc = rc_pb;
                perm_start    = 1'b1;
            end

            S_AD_OUT: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
            end

            S_AD_PAD_LOAD: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b00;
                dp_pad_enable = 1'b1;
                state_load    = 1'b1;
            end

            S_AD_PAD_START: begin
                perm_rounds   = G;
                perm_start_rc = rc_pb;
                perm_start    = 1'b1;
            end

            S_AD_PAD_OUT: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
            end

            S_DATA_LOAD: begin
                state_src_sel  = 2'b01;
                dp_block_sel   = 2'b01;
                dp_pad_enable  = data_last & ~extra_pad_block_needed;
                state_load     = 1'b1;
                data_out_valid = 1'b1;
            end

            S_DATA_START: begin
                perm_rounds   = G;
                perm_start_rc = rc_pb;
                perm_start    = 1'b1;
            end

            S_DATA_OUT: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
            end

            // FIX 2: PAD block - absorb into state, then go to FINAL
            S_DATA_PAD_LOAD: begin
                state_src_sel  = 2'b01;
                dp_block_sel   = 2'b01;
                dp_pad_enable  = 1'b1;
                state_load     = 1'b1;
                data_out_valid = 1'b0;  // pad block produces no output
            end

            S_FINAL_SETUP: begin
                do_pre_fin_key_xor = 1'b1;
                state_src_sel      = 2'b10;
                state_load         = 1'b1;
            end

            S_FINAL_START: begin
                perm_rounds   = G;
                perm_start_rc = rc_pa;
                perm_start    = 1'b1;
            end

            S_FINAL_OUT: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
            end

            S_GEN_TAG:  gen_tag     = 1'b1;
            S_CMP_TAG:  compare_tag = 1'b1;

            S_DONE: begin
                done = 1'b1;
                busy = 1'b0;
            end

            default: busy = 1'b0;
        endcase
    end

endmodule