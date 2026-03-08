// ============================================================
// Module: ascon_CONTROLLER  (FIXED v3)
//
// FIXES vs v2:
//   6. Added input port `extra_pad_block_needed` from DATAPATH.
//        When the last AD block or last data block is exactly
//        rate bytes (16 B), DATAPATH cannot fit the 0x01 pad
//        byte in that block.  The controller must absorb the
//        current (full) block unpadded, then inject one extra
//        all-zero block with pad_enable=1 so DATAPATH places
//        the 0x01 byte at position 0 of an empty block.
//
//        AD path:
//          S_AD_LOAD     : pad_enable = ad_last & !extra_pad_block_needed
//          S_POST_AD_LOAD: if (ad_last & extra_pad_block_needed)
//                            → S_AD_EXTRA_PAD (new state)
//                          elif ad_last → S_DOM_SEP
//                          else         → S_ABSORB_AD
//
//          S_AD_EXTRA_PAD      : absorb zero block with pad_enable=1
//          S_AD_EXTRA_PERM_START / _W / S_POST_AD_EXTRA_LOAD
//                              : run perm8, then → S_DOM_SEP
//
//        Data path: symmetric new states
//          S_DATA_EXTRA_PAD / _PERM_START / _PERM_W / S_POST_DATA_EXTRA_LOAD
//
// Prior fixes retained (v2):
//   1. S_FIN_LOAD: state_src_sel = 2'b10.
//   2. S_WAIT_TAG_VALID wait state before S_CMP_TAG.
//   3. Multi-block AD loop (ad_last).
//   4. Multi-block data loop (data_last).
//   5. b = 8 rounds for intermediate permutations.
// ============================================================
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

    // User outputs
    output reg  [127:0] data_out,
    output reg          data_out_valid,
    output reg  [127:0] tag_out,
    output reg          tag_valid,
    output reg          tag_match,
    output reg          done,
    output reg          busy,

    // INITIALIZATION
    output reg          load_key,
    output reg          load_nonce,
    output reg          init_start,

    // STATE REGISTER
    output reg  [1:0]   state_src_sel,
    output reg          state_load,

    // DATAPATH
    output reg          dp_pad_enable,
    output reg  [1:0]   dp_block_sel,
    output reg          dp_enc_dec,

    // PERMUTATION
    output reg  [3:0]   perm_rounds,
    output reg          perm_start,

    // TAG
    output reg          gen_tag,
    output reg          compare_tag,

    // Phase signals for CORE mux control
    output reg          do_post_init_key_xor,
    output reg          do_pre_fin_key_xor,
    output reg          do_dom_sep,

    // Sub-module status inputs
    input  wire         init_done,
    input  wire         perm_done,
    input  wire         tag_gen_valid,
    input  wire         tag_cmp_done,

    // NEW: full-block padding edge-case signal from DATAPATH
    input  wire         extra_pad_block_needed
);

    // ----------------------------------------------------------------
    // State encoding
    // ----------------------------------------------------------------
    localparam [5:0]
        S_IDLE                   = 6'd0,
        S_LOAD_KEY               = 6'd1,
        S_LOAD_NONCE             = 6'd2,
        S_INIT                   = 6'd3,
        S_INIT_LOAD              = 6'd4,
        S_INIT_PERM_START        = 6'd5,
        S_INIT_PERM_W            = 6'd6,
        S_POST_INIT_LOAD         = 6'd7,
        S_ABSORB_AD              = 6'd8,
        S_AD_LOAD                = 6'd9,
        S_AD_PERM_START          = 6'd10,
        S_AD_PERM_W              = 6'd11,
        S_POST_AD_LOAD           = 6'd12,
        S_DOM_SEP                = 6'd13,
        S_DOM_SEP_LOAD           = 6'd14,
        S_PROC_DATA              = 6'd15,
        S_DATA_LOAD              = 6'd16,
        S_DATA_PERM_START        = 6'd17,
        S_DATA_PERM_W            = 6'd18,
        S_POST_DATA_LOAD         = 6'd19,
        S_FINALIZE               = 6'd20,
        S_FIN_LOAD               = 6'd21,
        S_FIN_PERM_START         = 6'd22,
        S_FIN_PERM_W             = 6'd23,
        S_POST_FIN_LOAD          = 6'd24,
        S_GEN_TAG                = 6'd25,
        S_WAIT_TAG_VALID         = 6'd26,
        S_CMP_TAG                = 6'd27,
        S_DONE                   = 6'd28,
        // NEW: extra pad block states for AD
        S_AD_EXTRA_PAD           = 6'd29,
        S_AD_EXTRA_PERM_START    = 6'd30,
        S_AD_EXTRA_PERM_W        = 6'd31,
        S_POST_AD_EXTRA_LOAD     = 6'd32,
        // NEW: extra pad block states for data
        S_DATA_EXTRA_PAD         = 6'd33,
        S_DATA_EXTRA_PERM_START  = 6'd34,
        S_DATA_EXTRA_PERM_W      = 6'd35,
        S_POST_DATA_EXTRA_LOAD   = 6'd36;

    reg [5:0] state, next_state;

    localparam [3:0] DATA_ROUNDS = 4'd8;

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // ----------------------------------------------------------------
    // Next-state + output logic (combinational)
    // ----------------------------------------------------------------
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
                next_state = S_INIT_LOAD;
            end

            S_INIT_LOAD: begin
                state_src_sel = 2'b00;
                state_load    = 1'b1;
                next_state    = S_INIT_PERM_START;
            end

            S_INIT_PERM_START: begin
                perm_rounds = 4'd12;
                perm_start  = 1'b1;
                next_state  = S_INIT_PERM_W;
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
                next_state   = S_AD_LOAD;
            end

            S_AD_LOAD: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b00;
                // Only set pad_enable when last block AND it fits
                dp_pad_enable = ad_last & ~extra_pad_block_needed;
                state_load    = 1'b1;
                next_state    = S_AD_PERM_START;
            end

            S_AD_PERM_START: begin
                perm_rounds = DATA_ROUNDS;
                perm_start  = 1'b1;
                next_state  = S_AD_PERM_W;
            end

            S_AD_PERM_W: begin
                if (perm_done) next_state = S_POST_AD_LOAD;
            end

            S_POST_AD_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                // Decide next step
                if (ad_last & extra_pad_block_needed)
                    next_state = S_AD_EXTRA_PAD;    // need extra pad block
                else if (ad_last)
                    next_state = S_DOM_SEP;          // last block absorbed, done
                else
                    next_state = S_ABSORB_AD;        // more AD blocks
            end

            // ---- Extra AD pad block (full-block edge case) ----
            // Inject all-zero block; DATAPATH places 0x01 at byte 0
            S_AD_EXTRA_PAD: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b00;
                dp_pad_enable = 1'b1;   // pad a zero-length "block"
                state_load    = 1'b1;
                next_state    = S_AD_EXTRA_PERM_START;
            end

            S_AD_EXTRA_PERM_START: begin
                perm_rounds = DATA_ROUNDS;
                perm_start  = 1'b1;
                next_state  = S_AD_EXTRA_PERM_W;
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
                dp_pad_enable = data_last;
                next_state    = S_DATA_LOAD;
            end

            S_DATA_LOAD: begin
                state_src_sel  = 2'b01;
                dp_block_sel   = 2'b01;
                // Only pad when last block AND it fits in this block
                dp_pad_enable  = data_last & ~extra_pad_block_needed;
                state_load     = 1'b1;
                data_out_valid = 1'b1;
                if (data_last & extra_pad_block_needed)
                    next_state = S_DATA_PERM_START; // run perm, then extra pad
                else if (data_last)
                    next_state = S_FINALIZE;
                else
                    next_state = S_DATA_PERM_START;
            end

            S_DATA_PERM_START: begin
                perm_rounds = DATA_ROUNDS;
                perm_start  = 1'b1;
                next_state  = S_DATA_PERM_W;
            end

            S_DATA_PERM_W: begin
                if (perm_done) next_state = S_POST_DATA_LOAD;
            end

            S_POST_DATA_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                // Check if we came from the last full data block
                if (data_last & extra_pad_block_needed)
                    next_state = S_DATA_EXTRA_PAD;
                else if (data_last)
                    next_state = S_FINALIZE;
                else
                    next_state = S_PROC_DATA;
            end

            // ---- Extra data pad block (full-block edge case) ----
            S_DATA_EXTRA_PAD: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b01;
                dp_pad_enable = 1'b1;   // pad a zero-length "block"
                state_load    = 1'b1;
                next_state    = S_DATA_EXTRA_PERM_START;
            end

            S_DATA_EXTRA_PERM_START: begin
                perm_rounds = DATA_ROUNDS;
                perm_start  = 1'b1;
                next_state  = S_DATA_EXTRA_PERM_W;
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
                next_state = S_FIN_LOAD;
            end

            S_FIN_LOAD: begin
                state_src_sel      = 2'b10;   // FIX v2: was 2'b01
                do_pre_fin_key_xor = 1'b1;
                state_load         = 1'b1;
                next_state         = S_FIN_PERM_START;
            end

            S_FIN_PERM_START: begin
                perm_rounds = 4'd12;
                perm_start  = 1'b1;
                next_state  = S_FIN_PERM_W;
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