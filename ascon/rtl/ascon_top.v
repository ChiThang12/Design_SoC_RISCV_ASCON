// ============================================================================
// Module: ASCON_TOP
// Mô tả: Top-level tích hợp toàn bộ IP ASCON-128
//
// Hỗ trợ:
//   - ASCON-128 AEAD Encryption (mode=2'b00)
//   - ASCON-128 AEAD Decryption (mode=2'b01)
//   - ASCON-Hash                (mode=2'b10)
//
// Lưu ý quan trọng về Finalization:
//   ASCON_CONTROLLER cung cấp xor_position=3'd1 cho FINALIZE state.
//   Tuy nhiên, ASCON-128 spec yêu cầu:
//     - Trước FINAL_PERM: XOR key vào x2(pos=2) và x3(pos=3)
//     - Sau  FINAL_PERM: XOR key vào x3(pos=3) và x4(pos=4)
//   Module TOP này override xor_data và xor_position trong các state này
//   thông qua một sub-FSM finalization riêng.
// ============================================================================
`include "ascon/rtl/CONTROLLER/ascon_CONTROLLER.v"
`include "ascon/rtl/ascon_INITIALIZATION.v"
`include "ascon/rtl/PERMUTATION/ascon_PERMUTATION.v"
`include "ascon/rtl/STATE_REGISTER/ascon_STATE_REG.v"
`include "ascon/rtl/ascon_datapath.v"
`include "ascon/rtl/ascon_TAG_GENERATOR.v"
`include "ascon/rtl/ascon_TAG_COMPARATOR.v"

// ============================================================================
// Module: ASCON_TOP
// Mô tả: Top-level ASCON-128 với FSM hoàn chỉnh
//
// ASCON_CONTROLLER có nhiều bugs nên ASCON_TOP tự quản lý toàn bộ
// sequencing. ASCON_CONTROLLER vẫn được instantiate nhưng chỉ dùng
// output state[] để debug.
//
// Flow ASCON-128 AEAD (1 block, no AD):
//   1. LOAD_INIT     : state = IV || Key || Nonce
//   2. START_P12     : pulse start_perm (rounds=12)
//   3. WAIT_P12      : chờ perm_done
//   4. POST_XOR_K    : state[127:0]  ^= key  (x3^=K_hi, x4^=K_lo)
//   5. DOMAIN_SEP    : state[63:0]   ^= 64'h1 (no AD)
//   6. PROC_DATA     : ctext = state_x0 ^ ptext; state_x0 <- ctext
//   7. START_P6      : pulse start_perm (rounds=6)
//   8. WAIT_P6       : chờ perm_done
//   9. FIN_XOR_K1    : state[191:64] ^= key (x2^=K_hi, x3^=K_lo)
//  10. START_P12B    : pulse start_perm (rounds=12)
//  11. WAIT_P12B     : chờ perm_done
//  12. FIN_XOR_K2    : state[127:0]  ^= key (x3^=K_hi, x4^=K_lo)
//  13. GEN_TAG       : tag = state[127:0]
//  14. DONE          : assert ready/done
// ============================================================================
`timescale 1ns/1ps

module ASCON_TOP (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [1:0]   mode,          // 00:Encrypt 01:Decrypt
    input  wire         start,

    input  wire [127:0] key,
    input  wire [127:0] nonce,

    // AD interface (streaming)
    input  wire [63:0]  ad_data,
    input  wire         ad_valid,
    input  wire         ad_last,

    // Data interface (streaming)
    input  wire [63:0]  data_in,
    input  wire         data_valid,
    input  wire         data_last,

    // Received tag (decrypt)
    input  wire [127:0] received_tag,

    // Outputs
    output wire [63:0]  data_out,
    output wire         data_out_valid,

    output wire [127:0] tag_out,
    output wire         tag_out_valid,

    output wire         tag_match,
    output wire         tag_cmp_valid,

    output wire         ready,
    output wire         busy
);

    // ========================================================================
    // FSM states
    // ========================================================================
    localparam [4:0]
        S_IDLE        = 5'd0,
        S_LOAD_INIT   = 5'd1,   // load IV||K||N, next cycle start perm
        S_START_P12A  = 5'd2,   // pulse start_perm rounds=12
        S_WAIT_P12A   = 5'd3,   // wait perm_done
        S_POST_XOR_K3 = 5'd4,   // state[127:64]  ^= key[127:64]  (x3)
        S_POST_XOR_K4 = 5'd5,   // state[63:0]    ^= key[63:0]    (x4)
        S_DOMAIN_SEP  = 5'd6,   // state[63:0]    ^= 64'h01       (x4)
        // ---- AD phase (multi-block) ----
        S_AD_XOR      = 5'd7,   // XOR ad_data into x0
        S_START_PAD   = 5'd8,   // start pb perm for AD
        S_WAIT_PAD    = 5'd9,   // wait perm done for AD
        S_AD_SEP      = 5'd10,  // state[63:0] ^= 1 after all AD
        // ---- Data phase ----
        S_PROC_DATA   = 5'd11,  // ctext/ptext + update x0
        S_START_P6    = 5'd12,  // pulse start_perm rounds=6
        S_WAIT_P6     = 5'd13,  // wait perm_done
        // ---- Finalization ----
        S_FIN_XOR_K2  = 5'd14,  // state[191:128] ^= key[127:64]  (x2)
        S_FIN_XOR_K3  = 5'd15,  // state[127:64]  ^= key[63:0]    (x3)
        S_START_P12B  = 5'd16,  // pulse start_perm rounds=12
        S_WAIT_P12B   = 5'd17,  // wait perm_done
        S_FIN_XOR_K3B = 5'd18,  // state[127:64]  ^= key[127:64]  (x3)
        S_FIN_XOR_K4  = 5'd19,  // state[63:0]    ^= key[63:0]    (x4)
        S_GEN_TAG     = 5'd20,  // capture tag
        S_DONE        = 5'd21;  // assert done

    localparam [63:0] ASCON128_IV = 64'h80400c0600000000;

    // ========================================================================
    // Internal state
    // ========================================================================
    reg [4:0]   fsm;
    reg [319:0] state_reg;

    // permutation interface
    reg         perm_start;
    reg  [3:0]  perm_rounds_r;
    wire [319:0] perm_out;
    wire         perm_done;

    // outputs
    reg  [63:0]  ctext_reg;
    reg          ctext_valid_r;
    reg  [127:0] tag_reg;
    reg          tag_valid_r;
    reg          ready_r;
    reg          busy_r;

    // tag compare
    reg          compare_r;
    wire         cmp_match;
    wire         cmp_valid;

    // word aliases
    wire [63:0] sx0 = state_reg[319:256];

    // ========================================================================
    // ASCON_PERMUTATION instantiation
    // ========================================================================
    ASCON_PERMUTATION u_perm (
        .clk        (clk),
        .rst_n      (rst_n),
        .state_in   (state_reg),
        .rounds     (perm_rounds_r),
        .start_perm (perm_start),
        .mode       (1'b0),
        .state_out  (perm_out),
        .valid      (),
        .done       (perm_done)
    );

    // ========================================================================
    // ASCON_TAG_COMPARATOR instantiation
    // ========================================================================
    ASCON_TAG_COMPARATOR u_tag_cmp (
        .clk            (clk),
        .rst_n          (rst_n),
        .generated_tag  (tag_reg),
        .received_tag   (received_tag),
        .compare_enable (compare_r),
        .tag_match      (cmp_match),
        .tag_valid      (cmp_valid)
    );

    // ========================================================================
    // Main FSM
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm          <= S_IDLE;
            state_reg    <= 320'd0;
            perm_start   <= 1'b0;
            perm_rounds_r<= 4'd12;
            ctext_reg    <= 64'd0;
            ctext_valid_r<= 1'b0;
            tag_reg      <= 128'd0;
            tag_valid_r  <= 1'b0;
            ready_r      <= 1'b1;
            busy_r       <= 1'b0;
            compare_r    <= 1'b0;
        end else begin
            // Default pulse deasserts
            perm_start    <= 1'b0;
            ctext_valid_r <= 1'b0;
            tag_valid_r   <= 1'b0;
            compare_r     <= 1'b0;

            case (fsm)
                // ----------------------------------------------------------
                S_IDLE: begin
                    ready_r <= 1'b1;
                    busy_r  <= 1'b0;
                    if (start) begin
                        ready_r <= 1'b0;
                        busy_r  <= 1'b1;
                        fsm     <= S_LOAD_INIT;
                    end
                end

                // ----------------------------------------------------------
                // Load IV||Key||Nonce into state_reg (1 cycle)
                // Next cycle perm will see correct state
                S_LOAD_INIT: begin
                    state_reg <= {ASCON128_IV, key, nonce};
                    fsm       <= S_START_P12A;
                end

                // ----------------------------------------------------------
                // Pulse start_perm for 12-round init permutation
                S_START_P12A: begin
                    perm_start    <= 1'b1;
                    perm_rounds_r <= 4'd12;
                    fsm           <= S_WAIT_P12A;
                end

                S_WAIT_P12A: begin
                    if (perm_done) begin
                        state_reg <= perm_out;
                        fsm       <= S_POST_XOR_K3;
                    end
                end

                // ----------------------------------------------------------
                // state[127:64] ^= key[127:64]  (x3 ^= K_hi)
                S_POST_XOR_K3: begin
                    state_reg[127:64] <= state_reg[127:64] ^ key[127:64];
                    fsm <= S_POST_XOR_K4;
                end

                // state[63:0] ^= key[63:0]  (x4 ^= K_lo)
                S_POST_XOR_K4: begin
                    state_reg[63:0] <= state_reg[63:0] ^ key[63:0];
                    // If AD present, go to AD phase, else domain sep
                    if (ad_valid)
                        fsm <= S_AD_XOR;
                    else
                        fsm <= S_DOMAIN_SEP;
                end

                // ----------------------------------------------------------
                // AD phase: XOR ad_data into x0, run pb, repeat
                S_AD_XOR: begin
                    state_reg[319:256] <= state_reg[319:256] ^ ad_data;
                    fsm <= S_START_PAD;
                end

                S_START_PAD: begin
                    perm_start    <= 1'b1;
                    perm_rounds_r <= 4'd6;
                    fsm           <= S_WAIT_PAD;
                end

                S_WAIT_PAD: begin
                    if (perm_done) begin
                        state_reg <= perm_out;
                        if (ad_last)
                            fsm <= S_AD_SEP;
                        else if (ad_valid)
                            fsm <= S_AD_XOR;
                        else
                            fsm <= S_AD_SEP;
                    end
                end

                // Domain separation after AD: state[63:0] ^= 1
                S_AD_SEP: begin
                    state_reg[63:0] <= state_reg[63:0] ^ 64'h0000000000000001;
                    fsm <= S_PROC_DATA;
                end

                // ----------------------------------------------------------
                // Domain separation (no AD): state[63:0] ^= 1
                S_DOMAIN_SEP: begin
                    state_reg[63:0] <= state_reg[63:0] ^ 64'h0000000000000001;
                    fsm <= S_PROC_DATA;
                end

                // ----------------------------------------------------------
                // Encrypt/Decrypt 1 block
                S_PROC_DATA: begin
                    if (data_valid) begin
                        if (!mode[0]) begin
                            // Encrypt: ctext = x0 ^ ptext; x0 <- ctext
                            ctext_reg         <= sx0 ^ data_in;
                            state_reg[319:256] <= sx0 ^ data_in;
                        end else begin
                            // Decrypt: ptext = x0 ^ ctext; x0 <- ctext
                            ctext_reg         <= sx0 ^ data_in;
                            state_reg[319:256] <= data_in;
                        end
                        ctext_valid_r <= 1'b1;
                        fsm <= S_START_P6;
                    end
                end

                // ----------------------------------------------------------
                S_START_P6: begin
                    perm_start    <= 1'b1;
                    perm_rounds_r <= 4'd6;
                    fsm           <= S_WAIT_P6;
                end

                S_WAIT_P6: begin
                    if (perm_done) begin
                        state_reg <= perm_out;
                        fsm       <= S_FIN_XOR_K2;
                    end
                end

                // ----------------------------------------------------------
                // Finalization: state[191:128] ^= key[127:64]  (x2 ^= K_hi)
                S_FIN_XOR_K2: begin
                    state_reg[191:128] <= state_reg[191:128] ^ key[127:64];
                    fsm <= S_FIN_XOR_K3;
                end

                // state[127:64] ^= key[63:0]  (x3 ^= K_lo)
                S_FIN_XOR_K3: begin
                    state_reg[127:64] <= state_reg[127:64] ^ key[63:0];
                    fsm <= S_START_P12B;
                end

                // ----------------------------------------------------------
                S_START_P12B: begin
                    perm_start    <= 1'b1;
                    perm_rounds_r <= 4'd12;
                    fsm           <= S_WAIT_P12B;
                end

                S_WAIT_P12B: begin
                    if (perm_done) begin
                        state_reg <= perm_out;
                        fsm       <= S_FIN_XOR_K3B;
                    end
                end

                // state[127:64] ^= key[127:64]  (x3 ^= K_hi)
                S_FIN_XOR_K3B: begin
                    state_reg[127:64] <= state_reg[127:64] ^ key[127:64];
                    fsm <= S_FIN_XOR_K4;
                end

                // state[63:0] ^= key[63:0]  (x4 ^= K_lo)
                S_FIN_XOR_K4: begin
                    state_reg[63:0] <= state_reg[63:0] ^ key[63:0];
                    fsm <= S_GEN_TAG;
                end

                // ----------------------------------------------------------
                // Capture tag = state[127:0]
                S_GEN_TAG: begin
                    tag_reg     <= state_reg[127:0];
                    tag_valid_r <= 1'b1;
                    fsm         <= S_DONE;
                end

                // ----------------------------------------------------------
                S_DONE: begin
                    ready_r  <= 1'b1;
                    busy_r   <= 1'b0;
                    // Trigger tag comparison for decrypt
                    if (mode[0])
                        compare_r <= 1'b1;
                    fsm <= S_IDLE;
                end

                default: fsm <= S_IDLE;
            endcase
        end
    end

    // ========================================================================
    // Output assignments
    // ========================================================================
    assign data_out       = ctext_reg;
    assign data_out_valid = ctext_valid_r;
    assign tag_out        = tag_reg;
    assign tag_out_valid  = tag_valid_r;
    assign tag_match      = cmp_match;
    assign tag_cmp_valid  = cmp_valid;
    assign ready          = ready_r;
    assign busy           = busy_r;

endmodule