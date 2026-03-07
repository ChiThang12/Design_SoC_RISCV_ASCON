// ============================================================================
// Module: ASCON_DATAPATH
// Mô tả: Xử lý luồng dữ liệu (plaintext/ciphertext/AD)
//
// Chức năng:
//   Encrypt: ctext = state_x0 ^ ptext;  state_x0 (next) <- ctext
//   Decrypt: ptext = state_x0 ^ ctext;  state_x0 (next) <- ctext (feed-forward)
//
// Với AD: chỉ XOR vào x0, không output (handled qua xor_data/xor_enable)
//
// data_out: 64-bit kết quả (ciphertext hoặc plaintext)
// xor_data: 64-bit để XOR vào state x0 (gửi đến STATE_REG)
// ============================================================================

module ASCON_DATAPATH (
    input  wire         clk,
    input  wire         rst_n,

    // Mode: 0=encrypt, 1=decrypt
    input  wire         mode,          // 0: encrypt, 1: decrypt

    // Data input (plaintext for encrypt, ciphertext for decrypt, or AD)
    input  wire [63:0]  data_in,

    // Current x0 từ state register
    input  wire [63:0]  state_x0,

    // Control
    input  wire         enable,        // pulse: thực hiện encrypt/decrypt 1 block

    // Outputs
    output reg  [63:0]  data_out,      // ciphertext (enc) hoặc plaintext (dec)
    output reg  [63:0]  xor_data,      // giá trị để XOR vào state_x0
    output reg          xor_valid      // pulse: xor_data hợp lệ
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= 64'd0;
            xor_data  <= 64'd0;
            xor_valid <= 1'b0;
        end else begin
            xor_valid <= 1'b0;

            if (enable) begin
                if (!mode) begin
                    // Encrypt: ctext = x0 ^ ptext; x0 <- ctext
                    data_out  <= state_x0 ^ data_in;
                    xor_data  <= state_x0 ^ data_in;
                end else begin
                    // Decrypt: ptext = x0 ^ ctext; x0 <- ctext
                    data_out  <= state_x0 ^ data_in;
                    xor_data  <= data_in;           // đặt x0 <- ctext (feed-forward)
                end
                xor_valid <= 1'b1;
            end
        end
    end

endmodule