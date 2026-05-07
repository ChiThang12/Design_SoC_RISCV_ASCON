`timescale 1ns/1ps

// ============================================================================
// Module  : uart_irq_gen
// Project : RISC-V SoC — UART peripheral
//
// Tạo xung IRQ 1 cycle cho các sự kiện UART:
//   tx_empty_irq : TX FIFO chuyển từ non-empty → empty (CPU nên nạp thêm)
//   rx_valid_irq : RX FIFO chuyển từ empty → non-empty (có byte mới)
//
// WHY phát hiện cạnh (edge detect) thay vì level:
//   Level IRQ sẽ liên tục assert khi FIFO rỗng/đầy → CPU bị ngắt liên tục.
//   Edge detect chỉ báo khi trạng thái THAY ĐỔI → CPU nhận 1 IRQ, xử lý xong.
//   Sau đó IRQ_STATUS sticky latch giữ nguyên cho đến khi CPU RW1C clear.
// ============================================================================

module uart_irq_gen (
    input  wire clk,
    input  wire rst_n,
    // FIFO status inputs
    input  wire tx_fifo_empty,
    input  wire rx_fifo_empty,
    // IRQ pulse outputs (1-cycle)
    output wire tx_empty_irq,   // TX FIFO vừa trở nên rỗng
    output wire rx_valid_irq    // RX FIFO vừa có dữ liệu
);

    reg tx_empty_prev;
    reg rx_empty_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_empty_prev <= 1'b1;
            rx_empty_prev <= 1'b1;
        end else begin
            tx_empty_prev <= tx_fifo_empty;
            rx_empty_prev <= rx_fifo_empty;
        end
    end

    // Cạnh lên của tx_fifo_empty: FIFO vừa drain hết
    assign tx_empty_irq = tx_fifo_empty & ~tx_empty_prev;

    // Cạnh xuống của rx_fifo_empty: FIFO vừa có byte đầu tiên
    assign rx_valid_irq = ~rx_fifo_empty & rx_empty_prev;

endmodule