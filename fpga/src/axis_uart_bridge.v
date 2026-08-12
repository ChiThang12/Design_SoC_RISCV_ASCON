`timescale 1ns/1ps

module axis_uart_bridge #(
    parameter integer BAUD_DIV = 868
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tkeep,
    input  wire       s_axis_tvalid,
    input  wire       s_axis_tlast,
    output wire       s_axis_tready,

    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tkeep,
    output wire       m_axis_tvalid,
    output wire       m_axis_tlast,
    input  wire       m_axis_tready,

    output wire       uart_tx_to_soc,
    input  wire       uart_rx_from_soc
);
    localparam [1:0] TX_IDLE  = 2'd0;
    localparam [1:0] TX_START = 2'd1;
    localparam [1:0] TX_DATA  = 2'd2;
    localparam [1:0] TX_STOP  = 2'd3;

    reg [1:0] tx_state;
    reg [15:0] tx_cnt;
    reg [2:0] tx_bit;
    reg [7:0] tx_shift;
    reg tx_line;

    assign uart_tx_to_soc = tx_line;
    assign s_axis_tready  = (tx_state == TX_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_cnt   <= 16'd0;
            tx_bit   <= 3'd0;
            tx_shift <= 8'h00;
            tx_line  <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_line <= 1'b1;
                    tx_cnt  <= 16'd0;
                    tx_bit  <= 3'd0;
                    if (s_axis_tvalid && s_axis_tkeep) begin
                        tx_shift <= s_axis_tdata;
                        tx_line  <= 1'b0;
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    if (tx_cnt == BAUD_DIV - 1) begin
                        tx_cnt  <= 16'd0;
                        tx_line <= tx_shift[0];
                        tx_state <= TX_DATA;
                    end else begin
                        tx_cnt <= tx_cnt + 16'd1;
                    end
                end

                TX_DATA: begin
                    if (tx_cnt == BAUD_DIV - 1) begin
                        tx_cnt <= 16'd0;
                        if (tx_bit == 3'd7) begin
                            tx_line  <= 1'b1;
                            tx_bit   <= 3'd0;
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit   <= tx_bit + 3'd1;
                            tx_shift <= {1'b0, tx_shift[7:1]};
                            tx_line  <= tx_shift[1];
                        end
                    end else begin
                        tx_cnt <= tx_cnt + 16'd1;
                    end
                end

                TX_STOP: begin
                    if (tx_cnt == BAUD_DIV - 1) begin
                        tx_cnt   <= 16'd0;
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_cnt <= tx_cnt + 16'd1;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    localparam [2:0] RX_IDLE   = 3'd0;
    localparam [2:0] RX_CENTER = 3'd1;
    localparam [2:0] RX_DATA   = 3'd2;
    localparam [2:0] RX_STOP   = 3'd3;
    localparam [2:0] RX_HOLD   = 3'd4;

    reg [2:0] rx_state;
    reg [15:0] rx_cnt;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift;
    reg [7:0] rx_data_r;
    reg rx_valid_r;

    assign m_axis_tdata  = rx_data_r;
    assign m_axis_tkeep  = 1'b1;
    assign m_axis_tvalid = rx_valid_r;
    assign m_axis_tlast  = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            rx_cnt     <= 16'd0;
            rx_bit     <= 3'd0;
            rx_shift   <= 8'h00;
            rx_data_r  <= 8'h00;
            rx_valid_r <= 1'b0;
        end else begin
            if (rx_valid_r && m_axis_tready)
                rx_valid_r <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    rx_cnt <= 16'd0;
                    rx_bit <= 3'd0;
                    if (!uart_rx_from_soc)
                        rx_state <= RX_CENTER;
                end

                RX_CENTER: begin
                    if (rx_cnt == (BAUD_DIV / 2)) begin
                        rx_cnt <= 16'd0;
                        if (!uart_rx_from_soc)
                            rx_state <= RX_DATA;
                        else
                            rx_state <= RX_IDLE;
                    end else begin
                        rx_cnt <= rx_cnt + 16'd1;
                    end
                end

                RX_DATA: begin
                    if (rx_cnt == BAUD_DIV - 1) begin
                        rx_cnt <= 16'd0;
                        rx_shift <= {uart_rx_from_soc, rx_shift[7:1]};
                        if (rx_bit == 3'd7) begin
                            rx_bit <= 3'd0;
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit <= rx_bit + 3'd1;
                        end
                    end else begin
                        rx_cnt <= rx_cnt + 16'd1;
                    end
                end

                RX_STOP: begin
                    if (rx_cnt == BAUD_DIV - 1) begin
                        rx_cnt <= 16'd0;
                        rx_data_r <= rx_shift;
                        rx_valid_r <= 1'b1;
                        rx_state <= RX_HOLD;
                    end else begin
                        rx_cnt <= rx_cnt + 16'd1;
                    end
                end

                RX_HOLD: begin
                    if (!rx_valid_r || m_axis_tready)
                        rx_state <= RX_IDLE;
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end
endmodule
