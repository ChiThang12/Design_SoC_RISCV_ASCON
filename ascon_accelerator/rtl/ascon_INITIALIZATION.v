// ============================================================
// Module: ascon_INITIALIZATION  (FIXED for NIST Ascon-AEAD128)
//
// CHANGES vs original:
//   1. IV_128  updated to NIST Ascon-AEAD128 value:
//        OLD: 64'h80400c0600000000  (old Ascon-128 v1.2)
//        NEW: 64'h00001000808c0001  (LE-int of NIST IV bytes:
//             01 00 8c 80 00 10 00 00 = version=1, b||a=0x8c,
//             taglen=128 LE16=0x0080, rate=16=0x10)
//
//   2. Key and Nonce byte-reversed at load (each 8-byte word):
//        HW receives data as big-endian from TB.
//        SW (ascon.py) interprets bytes as little-endian integers.
//        To make internal state match SW, each 64-bit word is
//        byte-reversed so the LE integer value equals the SW value.
//
// State layout (320 bits):
//   [319:256] = x0 = IV  (64 bits)
//   [255:192] = x1 = bswap(key_in[127:64])
//   [191:128] = x2 = bswap(key_in[63:0])
//   [127: 64] = x3 = bswap(nonce_in[127:64])
//   [ 63:  0] = x4 = bswap(nonce_in[63:0])
// ============================================================
module ascon_INITIALIZATION (
    input  wire         clk,
    input  wire         rst_n,

    // Control
    input  wire         load_key,       // pulse: latch key
    input  wire         load_nonce,     // pulse: latch nonce
    input  wire [1:0]   mode,           // 00=Ascon-128, 01=Ascon-128a, 10=Ascon-Hash
    input  wire         init_start,     // pulse: trigger init output

    // Data
    input  wire [127:0] key_in,
    input  wire [127:0] nonce_in,

    // Output to ASCON STATE REGISTER
    output reg  [319:0] init_state_out,
    output reg          init_valid      // high when init_state_out is ready
);

    // ------------------------------------------------------------------
    // NIST Ascon-AEAD128 IV (FIXED):
    //   SW ascon.py builds IV bytes: [version=1, 0, (b<<4)|a=0x8c,
    //                                  taglen=128 as LE16 → 0x80,0x00,
    //                                  rate=16=0x10, 0, 0]
    //   = 01 00 8c 80 00 10 00 00  (8 bytes)
    //   SW loads as LE 64-bit int: int.from_bytes(...,'little')
    //                             = 0x00001000808c0001
    // ------------------------------------------------------------------
    localparam [63:0] IV_128  = 64'h00001000808c0001; // NIST Ascon-AEAD128
    localparam [63:0] IV_128A = 64'h00001000808c0002; // Ascon-AEAD128a (placeholder)
    localparam [63:0] IV_HASH = 64'h00400c0000000100; // Ascon-Hash (unchanged)

    // ------------------------------------------------------------------
    // Byte-swap function: reverse byte order within 64-bit word
    // Converts big-endian Verilog word to little-endian integer value
    // that matches SW ascon.py's bytes_to_int(..., 'little')
    // ------------------------------------------------------------------
    function [63:0] bswap64;
        input [63:0] x;
        begin
            bswap64 = { x[ 7: 0], x[15: 8], x[23:16], x[31:24],
                        x[39:32], x[47:40], x[55:48], x[63:56] };
        end
    endfunction

    reg [127:0] key_reg;
    reg [127:0] nonce_reg;

    // Latch key (store as-is; bswap applied when building state)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) key_reg <= 128'b0;
        else if (load_key) key_reg <= key_in;
    end

    // Latch nonce
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) nonce_reg <= 128'b0;
        else if (load_nonce) nonce_reg <= nonce_in;
    end

    // ------------------------------------------------------------------
    // Build initial state:
    //   x0 = IV  (already a LE integer constant — no swap needed)
    //   x1 = bswap(key[127:64])   = LE int of key bytes [0:7]
    //   x2 = bswap(key[63:0])     = LE int of key bytes [8:15]
    //   x3 = bswap(nonce[127:64]) = LE int of nonce bytes [0:7]
    //   x4 = bswap(nonce[63:0])   = LE int of nonce bytes [8:15]
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_state_out <= 320'b0;
            init_valid     <= 1'b0;
        end else if (init_start) begin
            init_valid <= 1'b1;
            case (mode)
                2'b00: init_state_out <= {
                    IV_128,
                    bswap64(key_reg[127:64]),    // x1: bswap key bytes 0..7
                    bswap64(key_reg[63:0]),      // x2: bswap key bytes 8..15
                    bswap64(nonce_reg[127:64]),  // x3: bswap nonce bytes 0..7
                    bswap64(nonce_reg[63:0])     // x4: bswap nonce bytes 8..15
                };
                2'b01: init_state_out <= {
                    IV_128A,
                    bswap64(key_reg[127:64]),
                    bswap64(key_reg[63:0]),
                    bswap64(nonce_reg[127:64]),
                    bswap64(nonce_reg[63:0])
                };
                2'b10: init_state_out <= {
                    IV_HASH,
                    bswap64(key_reg[127:64]),
                    bswap64(key_reg[63:0]),
                    bswap64(nonce_reg[127:64]),
                    bswap64(nonce_reg[63:0])
                };
                default: init_state_out <= {
                    IV_128,
                    bswap64(key_reg[127:64]),
                    bswap64(key_reg[63:0]),
                    bswap64(nonce_reg[127:64]),
                    bswap64(nonce_reg[63:0])
                };
            endcase
        end else begin
            init_valid <= 1'b0;
        end
    end

endmodule