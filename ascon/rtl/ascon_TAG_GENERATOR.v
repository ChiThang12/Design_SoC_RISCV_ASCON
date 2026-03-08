// ============================================================
// Module: ascon_TAG_GENERATOR  (FIXED for NIST Ascon-AEAD128)
//
// CHANGES vs original:
//   1. Tag output byte-reversed per 64-bit word:
//        SW: tag = int_to_bytes(S[3] ^ LE(key[0:8]), 8, 'little')
//                || int_to_bytes(S[4] ^ LE(key[8:16]), 8, 'little')
//        Internal state x3 and x4 are stored as LE integers in HW.
//        x3 ^ LE(key[0:8]) = x3 ^ bswap(key_hi) = the correct LE integer.
//        Output must be byte-reversed to produce the correct byte stream.
//
//   2. Key XOR uses bswapped key values (to match LE integer values):
//        SW: tag_w0 = S[3] ^ bytes_to_int(key[0:8],'little')
//                   = state[127:64] ^ bswap(key_in[127:64])
//        SW: tag_w1 = S[4] ^ bytes_to_int(key[8:16],'little')
//                   = state[63:0] ^ bswap(key_in[63:0])
//        Then output as LE bytes = bswap(tag_w0) || bswap(tag_w1)
//
// SW ascon.py finalization:
//   S[3] ^= bytes_to_int(key[-16:-8], 'little')  = bswap(key[127:64])
//   S[4] ^= bytes_to_int(key[-8:],   'little')  = bswap(key[63:0])
//   tag = int_to_bytes(S[3],8,'little') + int_to_bytes(S[4],8,'little')
//       = bswap(S[3] as 64-bit) || bswap(S[4] as 64-bit)  (in BE Verilog)
// ============================================================
module ascon_TAG_GENERATOR (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         gen_tag,
    input  wire [319:0] state_in,
    input  wire [127:0] key_in,

    output reg  [127:0] tag_out,
    output reg          tag_valid
);

    // ------------------------------------------------------------------
    // Byte-swap: reverse byte order within 64-bit word
    // ------------------------------------------------------------------
    function [63:0] bswap64;
        input [63:0] x;
        begin
            bswap64 = { x[ 7: 0], x[15: 8], x[23:16], x[31:24],
                        x[39:32], x[47:40], x[55:48], x[63:56] };
        end
    endfunction

    // x3 = state_in[127:64], x4 = state_in[63:0]
    // key_hi_bswap = bswap(key_in[127:64]) = LE int of key bytes [0:7]
    // key_lo_bswap = bswap(key_in[63:0])   = LE int of key bytes [8:15]
    //
    // tag_w0 = x3 ^ key_hi_bswap  (LE integer = SW tag word 0)
    // tag_w1 = x4 ^ key_lo_bswap  (LE integer = SW tag word 1)
    //
    // Output = bswap(tag_w0) || bswap(tag_w1)  (= LE bytes → BE for output)
    //        = (x3 ^ key_hi_bswap reversed) || (x4 ^ key_lo_bswap reversed)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_out   <= 128'b0;
            tag_valid <= 1'b0;
        end else if (gen_tag) begin
            // Step 1: compute LE integer XOR
            // tag_w0 = state[127:64] ^ bswap(key_in[127:64])
            // tag_w1 = state[63:0]   ^ bswap(key_in[63:0])
            // Step 2: output as bytes (bswap the result to get LE byte stream)
            tag_out <= {
                bswap64(state_in[127:64] ^ bswap64(key_in[127:64])),  // tag[127:64]
                bswap64(state_in[ 63: 0] ^ bswap64(key_in[ 63: 0]))   // tag[63:0]
            };
            tag_valid <= 1'b1;
        end else begin
            tag_valid <= 1'b0;
        end
    end

endmodule