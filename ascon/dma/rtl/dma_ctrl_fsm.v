// ============================================================================
// Module  : dma_ctrl_fsm  (v2.0 — Concurrent/Decoupled)
// ============================================================================

module dma_ctrl_fsm (
    input  wire         clk,
    input  wire         rst_n,

    // ── From axi_slave ───────────────────────────────────────────────────────
    input  wire         dma_start,
    input  wire         dma_soft_rst,
    input  wire [31:0]  byte_len,
    input  wire [7:0]   burst_len,

    // ── Status outputs ────────────────────────────────────────────────────────
    output reg          dma_busy,
    output reg          dma_done,
    output reg          dma_error,

    // ── Read engine ───────────────────────────────────────────────────────────
    output reg          rd_start,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         rd_busy,
    /* verilator lint_on UNUSEDSIGNAL */
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
    output reg          core_data_last,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         core_busy,
    input  wire         core_done,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire         core_data_out_valid,
    input  wire         core_tag_valid,

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

    // ── Write engine (Auto-triggering) ────────────────────────────────────────
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         wr_busy,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire         wr_done,
    input  wire         wr_error,

    // ── Status bits ───────────────────────────────────────────────────────────
    output reg          status_rd_done,
    output reg          status_wr_done,
    output reg          status_fifo_overflow
);

    wire [28:0] total_blocks    = byte_len[31:3]; // 8 bytes per block
    wire [28:0] blocks_per_read = {21'd0, burst_len} + 29'd1;

    // We write CT for EVERY block (total_blocks beats) + TAG logic (2 beats)
    // tag is 128-bit = 4 words = 2 beats (since we always write beats of AWLEN=0 / 2 words)
    wire [28:0] expected_wr_beats = total_blocks + 29'd2;

    reg [28:0] rd_blocks_sent;
    reg [28:0] core_blocks_fed;
    reg [28:0] wr_beats_done;

    // =========================================================================
    // BLOCK 1: rd_ctrl
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_start       <= 1'b0;
            rd_blocks_sent <= 29'd0;
            status_rd_done <= 1'b0;
        end else if (dma_soft_rst) begin
            rd_start       <= 1'b0;
            rd_blocks_sent <= 29'd0;
            status_rd_done <= 1'b0;
        end else begin
            rd_start <= 1'b0; // default pulse

            if (dma_start) begin
                rd_blocks_sent <= 29'd0;
                rd_start       <= 1'b1;
                status_rd_done <= 1'b0;
            end else if (rd_done) begin
                if (rd_blocks_sent + blocks_per_read < total_blocks) begin
                    rd_start       <= 1'b1;
                    rd_blocks_sent <= rd_blocks_sent + blocks_per_read;
                end else begin
                    rd_blocks_sent <= rd_blocks_sent + blocks_per_read;
                    status_rd_done <= 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // BLOCK 2: core_pump
    // =========================================================================
    localparam PUMP_IDLE      = 2'd0;
    localparam PUMP_WAIT      = 2'd1;
    localparam PUMP_LATCH     = 2'd2;
    localparam PUMP_WAIT_CORE = 2'd3;

    reg [1:0] pump_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
             pump_state      <= PUMP_IDLE;
             rd_fifo_pop     <= 1'b0;
             core_ptext_0    <= 32'h0;
             core_ptext_1    <= 32'h0;
             core_data_valid <= 1'b0;
             core_start      <= 1'b0;
             core_data_last  <= 1'b0;
             core_blocks_fed <= 29'd0;
        end else if (dma_soft_rst) begin
             pump_state      <= PUMP_IDLE;
             rd_fifo_pop     <= 1'b0;
             core_ptext_0    <= 32'h0;
             core_ptext_1    <= 32'h0;
             core_data_valid <= 1'b0;
             core_start      <= 1'b0;
             core_data_last  <= 1'b0;
             core_blocks_fed <= 29'd0;
        end else begin
             rd_fifo_pop <= 1'b0;
             core_start  <= 1'b0;

             if (dma_start) begin
                 pump_state      <= PUMP_IDLE;
                 core_blocks_fed <= 29'd0;
                 core_data_valid <= 1'b0;
             end

             case (pump_state)
                 PUMP_IDLE: begin
                     if (!rd_fifo_empty && dma_busy && (core_blocks_fed < total_blocks)) begin
                         rd_fifo_pop <= 1'b1;
                         pump_state  <= PUMP_WAIT;
                     end
                 end
                 PUMP_WAIT: begin
                     pump_state <= PUMP_LATCH;
                 end
                 PUMP_LATCH: begin
                     core_ptext_0    <= rd_fifo_dout[31:0];
                     core_ptext_1    <= rd_fifo_dout[63:32];
                     core_data_valid <= 1'b1;
                     core_data_last  <= (core_blocks_fed + 1 >= total_blocks);
                     core_start      <= 1'b1;  // 1-cycle pulse
                     core_blocks_fed <= core_blocks_fed + 1;
                     pump_state      <= PUMP_WAIT_CORE;
                 end
                 PUMP_WAIT_CORE: begin
                     if (core_data_out_valid) begin
                         core_data_valid <= 1'b0;
                         pump_state      <= PUMP_IDLE;
                     end
                 end
             endcase
        end
    end

    // =========================================================================
    // BLOCK 3: wr_push (combinational to WR FIFO) & Overall DMA Status
    // =========================================================================
    reg [2:0] push_state;
    reg [31:0] latch_ctext_1;
    reg [31:0] latch_tag_1, latch_tag_2, latch_tag_3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_fifo_push         <= 1'b0;
            wr_fifo_din          <= 32'h0;
            push_state           <= 3'd0;
            wr_beats_done        <= 29'd0;
            status_wr_done       <= 1'b0;
            status_fifo_overflow <= 1'b0;
            dma_busy             <= 1'b0;
            dma_done             <= 1'b0;
            dma_error            <= 1'b0;
            latch_ctext_1        <= 32'h0;
            latch_tag_1          <= 32'h0;
            latch_tag_2          <= 32'h0;
            latch_tag_3          <= 32'h0;
        end else if (dma_soft_rst) begin
            wr_fifo_push         <= 1'b0;
            wr_fifo_din          <= 32'h0;
            push_state           <= 3'd0;
            wr_beats_done        <= 29'd0;
            status_wr_done       <= 1'b0;
            status_fifo_overflow <= 1'b0;
            dma_busy             <= 1'b0;
            dma_done             <= 1'b0;
            dma_error            <= 1'b0;
        end else begin
            wr_fifo_push <= 1'b0;
            dma_done     <= 1'b0;

            if (dma_start) begin
                dma_busy       <= 1'b1;
                dma_error      <= 1'b0;
                status_wr_done <= 1'b0;
                wr_beats_done  <= 29'd0;
                push_state     <= 3'd0;
            end

            // Error monitoring
            if (rd_error || wr_error) begin
                 dma_error <= 1'b1;
            end

            // Push to FIFO based on core combination outputs
            if (wr_fifo_full && (core_data_out_valid || core_tag_valid || push_state != 0)) begin
                 status_fifo_overflow <= 1'b1;
                 dma_error <= 1'b1;
            end else begin
                case (push_state)
                    3'd0: begin
                        // Latch and Push first valid word immediately
                        if (core_data_out_valid) begin
                            wr_fifo_din   <= core_ctext_0;
                            wr_fifo_push  <= 1'b1;
                            latch_ctext_1 <= core_ctext_1;
                            push_state    <= 3'd1;
                        end else if (core_tag_valid) begin
                            wr_fifo_din  <= core_tag_0;
                            wr_fifo_push <= 1'b1;
                            latch_tag_1  <= core_tag_1;
                            latch_tag_2  <= core_tag_2;
                            latch_tag_3  <= core_tag_3;
                            push_state   <= 3'd2;
                        end
                    end
                    3'd1: begin
                        wr_fifo_din  <= latch_ctext_1;
                        wr_fifo_push <= 1'b1;
                        push_state   <= 3'd0;
                    end
                    3'd2: begin
                        wr_fifo_din  <= latch_tag_1;
                        wr_fifo_push <= 1'b1;
                        push_state   <= 3'd3;
                    end
                    3'd3: begin
                        wr_fifo_din  <= latch_tag_2;
                        wr_fifo_push <= 1'b1;
                        push_state   <= 3'd4;
                    end
                    3'd4: begin
                        wr_fifo_din  <= latch_tag_3;
                        wr_fifo_push <= 1'b1;
                        push_state   <= 3'd0;
                    end
                    default: push_state <= 3'd0;
                endcase
            end

            // Monitor Write Engine done pulses
            if (wr_done) begin
                wr_beats_done <= wr_beats_done + 1'b1;
                if (wr_beats_done + 1'b1 == expected_wr_beats) begin
                     status_wr_done <= 1'b1;
                     dma_busy <= 1'b0;
                     dma_done <= 1'b1;
                end
            end

        end
    end

endmodule