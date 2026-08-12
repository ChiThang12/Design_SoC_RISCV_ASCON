`timescale 1ns/1ps

// ============================================================================
// Module  : uart_rx
// Project : RISC-V SoC — UART peripheral
//
// RX sampler với x16 oversample, 8N1.
// Phát hiện start bit bằng cạnh xuống của rx_in.
// Lấy mẫu tại khe 8/16 (giữa bit) để đạt noise margin tốt nhất.
//
// WHY sample tại khe 8: đây là điểm cách cạnh bit xa nhất,
//   chịu được jitter ±7/16 ≈ 44% bit period trước khi lỗi.
//
// Overrun: nếu RX FIFO đầy khi RX hoàn thành 1 byte → set overrun flag,
//   byte mới bị bỏ (FIFO không push). CPU phải clear flag qua CTRL.
// ============================================================================

module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_rx16,  // 1 pulse mỗi 1/16 bit period
    // Input
    input  wire       rx_in,      // chân RX từ pad
    // RX FIFO interface
    input  wire       fifo_full,
    output wire [7:0] fifo_din,
    output wire       fifo_push,
    // Status
    output wire       rx_overrun  // set khi byte đến mà FIFO đầy
);

    // FSM states
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    // 2-FF synchronizer cho rx_in (tránh metastability từ async UART line)
    (* ASYNC_REG = "TRUE" *) reg rx_ff1, rx_ff2, rx_ff3;
    wire rx_sync = rx_ff2;
    wire rx_fall = rx_ff3 & ~rx_ff2;   // cạnh xuống (start bit detect)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_ff1 <= 1'b1;
            rx_ff2 <= 1'b1;
            rx_ff3 <= 1'b1;
        end else begin
            rx_ff1 <= rx_in;
            rx_ff2 <= rx_ff1;
            rx_ff3 <= rx_ff2;
        end
    end

    reg [1:0]  state;
    reg [3:0]  os_cnt;    // oversample counter 0..15
    reg [2:0]  bit_cnt;   // bit counter 0..7
    reg [7:0]  shift_reg;
    reg        push_r;
    reg        overrun_r;

    assign fifo_din  = shift_reg;
    assign fifo_push = push_r;
    assign rx_overrun = overrun_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            os_cnt    <= 4'd0;
            bit_cnt   <= 3'd0;
            shift_reg <= 8'd0;
            push_r    <= 1'b0;
            overrun_r <= 1'b0;
        end else begin
            push_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    overrun_r <= 1'b0;
                    if (rx_fall) begin
                        // Phát hiện start bit: bắt đầu đếm oversample
                        os_cnt <= 4'd0;
                        state  <= S_START;
                    end
                end

                S_START: begin
                    // Chờ đến khe 8 (giữa start bit) để xác nhận start bit thật
                    if (tick_rx16) begin
                        if (os_cnt == 4'd7) begin
                            // Sample giữa start bit: phải = 0
                            if (!rx_sync) begin
                                os_cnt  <= 4'd0;
                                bit_cnt <= 3'd0;
                                state   <= S_DATA;
                            end else begin
                                // Noise / glitch → quay lại IDLE
                                state <= S_IDLE;
                            end
                        end else begin
                            os_cnt <= os_cnt + 4'd1;
                        end
                    end
                end

                S_DATA: begin
                    if (tick_rx16) begin
                        if (os_cnt == 4'd15) begin
                            // Khe 15 = cuối bit hiện tại, cũng là sample point bit kế
                            // WHY sample tại khe 15 của os_cnt:
                            //   os_cnt reset về 0 khi bắt đầu bit mới, khe 7-8 là giữa.
                            //   Nhưng sau start bit align, sample tại 15 = giữa của bit data.
                            os_cnt    <= 4'd0;
                            shift_reg <= {rx_sync, shift_reg[7:1]};  // LSB first: shift right
                            if (bit_cnt == 3'd7) begin
                                state <= S_STOP;
                            end else begin
                                bit_cnt <= bit_cnt + 3'd1;
                            end
                        end else begin
                            os_cnt <= os_cnt + 4'd1;
                        end
                    end
                end

                S_STOP: begin
                    if (tick_rx16) begin
                        if (os_cnt == 4'd7) begin
                            // Sample giữa stop bit
                            if (rx_sync) begin
                                // Stop bit hợp lệ: push vào FIFO
                                if (!fifo_full) begin
                                    push_r <= 1'b1;
                                end else begin
                                    overrun_r <= 1'b1;   // FIFO đầy → overrun
                                end
                            end
                            // Dù stop bit có hợp lệ hay không → về IDLE
                            state  <= S_IDLE;
                            os_cnt <= 4'd0;
                        end else begin
                            os_cnt <= os_cnt + 4'd1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule