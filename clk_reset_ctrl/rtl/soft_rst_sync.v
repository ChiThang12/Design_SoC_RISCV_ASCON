// ============================================================================
// Module  : soft_rst_sync
// Project : RISC-V SoC
//
// Tái đồng bộ hóa soft_rst_pulse từ SOC CTRL vào domain fabric_rst_n.
//
// WHY cần module riêng:
//   soft_rst_pulse được tạo trong domain clock bởi soc_ctrl_slave (AXI write).
//   Tuy nhiên nó phải kết hợp với fabric_rst_n để tạo cpu_rst.
//   Nếu pulse rất ngắn (1 cycle), cần đảm bảo nó không bị miss hoặc gây
//   glitch trên rst_n combined.
//
// Logic:
//   1. Latch soft_rst_pulse vào SR-latch
//   2. Kéo dài thành STRETCH_CYCLES chu kỳ để đảm bảo tất cả FF nhận được
//   3. Kết hợp với por_rst_n thành fabric_rst_n_combined
//
// STRETCH_CYCLES = 8: đủ để truyền qua chuỗi reset_sync và flush pipeline CPU.
// ============================================================================

// PROVIDES: soft_rst_n (1-cycle pulse → stretched STRETCH_CYCLES cycles, active-low)
// REQUIRES: clk, por_rst_n (POR gate — inhibit soft_rst before power stable), soft_rst_pulse (1-cycle same domain)
module soft_rst_sync #(
    parameter STRETCH_CYCLES = 8   // WHY 8: đủ để flush 5-stage pipeline + 2FF sync
) (
    input  wire clk,
    input  wire por_rst_n,        // POR combined reset (đã sync)
    input  wire soft_rst_pulse,   // 1-cycle pulse từ soc_ctrl_slave
    output wire soft_rst_n        // active-low reset output, đã kéo dài
);

    localparam CTR_W = $clog2(STRETCH_CYCLES + 1);

    reg [CTR_W-1:0] ctr;
    reg             rst_active;

    always @(posedge clk or negedge por_rst_n) begin
        if (!por_rst_n) begin
            ctr        <= {CTR_W{1'b0}};
            rst_active <= 1'b0;
        end else begin
            if (soft_rst_pulse && !rst_active) begin
                // Bắt đầu soft reset: bắt pulse, khởi động counter
                ctr        <= {CTR_W{1'b0}};
                rst_active <= 1'b1;
            end else if (rst_active) begin
                if (ctr < STRETCH_CYCLES[CTR_W-1:0] - 1) begin
                    ctr <= ctr + 1'b1;
                end else begin
                    // Hết thời gian: release reset
                    rst_active <= 1'b0;
                    ctr        <= {CTR_W{1'b0}};
                end
            end
        end
    end

    // active-low: 0 khi đang reset, 1 khi bình thường
    assign soft_rst_n = ~rst_active;

endmodule