`timescale 1ns/1ps

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
//
// Trong SoC này: tất cả ngoại vi đều có sticky IRQ_STATUS (lưu trạng thái ngắt).
// Do đó PLIC Gateway ĐƯỢC THIẾT KẾ DẠNG LEVEL-TRIGGERED để bắt đúng các ngắt
// nối tiếp nhau mà không bị rơi rớt trong lúc CPU đang in-service.
// ============================================================================

module plic_gateway (
    input  wire clk,
    input  wire rst_n,

    input  wire irq_in,      // interrupt từ peripheral
    input  wire claim,       // 1-cycle pulse: CPU đang claim source này
    input  wire complete,    // 1-cycle pulse: CPU complete xử lý

    output wire pending      // 1 = source này đang pending
);

    reg  pending_r;
    reg  in_service;   // 1 = đang được claim, chưa complete

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_r  <= 1'b0;
            in_service <= 1'b0;
        end else begin
            if (claim) begin
                pending_r  <= 1'b0;  // clear pending khi CPU claim
                in_service <= 1'b1;  // mark in-service
            end

            if (complete) begin
                in_service <= 1'b0;  // CPU done, có thể nhận IRQ mới
            end

            // Level-triggered: Set pending khi irq_in=1 và đang không được xử lý
            if (irq_in && !in_service && !claim) begin
                pending_r <= 1'b1;
            end

`ifdef DEBUG_WDATA
            if (irq_in && !pending_r)
                $display("[%6d] [GW] irq_in=%b in_service=%b claim=%b → pending_r=%b (will set=%b)",
                         $time, irq_in, in_service, claim, pending_r,
                         irq_in && !in_service && !claim);
`endif
        end
    end

    assign pending = pending_r;

endmodule