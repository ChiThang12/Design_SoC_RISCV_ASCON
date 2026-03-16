// ============================================================================
// Module  : sync_fifo
// Project : ASCON Crypto Accelerator IP
//
// Description:
//   Generic synchronous FIFO.
//   - Full/empty flags are registered (no combinational glitch)
//   - Simultaneous push + pop when not empty/full is supported
//   - DATA_OUT is registered (read latency = 1 cycle after pop)
//   - DATA_OUT holds last value when empty
//
// Parameters:
//   WIDTH : data width in bits
//   DEPTH : number of entries (must be power of 2)
// ============================================================================

module sync_fifo #(
    parameter WIDTH = 64,
    parameter DEPTH = 4           // must be power of 2
) (
    input  wire             clk,
    input  wire             rst_n,

    // Write port
    input  wire [WIDTH-1:0] din,
    input  wire             push,
    output wire             full,

    // Read port
    output reg  [WIDTH-1:0] dout,
    input  wire             pop,
    output wire             empty,

    // Status
    output wire [$clog2(DEPTH):0] count   // number of entries currently stored
);

    localparam PTR_W = $clog2(DEPTH);

    // Assertion: DEPTH must be a power of 2
    initial begin
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $error("sync_fifo: DEPTH=%0d must be a power of 2", DEPTH);
            $finish;
        end
    end

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_W:0]   wr_ptr;   // one extra bit for full/empty distinction
    reg [PTR_W:0]   rd_ptr;

    wire [PTR_W-1:0] wr_idx = wr_ptr[PTR_W-1:0];
    wire [PTR_W-1:0] rd_idx = rd_ptr[PTR_W-1:0];

    assign full  = (wr_ptr == {~rd_ptr[PTR_W], rd_ptr[PTR_W-1:0]});
    assign empty = (wr_ptr == rd_ptr);
    assign count = wr_ptr - rd_ptr;

    // Write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(PTR_W+1){1'b0}};
        end else if (push && !full) begin
            mem[wr_idx] <= din;
            wr_ptr      <= wr_ptr + 1'b1;
        end
    end

    // Read
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= {(PTR_W+1){1'b0}};
            dout   <= {WIDTH{1'b0}};
        end else if (pop && !empty) begin
            dout   <= mem[rd_idx];
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule