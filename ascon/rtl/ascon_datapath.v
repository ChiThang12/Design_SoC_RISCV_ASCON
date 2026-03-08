// ============================================================
// Module: ascon_DATAPATH  (FIXED for NIST Ascon-AEAD128)
//
// CHANGES vs previous version:
//   7. Padding edge case: when data_len == rate (16), the block
//        is full and no pad byte fits. extra_pad_block_needed is
//        asserted so the controller can inject an extra all-zeros
//        block with only the 0x01 pad byte.
//        apply_padding behaviour unchanged when len < rate.
//
//   8. New output port: extra_pad_block_needed
//        Asserted combinationally when pad_enable=1 and
//        data_len == rate_bytes (full block, needs extra pad block).
//
// Prior fixes retained:
//   1. Rate fixed to 16 bytes for all supported modes.
//   2. Pad byte = 0x01.
//   3. Input byte-swap (BE input → LE integers matching SW).
//   4. mode=00 absorbs both x0 and x1 (128-bit rate).
//   5. Output byte-swap.
//   6. Decrypt state update uses bswapped ciphertext.
// ============================================================
module ascon_DATAPATH (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [1:0]   mode,
    input  wire         enc_dec,
    input  wire         pad_enable,
    input  wire [1:0]   block_sel,

    input  wire [127:0] ad_in,
    input  wire [127:0] data_in,
    input  wire [6:0]   data_len,
    input  wire [319:0] state_in,

    output reg  [319:0] state_xored,
    output reg  [127:0] data_out,
    output reg          data_out_valid,
    output wire         extra_pad_block_needed   // NEW: full-block pad signal
);

    // ------------------------------------------------------------------
    // Rate: Ascon-128 / Ascon-128a = 16 bytes
    // ------------------------------------------------------------------
    wire [6:0] rate_bytes = 7'd16;

    // Assert when the current data block is exactly rate bytes long —
    // the 0x01 pad byte cannot fit in this block, so controller must
    // absorb one additional all-zero block containing only the pad byte.
    assign extra_pad_block_needed = pad_enable && (data_len == rate_bytes);

    // Select correct input source
    wire [127:0] raw_input = (block_sel == 2'b00) ? ad_in : data_in;

    // ------------------------------------------------------------------
    // Byte-swap: reverse byte order within a 64-bit word
    // ------------------------------------------------------------------
    function [63:0] bswap64;
        input [63:0] x;
        begin
            bswap64 = { x[ 7: 0], x[15: 8], x[23:16], x[31:24],
                        x[39:32], x[47:40], x[55:48], x[63:56] };
        end
    endfunction

    // ------------------------------------------------------------------
    // Padding (FIXED pad byte = 0x01):
    //   • When len < rate : copy bytes [0..len-1], place 0x01 at byte[len],
    //     zero the rest.
    //   • When len == rate: the caller detects extra_pad_block_needed and
    //     will send a separate pad-only block.  For THIS block we return
    //     the raw data unmodified (pad_enable is still set so the caller
    //     knows it is the last data block, but no byte is appended here).
    // ------------------------------------------------------------------
    function [127:0] apply_padding;
        input [127:0] blk;
        input [6:0]   len;
        input [6:0]   rate;
        integer i;
        reg [127:0] out;
        begin
            out = 128'b0;
            for (i = 0; i < 16; i = i + 1) begin
                if (i < len)
                    out[127 - i*8 -: 8] = blk[127 - i*8 -: 8];
                else if (i == len && len < rate)
                    out[127 - i*8 -: 8] = 8'h01;
                // else: zero (already cleared) — also covers len==rate case
            end
            apply_padding = out;
        end
    endfunction

    // ---- Combinational signals ----
    reg [127:0] data_out_comb;
    reg         data_out_valid_comb;
    reg [127:0] padded_data;
    reg [319:0] state_temp;

    wire [63:0] x0 = state_in[319:256];
    wire [63:0] x1 = state_in[255:192];

    wire [63:0] pd_hi_bswap;
    wire [63:0] pd_lo_bswap;

    // ------------------------------------------------------------------
    // Two separate data paths:
    //   enc_padded : PT with padding applied  (used during ENCRYPT)
    //   dec_raw    : CT without padding       (used during DECRYPT)
    //
    // SW spec:
    //   ENCRYPT: S[0] ^= bytes_to_int(pad(PT), 'little')
    //            output CT = int_to_bytes(S[0], 'little')
    //   DECRYPT: S[0] ^= bytes_to_int(CT, 'little')   ← NO padding on CT
    //            output PT = int_to_bytes(S[0] XOR CT_int, 'little')
    //            then S[0] = CT_int  (state absorbs raw CT, not padded)
    //
    // AD absorption always uses padding (same in enc and dec).
    // ------------------------------------------------------------------
    always @(*) begin
        if (pad_enable)
            padded_data = apply_padding(raw_input, data_len, rate_bytes);
        else
            padded_data = raw_input;
    end

    // ------------------------------------------------------------------
    // Decrypt state update — SW ascon_process_ciphertext last block:
    //
    //   c_lastlen = len(ct) % rate         (= data_len for last block)
    //   c_padx[i] = 0x01 at byte[c_lastlen], 0x00 elsewhere
    //   c_mask[i] = 0x00 for bytes[0..c_lastlen-1], 0xFF for rest
    //   Ci        = bytes_to_int(ct_zero_padded, 'little')
    //   S[0] = (S[0] & mask_int_hi) ^ Ci[0] ^ padx_int_hi
    //   S[1] = (S[1] & mask_int_lo) ^ Ci[1] ^ padx_int_lo
    //
    // mask zeros out the bytes that CT occupies (positions 0..lastlen-1)
    // then ORs in CT_int and the pad bit at position lastlen.
    // Result equals: (S[0] with CT bytes replaced) XOR pad_bit_at_lastlen
    // This makes decrypt state identical to encrypt state after same CT.
    //
    // For full blocks (c_lastlen=0 for non-last, handled by multi-block loop):
    //   mask = 0x0000...0000, padx = 0x0000...0000
    //   S[0] = Ci[0]  (direct replacement)
    //
    // AD always uses encrypt-style XOR absorb (enc_dec irrelevant for AD).
    // ------------------------------------------------------------------

    // Build mask and padx as 128-bit LE integers from data_len
    // Bytes [0..data_len-1] of mask = 0x00, bytes [data_len..15] = 0xFF
    // Byte [data_len] of padx = 0x01, rest = 0x00
    function [127:0] build_dec_mask;
        input [6:0] len;
        integer i;
        reg [127:0] m;
        begin
            m = 128'b0;
            for (i = 0; i < 16; i = i + 1)
                if (i >= len) m[127 - i*8 -: 8] = 8'hFF;
            build_dec_mask = m;
        end
    endfunction

    function [127:0] build_dec_padx;
        input [6:0] len;
        integer i;
        reg [127:0] p;
        begin
            p = 128'b0;
            if (len < 16) p[127 - len*8 -: 8] = 8'h01;
            build_dec_padx = p;
        end
    endfunction

    // CT zero-padded to 16 bytes (raw_input already has upper bytes zeroed by TB)
    wire [127:0] ct_zero_padded = raw_input;

    // LE integers for the two 64-bit halves of zero-padded CT
    wire [63:0] ci_hi = bswap64(ct_zero_padded[127:64]);  // bytes_to_int(ct[0:8],'little')
    wire [63:0] ci_lo = bswap64(ct_zero_padded[ 63: 0]);  // bytes_to_int(ct[8:16],'little')

    // mask and padx (computed from data_len)
    wire [127:0] dec_mask_be = build_dec_mask(data_len);
    wire [127:0] dec_padx_be = build_dec_padx(data_len);
    wire [63:0]  mask_hi     = bswap64(dec_mask_be[127:64]);
    wire [63:0]  mask_lo     = bswap64(dec_mask_be[ 63: 0]);
    wire [63:0]  padx_hi     = bswap64(dec_padx_be[127:64]);
    wire [63:0]  padx_lo     = bswap64(dec_padx_be[ 63: 0]);

    // Decrypt new state words
    wire [63:0] dec_new_x0 = (x0 & mask_hi) ^ ci_hi ^ padx_hi;
    wire [63:0] dec_new_x1 = (x1 & mask_lo) ^ ci_lo ^ padx_lo;

    assign pd_hi_bswap = bswap64(padded_data[127:64]);
    assign pd_lo_bswap = bswap64(padded_data[ 63: 0]);

    always @(*) begin
        state_temp          = state_in;
        data_out_comb       = 128'b0;
        data_out_valid_comb = 1'b0;
        state_xored         = state_in;

        case (mode)
            // ---------------------------------------------------------------
            // Ascon-128  (128-bit rate: x0, x1)
            // ---------------------------------------------------------------
            2'b00: begin
                if (enc_dec == 1'b0) begin
                    // ENCRYPT output = bswap(x0 XOR PT_int) = CT bytes
                    data_out_comb[127:64] = bswap64(x0 ^ pd_hi_bswap);
                    data_out_comb[ 63: 0] = bswap64(x1 ^ pd_lo_bswap);
                end else begin
                    // DECRYPT output = bswap(x0 XOR CT_int) = PT bytes
                    data_out_comb[127:64] = bswap64(x0 ^ ci_hi);
                    data_out_comb[ 63: 0] = bswap64(x1 ^ ci_lo);
                end

                if (block_sel == 2'b00) begin
                    // AD block: always encrypt-style XOR absorb with padding
                    state_temp[319:256] = x0 ^ pd_hi_bswap;
                    state_temp[255:192] = x1 ^ pd_lo_bswap;
                    data_out_valid_comb = 1'b0;
                end else begin
                    if (enc_dec == 1'b0) begin
                        // ENCRYPT: S[i] ^= PT_int_padded
                        state_temp[319:256] = x0 ^ pd_hi_bswap;
                        state_temp[255:192] = x1 ^ pd_lo_bswap;
                    end else begin
                        // DECRYPT: SW formula for last block
                        // S[0] = (S[0] & mask_hi) ^ ci_hi ^ padx_hi
                        state_temp[319:256] = dec_new_x0;
                        state_temp[255:192] = dec_new_x1;
                    end
                    data_out_valid_comb = 1'b1;
                end
                state_xored = state_temp;
            end

            // ---------------------------------------------------------------
            // Ascon-128a  (same 128-bit rate)
            // ---------------------------------------------------------------
            2'b01: begin
                if (enc_dec == 1'b0) begin
                    data_out_comb[127:64] = bswap64(x0 ^ pd_hi_bswap);
                    data_out_comb[ 63: 0] = bswap64(x1 ^ pd_lo_bswap);
                end else begin
                    data_out_comb[127:64] = bswap64(x0 ^ ci_hi);
                    data_out_comb[ 63: 0] = bswap64(x1 ^ ci_lo);
                end

                if (block_sel == 2'b00) begin
                    state_temp[319:256] = x0 ^ pd_hi_bswap;
                    state_temp[255:192] = x1 ^ pd_lo_bswap;
                    data_out_valid_comb = 1'b0;
                end else begin
                    if (enc_dec == 1'b0) begin
                        state_temp[319:256] = x0 ^ pd_hi_bswap;
                        state_temp[255:192] = x1 ^ pd_lo_bswap;
                    end else begin
                        state_temp[319:256] = dec_new_x0;
                        state_temp[255:192] = dec_new_x1;
                    end
                    data_out_valid_comb = 1'b1;
                end
                state_xored = state_temp;
            end

            default: begin
                state_xored         = state_in;
                data_out_comb       = 128'b0;
                data_out_valid_comb = 1'b0;
            end
        endcase
    end

    // ---- Registered output ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out       <= 128'b0;
            data_out_valid <= 1'b0;
        end else begin
            data_out_valid <= data_out_valid_comb;
            if (data_out_valid_comb) begin
                data_out <= data_out_comb;
                $display("  [DP DEBUG] enc_dec=%b block_sel=%b x0=%h input[127:64]=%h → out[127:64]=%h",
                         enc_dec, block_sel, x0, padded_data[127:64], data_out_comb[127:64]);
            end
        end
    end

endmodule