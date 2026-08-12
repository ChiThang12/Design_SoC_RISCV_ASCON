`timescale 1ns/1ps
// spi_core.v — SPI Master shift-register FSM
//
// Hỗ trợ 4 SPI modes (CPOL×CPHA).
// Transfer: 8-bit, MSB first.
// SCK = clk / (2*(divider+1)) → divider=4 → SCK=10 MHz @ 100 MHz clk.
//
// CPOL=0: SCK idle LOW.  CPOL=1: SCK idle HIGH.
// CPHA=0: sample 1st edge, shift 2nd.
// CPHA=1: shift  1st edge, sample 2nd.

module spi_core #(
    parameter CS_WIDTH = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    // Config
    input  wire [15:0] divider,
    input  wire        spi_en,
    input  wire        cpol,
    input  wire        cpha,
    input  wire        cs_auto,
    input  wire [CS_WIDTH-1:0] cs_ctrl_manual,  // manual CS (cs_auto=0)

    // TX FIFO interface
    input  wire [7:0]  tx_fifo_dout,
    input  wire        tx_fifo_empty,
    output reg         tx_fifo_pop,

    // RX FIFO interface
    output reg  [7:0]  rx_fifo_din,
    input  wire        rx_fifo_full,
    output reg         rx_fifo_push,

    // SPI pads
    output reg                 sck,
    output wire                mosi,
    input  wire                miso,
    output reg  [CS_WIDTH-1:0] cs_n,   // active-low

    // Status
    output wire        busy,

    // IRQ triggers → spi_top
    output reg         tx_empty_irq,  // 1-cycle pulse khi TX FIFO vừa empty
    output reg         rx_valid_irq   // 1-cycle pulse khi byte mới vào RX FIFO
);

    // ── FSM ───────────────────────────────────────────────────────────────────
    localparam [1:0]
        S_IDLE    = 2'd0,
        S_LOAD    = 2'd1,  // latch TX byte, assert CS
        S_XFER    = 2'd2,  // clock 8 bits
        S_DONE    = 2'd3;  // deassert CS (if cs_auto), push RX

    reg [1:0]  state;
    reg [15:0] clk_cnt;    // baud divider counter
    reg        clk_phase;  // 0=first half, 1=second half of SCK period
    reg [2:0]  bit_cnt;    // 0-7
    reg [7:0]  shift_reg;  // shift register (TX side)
    reg [7:0]  rx_shift;   // shift register (RX side)
    reg        sck_idle;   // SCK level at idle (= cpol)

    assign busy = (state != S_IDLE);
    assign mosi = shift_reg[7];  // MSB first

    // ── Clock edge generation ─────────────────────────────────────────────────
    wire clk_tick = (clk_cnt == 16'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            clk_cnt      <= 16'd0;
            clk_phase    <= 1'b0;
            bit_cnt      <= 3'd0;
            shift_reg    <= 8'd0;
            rx_shift     <= 8'd0;
            sck          <= 1'b0;
            cs_n         <= {CS_WIDTH{1'b1}};
            tx_fifo_pop  <= 1'b0;
            rx_fifo_din  <= 8'd0;
            rx_fifo_push <= 1'b0;
            tx_empty_irq <= 1'b0;
            rx_valid_irq <= 1'b0;
        end else begin
            tx_fifo_pop  <= 1'b0;
            rx_fifo_push <= 1'b0;
            tx_empty_irq <= 1'b0;
            rx_valid_irq <= 1'b0;

            // Manual CS override
            if (!cs_auto) cs_n <= cs_ctrl_manual;

            case (state)
                // ── S_IDLE: wait for byte in TX FIFO ─────────────────────────
                S_IDLE: begin
                    sck     <= cpol;   // SCK idles per CPOL
                    clk_cnt <= divider;
                    clk_phase <= 1'b0;
                    if (spi_en && !tx_fifo_empty) begin
                        state <= S_LOAD;
                    end
                end

                // ── S_LOAD: pop byte, assert CS ───────────────────────────────
                S_LOAD: begin
                    shift_reg   <= tx_fifo_dout;
                    tx_fifo_pop <= 1'b1;
                    bit_cnt     <= 3'd0;
                    clk_cnt     <= divider;
                    clk_phase   <= 1'b0;
                    if (cs_auto) cs_n <= {CS_WIDTH{1'b0}};  // assert all CS (simplest)
                    state <= S_XFER;
                end

                // ── S_XFER: shift 8 bits ──────────────────────────────────────
                S_XFER: begin
                    if (clk_cnt != 16'd0) begin
                        clk_cnt <= clk_cnt - 16'd1;
                    end else begin
                        clk_cnt   <= divider;
                        clk_phase <= ~clk_phase;

                        if (!clk_phase) begin
                            // First half → SCK transition (idle→active)
                            sck <= cpol ^ 1'b1;  // toggle from idle
                            if (!cpha) begin
                                // CPHA=0: sample on first edge
                                rx_shift <= {rx_shift[6:0], miso};
                            end else begin
                                // CPHA=1: shift out on first edge
                                shift_reg <= {shift_reg[6:0], 1'b0};
                            end
                        end else begin
                            // Second half → SCK back to idle level
                            sck <= cpol;
                            if (!cpha) begin
                                // CPHA=0: shift out on second edge
                                shift_reg <= {shift_reg[6:0], 1'b0};
                            end else begin
                                // CPHA=1: sample on second edge
                                rx_shift <= {rx_shift[6:0], miso};
                            end
                            bit_cnt <= bit_cnt + 3'd1;
                            if (bit_cnt == 3'd7) begin
                                state <= S_DONE;
                            end
                        end
                    end
                end

                // ── S_DONE: push RX, deassert CS if cs_auto ──────────────────
                S_DONE: begin
                    if (!rx_fifo_full) begin
                        rx_fifo_din  <= rx_shift;
                        rx_fifo_push <= 1'b1;
                        rx_valid_irq <= 1'b1;
                    end
                    // Deassert CS if auto-mode and no more data
                    if (cs_auto && tx_fifo_empty) begin
                        cs_n <= {CS_WIDTH{1'b1}};
                    end
                    if (tx_fifo_empty) begin
                        tx_empty_irq <= 1'b1;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
