// ============================================================================
// Module  : dma_ctrl_fsm
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_dma
// Version : 1.2  (fixed FIFO latency off-by-one)
//
// FIX-1: FIFO read latency — off-by-one cycle (root cause of ptext=0 in TC2)
//   Vấn đề gốc: sync_fifo là synchronous FIFO — khi pop=1 tại posedge N,
//   FIFO thực hiện: dout <= mem[rd_idx] bằng nonblocking assignment tại posedge N.
//   Do đó dout chỉ thực sự valid SAU posedge N, tức là từ posedge N+1 trở đi.
//
//   Version 1.1 sai: S_FIFO_WAIT đọc rd_fifo_dout NGAY tại posedge N+1 —
//   đây chính là posedge mà FIFO đang latch dout (nonblocking chưa commit).
//   Kết quả: đọc được giá trị cũ = 0x0 thay vì plaintext thực sự.
//
//   Thứ tự sai (v1.1):
//     Cycle N   : S_RD_WAIT  → rd_fifo_pop=1
//     Cycle N+1 : S_FIFO_WAIT: đọc rd_fifo_dout → vẫn = 0! (FIFO đang latch)
//     Cycle N+2 : dout mới thực sự valid ← quá muộn
//
//   Fix (v1.2): tách thành 2 state:
//     S_FIFO_WAIT  — chỉ đợi, KHÔNG đọc dout
//     S_FIFO_LATCH — dout đã ổn định, latch vào core_ptext_0/1
//
//   Thứ tự đúng (v1.2):
//     Cycle N   : S_RD_WAIT   → rd_fifo_pop=1, next=S_FIFO_WAIT
//     Cycle N+1 : S_FIFO_WAIT : FIFO latch dout tại posedge này → chỉ đợi
//     Cycle N+2 : S_FIFO_LATCH: dout valid và ổn định → latch ptext_0/1
//     Cycle N+3 : S_CORE_START: core_ptext ổn định → pulse core_start
//     Cycle N+4 : CORE latch {ptext_0, ptext_1} ← ĐÚNG!
//
// FIX-2: core_start và core_data_valid không xung đột (giữ nguyên từ v1.1)
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
        S_RD_WAIT     = 4'd2,
        S_FIFO_WAIT   = 4'd3,   // đợi 1 cycle sau pop — KHÔNG đọc dout
        S_FIFO_LATCH  = 4'd4,   // dout ổn định — latch vào core_ptext_0/1
        S_CORE_START  = 4'd5,   // core_ptext ổn định — pulse core_start
        S_CORE_WAIT   = 4'd6,
        S_WR_LOAD     = 4'd7,
        S_WR_SETTLE   = 4'd8,   // wait 1 cycle for last FIFO push to commit
        S_WR_START    = 4'd9,   // assert wr_start pulse
        S_WR_WAIT     = 4'd10,  // wait wr_done
        S_DONE        = 4'd11;

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

                // ── FIX v1.2: Đợi 1 cycle sau pop — KHÔNG đọc dout ─────────
                // rd_fifo_pop=1 được assert tại posedge cycle trước (S_RD_WAIT).
                // Tại posedge cycle này, sync_fifo đang thực hiện:
                //   dout <= mem[rd_idx]  (nonblocking — chưa commit)
                // Vì vậy dout chưa ổn định — KHÔNG được đọc ở đây.
                // Chuyển sang S_FIFO_LATCH để đọc ở cycle tiếp theo.
                S_FIFO_WAIT: begin
                    state <= S_FIFO_LATCH;
                end

                // ── FIX v1.2: dout đã ổn định — latch vào core_ptext ─────────
                // Tại posedge cycle này, nonblocking của FIFO đã commit:
                //   dout = mem[rd_idx] valid và ổn định.
                // An toàn để latch vào core_ptext_0/1.
                S_FIFO_LATCH: begin
                    // [BUG1-FIX] AXI 64-bit read: addr_low → rdata[31:0], addr_high → rdata[63:32]
                    // DMEM[src+0] = PTEXT_0 → rdata[31:0]  → core_ptext_0
                    // DMEM[src+4] = PTEXT_1 → rdata[63:32] → core_ptext_1
                    core_ptext_0    <= rd_fifo_dout[31:0];
                    core_ptext_1    <= rd_fifo_dout[63:32];
                    core_data_valid <= 1'b1;
                    state           <= S_CORE_START;
                end

                // ── FIX: core_ptext regs ổn định — pulse core_start ──────────
                // core_ptext_0/1 đã được latch từ cycle trước → ổn định.
                // CORE samples data_in = {ptext_0, ptext_1} khi start=1.
                S_CORE_START: begin
                    core_data_valid <= 1'b0;
                    core_start      <= 1'b1;   // 1-cycle pulse
                    state           <= S_CORE_WAIT;
                end

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
                            // word[5]=tag_3 pushed this cycle via nonblocking assign.
                            // FIFO mem[] latches it AFTER this posedge.
                            // Must wait 1 extra cycle (S_WR_SETTLE) before wr_start.
                            state <= S_WR_SETTLE;
                        end else begin
                            wr_load_cnt <= wr_load_cnt + 1'b1;
                        end
                    end else begin
                        status_fifo_overflow <= 1'b1;
                        dma_error            <= 1'b1;
                        state                <= S_DONE;
                    end
                end

                // ── Wait 1 cycle for last FIFO push to settle ────────────────
                // word[5] nonblocking push was issued last cycle.
                // After THIS posedge, FIFO wr_ptr is updated and all 6 words
                // are readable. Safe to assert wr_start next cycle.
                S_WR_SETTLE: begin
                    state <= S_WR_START;
                end

                // ── Trigger write engine ──────────────────────────────────────
                // All 6 words confirmed in FIFO. Assert wr_start pulse.
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

endmodule