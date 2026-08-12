`timescale 1ns/1ps

// ============================================================================
// Module  : uart_baud_gen
// Project : RISC-V SoC — UART peripheral
//
// Tạo xung tick 1-cycle theo số chu kỳ clock lập trình trong divisor.
// TX dùng tick thẳng (1 tick = 1 bit period).
// RX dùng tick x16 oversample để lấy mẫu giữa bit (sample khi cnt_os==8).
//
// Công thức trong firmware/testbench hiện tại:
//   divisor = clk_freq / baud_rate
//   115200 baud @ 100 MHz → divisor = 868
//   9600   baud @ 100 MHz → divisor = 10416
//
// Divisor = 0 → tick mỗi 1 cycle (chỉ dùng test).
// ============================================================================

module uart_baud_gen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] divisor,    // từ thanh ghi BAUD_DIV
    output wire        tick_tx,    // 1 pulse mỗi bit period (TX)
    output wire        tick_rx16   // 1 pulse mỗi 1/16 bit period (RX oversample)
);

    reg [15:0] cnt_tx;
    reg [15:0] cnt_rx16;
    reg        tick_tx_r;
    reg        tick_rx16_r;

    // One programmed TX bit period is `divisor` core clocks. Keep divisor=0 as
    // a simulation-friendly 1-cycle period.
    wire [15:0] tx_period = (divisor <= 16'd1) ? 16'd1 : divisor;

    // RX oversample tick is approximately 1/16 bit period, clamped to 1 cycle.
    wire [15:0] rx16_period = (divisor < 16'd16) ? 16'd1 : (divisor >> 4);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_tx      <= 16'd0;
            cnt_rx16    <= 16'd0;
            tick_tx_r   <= 1'b0;
            tick_rx16_r <= 1'b0;
        end else begin
            tick_tx_r   <= 1'b0;
            tick_rx16_r <= 1'b0;

            if (cnt_tx >= (tx_period - 16'd1)) begin
                cnt_tx    <= 16'd0;
                tick_tx_r <= 1'b1;
            end else begin
                cnt_tx <= cnt_tx + 16'd1;
            end

            if (cnt_rx16 >= (rx16_period - 16'd1)) begin
                cnt_rx16    <= 16'd0;
                tick_rx16_r <= 1'b1;
            end else begin
                cnt_rx16 <= cnt_rx16 + 16'd1;
            end
        end
    end

    assign tick_tx   = tick_tx_r;
    assign tick_rx16 = tick_rx16_r;

endmodule
