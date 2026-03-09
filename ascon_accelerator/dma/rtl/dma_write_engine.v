// ============================================================================
// Module  : dma_write_engine
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_dma
//
// Description:
//   AXI4-Full Master write engine. Drains the WR FIFO and writes
//   ciphertext + tag out to memory.
//
// Phase 1 write layout (3 beats × 64-bit = 24 bytes):
//   Beat 0: {ctext_0[63:32], ctext_1[31:0]}
//   Beat 1: {tag_0[127:96],  tag_1[95:64]}
//   Beat 2: {tag_2[63:32],   tag_3[31:0]}
//
//   AWLEN  = 8'h02 (3 beats)
//   AWSIZE = 3'b011 (8 bytes/beat)
//   AWBURST= 2'b01 (INCR)
//   WSTRB  = 8'hFF (all bytes valid)
//
// FSM states:
//   WR_IDLE → WR_ADDR → WR_DATA → WR_RESP → WR_IDLE
//
// Error handling:
//   If BRESP != 2'b00, assert wr_error and capture wr_err_addr.
// ============================================================================

module dma_write_engine #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH   = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // ── Control (from DMA top FSM) ────────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0]       dst_addr,
    input  wire                        wr_start,     // 1-cycle pulse: begin transaction
    output reg                         wr_busy,
    output reg                         wr_done,      // 1-cycle pulse
    output reg                         wr_error,     // sticky
    output reg  [ADDR_WIDTH-1:0]       wr_err_addr,

    // ── WR FIFO pop interface (64-bit wide: two 32-bit words packed) ──────────
    // The FIFO holds 32-bit entries; we pop two per beat
    input  wire [31:0]                 fifo_dout,    // current head word
    output reg                         fifo_pop,
    input  wire                        fifo_empty,

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
    input  wire [AXI_ID_WIDTH-1:0]     M_AXI_BID,
    input  wire [1:0]                  M_AXI_BRESP,
    input  wire                        M_AXI_BVALID,
    output reg                         M_AXI_BREADY
);

    // Fixed AXI parameters
    // Phase 1: always 3 beats (ctext 64-bit + tag 128-bit = 24 bytes = 3 × 64-bit)
    assign M_AXI_AWLEN   = 8'h02;    // 3 beats (AWLEN = beats - 1)
    assign M_AXI_AWSIZE  = 3'b011;   // 8 bytes/beat
    assign M_AXI_AWBURST = 2'b01;    // INCR
    assign M_AXI_AWCACHE = 4'b0010;  // Normal Non-cacheable Bufferable
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_WSTRB   = {(AXI_DATA_WIDTH/8){1'b1}}; // all bytes valid

    // FSM
    localparam [1:0]
        WR_IDLE = 2'd0,
        WR_ADDR = 2'd1,
        WR_DATA = 2'd2,
        WR_RESP = 2'd3;

    reg [1:0] state;

    // Beat counter: 3 beats total (0, 1, 2)
    // Each beat pops 2 entries from the 32-bit WR FIFO
    reg [1:0]  beat_cnt;      // 0..2
    reg        word_half;     // 0 = high word pending, 1 = low word pending
    reg [31:0] wdata_hi;      // latched high word while waiting for low word

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= WR_IDLE;
            wr_busy        <= 1'b0;
            wr_done        <= 1'b0;
            wr_error       <= 1'b0;
            wr_err_addr    <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWVALID  <= 1'b0;
            M_AXI_AWID     <= {AXI_ID_WIDTH{1'b0}};
            M_AXI_AWADDR   <= {ADDR_WIDTH{1'b0}};
            M_AXI_WVALID   <= 1'b0;
            M_AXI_WDATA    <= {AXI_DATA_WIDTH{1'b0}};
            M_AXI_WLAST    <= 1'b0;
            M_AXI_BREADY   <= 1'b0;
            fifo_pop       <= 1'b0;
            beat_cnt       <= 2'd0;
            word_half      <= 1'b0;
            wdata_hi       <= 32'h0;
        end else begin
            // Default: clear 1-cycle signals
            wr_done  <= 1'b0;
            fifo_pop <= 1'b0;

            case (state)

                // ----------------------------------------------------------------
                WR_IDLE: begin
                    wr_busy       <= 1'b0;
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    M_AXI_WLAST   <= 1'b0;
                    beat_cnt      <= 2'd0;
                    word_half     <= 1'b0;
                    if (wr_start) begin
                        wr_busy       <= 1'b1;
                        wr_error      <= 1'b0;
                        M_AXI_AWID    <= {AXI_ID_WIDTH{1'b0}};
                        M_AXI_AWADDR  <= dst_addr;
                        M_AXI_AWVALID <= 1'b1;
                        state         <= WR_ADDR;
                    end
                end

                // ----------------------------------------------------------------
                WR_ADDR: begin
                    if (M_AXI_AWREADY && M_AXI_AWVALID) begin
                        M_AXI_AWVALID <= 1'b0;
                        state         <= WR_DATA;
                        // Kick off first FIFO pop (high word of beat 0)
                        if (!fifo_empty) begin
                            fifo_pop  <= 1'b1;
                            word_half <= 1'b0; // we will get high word next cycle
                        end
                    end
                end

                // ----------------------------------------------------------------
                // Data phase: pop 2 × 32-bit words per beat, pack into 64-bit WDATA
                // The FIFO outputs the popped word 1 cycle after pop is asserted.
                // So we use a 2-step sequence per beat:
                //   Step 0 (word_half=0): pop → latch dout as wdata_hi, pop again
                //   Step 1 (word_half=1): wdata_hi + dout → drive WDATA + WVALID
                // ----------------------------------------------------------------
                WR_DATA: begin
                    if (!word_half) begin
                        // Waiting for high word to be available in dout
                        // (was popped the previous cycle)
                        if (!fifo_empty) begin
                            wdata_hi  <= fifo_dout; // latch high word
                            fifo_pop  <= 1'b1;      // pop low word
                            word_half <= 1'b1;
                        end
                    end else begin
                        // Low word now available in dout; compose WDATA
                        if (!fifo_empty || M_AXI_WVALID) begin
                            if (!M_AXI_WVALID) begin
                                // Drive the beat
                                M_AXI_WDATA  <= {wdata_hi, fifo_dout};
                                M_AXI_WVALID <= 1'b1;
                                M_AXI_WLAST  <= (beat_cnt == 2'd2);
                                word_half    <= 1'b0;
                            end

                            // Handshake
                            if (M_AXI_WVALID && M_AXI_WREADY) begin
                                M_AXI_WVALID <= 1'b0;
                                M_AXI_WLAST  <= 1'b0;

                                if (beat_cnt == 2'd2) begin
                                    // All beats sent — wait for BRESP
                                    M_AXI_BREADY <= 1'b1;
                                    state        <= WR_RESP;
                                end else begin
                                    beat_cnt  <= beat_cnt + 1'b1;
                                    word_half <= 1'b0;
                                    // Pop next high word
                                    if (!fifo_empty)
                                        fifo_pop <= 1'b1;
                                end
                            end
                        end
                    end
                end

                // ----------------------------------------------------------------
                WR_RESP: begin
                    if (M_AXI_BVALID) begin
                        M_AXI_BREADY <= 1'b0;
                        if (M_AXI_BRESP != 2'b00) begin
                            wr_error    <= 1'b1;
                            wr_err_addr <= M_AXI_AWADDR;
                        end
                        wr_done <= 1'b1;
                        wr_busy <= 1'b0;
                        state   <= WR_IDLE;
                    end
                end

                default: state <= WR_IDLE;

            endcase
        end
    end

endmodule