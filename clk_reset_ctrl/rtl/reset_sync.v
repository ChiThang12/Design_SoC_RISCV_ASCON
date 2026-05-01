`timescale 1ns/1ps

// ============================================================================
// Module  : reset_sync
// Project : RISC-V SoC
//
// Đồng bộ hóa tín hiệu reset bất đồng bộ vào domain clock cục bộ.
// Dùng chuỗi 2 flip-flop (tiêu chuẩn công nghiệp để chống metastability).
//
// WHY 2FF: Khi rst_async_n thay đổi không đồng bộ với clk, FF đầu tiên
//   có thể rơi vào metastable. Xác suất FF vẫn metastable sau 1 chu kỳ
//   clock là cực nhỏ (< 10^-20 ở 28nm). FF thứ 2 bắt output đã ổn định.
//
// Lưu ý synthesis: Attribute (* ASYNC_REG = "TRUE" *) báo cho tool biết
//   đây là chuỗi đồng bộ hóa → không optimize / retime các FF này.
// ============================================================================

// PROVIDES: rst_sync_n (async-assert / sync-deassert, 2FF metastability filtered)
// REQUIRES: clk (destination domain clock), rst_async_n (any domain, active-low)
module reset_sync (
    input  wire clk,          // clock của domain nhận
    input  wire rst_async_n,  // reset bất đồng bộ đầu vào (active-low)
    output wire rst_sync_n    // reset đã đồng bộ ra (active-low)
);

    // 2 FF nối tiếp, attribute giữ FF không bị optimize / retimed bởi tool
    (* ASYNC_REG = "TRUE" *) reg ff1, ff2;

    always @(posedge clk or negedge rst_async_n) begin
        if (!rst_async_n) begin
            // Khi reset assert: cả 2 FF về 0 ngay lập tức (async path)
            ff1 <= 1'b0;
            ff2 <= 1'b0;
        end else begin
            // Khi reset deassert: 1 = release, truyền qua chuỗi FF
            // Sau 2 chu kỳ clock, rst_sync_n = 1 (released)
            ff1 <= 1'b1;
            ff2 <= ff1;
        end
    end

    assign rst_sync_n = ff2;

endmodule