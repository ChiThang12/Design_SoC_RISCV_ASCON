// ============================================================
// Module: ascon_CORE  (OPT v4-FIX)
//
// FIX: Pre-Perm Merging race condition
//   state_bypass + use_bypass thêm vào PERMUTATION
//   để bypass state_reg khi state_load và perm_start cùng cycle.
//
//   use_bypass = ctrl_state_load & ctrl_perm_start
//   state_bypass = state_next_final (cùng wire đang latch vào state_reg)
// ============================================================
`include "ascon/rtl/ascon_INITIALIZATION.v"
`include "ascon/rtl/ascon_STATE_REGISTER.v"
`include "ascon/rtl/ascon_DATAPATH.v"
`include "ascon/rtl/PERMUTATION/ascon_PERMUTATION.v"
`include "ascon/rtl/ascon_TAG_GENERATOR.v"
`include "ascon/rtl/ascon_TAG_COMPARATOR.v"
`include "ascon/rtl/ascon_CONTROLLER.v"

module ascon_CORE (
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

    output wire [127:0] data_out,
    output wire         data_out_valid,
    output wire [127:0] tag_out,
    output wire         tag_valid,
    output wire         tag_match,
    output wire         done,
    output wire         busy
);

    wire        ctrl_load_key, ctrl_load_nonce, ctrl_init_start;
    wire [1:0]  ctrl_state_src_sel;
    wire        ctrl_state_load;
    wire        ctrl_dp_pad_enable;
    wire [1:0]  ctrl_dp_block_sel;
    wire        ctrl_dp_enc_dec;
    wire [3:0]  ctrl_perm_rounds;
    wire        ctrl_perm_start;
    wire        ctrl_gen_tag, ctrl_compare_tag;
    wire        ctrl_data_out_valid;
    wire        ctrl_done_sig;
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
    wire         perm_done, perm_valid;
    wire [127:0] tag_gen_out;
    wire         tag_gen_valid;
    wire         tag_cmp_match, tag_cmp_done;

    // Key byte-swap
    wire [63:0] key_hi_bswap = {
        key_in[ 71: 64], key_in[ 79: 72], key_in[ 87: 80], key_in[ 95: 88],
        key_in[103: 96], key_in[111:104], key_in[119:112], key_in[127:120]
    };
    wire [63:0] key_lo_bswap = {
        key_in[  7:  0], key_in[ 15:  8], key_in[ 23: 16], key_in[ 31: 24],
        key_in[ 39: 32], key_in[ 47: 40], key_in[ 55: 48], key_in[ 63: 56]
    };

    // State mux
    wire [319:0] post_init_state = {
        perm_state_out[319:128],
        perm_state_out[127: 64] ^ key_hi_bswap,
        perm_state_out[ 63:  0] ^ key_lo_bswap
    };
    wire [319:0] pre_fin_state = {
        state_reg_out[319:192],
        state_reg_out[191:128] ^ key_hi_bswap,
        state_reg_out[127: 64] ^ key_lo_bswap,
        state_reg_out[ 63:  0]
    };
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

    // FIX: use_bypass = state_load và perm_start cùng cycle
    wire use_bypass = ctrl_state_load & ctrl_perm_start;

    ascon_INITIALIZATION u_init (
        .clk(clk), .rst_n(rst_n),
        .load_key(ctrl_load_key), .load_nonce(ctrl_load_nonce),
        .mode(mode), .init_start(ctrl_init_start),
        .key_in(key_in), .nonce_in(nonce_in),
        .init_state_out(init_state_out), .init_valid(init_valid)
    );

    ascon_STATE_REGISTER u_state_reg (
        .clk(clk), .rst_n(rst_n),
        .src_sel(ctrl_state_src_sel), .load(ctrl_state_load),
        .init_state(state_next_final),
        .dp_state(state_next_final),
        .perm_state(state_next_final),
        .state_out(state_reg_out)
    );

    ascon_DATAPATH u_dp (
        .clk(clk), .rst_n(rst_n),
        .mode(mode), .enc_dec(ctrl_dp_enc_dec),
        .pad_enable(ctrl_dp_pad_enable), .block_sel(ctrl_dp_block_sel),
        .ad_in(ad_in), .data_in(data_in), .data_len(data_len),
        .state_in(state_reg_out),
        .state_xored(dp_state_xored),
        .data_out(dp_data_out), .data_out_valid(dp_data_out_valid),
        .extra_pad_block_needed(dp_extra_pad)
    );

    ascon_PERMUTATION u_perm (
        .clk(clk), .rst_n(rst_n),
        .state_in(state_reg_out),           // bình thường: từ state_reg
        .state_bypass(state_next_final),    // FIX: bypass khi merge load+start
        .use_bypass(use_bypass),            // FIX: enable bypass
        .rounds(ctrl_perm_rounds),
        .start_perm(ctrl_perm_start),
        .mode(1'b0),
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

    ascon_CONTROLLER u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .start(start), .mode(mode), .enc_dec(enc_dec),
        .key_in(key_in), .nonce_in(nonce_in),
        .ad_in(ad_in), .ad_valid(ad_valid), .ad_last(ad_last),
        .data_in(data_in), .data_last(data_last), .data_len(data_len),
        .tag_received(tag_received),
        .data_out(), .data_out_valid(ctrl_data_out_valid),
        .tag_out(), .tag_valid(), .tag_match(),
        .done(ctrl_done_sig), .busy(busy),
        .load_key(ctrl_load_key), .load_nonce(ctrl_load_nonce),
        .init_start(ctrl_init_start),
        .state_src_sel(ctrl_state_src_sel), .state_load(ctrl_state_load),
        .dp_pad_enable(ctrl_dp_pad_enable), .dp_block_sel(ctrl_dp_block_sel),
        .dp_enc_dec(ctrl_dp_enc_dec),
        .perm_rounds(ctrl_perm_rounds), .perm_start(ctrl_perm_start),
        .gen_tag(ctrl_gen_tag), .compare_tag(ctrl_compare_tag),
        .do_post_init_key_xor(ctrl_post_init_key_xor),
        .do_pre_fin_key_xor(ctrl_pre_fin_key_xor),
        .do_dom_sep(ctrl_dom_sep),
        .extra_pad_block_needed(dp_extra_pad),
        .init_done(init_valid), .perm_done(perm_done),
        .tag_gen_valid(tag_gen_valid), .tag_cmp_done(tag_cmp_done)
    );

    assign data_out       = dp_data_out;
    assign data_out_valid = dp_data_out_valid & ctrl_data_out_valid;
    assign tag_out        = tag_gen_out;
    assign tag_valid      = tag_gen_valid;
    assign tag_match      = tag_cmp_match;
    assign done           = ctrl_done_sig;

`ifdef SIMULATION
    always @(posedge clk) begin
        if (ctrl_state_load)
            $display("  [CORE DBG] state_load: post_init=%b pre_fin=%b dom_sep=%b src_sel=%b use_bypass=%b",
                     ctrl_post_init_key_xor, ctrl_pre_fin_key_xor, ctrl_dom_sep,
                     ctrl_state_src_sel, use_bypass);
        if (ctrl_perm_start)
            $display("  [CORE DBG] perm_start: rounds=%0d bypass=%b state[319:256]=%h",
                     ctrl_perm_rounds, use_bypass,
                     use_bypass ? state_next_final[319:256] : state_reg_out[319:256]);
    end
`endif

endmodule