// ============================================================================
// Module: ASCON_INITIALIZATION
// Mô tả: Tạo giá trị khởi tạo 320-bit cho state register
//
//  ASCON-128:  IV(64) || Key(128) || Nonce(128)
//              IV = 0x80400C0600000000
//
//  ASCON-Hash: IV_Hash(320) = 0x00400C0000000100 || 0 || 0 || 0 || 0
//              (từ ASCON spec, IV khác cho hash mode)
//
// Outputs:
//   init_value  — 320-bit giá trị để nạp vào state register
// ============================================================================

module ASCON_INITIALIZATION (
    input  wire [1:0]   mode,          // 00/01: AEAD, 10: Hash
    input  wire [127:0] key,           // 128-bit key
    input  wire [127:0] nonce,         // 128-bit nonce

    output reg  [319:0] init_value     // giá trị khởi tạo ra state
);

    // ASCON-128 IV cố định
    localparam [63:0] ASCON128_IV   = 64'h80400c0600000000;
    // ASCON-Hash IV
    localparam [63:0] ASCON_HASH_IV = 64'h00400c0000000100;

    always @(*) begin
        case (mode)
            2'b00,    // Encrypt
            2'b01:    // Decrypt
                // State = IV || Key[127:64] || Key[63:0] || Nonce[127:64] || Nonce[63:0]
                init_value = {ASCON128_IV, key, nonce};

            2'b10:    // Hash
                // State = IV_Hash || 0 || 0 || 0 || 0
                init_value = {ASCON_HASH_IV, 256'h0};

            default:
                init_value = {ASCON128_IV, key, nonce};
        endcase
    end

endmodule