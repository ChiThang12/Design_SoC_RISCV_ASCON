// ============================================================================
// Module  : uart_fifo
// Project : RISC-V SoC — UART peripheral
//
// Synchronous FIFO 8-bit, depth cấu hình bằng tham số DEPTH.
// TX FIFO: depth=16, push từ AXI write, pop từ TX shift register
// RX FIFO: depth=16, push từ RX shift register, pop từ AXI read
//
// WHY FIFO: tách clock domain AXI (bursty, CPU-driven) khỏi UART baud
//   (constant rate). CPU có thể burst ghi nhiều byte rồi để FIFO drain
//   từ từ mà không cần polling liên tục.
//
// Flags:
//   full   = không thể push thêm (TX: CPU block / RX: overrun nếu vẫn push)
//   empty  = không có data để pop (TX: TX idle / RX: CPU chờ)
//   almost_full = còn 1 slot (dùng cho flow control nếu cần)
// ============================================================================

module uart_fifo #(
    parameter DEPTH = 16   // phải là lũy thừa của 2
) (
    input  wire       clk,
    input  wire       rst_n,
    // Write port
    input  wire [7:0] din,
    input  wire       push,
    output wire       full,
    output wire       almost_full,
    // Read port
    output wire [7:0] dout,
    input  wire       pop,
    output wire       empty,
    // Status
    output wire [$clog2(DEPTH):0] count   // số phần tử hiện có
);

    localparam PTR_W = $clog2(DEPTH);

    reg [7:0]       mem [0:DEPTH-1];
    reg [PTR_W:0]   wr_ptr;   // PTR_W+1 bit: bit cao là wrap bit
    reg [PTR_W:0]   rd_ptr;

    // WHY wrap-bit trick: dùng 1 bit thêm để phân biệt full vs empty
    // empty: wr_ptr == rd_ptr (kể cả wrap bit)
    // full : wr_ptr[PTR_W] != rd_ptr[PTR_W] && wr_ptr[PTR_W-1:0] == rd_ptr[PTR_W-1:0]
    assign empty       = (wr_ptr == rd_ptr);
    assign full        = (wr_ptr[PTR_W] != rd_ptr[PTR_W]) &&
                         (wr_ptr[PTR_W-1:0] == rd_ptr[PTR_W-1:0]);
    assign count       = wr_ptr - rd_ptr;
    assign almost_full = (count == (DEPTH - 1));
    assign dout        = mem[rd_ptr[PTR_W-1:0]];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(PTR_W+1){1'b0}};
            rd_ptr <= {(PTR_W+1){1'b0}};
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= 8'd0;
        end else begin
            if (push && !full) begin
                mem[wr_ptr[PTR_W-1:0]] <= din;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (pop && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule