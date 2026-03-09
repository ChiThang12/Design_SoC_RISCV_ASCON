// ============================================================================
// Module  : dma_read_engine
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_dma
//
// Description:
//   AXI4-Full Master read engine. Issues one read transaction to fetch
//   plaintext from memory and pushes the received data into the RD FIFO.
//
// Phase 1 behaviour (single beat, 64-bit bus):
//   ARLEN  = 8'h00  (1 beat)
//   ARSIZE = 3'b011 (8 bytes/beat)
//   ARBURST= 2'b01  (INCR)
//
// FSM states:
//   RD_IDLE  → RD_ADDR → RD_DATA → RD_IDLE
//
// Error handling:
//   If RRESP != 2'b00, assert rd_error and return to IDLE immediately.
//   The address that caused the error is captured in rd_err_addr.
// ============================================================================

module dma_read_engine #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH   = 4
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // ── Control (from DMA top FSM) ────────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0]      src_addr,
    input  wire [7:0]                 burst_len,    // ARLEN value (0 = 1 beat)
    input  wire                       rd_start,     // 1-cycle pulse: begin transaction
    output reg                        rd_busy,
    output reg                        rd_done,      // 1-cycle pulse: all beats received
    output reg                        rd_error,     // sticky: AXI returned error
    output reg  [ADDR_WIDTH-1:0]      rd_err_addr,

    // ── RD FIFO push interface ────────────────────────────────────────────────
    output reg  [AXI_DATA_WIDTH-1:0]  fifo_din,
    output reg                        fifo_push,
    input  wire                       fifo_full,

    // ── AXI4 Read Address Channel ─────────────────────────────────────────────
    output reg  [AXI_ID_WIDTH-1:0]    M_AXI_ARID,
    output reg  [ADDR_WIDTH-1:0]      M_AXI_ARADDR,
    output reg  [7:0]                 M_AXI_ARLEN,
    output wire [2:0]                 M_AXI_ARSIZE,
    output wire [1:0]                 M_AXI_ARBURST,
    output wire [3:0]                 M_AXI_ARCACHE,
    output wire [2:0]                 M_AXI_ARPROT,
    output reg                        M_AXI_ARVALID,
    input  wire                       M_AXI_ARREADY,

    // ── AXI4 Read Data Channel ────────────────────────────────────────────────
    input  wire [AXI_ID_WIDTH-1:0]    M_AXI_RID,
    input  wire [AXI_DATA_WIDTH-1:0]  M_AXI_RDATA,
    input  wire [1:0]                 M_AXI_RRESP,
    input  wire                       M_AXI_RLAST,
    input  wire                       M_AXI_RVALID,
    output reg                        M_AXI_RREADY
);

    // Fixed AXI parameters
    assign M_AXI_ARSIZE  = 3'b011;   // 8 bytes/beat (64-bit bus)
    assign M_AXI_ARBURST = 2'b01;    // INCR
    assign M_AXI_ARCACHE = 4'b0010;  // Normal Non-cacheable Bufferable
    assign M_AXI_ARPROT  = 3'b000;

    // FSM
    localparam [1:0]
        RD_IDLE = 2'd0,
        RD_ADDR = 2'd1,
        RD_DATA = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= RD_IDLE;
            rd_busy        <= 1'b0;
            rd_done        <= 1'b0;
            rd_error       <= 1'b0;
            rd_err_addr    <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARVALID  <= 1'b0;
            M_AXI_ARID     <= {AXI_ID_WIDTH{1'b0}};
            M_AXI_ARADDR   <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARLEN    <= 8'h00;
            M_AXI_RREADY   <= 1'b0;
            fifo_push      <= 1'b0;
            fifo_din       <= {AXI_DATA_WIDTH{1'b0}};
        end else begin
            // Default: clear 1-cycle signals
            rd_done   <= 1'b0;
            fifo_push <= 1'b0;

            case (state)

                // ----------------------------------------------------------------
                RD_IDLE: begin
                    rd_busy       <= 1'b0;
                    M_AXI_ARVALID <= 1'b0;
                    M_AXI_RREADY  <= 1'b0;
                    if (rd_start) begin
                        rd_busy       <= 1'b1;
                        rd_error      <= 1'b0;   // clear previous error on new start
                        M_AXI_ARID    <= {AXI_ID_WIDTH{1'b0}};
                        M_AXI_ARADDR  <= src_addr;
                        M_AXI_ARLEN   <= burst_len;
                        M_AXI_ARVALID <= 1'b1;
                        state         <= RD_ADDR;
                    end
                end

                // ----------------------------------------------------------------
                RD_ADDR: begin
                    if (M_AXI_ARREADY && M_AXI_ARVALID) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY  <= 1'b1;  // ready to receive data
                        state         <= RD_DATA;
                    end
                end

                // ----------------------------------------------------------------
                RD_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        // Check AXI response
                        if (M_AXI_RRESP != 2'b00) begin
                            rd_error    <= 1'b1;
                            rd_err_addr <= M_AXI_ARADDR;
                        end

                        // Push data into FIFO regardless of error
                        // (error flag will prevent core from starting)
                        if (!fifo_full) begin
                            fifo_din  <= M_AXI_RDATA;
                            fifo_push <= 1'b1;
                        end

                        // RLAST = end of burst
                        if (M_AXI_RLAST) begin
                            M_AXI_RREADY <= 1'b0;
                            rd_done      <= 1'b1;
                            rd_busy      <= 1'b0;
                            state        <= RD_IDLE;
                        end
                    end
                end

                default: state <= RD_IDLE;

            endcase
        end
    end

endmodule