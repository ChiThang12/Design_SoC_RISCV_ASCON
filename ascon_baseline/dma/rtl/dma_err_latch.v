`timescale 1ns/1ps

module dma_err_latch #(
    parameter ADDR_WIDTH = 32
) (
    input  wire                        clk,
    input  wire                        rst_n,

    input  wire                        rd_error,
    input  wire [ADDR_WIDTH-1:0]       rd_err_addr,
    input  wire                        wr_error,
    input  wire [ADDR_WIDTH-1:0]       wr_err_addr,
    input  wire                        fsm_error,

    output wire                        dma_error,
    output wire [ADDR_WIDTH-1:0]       dma_err_addr,

    output wire                        status_rd_error,
    output wire                        status_wr_error
);

    assign status_rd_error = rd_error;
    assign status_wr_error = wr_error;

    reg        dma_error_r;
    reg [ADDR_WIDTH-1:0] dma_err_addr_r;
    reg        dma_error_meta;
    wire       dma_error_raw = rd_error | wr_error | fsm_error;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_error_meta <= 1'b0;
            dma_error_r    <= 1'b0;
            dma_err_addr_r <= {ADDR_WIDTH{1'b0}};
        end else begin
            dma_error_meta <= dma_error_raw;
            dma_error_r    <= dma_error_raw && !dma_error_meta;
            if (dma_error_raw && !dma_error_meta)
                dma_err_addr_r <= rd_error ? rd_err_addr : wr_err_addr;
        end
    end

    assign dma_error    = dma_error_r;
    assign dma_err_addr = dma_err_addr_r;

endmodule
