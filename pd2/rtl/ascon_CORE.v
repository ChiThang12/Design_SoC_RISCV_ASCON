`timescale 1ns/1ps

// ============================================================
// Module: ascon_CORE  (v12 — fix mode_int: bỏ đảo bit, dùng mode trực tiếp)
//
// FIX vs v11:
//   BUG: mode_int = {mode[1], ~mode[0]} đảo bit0 khiến:
//        TB mode=00 (ASCON-128) → mode_int=01 → CONTROLLER chạy ASCON-128a params
//        → calls_pa=3 thay vì 2, calls_pb=2 thay vì 1 → FSM stuck ở S_POST_INIT
//
//   FIX: mode_int = mode (không đảo).
//        Convention thống nhất toàn hệ thống:
//          mode=2'b00 → ASCON-128  (G=6, pa=2calls, pb=1call)
//          mode=2'b01 → ASCON-128a (G=4, pa=3calls, pb=2calls)
//        CONTROLLER decode: mode[0]=0 → 128, mode[0]=1 → 128a
//
// Mode routing (sau fix):
//   u_init  ← mode      (chọn IV_128 hoặc IV_128a)
//   u_ctrl  ← mode_int  (= mode, chọn G/calls_pa/calls_pb)
//   u_dp    ← mode_int  (= mode, chọn rate 64 hoặc 128-bit)
//   u_perm  ← mode_int  (= mode, consistent)
// ============================================================
// `include "ascon/rtl/ascon_INITIALIZATION.v"
// `include "ascon/rtl/ascon_STATE_REGISTER.v"
// `include "ascon/rtl/ascon_datapath.v"
// `include "ascon/rtl/PERMUTATION/ascon_PERMUTATION.v"
// `include "ascon/rtl/ascon_TAG_GENERATOR.v"
// `include "ascon/rtl/ascon_TAG_COMPARATOR.v"
// `include "ascon/rtl/ascon_CONTROLLER.v"


module ascon_CORE #(
    parameter G_COMB_RND_128  = 6,
    parameter G_COMB_RND_128A = 4,
    parameter G_SBOX_PIPELINE = 0,
    parameter G_DUAL_RATE     = 1,
    /* verilator lint_off UNUSEDPARAM */
    parameter G_AXI_DATA_W    = 64  // passed to submodules for future use
    /* verilator lint_on UNUSEDPARAM */
) (
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
    input  wire         data_valid,
    input  wire         data_last,
    input  wire [6:0]   data_len,
    input  wire [127:0] tag_received,

    output wire [127:0] data_out,
    output wire         data_out_valid,
    output wire         data_ready,
    output wire [127:0] tag_out,
    output wire         tag_valid,
    output wire         tag_match,
    output wire         done,
    output wire         busy
);

    // Convention: mode=2'b00 = ASCON-128, mode=2'b01 = ASCON-128a
    // Tất cả submodule nhận cùng mode, không đảo bit.
    // INIT dùng mode gốc để chọn IV đúng.
    // CONTROLLER/DATAPATH/PERMUTATION dùng mode[0]:
    //   mode[0]=0 → ASCON-128  (G=6, calls_pa=2, calls_pb=1)
    //   mode[0]=1 → ASCON-128a (G=4, calls_pa=3, calls_pb=2)
    wire [1:0] mode_int = mode;

    // ----------------------------------------------------------------
    // Internal control wires
    // ----------------------------------------------------------------
    wire        ctrl_load_key, ctrl_load_nonce, ctrl_init_start;
    wire [1:0]  ctrl_state_src_sel;
    wire        ctrl_state_load;
    wire        ctrl_dp_pad_enable;
    wire [1:0]  ctrl_dp_block_sel;
    wire        ctrl_dp_enc_dec;
    wire [3:0]  ctrl_perm_rounds;
    wire [3:0]  ctrl_perm_start_rc;
    wire        ctrl_perm_start;
    wire        ctrl_gen_tag, ctrl_compare_tag;
    /* verilator lint_off UNUSEDSIGNAL */
    wire        ctrl_data_out_valid; // shadowed by dp_data_out_valid
    /* verilator lint_on UNUSEDSIGNAL */
    wire        ctrl_done_sig;
    wire        ctrl_busy_sig;
    wire        ctrl_post_init_key_xor;
    wire        ctrl_pre_fin_key_xor;
    wire        ctrl_dom_sep;

    wire [319:0] init_state_out;
    wire         init_valid;
    wire [319:0] state_reg_out;
    wire [319:0] dp_state_xored;
    wire [127:0] dp_data_out;
    wire         dp_data_out_valid;
    wire         dp_extra_pad;
    wire [319:0] perm_state_out;
    wire         perm_done;
    /* verilator lint_off UNUSEDSIGNAL */
    wire         perm_valid; // not used in current pipeline
    /* verilator lint_on UNUSEDSIGNAL */
    wire [127:0] tag_gen_out;
    wire         tag_gen_valid;
    wire         tag_cmp_match, tag_cmp_done;

    // ----------------------------------------------------------------
    // [FIX-UNOPTFLAT] Break combinational loop on ctrl_dp_pad_enable.
    //
    // Root cause:
    //   CONTROLLER (comb always@*) drives ctrl_dp_pad_enable
    //   → DATAPATH  (comb always@*) computes:
    //       extra_pad_block_needed = pad_enable && (data_len == rate_bytes)
    //   → dp_extra_pad wire feeds back directly into CONTROLLER comb block
    //     (S_AD_LOAD / S_DATA_LOAD read extra_pad_block_needed to decide
    //      the next value of dp_pad_enable) → pure combinational loop.
    //
    // Fix: register dp_extra_pad through one flip-flop here in CORE.
    //   dp_extra_pad   — raw combinational output from DATAPATH  (wire)
    //   dp_extra_pad_r — registered 1-cycle later               (reg)
    //
    // Timing: CONTROLLER only needs extra_pad_block_needed at the
    //   S_AD_LOAD / S_DATA_LOAD states, which fire *after* the block
    //   has already been presented and data_len is stable.  The 1-cycle
    //   pipeline delay is absorbed by the FSM before it transitions.
    // ----------------------------------------------------------------
    reg dp_extra_pad_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dp_extra_pad_r <= 1'b0;
        else
            dp_extra_pad_r <= dp_extra_pad;
    end

    // ----------------------------------------------------------------
    // Key byte-swap (BE → LE)
    // ----------------------------------------------------------------
    wire [63:0] key_hi_bswap = {
        key_in[ 71: 64], key_in[ 79: 72], key_in[ 87: 80], key_in[ 95: 88],
        key_in[103: 96], key_in[111:104], key_in[119:112], key_in[127:120]
    };
    wire [63:0] key_lo_bswap = {
        key_in[  7:  0], key_in[ 15:  8], key_in[ 23: 16], key_in[ 31: 24],
        key_in[ 39: 32], key_in[ 47: 40], key_in[ 55: 48], key_in[ 63: 56]
    };

    // POST_INIT: XOR key vào x3 và x4
    wire [319:0] post_init_state = {
        perm_state_out[319:128],
        perm_state_out[127: 64] ^ key_hi_bswap,
        perm_state_out[ 63:  0] ^ key_lo_bswap
    };

    // PRE_FIN: XOR key vào x2 và x3
    wire [319:0] pre_fin_state = {
        state_reg_out[319:192],
        state_reg_out[191:128] ^ key_hi_bswap,
        state_reg_out[127: 64] ^ key_lo_bswap,
        state_reg_out[ 63:  0]
    };

    // DOM_SEP: flip MSB của x4
    wire [319:0] dom_sep_state = {
        state_reg_out[319:64],
        ~state_reg_out[63],
        state_reg_out[ 62:  0]
    };

    wire [319:0] state_next_final =
        ctrl_post_init_key_xor ? post_init_state  :
        ctrl_pre_fin_key_xor   ? pre_fin_state     :
        ctrl_dom_sep           ? dom_sep_state      :
        (ctrl_state_src_sel == 2'b00) ? init_state_out  :
        (ctrl_state_src_sel == 2'b01) ? dp_state_xored  :
                                        perm_state_out;

    wire use_bypass = ctrl_state_load & ctrl_perm_start;

    // ----------------------------------------------------------------
    // Submodule instantiation
    // ----------------------------------------------------------------

    // FIX: INITIALIZATION dùng mode GỐC (không đảo) → chọn đúng IV
    ascon_INITIALIZATION u_init (
        .clk(clk), .rst_n(rst_n),
        .load_key(ctrl_load_key), .load_nonce(ctrl_load_nonce),
        .mode(mode),                 // ← mode gốc, không đảo
        .init_start(ctrl_init_start),
        .key_in(key_in), .nonce_in(nonce_in),
        .init_state_out(init_state_out), .init_valid(init_valid)
    );

    ascon_STATE_REGISTER u_state_reg (
        .clk(clk), .rst_n(rst_n),
        .src_sel(ctrl_state_src_sel), .load(ctrl_state_load),
        .state_in(state_next_final),
        .init_state(init_state_out),
        .dp_state(dp_state_xored),
        .perm_state(perm_state_out),
        .state_out(state_reg_out)
    );

    // FIX: DATAPATH dùng mode_int → 128a rate (128-bit)
    ascon_DATAPATH #(
        .G_DUAL_RATE(G_DUAL_RATE)
    ) u_dp (
        .clk(clk), .rst_n(rst_n),
        .mode(mode_int),             // ← mode_int
        .enc_dec(ctrl_dp_enc_dec),
        .pad_enable(ctrl_dp_pad_enable), .block_sel(ctrl_dp_block_sel),
        .ad_in(ad_in), .data_in(data_in), .data_len(data_len),
        .state_in(state_reg_out),
        .state_xored(dp_state_xored),
        .data_out(dp_data_out), .data_out_valid(dp_data_out_valid),
        .extra_pad_block_needed(dp_extra_pad)
    );

    // FIX: PERMUTATION dùng mode_int (consistent)
    ascon_PERMUTATION #(
        .G_SBOX_PIPELINE(G_SBOX_PIPELINE)
    ) u_perm (
        .clk(clk), .rst_n(rst_n),
        .state_in(state_reg_out),
        .state_bypass(state_next_final),
        .use_bypass(use_bypass),
        .rounds(ctrl_perm_rounds),
        .start_rc(ctrl_perm_start_rc),
        .start_perm(ctrl_perm_start),
        .mode(mode_int[0]),          // ← mode_int
        .state_out(perm_state_out),
        .valid(perm_valid), .done(perm_done)
    );

    ascon_TAG_GENERATOR u_tag_gen (
        .clk(clk), .rst_n(rst_n),
        .gen_tag(ctrl_gen_tag),
        .state_in(state_reg_out), .key_in(key_in),
        .tag_out(tag_gen_out), .tag_valid(tag_gen_valid)
    );

    ascon_TAG_COMPARATOR u_tag_cmp (
        .clk(clk), .rst_n(rst_n),
        .compare(ctrl_compare_tag),
        .tag_computed(tag_gen_out), .tag_received(tag_received),
        .tag_match(tag_cmp_match), .tag_done(tag_cmp_done)
    );

    // FIX: CONTROLLER dùng mode_int → 128a GCD params
    ascon_CONTROLLER #(
        .G_COMB_RND_128 (G_COMB_RND_128),
        .G_COMB_RND_128A(G_COMB_RND_128A),
        .G_SBOX_PIPELINE(G_SBOX_PIPELINE)
    ) u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .start(start), .mode(mode_int), .enc_dec(enc_dec),  // ← mode_int
        .key_in(key_in), .nonce_in(nonce_in),
        .ad_in(ad_in), .ad_valid(ad_valid), .ad_last(ad_last),
        .data_in(data_in), .data_valid(data_valid), .data_last(data_last), .data_len(data_len),
        .tag_received(tag_received),
        .data_ready(data_ready), .data_out_valid(ctrl_data_out_valid),
        .done(ctrl_done_sig), .busy(ctrl_busy_sig),
        .load_key(ctrl_load_key), .load_nonce(ctrl_load_nonce),
        .init_start(ctrl_init_start),
        .state_src_sel(ctrl_state_src_sel), .state_load(ctrl_state_load),
        .dp_pad_enable(ctrl_dp_pad_enable), .dp_block_sel(ctrl_dp_block_sel),
        .dp_enc_dec(ctrl_dp_enc_dec),
        .perm_rounds(ctrl_perm_rounds),
        .perm_start_rc(ctrl_perm_start_rc),
        .perm_start(ctrl_perm_start),
        .gen_tag(ctrl_gen_tag), .compare_tag(ctrl_compare_tag),
        .do_post_init_key_xor(ctrl_post_init_key_xor),
        .do_pre_fin_key_xor(ctrl_pre_fin_key_xor),
        .do_dom_sep(ctrl_dom_sep),
        .extra_pad_block_needed(dp_extra_pad_r),  // [FIX-UNOPTFLAT] registered
        .init_done(init_valid), .perm_done(perm_done),
        .tag_gen_valid(tag_gen_valid), .tag_cmp_done(tag_cmp_done)
    );

    assign data_out       = dp_data_out;
    assign data_out_valid = dp_data_out_valid;
    assign tag_out        = tag_gen_out;
    assign tag_valid      = tag_gen_valid;
    assign tag_match      = tag_cmp_match;
    assign done           = ctrl_done_sig;
    assign busy           = ctrl_busy_sig;

endmodule