// ============================================================================
// Module  : dma_write_engine
// Project : ASCON Crypto Accelerator IP
// Version : 3.0 (fixed sync-FIFO latency, all beats correct)
//
// Fix vs v2.0:
//   WR_ADDR issue fifo_pop=1 → chuyển WR_FIFO_WAIT (đợi 1 cycle cho dout valid)
//   → WR_POP_H latch wdata_hi đúng → WR_POP_L compose WDATA đúng → WR_BEAT
//
// Timeline đúng (sync FIFO: dout valid 1 cycle SAU pop):
//
//   Cycle N   WR_ADDR   : AW handshake, fifo_pop=1 (pop word0=ctext_0)
//   Cycle N+1 WR_FIFO_W : dout = ctext_0 valid → latch wdata_hi=ctext_0
//                          fifo_pop=1 (pop word1=ctext_1)
//   Cycle N+2 WR_POP_L  : dout = ctext_1 valid
//                          WDATA={ctext_0, ctext_1}, WVALID=1, WLAST=0
//   Cycle N+3 WR_BEAT   : hold WVALID, wait WREADY
//   Cycle N+4 WR_BEAT   : WREADY=1 → beat0 done, beat_cnt=1
//                          fifo_pop=1 (pop word2=tag_0)
//   Cycle N+5 WR_FIFO_W : dout = tag_0 valid → latch wdata_hi=tag_0
//                          fifo_pop=1 (pop word3=tag_1)
//   Cycle N+6 WR_POP_L  : dout = tag_1 valid
//                          WDATA={tag_0, tag_1}, WVALID=1, WLAST=0
//   ...repeat for beat2 (tag_2, tag_3, WLAST=1)...
//   WR_RESP : wait BVALID → wr_done
//
// States:
//   WR_IDLE   → WR_ADDR → WR_FIFO_W → WR_POP_L → WR_BEAT
//                              ↑_____________↓  (lặp beat 1, 2)
//                         WR_RESP (sau beat 2)
// ============================================================================

module dma_write_engine #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH   = 4,
    parameter WR_BEATS       = 3        // default 3 beats (ctext_0/1 + tag_0/1 + tag_2/3)
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // ── Control ───────────────────────────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0]       dst_addr,
    input  wire                        wr_start,
    output reg                         wr_busy,
    output reg                         wr_done,
    output reg                         wr_error,
    output reg  [ADDR_WIDTH-1:0]       wr_err_addr,

    // ── WR FIFO pop interface (32-bit entries) ────────────────────────────────
    input  wire [31:0]                 fifo_dout,
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

    // ── Fixed AXI parameters ─────────────────────────────────────────────────
    assign M_AXI_AWLEN   = WR_BEATS - 1;       // e.g. WR_BEATS=3 → AWLEN=2 (3 beats)
    assign M_AXI_AWSIZE  = 3'b011;         // 8 bytes/beat
    assign M_AXI_AWBURST = 2'b01;          // INCR
    assign M_AXI_AWCACHE = 4'b0010;        // Normal Non-cacheable Bufferable
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_WSTRB   = {(AXI_DATA_WIDTH/8){1'b1}};

    // ── FSM states ────────────────────────────────────────────────────────────
    localparam [2:0]
        WR_IDLE   = 3'd0,   // chờ wr_start
        WR_ADDR   = 3'd1,   // gửi AW, chờ AWREADY, pop word_hi
        WR_FIFO_W = 3'd2,   // FIX: đợi 1 cycle cho dout[hi] valid → latch, pop word_lo
        WR_POP_L  = 3'd3,   // đợi 1 cycle cho dout[lo] valid → compose WDATA, drive WVALID
        WR_BEAT   = 3'd4,   // giữ WVALID, chờ WREADY
        WR_RESP   = 3'd5;   // chờ BVALID, pulse wr_done

    reg [2:0]  state;
    reg [2:0]  beat_cnt;    // 0 .. WR_BEATS-1
    reg [31:0] wdata_hi;    // latched high word

    localparam [2:0] LAST_BEAT = WR_BEATS - 1;

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
            beat_cnt      <= 3'd0;
            wdata_hi      <= 32'h0;
        end else begin
            // Default: clear 1-cycle pulse signals
            wr_done  <= 1'b0;
            fifo_pop <= 1'b0;

            case (state)

                // ── Chờ wr_start ─────────────────────────────────────────────
                WR_IDLE: begin
                    wr_busy       <= 1'b0;
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    M_AXI_WLAST   <= 1'b0;
                    beat_cnt      <= 3'd0;
                    if (wr_start) begin
                        wr_busy       <= 1'b1;
                        wr_error      <= 1'b0;
                        M_AXI_AWID    <= {AXI_ID_WIDTH{1'b0}};
                        M_AXI_AWADDR  <= dst_addr;
                        M_AXI_AWVALID <= 1'b1;
                        state         <= WR_ADDR;
                    end
                end

                // ── Gửi AW channel, chờ AWREADY ──────────────────────────────
                // Khi handshake: pop word[hi] của beat đầu tiên
                // dout sẽ valid ở WR_FIFO_W (cycle tiếp)
                WR_ADDR: begin
                    if (M_AXI_AWREADY && M_AXI_AWVALID) begin
                        M_AXI_AWVALID <= 1'b0;
                        fifo_pop      <= 1'b1;   // pop word[hi]
                        state         <= WR_FIFO_W;
                    end
                end

                // ── FIX: Đợi 1 cycle cho dout[hi] valid (sync FIFO latency) ──
                // Cycle này: dout = word[hi] đã valid
                // → latch wdata_hi, pop word[lo]
                // dout[lo] sẽ valid ở WR_POP_L (cycle tiếp)
                WR_FIFO_W: begin
                    wdata_hi <= fifo_dout;   // latch high word
                    fifo_pop <= 1'b1;        // pop word[lo]
                    state    <= WR_POP_L;
                end

                // ── Đợi 1 cycle cho dout[lo] valid ───────────────────────────
                // Cycle này: dout = word[lo] đã valid
                // → compose WDATA = {wdata_hi, fifo_dout}, drive WVALID
                WR_POP_L: begin
                    M_AXI_WDATA  <= {wdata_hi, fifo_dout};
                    M_AXI_WVALID <= 1'b1;
                    M_AXI_WLAST  <= (beat_cnt == LAST_BEAT);
                    state        <= WR_BEAT;
                end

                // ── Giữ WVALID, chờ WREADY handshake ─────────────────────────
                // WVALID giữ nguyên nếu WREADY chưa đến (backpressure OK)
                WR_BEAT: begin
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        M_AXI_WVALID <= 1'b0;
                        M_AXI_WLAST  <= 1'b0;

                        if (beat_cnt == LAST_BEAT) begin
                            // Beat cuối → chờ BRESP
                            M_AXI_BREADY <= 1'b1;
                            state        <= WR_RESP;
                        end else begin
                            // Còn beat tiếp → pop word[hi] tiếp theo
                            beat_cnt <= beat_cnt + 1'b1;
                            fifo_pop <= 1'b1;      // pop word[hi] của beat kế
                            state    <= WR_FIFO_W;
                        end
                    end
                end

                // ── Chờ BVALID, capture BRESP, pulse wr_done ─────────────────
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

    // ── Simulation debug ─────────────────────────────────────────────────────
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (state == WR_FIFO_W)
            $display("[WR_ENG @%0t] WR_FIFO_W beat%0d: latching hi=%08h",
                     $time, beat_cnt, fifo_dout);
        if (state == WR_POP_L)
            $display("[WR_ENG @%0t] WR_POP_L  beat%0d: lo=%08h -> WDATA=%016h WLAST=%b",
                     $time, beat_cnt, fifo_dout,
                     {wdata_hi, fifo_dout}, (beat_cnt == LAST_BEAT));
        if (state == WR_BEAT && M_AXI_WVALID && M_AXI_WREADY)
            $display("[WR_ENG @%0t] WR_BEAT   beat%0d accepted: WDATA=%016h WLAST=%b",
                     $time, beat_cnt, M_AXI_WDATA, M_AXI_WLAST);
        if (state == WR_RESP && M_AXI_BVALID)
            $display("[WR_ENG @%0t] WR_RESP: BRESP=%0d wr_error=%b",
                     $time, M_AXI_BRESP, (M_AXI_BRESP != 2'b00));
    end
    `endif

endmodule