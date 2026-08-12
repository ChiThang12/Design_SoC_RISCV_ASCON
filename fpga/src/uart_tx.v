`timescale 1ns/1ps

// ============================================================================
// Module  : uart_tx
// Project : RISC-V SoC — UART peripheral
//
// TX shift register 8N1: Start(0) + 8 data bits (LSB first) + Stop(1).
// Hoạt động:
//   IDLE:    tx_out=1, chờ fifo_empty=0
//   START:   shift out bit start (0) khi tick_tx
//   DATA:    shift ra 8 bit data, LSB trước
//   STOP:    shift out bit stop (1), sau đó về IDLE
//
// WHY LSB first: chuẩn UART/RS-232 truyền LSB trước (bit 0 ra trước bit 7).
// ============================================================================

module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_tx,    // 1 pulse mỗi bit period từ baud_gen
    // TX FIFO interface
    input  wire [7:0] fifo_dout,  // data từ TX FIFO
    input  wire       fifo_empty, // TX FIFO rỗng
    output wire       fifo_pop,   // pop 1 byte từ TX FIFO
    // UART line
    output wire       tx_out,     // chân TX ra pad
    // Status
    output wire       tx_busy     // 1 khi đang truyền (dùng cho IRQ tx_empty)
);

    // FSM states
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [7:0]  shift_reg;
    reg [2:0]  bit_cnt;   // đếm 0..7 cho 8 bit data
    reg        tx_reg;    // output register
    reg        pop_reg;

    assign tx_out   = tx_reg;
    assign fifo_pop = pop_reg;
    assign tx_busy  = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            shift_reg <= 8'd0;
            bit_cnt   <= 3'd0;
            tx_reg    <= 1'b1;   // line idle = high
            pop_reg   <= 1'b0;
        end else begin
            pop_reg <= 1'b0;    // pulse 1 cycle

            case (state)
                S_IDLE: begin
                    tx_reg <= 1'b1;
                    if (!fifo_empty && tick_tx) begin
                        // Load byte từ FIFO, bắt đầu truyền
                        shift_reg <= fifo_dout;
                        pop_reg   <= 1'b1;   // pop byte này
                        state     <= S_START;
                    end
                end

                S_START: begin
                    if (tick_tx) begin
                        tx_reg  <= 1'b0;   // start bit = 0
                        bit_cnt <= 3'd0;
                        state   <= S_DATA;
                    end
                end

                S_DATA: begin
                    if (tick_tx) begin
                        tx_reg    <= shift_reg[0];       // LSB first
                        shift_reg <= {1'b0, shift_reg[7:1]};  // shift right
                        if (bit_cnt == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end
                end

                S_STOP: begin
                    if (tick_tx) begin
                        tx_reg <= 1'b1;   // stop bit = 1
                        state  <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule