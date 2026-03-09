// ============================================================================
// Module  : dma_ctrl_fsm
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_dma
//
// Description:
//   Top-level control FSM that sequences the DMA pipeline:
//
//   IDLE → RD_START → CORE_FEED → CORE_WAIT → WR_START → DONE → IDLE
//
//   Detailed flow:
//     1. IDLE      : wait for dma_start pulse from axi_slave
//     2. RD_START  : kick dma_read_engine, wait for rd_done
//     3. CORE_FEED : pop RD FIFO → drive core_ptext, assert core_data_valid
//                    when core_data_ready, assert core_start (1 cycle) → CORE_WAIT
//     4. CORE_WAIT : wait for core_done pulse
//     5. WR_START  : push result into WR FIFO, kick dma_write_engine, wait for wr_done
//     6. DONE      : pulse dma_done, go back to IDLE
//
//   Error shortcut:
//     If rd_error after RD_START → skip CORE and WR, go to DONE with error set.
//     If wr_error after WR_START → DONE with error set.
// ============================================================================

module dma_ctrl_fsm (
    input  wire         clk,
    input  wire         rst_n,

    // ── From axi_slave (register interface) ──────────────────────────────────
    input  wire         dma_start,    // 1-cycle pulse
    input  wire         dma_soft_rst,

    // ── Status outputs ────────────────────────────────────────────────────────
    output reg          dma_busy,
    output reg          dma_done,     // 1-cycle pulse
    output reg          dma_error,    // sticky

    // ── Read engine control ───────────────────────────────────────────────────
    output reg          rd_start,     // 1-cycle pulse
    input  wire         rd_busy,
    input  wire         rd_done,      // 1-cycle pulse
    input  wire         rd_error,

    // ── RD FIFO pop interface (towards core_feed) ─────────────────────────────
    input  wire [63:0]  rd_fifo_dout,
    output reg          rd_fifo_pop,
    input  wire         rd_fifo_empty,

    // ── ascon_CORE interface ──────────────────────────────────────────────────
    output reg  [31:0]  core_ptext_0,
    output reg  [31:0]  core_ptext_1,
    output reg          core_data_valid,
    input  wire         core_data_ready,
    output reg          core_start,    // 1-cycle pulse
    input  wire         core_busy,
    input  wire         core_done,     // 1-cycle pulse

    // ── Result capture (on core_done) ─────────────────────────────────────────
    input  wire [31:0]  core_ctext_0,
    input  wire [31:0]  core_ctext_1,
    input  wire [31:0]  core_tag_0,
    input  wire [31:0]  core_tag_1,
    input  wire [31:0]  core_tag_2,
    input  wire [31:0]  core_tag_3,

    // ── WR FIFO push interface ────────────────────────────────────────────────
    output reg  [31:0]  wr_fifo_din,
    output reg          wr_fifo_push,
    input  wire         wr_fifo_full,

    // ── Write engine control ──────────────────────────────────────────────────
    output reg          wr_start,     // 1-cycle pulse
    input  wire         wr_busy,
    input  wire         wr_done,      // 1-cycle pulse
    input  wire         wr_error,

    // ── Status bits (to DMA status register) ──────────────────────────────────
    output reg          status_rd_done,
    output reg          status_wr_done,
    output reg          status_fifo_overflow
);

    // FSM states
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_RD_START  = 3'd1,
        S_RD_WAIT   = 3'd2,
        S_CORE_FEED = 3'd3,
        S_CORE_WAIT = 3'd4,
        S_WR_LOAD   = 3'd5,   // push result into WR FIFO
        S_WR_START  = 3'd6,
        S_DONE      = 3'd7;

    reg [2:0] state;

    // WR FIFO load counter: 6 pushes (ctext_0, ctext_1, tag_0..3)
    reg [2:0] wr_load_cnt;

    // Result capture registers
    reg [31:0] r_ctext_0, r_ctext_1;
    reg [31:0] r_tag_0, r_tag_1, r_tag_2, r_tag_3;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || dma_soft_rst) begin
            state               <= S_IDLE;
            dma_busy            <= 1'b0;
            dma_done            <= 1'b0;
            dma_error           <= 1'b0;
            rd_start            <= 1'b0;
            rd_fifo_pop         <= 1'b0;
            core_ptext_0        <= 32'h0;
            core_ptext_1        <= 32'h0;
            core_data_valid     <= 1'b0;
            core_start          <= 1'b0;
            wr_fifo_din         <= 32'h0;
            wr_fifo_push        <= 1'b0;
            wr_start            <= 1'b0;
            wr_load_cnt         <= 3'd0;
            status_rd_done      <= 1'b0;
            status_wr_done      <= 1'b0;
            status_fifo_overflow<= 1'b0;
            r_ctext_0 <= 32'h0; r_ctext_1 <= 32'h0;
            r_tag_0   <= 32'h0; r_tag_1   <= 32'h0;
            r_tag_2   <= 32'h0; r_tag_3   <= 32'h0;
        end else begin
            // Default: clear 1-cycle signals
            dma_done     <= 1'b0;
            rd_start     <= 1'b0;
            rd_fifo_pop  <= 1'b0;
            core_start   <= 1'b0;
            wr_fifo_push <= 1'b0;
            wr_start     <= 1'b0;

            case (state)

                // ----------------------------------------------------------------
                S_IDLE: begin
                    dma_busy <= 1'b0;
                    if (dma_start) begin
                        dma_busy  <= 1'b1;
                        dma_error <= 1'b0;
                        status_rd_done <= 1'b0;
                        status_wr_done <= 1'b0;
                        rd_start  <= 1'b1;
                        state     <= S_RD_WAIT;
                    end
                end

                // ----------------------------------------------------------------
                // Wait for read engine to finish
                // ----------------------------------------------------------------
                S_RD_WAIT: begin
                    if (rd_done) begin
                        status_rd_done <= 1'b1;
                        if (rd_error) begin
                            dma_error <= 1'b1;
                            state     <= S_DONE; // skip core + write
                        end else begin
                            // Initiate FIFO pop — data arrives 1 cycle later
                            rd_fifo_pop <= 1'b1;
                            state       <= S_CORE_FEED;
                        end
                    end
                end

                // ----------------------------------------------------------------
                // Feed plaintext from RD FIFO into core
                // ----------------------------------------------------------------
                S_CORE_FEED: begin
                    // rd_fifo_dout is valid this cycle (popped previous cycle)
                    core_ptext_0    <= rd_fifo_dout[63:32];
                    core_ptext_1    <= rd_fifo_dout[31:0];
                    core_data_valid <= 1'b1;

                    if (core_data_ready) begin
                        core_data_valid <= 1'b0;
                        core_start      <= 1'b1;  // 1-cycle pulse to start ASCON
                        state           <= S_CORE_WAIT;
                    end
                end

                // ----------------------------------------------------------------
                // Wait for ASCON core to finish
                // ----------------------------------------------------------------
                S_CORE_WAIT: begin
                    if (core_done) begin
                        // Latch results
                        r_ctext_0 <= core_ctext_0;
                        r_ctext_1 <= core_ctext_1;
                        r_tag_0   <= core_tag_0;
                        r_tag_1   <= core_tag_1;
                        r_tag_2   <= core_tag_2;
                        r_tag_3   <= core_tag_3;
                        wr_load_cnt <= 3'd0;
                        state       <= S_WR_LOAD;
                    end
                end

                // ----------------------------------------------------------------
                // Push 6 × 32-bit words into WR FIFO sequentially
                // Order: ctext_0, ctext_1, tag_0, tag_1, tag_2, tag_3
                // ----------------------------------------------------------------
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
                            wr_fifo_push <= 1'b1; // push last word
                            wr_start     <= 1'b1; // kick write engine
                            state        <= S_WR_START;
                        end else begin
                            wr_load_cnt <= wr_load_cnt + 1'b1;
                        end
                    end else begin
                        // FIFO full — overflow condition (should not happen in Phase 1)
                        status_fifo_overflow <= 1'b1;
                        dma_error            <= 1'b1;
                        state                <= S_DONE;
                    end
                end

                // ----------------------------------------------------------------
                // Wait for write engine to finish
                // ----------------------------------------------------------------
                S_WR_START: begin
                    if (wr_done) begin
                        status_wr_done <= 1'b1;
                        if (wr_error)
                            dma_error <= 1'b1;
                        state <= S_DONE;
                    end
                end

                // ----------------------------------------------------------------
                S_DONE: begin
                    dma_done <= 1'b1;  // 1-cycle pulse
                    dma_busy <= 1'b0;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule