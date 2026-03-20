// ============================================================================
// Module  : uart_baud_gen
// Project : RISC-V SoC — UART peripheral
//
// Tạo xung tick 1-cycle mỗi khi đủ (divisor+1) chu kỳ clock.
// TX dùng tick thẳng (1 tick = 1 bit period).
// RX dùng tick x16 oversample để lấy mẫu giữa bit (sample khi cnt_os==8).
//
// Công thức: divisor = clk_freq / baud_rate - 1
//   115200 baud @ 100 MHz → divisor = 868 - 1 = 867 (0x363)
//   9600   baud @ 100 MHz → divisor = 10416 - 1 = 10415
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

    // -------------------------------------------------------------------------
    // Counter chia 16 lần cho oversample RX
    // WHY x16: chia bit period thành 16 khe → lấy mẫu tại khe 8 (giữa bit)
    //          chịu được jitter ±6/16 = 37.5% bit period
    // -------------------------------------------------------------------------
    reg [15:0] cnt_tx;
    reg [3:0]  cnt_os;   // 0..15 oversample counter
    reg        tick_tx_r;
    reg        tick_rx16_r;

    // divisor_os = divisor / 16 (baud tick chia 16 cho oversample)
    // WHY dùng shift: divisor >> 4 = divisor / 16, tổng hợp thành wire
    wire [15:0] divisor_os = (divisor == 16'd0) ? 16'd0 : (divisor >> 4);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_tx      <= 16'd0;
            cnt_os      <= 4'd0;
            tick_tx_r   <= 1'b0;
            tick_rx16_r <= 1'b0;
        end else begin
            tick_tx_r   <= 1'b0;
            tick_rx16_r <= 1'b0;

            // Oversample tick (÷16 của baud)
            if (cnt_tx >= divisor_os) begin
                cnt_tx      <= 16'd0;
                tick_rx16_r <= 1'b1;

                // TX tick: mỗi 16 oversample ticks = 1 bit period
                if (cnt_os == 4'd15) begin
                    cnt_os    <= 4'd0;
                    tick_tx_r <= 1'b1;
                end else begin
                    cnt_os <= cnt_os + 4'd1;
                end
            end else begin
                cnt_tx <= cnt_tx + 16'd1;
            end
        end
    end

    assign tick_tx   = tick_tx_r;
    assign tick_rx16 = tick_rx16_r;

endmodule