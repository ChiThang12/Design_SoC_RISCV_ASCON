// ============================================================================
// Module  : dma_ctrl_fsm
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_dma
// Version : 1.1  (fixed)
//
// FIX-1: FIFO read latency (root cause of ptext=0)
//   Vấn đề gốc: sync_fifo là synchronous FIFO — khi pop=1 ở cycle N,
//   dout chỉ valid ở cycle N+1. Nhưng S_CORE_FEED cũ đọc dout NGAY cycle
//   sau khi pop (vẫn là 0 vì chưa propagate qua flip-flop của FIFO).
//
//   Thứ tự sai (cũ):
//     Cycle N   : S_RD_WAIT → rd_fifo_pop=1, next=S_CORE_FEED
//     Cycle N+1 : S_CORE_FEED: đọc rd_fifo_dout → vẫn = 0!
//                              core_ptext_0/1 <= 0; core_start=1 → CORE bị sai
//     Cycle N+2 : rd_fifo_dout mới = 0001020304050607 ← quá muộn
//
//   Fix: thêm state S_FIFO_WAIT — đợi 1 cycle sau pop để dout ổn định,
//   sau đó mới latch vào core_ptext_0/1 và assert core_start cycle tiếp theo.
//
//   Thứ tự đúng (mới):
//     Cycle N   : S_RD_WAIT → rd_fifo_pop=1, next=S_FIFO_WAIT
//     Cycle N+1 : S_FIFO_WAIT: rd_fifo_dout valid → latch ptext_0/1, next=S_CORE_START
//     Cycle N+2 : S_CORE_START: core_ptext_0/1 ổn định → core_start=1, next=S_CORE_WAIT
//     Cycle N+3 : CORE latch data_in = {ptext_0, ptext_1, 64'h0} ← ĐÚNG!
//
// FIX-2: core_start và core_data_valid không xung đột
//   core_data_valid chỉ cần thiết nếu CORE có handshake riêng.
//   Trong ascon_CORE hiện tại, core_data_in được latch khi start=1.
//   Tách state rõ ràng: S_CORE_FEED (latch) → S_CORE_START (pulse start).
// ============================================================================

module dma_ctrl_fsm (
    input  wire         clk,
    input  wire         rst_n,

    // ── From axi_slave ───────────────────────────────────────────────────────
    input  wire         dma_start,
    input  wire         dma_soft_rst,

    // ── Status outputs ────────────────────────────────────────────────────────
    output reg          dma_busy,
    output reg          dma_done,
    output reg          dma_error,

    // ── Read engine ───────────────────────────────────────────────────────────
    output reg          rd_start,
    input  wire         rd_busy,
    input  wire         rd_done,
    input  wire         rd_error,

    // ── RD FIFO ───────────────────────────────────────────────────────────────
    input  wire [63:0]  rd_fifo_dout,
    output reg          rd_fifo_pop,
    input  wire         rd_fifo_empty,

    // ── ascon_CORE ────────────────────────────────────────────────────────────
    output reg  [31:0]  core_ptext_0,
    output reg  [31:0]  core_ptext_1,
    output reg          core_data_valid,
    input  wire         core_data_ready,
    output reg          core_start,
    input  wire         core_busy,
    input  wire         core_done,

    // ── Result capture ────────────────────────────────────────────────────────
    input  wire [31:0]  core_ctext_0,
    input  wire [31:0]  core_ctext_1,
    input  wire [31:0]  core_tag_0,
    input  wire [31:0]  core_tag_1,
    input  wire [31:0]  core_tag_2,
    input  wire [31:0]  core_tag_3,

    // ── WR FIFO ───────────────────────────────────────────────────────────────
    output reg  [31:0]  wr_fifo_din,
    output reg          wr_fifo_push,
    input  wire         wr_fifo_full,

    // ── Write engine ──────────────────────────────────────────────────────────
    output reg          wr_start,
    input  wire         wr_busy,
    input  wire         wr_done,
    input  wire         wr_error,

    // ── Status bits ───────────────────────────────────────────────────────────
    output reg          status_rd_done,
    output reg          status_wr_done,
    output reg          status_fifo_overflow
);

    // -------------------------------------------------------------------------
    // FSM states
    // FIX: thêm S_FIFO_WAIT và S_CORE_START để giải quyết FIFO latency
    // -------------------------------------------------------------------------
    localparam [3:0]
        S_IDLE        = 4'd0,
        S_RD_START    = 4'd1,
        S_RD_WAIT     = 4'd2,
        S_FIFO_WAIT   = 4'd3,
        S_CORE_FEED   = 4'd4,
        S_CORE_START  = 4'd5,
        S_CORE_WAIT   = 4'd6,
        S_WR_LOAD     = 4'd7,
        S_WR_START    = 4'd8,   // FIX: assert wr_start 1 cycle sau push cuối
        S_WR_WAIT     = 4'd10,  // FIX: chờ wr_done
        S_DONE        = 4'd9;

    reg [3:0] state;

    reg [2:0] wr_load_cnt;

    // Result capture registers
    reg [31:0] r_ctext_0, r_ctext_1;
    reg [31:0] r_tag_0, r_tag_1, r_tag_2, r_tag_3;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || dma_soft_rst) begin
            state                <= S_IDLE;
            dma_busy             <= 1'b0;
            dma_done             <= 1'b0;
            dma_error            <= 1'b0;
            rd_start             <= 1'b0;
            rd_fifo_pop          <= 1'b0;
            core_ptext_0         <= 32'h0;
            core_ptext_1         <= 32'h0;
            core_data_valid      <= 1'b0;
            core_start           <= 1'b0;
            wr_fifo_din          <= 32'h0;
            wr_fifo_push         <= 1'b0;
            wr_start             <= 1'b0;
            wr_load_cnt          <= 3'd0;
            status_rd_done       <= 1'b0;
            status_wr_done       <= 1'b0;
            status_fifo_overflow <= 1'b0;
            r_ctext_0 <= 32'h0; r_ctext_1 <= 32'h0;
            r_tag_0   <= 32'h0; r_tag_1   <= 32'h0;
            r_tag_2   <= 32'h0; r_tag_3   <= 32'h0;
        end else begin
            // Default: clear all 1-cycle pulse signals
            dma_done     <= 1'b0;
            rd_start     <= 1'b0;
            rd_fifo_pop  <= 1'b0;
            core_start   <= 1'b0;
            wr_fifo_push <= 1'b0;
            wr_start     <= 1'b0;

            case (state)

                // ── Wait for CPU to trigger DMA ──────────────────────────────
                S_IDLE: begin
                    dma_busy <= 1'b0;
                    if (dma_start) begin
                        dma_busy       <= 1'b1;
                        dma_error      <= 1'b0;
                        status_rd_done <= 1'b0;
                        status_wr_done <= 1'b0;
                        rd_start       <= 1'b1;
                        state          <= S_RD_WAIT;
                    end
                end

                // ── Wait for AXI read to complete, data in FIFO ──────────────
                S_RD_WAIT: begin
                    if (rd_done) begin
                        status_rd_done <= 1'b1;
                        if (rd_error) begin
                            dma_error <= 1'b1;
                            state     <= S_DONE;
                        end else begin
                            // FIX: assert pop — dout valid NEXT cycle
                            rd_fifo_pop <= 1'b1;
                            state       <= S_FIFO_WAIT;
                        end
                    end
                end

                // ── FIX: Wait 1 cycle for synchronous FIFO output to settle ──
                // rd_fifo_pop=1 was asserted last cycle.
                // rd_fifo_dout is now valid and stable this cycle.
                S_FIFO_WAIT: begin
                    // rd_fifo_dout is valid here — latch into registers
                    core_ptext_0    <= rd_fifo_dout[63:32];
                    core_ptext_1    <= rd_fifo_dout[31:0];
                    core_data_valid <= 1'b1;
                    state           <= S_CORE_START;
                end

                // ── FIX: core_ptext regs are stable — now pulse core_start ───
                // ascon_top muxes: core_data_in = {ptext_0, ptext_1, 64'h0}
                // CORE samples data_in on the same cycle as start=1 → must be stable
                S_CORE_START: begin
                    core_data_valid <= 1'b0;
                    core_start      <= 1'b1;   // 1-cycle pulse
                    state           <= S_CORE_WAIT;
                end

                // ── (removed S_CORE_FEED — merged into S_FIFO_WAIT) ──────────
                // Old S_CORE_FEED tried to read dout and start in same cycle.
                // Now split into S_FIFO_WAIT (latch) + S_CORE_START (pulse).

                // ── Wait for ASCON core to finish ─────────────────────────────
                S_CORE_WAIT: begin
                    if (core_done) begin
                        r_ctext_0   <= core_ctext_0;
                        r_ctext_1   <= core_ctext_1;
                        r_tag_0     <= core_tag_0;
                        r_tag_1     <= core_tag_1;
                        r_tag_2     <= core_tag_2;
                        r_tag_3     <= core_tag_3;
                        wr_load_cnt <= 3'd0;
                        state       <= S_WR_LOAD;
                    end
                end

                // ── Push 6×32-bit result words into WR FIFO ──────────────────
                // Order: ctext_0, ctext_1, tag_0, tag_1, tag_2, tag_3
                S_WR_LOAD: begin
                    if (!wr_fifo_full) begin
                        wr_fifo_push <= 1'b1;
                        case (wr_load_cnt)
                            3'd0: wr_fifo_din <= r_ctext_0;
                            3'd1: wr_fifo_din <= r_ctext_1;
                            3'd2: wr_fifo_din <= r_tag_0;
                            3'd3: wr_fifo_din <= r_tag_1;
                            3'd4: wr_fifo_din <= r_tag_2;
                            3'd5: wr_fifo_din <= r_tag_3;
                            default: ;
                        endcase

                        if (wr_load_cnt == 3'd5) begin
                            // FIX: KHÔNG assert wr_start cùng cycle push cuối.
                            // sync_fifo: mem[wr_idx] <= din tại posedge này,
                            // word[5]=tag_3 chỉ vào FIFO SAU posedge → phải
                            // đợi 1 cycle (S_WR_START) trước khi trigger engine.
                            state <= S_WR_START;
                        end else begin
                            wr_load_cnt <= wr_load_cnt + 1'b1;
                        end
                    end else begin
                        status_fifo_overflow <= 1'b1;
                        dma_error            <= 1'b1;
                        state                <= S_DONE;
                    end
                end

                // ── Trigger write engine (1 cycle sau push cuối) ─────────────
                // FIX: FIFO đã chứa đủ 6 words. Assert wr_start rồi sang S_WR_WAIT.
                S_WR_START: begin
                    wr_start <= 1'b1;
                    state    <= S_WR_WAIT;
                end

                // ── Wait for AXI write to complete ────────────────────────────
                S_WR_WAIT: begin
                    if (wr_done) begin
                        status_wr_done <= 1'b1;
                        if (wr_error)
                            dma_error <= 1'b1;
                        state <= S_DONE;
                    end
                end

                // ── Pulse dma_done, return to IDLE ────────────────────────────
                S_DONE: begin
                    dma_done <= 1'b1;
                    dma_busy <= 1'b0;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Simulation debug
    // -------------------------------------------------------------------------
    `ifdef SIMULATION

    // Read side
    always @(posedge clk) begin
        if (state == S_FIFO_WAIT)
            $display("[DMA FSM @%0t] S_FIFO_WAIT: latching ptext_0=%08h ptext_1=%08h (from dout=%016h)",
                $time, rd_fifo_dout[63:32], rd_fifo_dout[31:0], rd_fifo_dout);
        if (state == S_CORE_START)
            $display("[DMA FSM @%0t] S_CORE_START: asserting core_start, ptext_0=%08h ptext_1=%08h",
                $time, core_ptext_0, core_ptext_1);
    end

    // WR FIFO push monitor — log gia tri THUC TE duoc push vao FIFO tai posedge
    // NOTE: wr_fifo_din/push la nonblocking nen gia tri hien tai truoc posedge
    // la gia tri cu (cycle truoc). Can xem wr_load_cnt va r_* de biet FIFO nhan gi.
    always @(posedge clk) begin
        if (wr_fifo_push && !wr_fifo_full)
            $display("[WR PUSH @%0t] cnt_BEFORE=%0d  din_BEFORE=%08h | r_ctext={%08h,%08h} r_tag={%08h,%08h,%08h,%08h}",
                $time, wr_load_cnt, wr_fifo_din,
                r_ctext_0, r_ctext_1, r_tag_0, r_tag_1, r_tag_2, r_tag_3);
    end

    // Core done capture check
    always @(posedge clk) begin
        if (state == S_CORE_WAIT && core_done)
            $display("[DMA FSM @%0t] CORE_DONE: ctext={%08h,%08h} tag={%08h,%08h,%08h,%08h}",
                $time, core_ctext_0, core_ctext_1,
                core_tag_0, core_tag_1, core_tag_2, core_tag_3);
        if (state == S_WR_LOAD && wr_load_cnt == 3'd0 && !wr_fifo_full)
            $display("[DMA FSM @%0t] S_WR_LOAD[0]: r_ctext={%08h,%08h} r_tag={%08h,%08h,%08h,%08h}",
                $time, r_ctext_0, r_ctext_1, r_tag_0, r_tag_1, r_tag_2, r_tag_3);
        if (state == S_WR_START)
            $display("[DMA FSM @%0t] S_WR_START: wr_start pulse (FIFO should have 6 words ready)",
                $time);
    end

    `endif

endmodule