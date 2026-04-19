// ============================================================================
// Module  : dma_write_engine
// Description:
//   Write Engine automatically triggers AW requests containing exactly 1 beat
//   whenever the WR FIFO has at least 2 words (1 beat = 64 bits = 2 words). 
//   This elegantly handles the streaming architecture decoupling.
// ============================================================================

module dma_write_engine #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH   = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // ── Control ───────────────────────────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0]       dst_addr,
    input  wire                        dma_start, // Repurposed: reset state / addr
    output reg                         wr_busy,
    output reg                         wr_done,   // pulsed on every 1-beat completion
    output reg                         wr_error,
    output reg  [ADDR_WIDTH-1:0]       wr_err_addr,

    // ── WR FIFO pop interface (32-bit entries) ────────────────────────────────
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0]                 fifo_dout,
    /* verilator lint_on UNUSEDSIGNAL */
    output reg                         fifo_pop,
    input  wire [3:0]                  fifo_count, // FIFO entries currently held

    // ── AXI4 Write Address Channel ────────────────────────────────────────────
    output reg  [AXI_ID_WIDTH-1:0]     M_AXI_AWID,
    output reg  [ADDR_WIDTH-1:0]       M_AXI_AWADDR,
    output wire [7:0]                  M_AXI_AWLEN,
    output wire [2:0]                  M_AXI_AWSIZE,
    output wire [1:0]                  M_AXI_AWBURST,
    output wire [3:0]                  M_AXI_AWCACHE,
    output wire [2:0]                  M_AXI_AWPROT,
    output reg                         M_AXI_AWVALID,
    input  wire                        M_AXI_AWREADY,

    // ── AXI4 Write Data Channel ───────────────────────────────────────────────
    output reg  [AXI_DATA_WIDTH-1:0]   M_AXI_WDATA,
    output wire [AXI_DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output reg                         M_AXI_WLAST,
    output reg                         M_AXI_WVALID,
    input  wire                        M_AXI_WREADY,

    // ── AXI4 Write Response Channel ───────────────────────────────────────────
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [AXI_ID_WIDTH-1:0]     M_AXI_BID,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [1:0]                  M_AXI_BRESP,
    input  wire                        M_AXI_BVALID,
    output reg                         M_AXI_BREADY
);

    // ── Fixed AXI parameters ─────────────────────────────────────────────────
    assign M_AXI_AWLEN   = 8'd0;           // ALWAYS 1 beat
    assign M_AXI_AWSIZE  = 3'b011;         // 8 bytes/beat
    assign M_AXI_AWBURST = 2'b01;          // INCR
    assign M_AXI_AWCACHE = 4'b0010;        // Normal Non-cacheable Bufferable
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_WSTRB   = {(AXI_DATA_WIDTH/8){1'b1}};

    // ── FSM states ────────────────────────────────────────────────────────────
    localparam [2:0]
        WR_IDLE    = 3'd0,
        WR_ADDR    = 3'd1,
        WR_WAIT_H  = 3'd2,   // waiting for dout[hi] to settle
        WR_LATCH_H = 3'd3,   // latch hi, pop lo
        WR_WAIT_L  = 3'd4,   // wait dout[lo]
        WR_LATCH_L = 3'd5,   // combine
        WR_BEAT    = 3'd6,
        WR_RESP    = 3'd7;

    reg [2:0]  state;
    reg [31:0] wdata_hi;
    reg [ADDR_WIDTH-1:0] cur_dst_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= WR_IDLE;
            wr_busy       <= 1'b0;
            wr_done       <= 1'b0;
            wr_error      <= 1'b0;
            wr_err_addr   <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWVALID <= 1'b0;
            M_AXI_AWID    <= {AXI_ID_WIDTH{1'b0}};
            M_AXI_AWADDR  <= {ADDR_WIDTH{1'b0}};
            M_AXI_WVALID  <= 1'b0;
            M_AXI_WDATA   <= {AXI_DATA_WIDTH{1'b0}};
            M_AXI_WLAST   <= 1'b0;
            M_AXI_BREADY  <= 1'b0;
            fifo_pop      <= 1'b0;
            wdata_hi      <= 32'h0;
            cur_dst_addr  <= {ADDR_WIDTH{1'b0}};
        end else begin
            // Default strbs
            wr_done  <= 1'b0;
            fifo_pop <= 1'b0;

            case (state)
                // ── WR_IDLE: Auto-trigger based on FIFO Count ───────────────
                WR_IDLE: begin
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    M_AXI_WLAST   <= 1'b0;
                    // dma_start pulses to reset address per DMA block transaction
                    if (dma_start) begin
                        cur_dst_addr <= dst_addr;
                        wr_error     <= 1'b0;
                        wr_busy      <= 1'b0;
                    end else if (fifo_count >= 4'd2) begin
                        wr_busy       <= 1'b1;
                        M_AXI_AWID    <= {AXI_ID_WIDTH{1'b0}};
                        M_AXI_AWADDR  <= cur_dst_addr;
                        M_AXI_AWVALID <= 1'b1;
                        state         <= WR_ADDR;
                    end else begin
                        wr_busy <= 1'b0;
                    end
                end

                WR_ADDR: begin
                    if (M_AXI_AWREADY && M_AXI_AWVALID) begin
                        M_AXI_AWVALID <= 1'b0;
                        fifo_pop      <= 1'b1;   // pop word[hi]
                        state         <= WR_WAIT_H;
                    end
                end

                WR_WAIT_H: begin
                    state <= WR_LATCH_H;
                end

                WR_LATCH_H: begin
                    wdata_hi <= fifo_dout;   // latch hi word
                    fifo_pop <= 1'b1;        // pop lo word
                    state    <= WR_WAIT_L;
                end

                WR_WAIT_L: begin
                    state <= WR_LATCH_L;
                end

                WR_LATCH_L: begin
                    M_AXI_WDATA  <= {fifo_dout, wdata_hi};
                    M_AXI_WVALID <= 1'b1;
                    M_AXI_WLAST  <= 1'b1;     // AWLEN=0 ALWAYS
                    state        <= WR_BEAT;
                end

                WR_BEAT: begin
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        M_AXI_WVALID <= 1'b0;
                        M_AXI_WLAST  <= 1'b0;
                        M_AXI_BREADY <= 1'b1;
                        state        <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (M_AXI_BVALID) begin
                        M_AXI_BREADY <= 1'b0;
                        if (M_AXI_BRESP != 2'b00) begin
                            wr_error    <= 1'b1;
                            if (!wr_error) wr_err_addr <= M_AXI_AWADDR;
                        end
                        wr_done <= 1'b1;
                        cur_dst_addr <= cur_dst_addr + 8; // Advance address
                        state   <= WR_IDLE;
                    end
                end

                default: state <= WR_IDLE;
            endcase
        end
    end
endmodule