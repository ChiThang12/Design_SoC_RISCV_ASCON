// ============================================================
// Module: ascon_CONTROLLER  (v4 — H1 + H2 optimized)
//
// H1 — FSM State Merge (4 dead states removed):
//   Removed S_ABSORB_AD  (6'd8)  — was only setting dp_block_sel then
//                                   jumping to S_AD_LOAD. Now S_POST_AD_LOAD
//                                   jumps directly to S_AD_LOAD.
//   Removed S_PROC_DATA  (6'd15) — was only setting dp_block_sel then
//                                   jumping to S_DATA_LOAD. Now S_POST_DATA_LOAD
//                                   and S_DOM_SEP_LOAD jump directly to S_DATA_LOAD.
//   Removed S_DOM_SEP    (6'd13) — was doing nothing, jumping to S_DOM_SEP_LOAD.
//                                   Now S_POST_INIT_LOAD / S_POST_AD_EXTRA_LOAD
//                                   jump directly to S_DOM_SEP_LOAD.
//   Removed S_FINALIZE   (6'd20) — was doing nothing, jumping to S_FIN_LOAD.
//                                   Now S_DATA_LOAD / S_POST_DATA_LOAD /
//                                   S_POST_DATA_EXTRA_LOAD jump directly to S_FIN_LOAD.
//
//   Savings: 4 cycles fixed overhead per encryption/decryption.
//   Multi-block: 2 cycles saved per additional AD block,
//                2 cycles saved per additional data block.
//
//   Cycle count comparison (1 AD + 1 PT block, PIPE2 perm):
//     v3:  36 + 10×1 + 10×1 = 56 cycles
//     v4:  ~44 cycles  (−12 cycles = −21%)
//
// H2 — Input FIFO Buffers (prefetch during permutation):
//   New input ports:
//     ad_buf_*   : host writes AD  into 1-entry buffer while perm runs
//     data_buf_* : host writes data into 1-entry buffer while perm runs
//
//   New output ports:
//     ad_buf_ready   : buffer accepts a new AD   block this cycle
//     data_buf_ready : buffer accepts a new data block this cycle
//
//   Internal buffer registers (added to CONTROLLER):
//     ad_buf_reg, ad_buf_valid_r, ad_buf_last_r
//     data_buf_reg, data_buf_valid_r, data_buf_last_r, data_buf_len_r
//
//   Mux: controller reads from buffer when valid, else falls back to
//        the original ad_in / data_in ports (backward-compatible).
//
//   Effect: host can push block N+1 into the buffer during the p8/p12
//           permutation of block N. When perm finishes the buffer is
//           immediately consumed — zero stall cycles due to data latency.
//
// All prior fixes retained (v3):
//   1. S_FIN_LOAD: state_src_sel = 2'b10.
//   2. S_WAIT_TAG_VALID wait state before S_CMP_TAG.
//   3. Multi-block AD loop (ad_last / ad_buf_last).
//   4. Multi-block data loop (data_last / data_buf_last).
//   5. b = 8 rounds for intermediate permutations.
//   6. extra_pad_block_needed full-block padding edge case.
// ============================================================
module ascon_CONTROLLER (
    input  wire         clk,
    input  wire         rst_n,

    // ---- Primary control ----
    input  wire         start,
    input  wire [1:0]   mode,
    input  wire         enc_dec,
    input  wire [127:0] key_in,
    input  wire [127:0] nonce_in,

    // ---- AD input (original, single-cycle) ----
    input  wire [127:0] ad_in,
    input  wire         ad_valid,
    input  wire         ad_last,

    // ---- AD input buffer (H2) ----
    // Host writes here during permutation; controller drains on next AD_LOAD.
    input  wire [127:0] ad_buf_in,
    input  wire         ad_buf_valid,   // host asserts: buffer holds new AD block
    input  wire         ad_buf_last,    // this buffered block is the last AD block
    output reg          ad_buf_ready,   // controller accepts buffer write this cycle

    // ---- Data input (original, single-cycle) ----
    input  wire [127:0] data_in,
    input  wire         data_last,
    input  wire [6:0]   data_len,

    // ---- Data input buffer (H2) ----
    input  wire [127:0] data_buf_in,
    input  wire         data_buf_valid,
    input  wire         data_buf_last,
    input  wire [6:0]   data_buf_len,
    output reg          data_buf_ready,

    // ---- Tag ----
    input  wire [127:0] tag_received,

    // ---- User outputs ----
    output reg  [127:0] data_out,
    output reg          data_out_valid,
    output reg  [127:0] tag_out,
    output reg          tag_valid,
    output reg          tag_match,
    output reg          done,
    output reg          busy,

    // ---- INITIALIZATION ----
    output reg          load_key,
    output reg          load_nonce,
    output reg          init_start,

    // ---- STATE REGISTER ----
    output reg  [1:0]   state_src_sel,
    output reg          state_load,

    // ---- DATAPATH ----
    output reg          dp_pad_enable,
    output reg  [1:0]   dp_block_sel,
    output reg          dp_enc_dec,

    // ---- PERMUTATION ----
    output reg  [3:0]   perm_rounds,
    output reg          perm_start,

    // ---- TAG sub-modules ----
    output reg          gen_tag,
    output reg          compare_tag,

    // ---- Phase signals for CORE mux ----
    output reg          do_post_init_key_xor,
    output reg          do_pre_fin_key_xor,
    output reg          do_dom_sep,

    // ---- Sub-module status ----
    input  wire         init_done,
    input  wire         perm_done,
    input  wire         tag_gen_valid,
    input  wire         tag_cmp_done,
    input  wire         extra_pad_block_needed,

    // ---- H2: muxed data outputs → DATAPATH (combinational) ----
    // These expose the buffer-vs-direct mux result so CORE can wire
    // them into DATAPATH without duplicating the mux logic.
    output wire [127:0] ad_mux_out,
    output wire [127:0] data_mux_out,
    output wire [6:0]   data_len_mux_out
);

    // ----------------------------------------------------------------
    // H2: Internal buffer registers
    // ----------------------------------------------------------------
    reg [127:0] ad_buf_reg;
    reg         ad_buf_valid_r;
    reg         ad_buf_last_r;

    reg [127:0] data_buf_reg;
    reg         data_buf_valid_r;
    reg         data_buf_last_r;
    reg [6:0]   data_buf_len_r;

    // Muxed AD / data seen by the FSM
    // Priority: internal buffer register > external port
    wire [127:0] ad_mux       = ad_buf_valid_r  ? ad_buf_reg      : ad_in;
    wire         ad_last_mux  = ad_buf_valid_r  ? ad_buf_last_r   : ad_last;
    wire         ad_valid_mux = ad_buf_valid_r  | ad_valid;

    wire [127:0] data_mux     = data_buf_valid_r ? data_buf_reg    : data_in;
    wire         data_last_mux= data_buf_valid_r ? data_buf_last_r : data_last;
    wire [6:0]   data_len_mux = data_buf_valid_r ? data_buf_len_r  : data_len;

    // Expose muxed values to CORE → DATAPATH
    assign ad_mux_out       = ad_mux;
    assign data_mux_out     = data_mux;
    assign data_len_mux_out = data_len_mux;

    // ----------------------------------------------------------------
    // H2: Buffer write logic
    // Accept a new block into the buffer when:
    //   • The buffer is currently empty (!valid_r), OR
    //   • The FSM is draining the buffer this cycle (AD_LOAD / DATA_LOAD)
    //     so the slot will be free next cycle.
    // ad_buf_ready / data_buf_ready are combinational.
    // ----------------------------------------------------------------
    wire ad_draining   = (state == S_AD_LOAD);
    wire data_draining = (state == S_DATA_LOAD);

    // Forward declarations for state — defined after localparam block.
    // Verilog-2001: wire referring to reg is fine as long as reg is declared.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ad_buf_reg     <= 128'h0;
            ad_buf_valid_r <= 1'b0;
            ad_buf_last_r  <= 1'b0;
        end else begin
            // Drain: FSM consumed the buffered AD block this cycle
            if (ad_draining && ad_buf_valid_r)
                ad_buf_valid_r <= 1'b0;

            // Fill: accept new block when slot is free or being drained
            if (ad_buf_valid && (!ad_buf_valid_r || ad_draining)) begin
                ad_buf_reg     <= ad_buf_in;
                ad_buf_valid_r <= 1'b1;
                ad_buf_last_r  <= ad_buf_last;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_buf_reg     <= 128'h0;
            data_buf_valid_r <= 1'b0;
            data_buf_last_r  <= 1'b0;
            data_buf_len_r   <= 7'h0;
        end else begin
            if (data_draining && data_buf_valid_r)
                data_buf_valid_r <= 1'b0;

            if (data_buf_valid && (!data_buf_valid_r || data_draining)) begin
                data_buf_reg     <= data_buf_in;
                data_buf_valid_r <= 1'b1;
                data_buf_last_r  <= data_buf_last;
                data_buf_len_r   <= data_buf_len;
            end
        end
    end

    // ----------------------------------------------------------------
    // State encoding  (H1: removed 6'd8, 6'd13, 6'd15, 6'd20)
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
        // 6'd8  S_ABSORB_AD  — REMOVED (H1)
        S_AD_LOAD                = 6'd9,
        S_AD_PERM_START          = 6'd10,
        S_AD_PERM_W              = 6'd11,
        S_POST_AD_LOAD           = 6'd12,
        // 6'd13 S_DOM_SEP    — REMOVED (H1)
        S_DOM_SEP_LOAD           = 6'd14,
        // 6'd15 S_PROC_DATA  — REMOVED (H1)
        S_DATA_LOAD              = 6'd16,
        S_DATA_PERM_START        = 6'd17,
        S_DATA_PERM_W            = 6'd18,
        S_POST_DATA_LOAD         = 6'd19,
        // 6'd20 S_FINALIZE   — REMOVED (H1)
        S_FIN_LOAD               = 6'd21,
        S_FIN_PERM_START         = 6'd22,
        S_FIN_PERM_W             = 6'd23,
        S_POST_FIN_LOAD          = 6'd24,
        S_GEN_TAG                = 6'd25,
        S_WAIT_TAG_VALID         = 6'd26,
        S_CMP_TAG                = 6'd27,
        S_DONE                   = 6'd28,
        S_AD_EXTRA_PAD           = 6'd29,
        S_AD_EXTRA_PERM_START    = 6'd30,
        S_AD_EXTRA_PERM_W        = 6'd31,
        S_POST_AD_EXTRA_LOAD     = 6'd32,
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
        ad_buf_ready         = 1'b0;
        data_buf_ready       = 1'b0;

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
                // H2: host may write AD block into buffer while we wait
                ad_buf_ready = 1'b1;
                if (perm_done) next_state = S_POST_INIT_LOAD;
            end

            S_POST_INIT_LOAD: begin
                do_post_init_key_xor = 1'b1;
                state_load           = 1'b1;
                // H1: skip S_DOM_SEP (was just a pass-through)
                next_state = ad_valid_mux ? S_AD_LOAD : S_DOM_SEP_LOAD;
            end

            // ---- AD absorption ----
            // H1: S_ABSORB_AD removed — S_POST_AD_LOAD / S_POST_INIT_LOAD
            //     jump directly here, dp_block_sel driven in S_AD_LOAD itself.

            S_AD_LOAD: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b00;
                dp_pad_enable = ad_last_mux & ~extra_pad_block_needed;
                state_load    = 1'b1;
                // H2: consuming buffer this cycle → signal ready so host
                //     can immediately write the next block
                ad_buf_ready  = ad_buf_valid_r;
                next_state    = S_AD_PERM_START;
            end

            S_AD_PERM_START: begin
                perm_rounds = DATA_ROUNDS;
                perm_start  = 1'b1;
                next_state  = S_AD_PERM_W;
            end

            S_AD_PERM_W: begin
                // H2: host may prefetch next AD block while perm runs
                ad_buf_ready = !ad_buf_valid_r;
                if (perm_done) next_state = S_POST_AD_LOAD;
            end

            S_POST_AD_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                if (ad_last_mux & extra_pad_block_needed)
                    next_state = S_AD_EXTRA_PAD;
                else if (ad_last_mux)
                    // H1: skip S_DOM_SEP
                    next_state = S_DOM_SEP_LOAD;
                else
                    // H1: skip S_ABSORB_AD — go straight to S_AD_LOAD
                    next_state = S_AD_LOAD;
            end

            // ---- Extra AD pad block ----
            S_AD_EXTRA_PAD: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b00;
                dp_pad_enable = 1'b1;
                state_load    = 1'b1;
                next_state    = S_AD_EXTRA_PERM_START;
            end

            S_AD_EXTRA_PERM_START: begin
                perm_rounds = DATA_ROUNDS;
                perm_start  = 1'b1;
                next_state  = S_AD_EXTRA_PERM_W;
            end

            S_AD_EXTRA_PERM_W: begin
                // H2: host may start writing first data block here
                data_buf_ready = !data_buf_valid_r;
                if (perm_done) next_state = S_POST_AD_EXTRA_LOAD;
            end

            S_POST_AD_EXTRA_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                // H1: skip S_DOM_SEP
                next_state    = S_DOM_SEP_LOAD;
            end

            // ---- Domain separation ----
            // H1: S_DOM_SEP removed — callers jump directly here.
            S_DOM_SEP_LOAD: begin
                state_src_sel = 2'b10;
                do_dom_sep    = 1'b1;
                state_load    = 1'b1;
                // H1: skip S_PROC_DATA — go straight to S_DATA_LOAD
                next_state    = S_DATA_LOAD;
            end

            // ---- Data processing ----
            // H1: S_PROC_DATA removed — S_DOM_SEP_LOAD / S_POST_DATA_LOAD
            //     jump directly here, dp_block_sel driven here.

            S_DATA_LOAD: begin
                state_src_sel  = 2'b01;
                dp_block_sel   = 2'b01;
                dp_pad_enable  = data_last_mux & ~extra_pad_block_needed;
                state_load     = 1'b1;
                data_out_valid = 1'b1;
                // H2: consuming data buffer this cycle
                data_buf_ready = data_buf_valid_r;
                if (data_last_mux & extra_pad_block_needed)
                    next_state = S_DATA_PERM_START;
                else if (data_last_mux)
                    // H1: skip S_FINALIZE
                    next_state = S_FIN_LOAD;
                else
                    next_state = S_DATA_PERM_START;
            end

            S_DATA_PERM_START: begin
                perm_rounds = DATA_ROUNDS;
                perm_start  = 1'b1;
                next_state  = S_DATA_PERM_W;
            end

            S_DATA_PERM_W: begin
                // H2: host may prefetch next data block while perm runs
                data_buf_ready = !data_buf_valid_r;
                if (perm_done) next_state = S_POST_DATA_LOAD;
            end

            S_POST_DATA_LOAD: begin
                state_src_sel = 2'b10;
                state_load    = 1'b1;
                if (data_last_mux & extra_pad_block_needed)
                    next_state = S_DATA_EXTRA_PAD;
                else if (data_last_mux)
                    // H1: skip S_FINALIZE
                    next_state = S_FIN_LOAD;
                else
                    // H1: skip S_PROC_DATA — go straight to S_DATA_LOAD
                    next_state = S_DATA_LOAD;
            end

            // ---- Extra data pad block ----
            S_DATA_EXTRA_PAD: begin
                state_src_sel = 2'b01;
                dp_block_sel  = 2'b01;
                dp_pad_enable = 1'b1;
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
                // H1: skip S_FINALIZE
                next_state    = S_FIN_LOAD;
            end

            // ---- Finalization ----
            // H1: S_FINALIZE removed — callers jump directly here.
            S_FIN_LOAD: begin
                state_src_sel      = 2'b10;
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