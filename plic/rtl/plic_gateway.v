// ============================================================================
// Module  : plic_gateway
// Project : RISC-V SoC — PLIC
//
// Interrupt Gateway cho MỘT source. Theo RISC-V PLIC spec:
//   - Nhận tín hiệu interrupt từ peripheral (level hoặc edge)
//   - Latch thành PENDING bit (sticky until claim)
//   - Khi claim xảy ra: clear pending, cho phép nhận IRQ tiếp theo
//   - Khi complete xảy ra: re-enable gate để nhận IRQ mới từ peripheral
//
// Level-triggered: pending set khi interrupt HIGH, hold cho đến claim.
// Edge-triggered:  pending set khi cạnh lên, giữ đến claim.
//
// WHY separate gateway per source: mỗi peripheral có thể mix level/edge.
// GPIO thường edge-trigger, UART thường level-trigger.
//
// Trong SoC này: tất cả dùng EDGE (peripheral đã có sticky IRQ_STATUS
// riêng, nên PLIC chỉ cần bắt cạnh lên của irq_in).
// ============================================================================

module plic_gateway (
    input  wire clk,
    input  wire rst_n,

    input  wire irq_in,      // interrupt từ peripheral
    input  wire claim,       // 1-cycle pulse: CPU đang claim source này
    input  wire complete,    // 1-cycle pulse: CPU complete xử lý

    output wire pending      // 1 = source này đang pending
);

    reg  irq_prev;
    reg  pending_r;
    reg  in_service;   // 1 = đang được claim, chưa complete

    wire irq_edge = irq_in & ~irq_prev;  // rising edge detect

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_prev   <= 1'b0;
            pending_r  <= 1'b0;
            in_service <= 1'b0;
        end else begin
            irq_prev <= irq_in;

            if (claim) begin
                pending_r  <= 1'b0;  // clear pending khi CPU claim
                in_service <= 1'b1;  // mark in-service
            end

            if (complete) begin
                in_service <= 1'b0;  // CPU done, có thể nhận IRQ mới
            end

            // Set pending: chỉ khi không đang in_service (hoặc vừa complete)
            // WHY: tránh race condition nếu peripheral vẫn assert trong khi complete
            if (irq_edge && !in_service && !claim) begin
                pending_r <= 1'b1;
            end
        end
    end

    assign pending = pending_r;

endmodule