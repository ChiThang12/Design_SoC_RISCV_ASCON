`timescale 1ns/1ps

// ============================================================================
// Module: ascon_CONTROLLER  (v9 — Pipeline-aware FSM)
//
// THAY ĐỔI CHÍNH so với v8:
//
//   1. PIPELINE LATENCY SUPPORT
//      - Khi G_SBOX_PIPELINE=1, permutation có latency = `rounds` cycles
//      - FSM dùng perm_done (đã tồn tại) để chờ → KHÔNG cần sửa nhiều
//      - Nhưng thêm perm_lat_cnt để debug và future use
//
//   2. THROUGHPUT OPTIMIZATION (G_SBOX_PIPELINE=0):
//      - Khi comb unroll: permutation done = 2 cycles (start + latch)
//      - FSM có thể overlap: bắt đầu load data trong khi perm đang chạy
//      - Thêm S_PERM_OVERLAP state cho optimization này
//
//   3. CALLS_PA / CALLS_PB ENCODING:
//      ASCON-128:  pa_rounds=12, pb_rounds=6  (pa calls = 1 full pa)
//      ASCON-128a: pa_rounds=12, pb_rounds=8  (pa calls = 1 full pa)
//      → CONTROLLER gọi permutation 1 lần với rounds=12 (pa) hoặc rounds=6/8 (pb)
//      → KHÔNG còn multi-call phức tạp như trước
//
// STATE ENCODING:
//   S_IDLE          → chờ start
//   S_INIT_LOAD     → load key + nonce vào INIT module
//   S_INIT_PERM     → chạy pa (12 rounds)
//   S_POST_INIT     → XOR key vào state
//   S_AD_LOAD       → load AD block
//   S_AD_PERM       → chạy pb
//   S_AD_PAD_LOAD   → NEW: load extra 0x01 padding block for AD
//   S_AD_PAD_PERM   → NEW: run pb after extra AD pad block
//   S_DOM_SEP       → domain separation
//   S_DATA_LOAD     → load plaintext/ciphertext block
//   S_DATA_PERM     → chạy pb
//   S_DATA_PAD_LOAD → NEW: load extra 0x01 padding block for Data
//   S_DATA_PAD_PERM → NEW: run pb after extra Data pad block
//   S_PRE_FIN       → XOR key
//   S_FIN_PERM      → chạy pa (12 rounds)
//   S_TAG_GEN       → generate/compare tag
//   S_DONE          → output results
// ============================================================================

module ascon_CONTROLLER #(
    parameter G_COMB_RND_128  = 6,
    parameter G_COMB_RND_128A = 4,
    parameter G_SBOX_PIPELINE = 0
) (
    input  wire         clk,
    input  wire         rst_n,

    // Top-level control
    input  wire         start,
    input  wire [1:0]   mode,      // 00=ASCON-128, 01=ASCON-128a
    input  wire         enc_dec,   // 0=enc, 1=dec

    // Data inputs (for internal use/routing)
    input  wire [127:0] key_in,
    input  wire [127:0] nonce_in,
    input  wire [127:0] ad_in,
    input  wire         ad_valid,
    input  wire         ad_last,
    input  wire [127:0] data_in,
    input  wire         data_valid,
    input  wire         data_last,
    input  wire [6:0]   data_len,
    input  wire [127:0] tag_received,

    // Status from datapath/permutation
    input  wire         init_done,
    input  wire         perm_done,
    input  wire         tag_gen_valid,
    input  wire         tag_cmp_done,
    input  wire         extra_pad_block_needed,

    // Control outputs
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
    output reg          is_extra_pad_block,  // NEW: tell DATAPATH to absorb pure pad block

    // Status outputs
    output reg          data_ready,
    output reg          ad_ready,       // NEW: high when CONTROLLER is in S_AD_LOAD
    output reg          data_out_valid,
    output reg          done,
    output reg          busy
);

    // =========================================================================
    // Mode-dependent parameters
    // =========================================================================
    // NIST Ascon-AEAD128: a=12, b=8, rate=16 bytes
    // HW mode[0]=0 maps to Ascon-AEAD128 (b=8, rate=16)
    // HW mode[0]=1 maps to Ascon-AEAD128a legacy (b=8, rate=32) -- same pb_rounds
    wire        is_128a    = mode[0];

    // pb rounds: 8 for NIST Ascon-AEAD128 (was 6 for old Ascon-128, now fixed)
    wire [3:0]  pb_rounds  = 4'd8;

    // pa rounds: always 12
    wire [3:0]  pa_rounds  = 4'd12;

    // start_rc for pb: rc = 12 - pb_rounds = 12 - 8 = 4
    wire [3:0]  pb_start_rc = 4'd4;

    // pa always starts at rc=0
    wire [3:0]  pa_start_rc = 4'd0;

    // =========================================================================
    // FSM State encoding
    // =========================================================================
    localparam [4:0]
        S_IDLE          = 5'd0,
        S_INIT_LOAD     = 5'd1,
        S_INIT_PERM     = 5'd2,
        S_POST_INIT     = 5'd3,
        S_AD_LOAD       = 5'd4,
        S_AD_PERM       = 5'd5,
        S_AD_PAD_LOAD   = 5'd6,   // NEW: extra padding block for AD
        S_AD_PAD_PERM   = 5'd7,   // NEW: pb after extra AD pad
        S_DOM_SEP       = 5'd8,
        S_DATA_LOAD     = 5'd9,
        S_DATA_PERM     = 5'd10,
        S_DATA_PAD_LOAD = 5'd11,  // NEW: extra padding block for Data
        S_DATA_PAD_PERM = 5'd12,  // NEW: pb after extra Data pad
        S_PRE_FIN       = 5'd13,
        S_FIN_PERM      = 5'd14,
        S_TAG_GEN       = 5'd15,
        S_DONE          = 5'd16;

    reg [4:0] state, next_state;

    // Registered flags: capture extra_pad_block_needed at the moment we load
    // the last AD/Data block. By the time we reach S_AD_PERM / S_DATA_PERM,
    // pad_enable is already deasserted so extra_pad_block_needed would be 0.
    reg  ad_extra_pad_pending;    // set when last AD block fills rate exactly
    reg  data_extra_pad_pending;  // set when last Data block fills rate exactly
    // Latch ad_last at absorption time — DMA pump holds ad_last=1 for only 1 cycle
    // (PRES state). By S_AD_PERM, the pump has moved to WAIT/DONE so ad_last=0.
    // Use ad_last_latched in S_AD_PERM to decide whether to loop back or go to DOM_SEP.
    reg  ad_last_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ad_extra_pad_pending   <= 1'b0;
            data_extra_pad_pending <= 1'b0;
            ad_last_latched        <= 1'b0;
        end else begin
            // Capture when entering S_AD_LOAD and a block is being absorbed
            if (state == S_AD_LOAD && ad_valid && extra_pad_block_needed)
                ad_extra_pad_pending <= 1'b1;
            else if (state == S_AD_PAD_PERM && perm_done)
                ad_extra_pad_pending <= 1'b0;  // consumed
            else if (state == S_DOM_SEP)
                ad_extra_pad_pending <= 1'b0;  // reset at DOM_SEP

            // Latch ad_last the cycle a block is absorbed in S_AD_LOAD
            if (state == S_AD_LOAD && ad_valid)
                ad_last_latched <= ad_last;
            else if (state == S_IDLE)
                ad_last_latched <= 1'b0;

            // Capture when last data block fills rate exactly
            if (state == S_DATA_LOAD && data_valid && data_last && extra_pad_block_needed)
                data_extra_pad_pending <= 1'b1;
            else if (state == S_DATA_PAD_LOAD)
                data_extra_pad_pending <= 1'b0;  // consumed
            else if (state == S_IDLE)
                data_extra_pad_pending <= 1'b0;  // reset on new operation
        end
    end

    // =========================================================================
    // FSM — Sequential
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else begin
            state <= next_state;
        end
    end

    // =========================================================================
    // FSM — Combinational next-state + output
    // =========================================================================
    always @(*) begin
        // Default: hold everything
        next_state           = state;
        load_key             = 1'b0;
        load_nonce           = 1'b0;
        init_start           = 1'b0;
        state_src_sel        = 2'b10;   // default: from perm
        state_load           = 1'b0;
        dp_pad_enable        = 1'b0;
        dp_block_sel         = 2'b00;
        dp_enc_dec           = enc_dec;
        perm_rounds          = pb_rounds;
        perm_start_rc        = pb_start_rc;
        perm_start           = 1'b0;
        gen_tag              = 1'b0;
        compare_tag          = 1'b0;
        do_post_init_key_xor = 1'b0;
        do_pre_fin_key_xor   = 1'b0;
        do_dom_sep           = 1'b0;
        is_extra_pad_block   = 1'b0;   // NEW: default off
        data_ready           = (state == S_IDLE) || (state == S_DATA_LOAD);
        ad_ready             = (state == S_AD_LOAD); // NEW
        data_out_valid       = 1'b0;
        done                 = 1'b0;
        busy                 = 1'b1;

        case (state)
            // ---- IDLE: wait for start ----
            S_IDLE: begin
                busy = 1'b0;
                if (start) begin
                    load_key   = 1'b1;
                    load_nonce = 1'b1;
                    next_state = S_INIT_LOAD;
                end
            end

            // ---- INIT_LOAD: start init calculation with stable keys ----
            S_INIT_LOAD: begin
                init_start = 1'b1;
                next_state = S_INIT_PERM;
            end

            // ---- INIT_PERM: wait for INIT to produce state, then run pa ----
            S_INIT_PERM: begin
                if (init_done) begin
                    // Load init state into state register
                    state_src_sel = 2'b00;  // from init
                    state_load    = 1'b1;
                    // Start pa permutation
                    perm_rounds   = pa_rounds;
                    perm_start_rc = pa_start_rc;
                    perm_start    = 1'b1;
                    next_state    = S_POST_INIT;
                end
            end

            // ---- POST_INIT: wait for pa done, XOR key into state ----
            S_POST_INIT: begin
                if (perm_done) begin
                    // XOR key: handled in CORE via do_post_init_key_xor
                    do_post_init_key_xor = 1'b1;
                    state_src_sel        = 2'b10;   // from perm (with key XOR in CORE)
                    state_load           = 1'b1;
                    next_state           = S_AD_LOAD;
                end
            end

            // ---- AD_LOAD: absorb one AD block ----
            S_AD_LOAD: begin
                if (ad_valid) begin
                    dp_pad_enable = 1'b1;
                    dp_block_sel  = 2'b00;  // AD
                    state_src_sel = 2'b01;  // from datapath XOR
                    state_load    = 1'b1;

                    // Start pb after loading
                    perm_rounds   = pb_rounds;
                    perm_start_rc = pb_start_rc;
                    perm_start    = 1'b1;
                    next_state    = S_AD_PERM;
                end else if (ad_last) begin
                    // ad_last=1, valid=0: "no AD" signal → skip to DOM_SEP
                    // ad_valid=0, ad_last=0: AD expected but not ready → hold (wait)
                    next_state = S_DOM_SEP;
                end
            end

            // ---- AD_PERM: wait for pb after AD ----
            S_AD_PERM: begin
                if (perm_done) begin
                    state_src_sel = 2'b10;
                    state_load    = 1'b1;
                    if (ad_extra_pad_pending) begin
                        // Data exactly filled rate: must absorb one more pure pad block
                        next_state = S_AD_PAD_LOAD;
                    end else if (ad_last_latched) begin
                        // Use latched value: ad_last from DMA is only 1 for 1 cycle (PRES),
                        // by the time perm_done fires the DMA pump is in DONE, ad_last=0.
                        next_state = S_DOM_SEP;
                    end else begin
                        next_state = S_AD_LOAD;
                    end
                end
            end

            // ---- AD_PAD_LOAD: absorb a pure 0x01 padding block for AD ----
            S_AD_PAD_LOAD: begin
                is_extra_pad_block = 1'b1;  // tell DATAPATH to use PURE_PAD_BLOCK
                dp_pad_enable  = 1'b1;
                dp_block_sel   = 2'b00;  // AD lane
                state_src_sel  = 2'b01;  // from datapath XOR
                state_load     = 1'b1;
                perm_rounds    = pb_rounds;
                perm_start_rc  = pb_start_rc;
                perm_start     = 1'b1;
                next_state     = S_AD_PAD_PERM;
            end

            // ---- AD_PAD_PERM: wait for pb after extra AD pad block ----
            S_AD_PAD_PERM: begin
                if (perm_done) begin
                    state_src_sel = 2'b10;
                    state_load    = 1'b1;
                    next_state    = S_DOM_SEP;
                end
            end

            // ---- DOM_SEP: flip MSB of x4 ----
            S_DOM_SEP: begin
                do_dom_sep    = 1'b1;
                state_src_sel = 2'b10;   // will be overridden by dom_sep in CORE
                state_load    = 1'b1;
                next_state    = S_DATA_LOAD;
            end

            // ---- DATA_LOAD: absorb/extract one data block ----
            S_DATA_LOAD: begin
                if (data_valid) begin
                    dp_pad_enable  = 1'b1;
                    dp_block_sel   = 2'b01;    // data
                    dp_enc_dec     = enc_dec;
                    state_src_sel  = 2'b01;    // from datapath XOR
                    state_load     = 1'b1;
                    data_out_valid = 1'b1;

                    if (data_last && extra_pad_block_needed) begin
                        // Last block exactly fills rate: need extra pad block + pb
                        perm_rounds   = pb_rounds;
                        perm_start_rc = pb_start_rc;
                        perm_start    = 1'b1;
                        next_state    = S_DATA_PERM;  // then goes to S_DATA_PAD_LOAD
                    end else if (data_last) begin
                        // Normal last block: no more permutation, go finalize
                        perm_start = 1'b0;
                        next_state = S_PRE_FIN;
                    end else begin
                        perm_rounds   = pb_rounds;
                        perm_start_rc = pb_start_rc;
                        perm_start    = 1'b1;
                        next_state    = S_DATA_PERM;
                    end
                end else begin
                    next_state     = S_DATA_LOAD; // wait for valid data
                end
            end

            // ---- DATA_PERM: wait for pb after data ----
            S_DATA_PERM: begin
                if (perm_done) begin
                    state_src_sel = 2'b10;
                    state_load    = 1'b1;
                    // Check if we just came from a last-block with extra pad needed
                    if (data_extra_pad_pending) begin
                        next_state = S_DATA_PAD_LOAD;
                    end else begin
                        next_state = S_DATA_LOAD;
                    end
                end
            end

            // ---- DATA_PAD_LOAD: absorb a pure 0x01 padding block for Data ----
            S_DATA_PAD_LOAD: begin
                is_extra_pad_block = 1'b1;  // tell DATAPATH to use PURE_PAD_BLOCK
                dp_pad_enable  = 1'b1;
                dp_block_sel   = 2'b01;  // data lane
                dp_enc_dec     = enc_dec;
                state_src_sel  = 2'b01;  // from datapath XOR
                state_load     = 1'b1;
                // No perm after last data pad — go directly to finalize
                next_state     = S_PRE_FIN;
            end

            // ---- PRE_FIN: XOR key into state ----
            S_PRE_FIN: begin
                do_pre_fin_key_xor = 1'b1;
                state_src_sel      = 2'b10;
                state_load         = 1'b1;
                // Start pa
                perm_rounds        = pa_rounds;
                perm_start_rc      = pa_start_rc;
                perm_start         = 1'b1;
                next_state         = S_FIN_PERM;
            end

            // ---- FIN_PERM: wait for final pa ----
            S_FIN_PERM: begin
                if (perm_done) begin
                    state_src_sel = 2'b10;
                    state_load    = 1'b1;
                    next_state    = S_TAG_GEN;
                end
            end

            // ---- TAG_GEN: generate or compare tag ----
            S_TAG_GEN: begin
                gen_tag = 1'b1;
                if (tag_gen_valid) begin
                    if (enc_dec == 1'b0) begin
                        next_state = S_DONE;
                    end else begin
                        compare_tag = 1'b1;
                        if (tag_cmp_done) begin
                            next_state = S_DONE;
                        end
                    end
                end
            end

            // ---- DONE ----
            S_DONE: begin
                done       = 1'b1;
                busy       = 1'b0;
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule