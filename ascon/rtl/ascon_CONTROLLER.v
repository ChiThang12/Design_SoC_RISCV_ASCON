// ============================================================================
// Module: ascon_CONTROLLER  (OPT v4 — Pre-Permutation Merging)
//
// OPTIMIZATION: Gộp _LOAD + _PERM_START vào 1 state duy nhất
//
//   Baseline (v3):
//     S_INIT_LOAD (1 cycle) → S_INIT_PERM_START (1 cycle) → S_INIT_PERM_W
//     S_AD_LOAD   (1 cycle) → S_AD_PERM_START   (1 cycle) → S_AD_PERM_W
//     S_DATA_LOAD (1 cycle) → S_DATA_PERM_START (1 cycle) → S_DATA_PERM_W
//     S_FIN_LOAD  (1 cycle) → S_FIN_PERM_START  (1 cycle) → S_FIN_PERM_W
//
//   Optimized (v4):
//     S_INIT_LOAD_AND_START (1 cycle: state_load=1 + perm_start=1) → S_INIT_PERM_W
//     S_AD_LOAD_AND_START   (1 cycle) → S_AD_PERM_W
//     S_DATA_LOAD_AND_START (1 cycle) → S_DATA_PERM_W
//     S_FIN_LOAD_AND_START  (1 cycle) → S_FIN_PERM_W
//
//   Tại sao khả thi:
//     state_load và perm_start không xung đột.
//     PERMUTATION đọc state_in (= state_reg_out) ngay khi start_perm=1.
//     STATE_REGISTER latch vào cuối cycle đó → PERMUTATION bắt đầu với
//     current_state = state_in (latch cùng cycle) → đúng.
//
//   Tiết kiệm: 4 cycles/message (1 cycle × 4 lần gọi permutation)
//   Cộng với u=2 unrolling: tổng tiết kiệm ~54% số cycles/message
//
// All v3 fixes retained.
// ============================================================================
module ascon_CONTROLLER (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         start,
    input  wire [1:0]   mode,
    input  wire         enc_dec,
    input  wire [127:0] key_in,
    input  wire [127:0] nonce_in,
    input  wire [127:0] ad_in,
    input  wire         ad_valid,
    input  wire         ad_last,
    input  wire [127:0] data_in,
    input  wire         data_last,
    input  wire [6:0]   data_len,
    input  wire [127:0] tag_received,

    output reg  [127:0] data_out,
    output reg          data_out_valid,
    output reg  [127:0] tag_out,
    output reg          tag_valid,
    output reg          tag_match,
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
    output reg          perm_start,

    output reg          gen_tag,
    output reg          compare_tag,

    output reg          do_post_init_key_xor,
    output reg          do_pre_fin_key_xor,
    output reg          do_dom_sep,

    input  wire         init_done,
    input  wire         perm_done,
    input  wire         tag_gen_valid,
    input  wire         tag_cmp_done,
    input  wire         extra_pad_block_needed
);

    // ----------------------------------------------------------------
    // State encoding — _PERM_START states bị loại bỏ, thay bằng _LOAD_AND_START
    // ----------------------------------------------------------------
    localparam [5:0]
        S_IDLE                    = 6'd0,
        S_LOAD_KEY                = 6'd1,
        S_LOAD_NONCE              = 6'd2,
        S_INIT                    = 6'd3,
        // MERGED: S_INIT_LOAD + S_INIT_PERM_START
        S_INIT_LOAD_AND_START     = 6'd4,
        S_INIT_PERM_W             = 6'd5,
        S_POST_INIT_LOAD          = 6'd6,
        S_ABSORB_AD               = 6'd7,
        // MERGED: S_AD_LOAD + S_AD_PERM_START
        S_AD_LOAD_AND_START       = 6'd8,
        S_AD_PERM_W               = 6'd9,
        S_POST_AD_LOAD            = 6'd10,
        S_DOM_SEP                 = 6'd11,
        S_DOM_SEP_LOAD            = 6'd12,
        S_PROC_DATA               = 6'd13,
        // MERGED: S_DATA_LOAD + S_DATA_PERM_START
        S_DATA_LOAD_AND_START     = 6'd14,
        S_DATA_PERM_W             = 6'd15,
        S_POST_DATA_LOAD          = 6'd16,
        S_FINALIZE                = 6'd17,
        // MERGED: S_FIN_LOAD + S_FIN_PERM_START
        S_FIN_LOAD_AND_START      = 6'd18,
        S_FIN_PERM_W              = 6'd19,
        S_POST_FIN_LOAD           = 6'd20,
        S_GEN_TAG                 = 6'd21,
        S_WAIT_TAG_VALID          = 6'd22,
        S_CMP_TAG                 = 6'd23,
        S_DONE                    = 6'd24,
        // Extra pad states (giữ nguyên từ v3)
        S_AD_EXTRA_PAD            = 6'd25,
        S_AD_EXTRA_LOAD_AND_START = 6'd26,
        S_AD_EXTRA_PERM_W         = 6'd27,
        S_POST_AD_EXTRA_LOAD      = 6'd28,
        S_DATA_EXTRA_PAD          = 6'd29,
        S_DATA_EXTRA_LOAD_AND_START = 6'd30,
        S_DATA_EXTRA_PERM_W       = 6'd31,
        S_POST_DATA_EXTRA_LOAD    = 6'd32;

    reg [5:0] state, next_state;

    localparam [3:0] DATA_ROUNDS = 4'd8;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    always @(*) begin
        // ---------- defaults ----------
        next_state           = state;
        load_key             = 1'b0;
        load_nonce           = 1'b0;
        init_start           = 1'b0;
        state_src_sel        = 2'b10;
        state_load           = 1'b0;
        dp_pad_enable        = 1'b0;
        dp_block_sel         = 2'b00;
        dp_enc_dec           = enc_dec;
        perm_rounds          = 4'd12;
        perm_start           = 1'b0;
        gen_tag              = 1'b0;
        compare_tag          = 1'b0;
        data_out_valid       = 1'b0;
        do_post_init_key_xor = 1'b0;
        do_pre_fin_key_xor   = 1'b0;
        do_dom_sep           = 1'b0;
        done                 = 1'b0;
        busy                 = 1'b1;
        data_out             = 128'b0;
        tag_out              = 128'b0;
        tag_valid            = 1'b0;
        tag_match            = 1'b0;

        case (state)

            S_IDLE: begin
                busy = 1'b0;
                if (start) next_state = S_LOAD_KEY;
            end

            S_LOAD_KEY: begin
                load_key   = 1'b1;
                next_state = S_LOAD_NONCE;
            end

            S_LOAD_NONCE: begin
                load_nonce = 1'b1;
                next_state = S_INIT;
            end

            S_INIT: begin
                init_start = 1'b1;
                next_state = S_INIT_LOAD_AND_START;
            end

            // ---- INIT: load + perm_start cùng cycle ----
            S_INIT_LOAD_AND_START: begin
                state_src_sel = 2'b00;
                state_load    = 1'b1;   // latch init_state vào register
                perm_rounds   = 4'd12;
                perm_start    = 1'b1;   // bắt đầu permutation ngay
                next_state    = S_INIT_PERM_W;
            end

            S_INIT_PERM_W: begin
                if (perm_done) next_state = S_POST_INIT_LOAD;
            end

            S_POST_INIT_LOAD: begin
                do_post_init_key_xor = 1'b1;
                state_load           = 1'b1;
                next_state           = ad_valid ? S_ABSORB_AD : S_DOM_SEP;
            end

            // ---- AD absorption ----
            S_ABSORB_AD: begin
                dp_block_sel = 2'b00;
                next_state   = S_AD_LOAD_AND_START;
            end

            // ---- AD: load + perm_start cùng cycle ----
            S_AD_LOAD_AND_START: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b00;
                dp_pad_enable = ad_last & ~extra_pad_block_needed;
                state_load    = 1'b1;   // latch dp_state_xored
                perm_rounds   = DATA_ROUNDS;
                perm_start    = 1'b1;   // bắt đầu permutation ngay
                next_state    = S_AD_PERM_W;
            end

            S_AD_PERM_W: begin
                if (perm_done) next_state = S_POST_AD_LOAD;
            end

            S_POST_AD_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                if (ad_last & extra_pad_block_needed)
                    next_state = S_AD_EXTRA_PAD;
                else if (ad_last)
                    next_state = S_DOM_SEP;
                else
                    next_state = S_ABSORB_AD;
            end

            // ---- Extra AD pad block ----
            S_AD_EXTRA_PAD: begin
                next_state = S_AD_EXTRA_LOAD_AND_START;
            end

            S_AD_EXTRA_LOAD_AND_START: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b00;
                dp_pad_enable = 1'b1;
                state_load    = 1'b1;
                perm_rounds   = DATA_ROUNDS;
                perm_start    = 1'b1;
                next_state    = S_AD_EXTRA_PERM_W;
            end

            S_AD_EXTRA_PERM_W: begin
                if (perm_done) next_state = S_POST_AD_EXTRA_LOAD;
            end

            S_POST_AD_EXTRA_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                next_state    = S_DOM_SEP;
            end

            // ---- Domain separation ----
            S_DOM_SEP: begin
                next_state = S_DOM_SEP_LOAD;
            end

            S_DOM_SEP_LOAD: begin
                state_src_sel = 2'b10;
                do_dom_sep    = 1'b1;
                state_load    = 1'b1;
                next_state    = S_PROC_DATA;
            end

            // ---- Data processing ----
            S_PROC_DATA: begin
                dp_block_sel  = 2'b01;
                next_state    = S_DATA_LOAD_AND_START;
            end

            // ---- DATA: load + perm_start cùng cycle ----
            S_DATA_LOAD_AND_START: begin
                state_src_sel  = 2'b01;
                dp_block_sel   = 2'b01;
                dp_pad_enable  = data_last & ~extra_pad_block_needed;
                state_load     = 1'b1;
                data_out_valid = 1'b1;
                if (data_last & extra_pad_block_needed) begin
                    // Cần extra pad block — chạy perm trước
                    perm_rounds = DATA_ROUNDS;
                    perm_start  = 1'b1;
                    next_state  = S_DATA_PERM_W;
                end else if (data_last) begin
                    // Block cuối — không cần perm, đến finalize
                    perm_start  = 1'b0;
                    next_state  = S_FINALIZE;
                end else begin
                    perm_rounds = DATA_ROUNDS;
                    perm_start  = 1'b1;
                    next_state  = S_DATA_PERM_W;
                end
            end

            S_DATA_PERM_W: begin
                if (perm_done) next_state = S_POST_DATA_LOAD;
            end

            S_POST_DATA_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                if (data_last & extra_pad_block_needed)
                    next_state = S_DATA_EXTRA_PAD;
                else if (data_last)
                    next_state = S_FINALIZE;
                else
                    next_state = S_PROC_DATA;
            end

            // ---- Extra data pad block ----
            S_DATA_EXTRA_PAD: begin
                next_state = S_DATA_EXTRA_LOAD_AND_START;
            end

            S_DATA_EXTRA_LOAD_AND_START: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b01;
                dp_pad_enable = 1'b1;
                state_load    = 1'b1;
                perm_rounds   = DATA_ROUNDS;
                perm_start    = 1'b1;
                next_state    = S_DATA_EXTRA_PERM_W;
            end

            S_DATA_EXTRA_PERM_W: begin
                if (perm_done) next_state = S_POST_DATA_EXTRA_LOAD;
            end

            S_POST_DATA_EXTRA_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                next_state    = S_FINALIZE;
            end

            // ---- Finalization ----
            S_FINALIZE: begin
                next_state = S_FIN_LOAD_AND_START;
            end

            // ---- FIN: load + perm_start cùng cycle ----
            S_FIN_LOAD_AND_START: begin
                state_src_sel      = 2'b10;
                do_pre_fin_key_xor = 1'b1;
                state_load         = 1'b1;
                perm_rounds        = 4'd12;
                perm_start         = 1'b1;
                next_state         = S_FIN_PERM_W;
            end

            S_FIN_PERM_W: begin
                if (perm_done) next_state = S_POST_FIN_LOAD;
            end

            S_POST_FIN_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                next_state    = S_GEN_TAG;
            end

            // ---- Tag generation ----
            S_GEN_TAG: begin
                gen_tag    = 1'b1;
                next_state = S_WAIT_TAG_VALID;
            end

            S_WAIT_TAG_VALID: begin
                if (tag_gen_valid)
                    next_state = enc_dec ? S_CMP_TAG : S_DONE;
            end

            S_CMP_TAG: begin
                compare_tag = 1'b1;
                next_state  = S_DONE;
            end

            S_DONE: begin
                done       = 1'b1;
                busy       = 1'b0;
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule