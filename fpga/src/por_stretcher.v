`timescale 1ns/1ps

// ============================================================================
// Module  : por_stretcher
// Project : RISC-V SoC
//
// Kéo dài tín hiệu Power-On Reset (POR) tối thiểu POR_CYCLES chu kỳ
// sau khi por_n từ pad assert (low). Đảm bảo toàn bộ rail nguồn đã ổn
// định trước khi reset release.
//
// WHY: Pad POR_N từ foundry có thể bounce hoặc rise rất nhanh. Counter
//   giữ reset thêm N chu kỳ sau khi pad lên 1 → safe margin.
//
// POR_CYCLES = 1000 → tại 100 MHz = 10 µs (đáp ứng yêu cầu spec ≥10 µs).
// ============================================================================

// PROVIDES: por_n_out (POR stretched ≥ POR_CYCLES cycles, glitch-filtered, active-low)
// REQUIRES: clk (any freq), por_n_raw (pad POR, active-low, may bounce)
module por_stretcher #(
    parameter POR_CYCLES = 1000   // WHY 1000: 10µs @ 100MHz. Tăng nếu VDD rise chậm hơn.
) (
    input  wire clk,
    input  wire por_n_raw,    // POR từ pad (có thể glitch)
    output wire por_n_out     // POR đã kéo dài, sạch
);

    // Counter đủ rộng để đếm POR_CYCLES
    localparam CTR_W = $clog2(POR_CYCLES + 1);

    reg [CTR_W-1:0] ctr;
    reg             stretched;

    always @(posedge clk or negedge por_n_raw) begin
        if (!por_n_raw) begin
            // POR assert → reset counter, giữ output ở 0
            ctr       <= {CTR_W{1'b0}};
            stretched <= 1'b0;
        end else begin
            if (ctr < POR_CYCLES[CTR_W-1:0]) begin
                // Đang đếm: giữ reset
                ctr       <= ctr + 1'b1;
                stretched <= 1'b0;
            end else begin
                // Đã đủ chu kỳ: release reset
                stretched <= 1'b1;
            end
        end
    end

    assign por_n_out = stretched;

endmodule