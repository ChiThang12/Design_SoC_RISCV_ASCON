// ============================================================
// Module: ascon_CORE  (v4 — H1+H2 optimized, interface unchanged)
//
// CHANGES vs v3:
//   H1 — FSM State Merge (in ascon_CONTROLLER v4):
//     4 dead states removed → 4+ fewer cycles per operation.
//     No port changes; CORE benefits automatically.
//
//   H2 — Input Buffer (in ascon_CONTROLLER v4):
//     Buffer registers and mux logic live entirely in CONTROLLER.
//     ascon_CORE external interface is UNCHANGED — fully backward-
//     compatible with existing testbenches. The H2 buffer ports of
//     u_ctrl are tied to 0 inside this module.
//     To use H2 prefetch, instantiate ascon_CONTROLLER directly.
//
//   BN-05 — $display wrapped in `ifdef SIMULATION.
//
// Prior fixes retained (v3):
//   1. Domain separation: flip x4 bit 63 (MSB).
//   2. Post-init key XOR: bswapped key into x3/x4.
//   3. Pre-fin key XOR:   bswapped key into x2/x3.
//   4. STATE_REGISTER fed via single pre-muxed state_next_final.
//   5. ad_last, extra_pad_block_needed forwarded to CONTROLLER.
//
// State word layout (320 bits, big-endian Verilog register):
//   [319:256]=x0  [255:192]=x1  [191:128]=x2
//   [127: 64]=x3  [ 63:  0]=x4
// ============================================================
`include "ascon_accelerator/rtl/ascon_INITIALIZATION.v"
`include "ascon_accelerator/rtl/ascon_STATE_REGISTER.v"
`include "ascon_accelerator/rtl/ascon_DATAPATH.v"
`include "ascon_accelerator/rtl/PERMUTATION/ascon_PERMUTATION.v"
`include "ascon_accelerator/rtl/ascon_TAG_GENERATOR.v"
`include "ascon_accelerator/rtl/ascon_TAG_COMPARATOR.v"
`include "ascon_accelerator/rtl/ascon_CONTROLLER.v"

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

    // ---- Controller wires ----
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

    // H2: muxed data from controller → datapath
    // When buffer tied off (ad_buf_valid=0), these equal ad_in/data_in.
    wire [127:0] ctrl_ad_mux;
    wire [127:0] ctrl_data_mux;
    wire [6:0]   ctrl_data_len_mux;

    // ---- Sub-module wires ----
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

    // ================================================================
    // Key byte-swap helpers
    // ================================================================
    wire [63:0] key_hi_bswap = {
        key_in[ 71: 64], key_in[ 79: 72], key_in[ 87: 80], key_in[ 95: 88],
        key_in[103: 96], key_in[111:104], key_in[119:112], key_in[127:120]
    };
    wire [63:0] key_lo_bswap = {
        key_in[  7:  0], key_in[ 15:  8], key_in[ 23: 16], key_in[ 31: 24],
        key_in[ 39: 32], key_in[ 47: 40], key_in[ 55: 48], key_in[ 63: 56]
    };

    // ================================================================
    // State mux
    // ================================================================
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

    // ================================================================
    // Sub-module instantiations
    // ================================================================

    ascon_INITIALIZATION u_init (
        .clk            (clk),
        .rst_n          (rst_n),
        .load_key       (ctrl_load_key),
        .load_nonce     (ctrl_load_nonce),
        .mode           (mode),
        .init_start     (ctrl_init_start),
        .key_in         (key_in),
        .nonce_in       (nonce_in),
        .init_state_out (init_state_out),
        .init_valid     (init_valid)
    );

    ascon_STATE_REGISTER u_state_reg (
        .clk        (clk),
        .rst_n      (rst_n),
        .src_sel    (ctrl_state_src_sel),
        .load       (ctrl_state_load),
        .init_state (state_next_final),
        .dp_state   (state_next_final),
        .perm_state (state_next_final),
        .state_out  (state_reg_out)
    );

    ascon_DATAPATH u_dp (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .mode                   (mode),
        .enc_dec                (ctrl_dp_enc_dec),
        .pad_enable             (ctrl_dp_pad_enable),
        .block_sel              (ctrl_dp_block_sel),
        .ad_in                  (ctrl_ad_mux),
        .data_in                (ctrl_data_mux),
        .data_len               (ctrl_data_len_mux),
        .state_in               (state_reg_out),
        .state_xored            (dp_state_xored),
        .data_out               (dp_data_out),
        .data_out_valid         (dp_data_out_valid),
        .extra_pad_block_needed (dp_extra_pad)
    );

    ascon_PERMUTATION u_perm (
        .clk        (clk),
        .rst_n      (rst_n),
        .state_in   (state_reg_out),
        .rounds     (ctrl_perm_rounds),
        .start_perm (ctrl_perm_start),
        .mode       (1'b0),
        .state_out  (perm_state_out),
        .valid      (perm_valid),
        .done       (perm_done)
    );

    ascon_TAG_GENERATOR u_tag_gen (
        .clk       (clk),
        .rst_n     (rst_n),
        .gen_tag   (ctrl_gen_tag),
        .state_in  (state_reg_out),
        .key_in    (key_in),
        .tag_out   (tag_gen_out),
        .tag_valid (tag_gen_valid)
    );

    ascon_TAG_COMPARATOR u_tag_cmp (
        .clk          (clk),
        .rst_n        (rst_n),
        .compare      (ctrl_compare_tag),
        .tag_computed (tag_gen_out),
        .tag_received (tag_received),
        .tag_match    (tag_cmp_match),
        .tag_done     (tag_cmp_done)
    );

    ascon_CONTROLLER u_ctrl (
        .clk                    (clk),
        .rst_n                  (rst_n),
        // Primary control
        .start                  (start),
        .mode                   (mode),
        .enc_dec                (enc_dec),
        .key_in                 (key_in),
        .nonce_in               (nonce_in),
        // AD — original ports
        .ad_in                  (ad_in),
        .ad_valid               (ad_valid),
        .ad_last                (ad_last),
        // AD — H2 buffer tied off (not used at ascon_CORE level)
        .ad_buf_in              (128'h0),
        .ad_buf_valid           (1'b0),
        .ad_buf_last            (1'b0),
        .ad_buf_ready           (),
        // Data — original ports
        .data_in                (data_in),
        .data_last              (data_last),
        .data_len               (data_len),
        // Data — H2 buffer tied off
        .data_buf_in            (128'h0),
        .data_buf_valid         (1'b0),
        .data_buf_last          (1'b0),
        .data_buf_len           (7'h0),
        .data_buf_ready         (),
        // Tag
        .tag_received           (tag_received),
        // User outputs (real crypto values come from dp/tag submodules)
        .data_out               (),
        .data_out_valid         (ctrl_data_out_valid),
        .tag_out                (),
        .tag_valid              (),
        .tag_match              (),
        .done                   (ctrl_done_sig),
        .busy                   (busy),
        // Control outputs
        .load_key               (ctrl_load_key),
        .load_nonce             (ctrl_load_nonce),
        .init_start             (ctrl_init_start),
        .state_src_sel          (ctrl_state_src_sel),
        .state_load             (ctrl_state_load),
        .dp_pad_enable          (ctrl_dp_pad_enable),
        .dp_block_sel           (ctrl_dp_block_sel),
        .dp_enc_dec             (ctrl_dp_enc_dec),
        .perm_rounds            (ctrl_perm_rounds),
        .perm_start             (ctrl_perm_start),
        .gen_tag                (ctrl_gen_tag),
        .compare_tag            (ctrl_compare_tag),
        .do_post_init_key_xor   (ctrl_post_init_key_xor),
        .do_pre_fin_key_xor     (ctrl_pre_fin_key_xor),
        .do_dom_sep             (ctrl_dom_sep),
        // Sub-module status
        .extra_pad_block_needed (dp_extra_pad),
        .init_done              (init_valid),
        .perm_done              (perm_done),
        .tag_gen_valid          (tag_gen_valid),
        .tag_cmp_done           (tag_cmp_done),
        // H2 mux outputs → DATAPATH
        .ad_mux_out             (ctrl_ad_mux),
        .data_mux_out           (ctrl_data_mux),
        .data_len_mux_out       (ctrl_data_len_mux)
    );

    // ---- Output assignments ----
    assign data_out       = dp_data_out;
    // data_out_valid: use dp_data_out_valid directly.
    // DATAPATH registers its output 1 cycle after data_out_valid_comb fires
    // (i.e., the cycle after S_DATA_LOAD). Gating with ctrl_data_out_valid
    // (which is combinational and only high during S_DATA_LOAD itself) causes
    // the two signals to never overlap — this AND was masking valid CT output.
    // DATAPATH already knows exactly when its output is valid; trust it.
    assign data_out_valid = dp_data_out_valid;
    assign tag_out        = tag_gen_out;
    assign tag_valid      = tag_gen_valid;
    assign tag_match      = tag_cmp_match;
    assign done           = ctrl_done_sig;

`ifdef SIMULATION
    always @(posedge clk) begin
        if (ctrl_state_load)
            $display("  [CORE DBG] state_load: post_init=%b pre_fin=%b dom_sep=%b src_sel=%b  state_next[319:256]=%h",
                ctrl_post_init_key_xor, ctrl_pre_fin_key_xor, ctrl_dom_sep,
                ctrl_state_src_sel, state_next_final[319:256]);
        if (ctrl_perm_start)
            $display("  [CORE DBG] perm_start: rounds=%0d  state_reg[319:256]=%h",
                ctrl_perm_rounds, state_reg_out[319:256]);
    end
`endif

endmodule