`timescale 1ns/1ps

// ============================================================================
// Module  : dma_ctrl_fsm  (v4.0 — AD + Payload Sequential Phases)
//
// CHANGES from v3.0:
//   [AD-1] Thêm port: ad_src_addr, ad_len (từ slave register ADDR_AD_ADDR/LEN).
//   [AD-2] Thêm output: core_ad_in[127:0], core_ad_valid, core_ad_last.
//          FSM tự sinh các tín hiệu này khi đọc AD từ AXI Master.
//   [AD-3] Khi ad_len=0: bỏ qua AD phase (core_ad_valid luôn=0).
//   [AD-4] Sequence:
//            dma_start → [RD_AD phase] → [PUMP_AD phase]
//                      → [RD_PAYLOAD phase] → [PUMP_PAYLOAD phase]
//                      → WR CT/Tag → DONE
//          Read engine dùng chung AXI Master port. Khi AD phase xong,
//          FSM chuyển rd_src_addr sang payload src_addr và tiếp tục.
//   [AD-5] AD block = 64-bit (ASCON-128 rate). Lấy 1 FIFO pop (64-bit)
//          làm 1 AD block. 128-bit upper half = FIFO data, lower = 0 (ASCON-128).
//          Với ASCON-128a (core tự xử lý rate=128-bit), cần 2 pop → 1 block.
//          Hiện implement theo ASCON-128 (1 pop = 1 block). Core mode[0]
//          quyết định có dùng upper 64-bit hay full 128-bit.
//
// Retained from v3.0:
//   FWFT zero-latency pop, PUMP_START/PUMP_WAIT_CORE, wr_push logic.
// ============================================================================

module dma_ctrl_fsm #(
    parameter RD_FIFO_DEPTH = 4          // RD FIFO entries (64-bit); caps AD burst
) (
    input  wire         clk,
    input  wire         rst_n,

    // ── From axi_slave ────────────────────────────────────────────────────────
    input  wire         dma_start,
    input  wire         dma_soft_rst,
    input  wire [31:0]  byte_len,          // plaintext byte length
    input  wire [7:0]   burst_len,

    // ── AD parameters (v4.0) ─────────────────────────────────────────────────
    input  wire [31:0]  ad_src_addr,       // AD source address in memory
    input  wire [31:0]  ad_len,            // AD byte length (0 = no AD)

    // ── Status outputs ────────────────────────────────────────────────────────
    output reg          dma_busy,
    output reg          dma_done,
    output reg          dma_error,

    // ── Read engine ───────────────────────────────────────────────────────────
    output reg          rd_start,
    output reg  [31:0]  rd_override_addr,  // NEW: override src_addr for AD fetch
    output reg          rd_use_override,   // NEW: 1=use rd_override_addr, 0=use default src_addr
    output wire [7:0]   rd_burst_len,      // [FIX-AD-BURST] per-phase ARLEN to read engine
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         rd_busy,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire         rd_done,
    input  wire         rd_error,

    // ── RD FIFO (registered path — kept for compatibility) ────────────────────
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [63:0]  rd_fifo_dout,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire         rd_fifo_pop,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire         rd_fifo_empty,
    /* verilator lint_on UNUSEDSIGNAL */

    // ── RD FIFO (FWFT — combinational, zero-latency) ─────────────────────────
    input  wire [63:0]  rd_fifo_fwft_dout,
    input  wire         rd_fifo_fwft_valid,

    // ── ascon_CORE — Payload (PT/CT) interface ────────────────────────────────
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

    // ── ascon_CORE — AD interface (v4.0) ─────────────────────────────────────
    output reg  [127:0] core_ad_in,        // AD block data (upper 64-bit valid for ASCON-128)
    output reg          core_ad_valid,     // level: AD block presented to core
    output reg          core_ad_last,      // high on last AD block
    input  wire         core_ad_ready,     // CONTROLLER in S_AD_LOAD (gate AD pump)

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

    // =========================================================================
    // Derived counters
    // =========================================================================
    // Payload: 8 bytes per block (ASCON-128 rate)
    wire [28:0] total_blocks    = byte_len[31:3];

    // AD: 8 bytes per block (ASCON-128 rate), round up
    wire        has_ad          = (ad_len != 32'd0);
    wire [28:0] ad_total_blocks = (!has_ad)        ? 29'd0 :
                                  (ad_len[2:0]==0) ? {3'd0, ad_len[31:3]} :
                                                     {3'd0, ad_len[31:3]} + 29'd1;

    // [FIX-AD-BURST] AD phase must read EXACTLY ad_total_blocks (capped to RD FIFO
    // depth), NOT the payload burst. The AD pump consumes only ad_total_blocks; a
    // payload-sized over-read (8 beats) fills the 4-entry RD FIFO → read engine
    // stalls mid-burst waiting for FIFO space that never frees → DMA deadlock (T4).
    wire [7:0]  ad_burst_len = (ad_total_blocks == 29'd0)             ? 8'd0 :
                               (ad_total_blocks >= RD_FIFO_DEPTH)     ? (RD_FIFO_DEPTH[7:0] - 8'd1) :
                                                                        (ad_total_blocks[7:0] - 8'd1);

    wire [28:0] expected_wr_beats = total_blocks + 29'd2;

    // =========================================================================
    // Top-level DMA phase
    // =========================================================================
    localparam [1:0]
        DMA_PHASE_AD      = 2'd0,
        DMA_PHASE_PAYLOAD = 2'd1,
        DMA_PHASE_DONE    = 2'd2;

    reg [1:0] dma_phase;

    // [FIX-AD-BURST] Burst length latched by read engine at rd_start, selected by
    // current phase. blocks_per_read accounting MUST use the same value so AD/payload
    // block counters advance consistently with what the read engine actually fetches.
    wire [7:0]  cur_burst_len   = (dma_phase == DMA_PHASE_AD) ? ad_burst_len : burst_len;
    assign      rd_burst_len    = cur_burst_len;
    wire [28:0] blocks_per_read = {21'd0, cur_burst_len} + 29'd1;

    // =========================================================================
    // Block counters
    // =========================================================================
    reg [28:0] rd_blocks_sent;      // blocks issued to read engine in current phase
    reg [28:0] core_blocks_fed;     // blocks fed to core (payload pump)
    reg [28:0] ad_blocks_pumped;    // AD blocks pumped to core AD interface
    reg [28:0] wr_beats_done;

    // =========================================================================
    // BLOCK 1: rd_ctrl — issue rd_start for AD phase then payload phase
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_start         <= 1'b0;
            rd_override_addr <= 32'h0;
            rd_use_override  <= 1'b0;
            rd_blocks_sent   <= 29'd0;
            dma_phase        <= DMA_PHASE_AD;
            status_rd_done   <= 1'b0;
        end else if (dma_soft_rst) begin
            rd_start         <= 1'b0;
            rd_override_addr <= 32'h0;
            rd_use_override  <= 1'b0;
            rd_blocks_sent   <= 29'd0;
            dma_phase        <= DMA_PHASE_AD;
            status_rd_done   <= 1'b0;
        end else begin
            rd_start <= 1'b0; // default pulse

            if (dma_start) begin
                rd_blocks_sent   <= 29'd0;
                status_rd_done   <= 1'b0;
                if (has_ad) begin
                    dma_phase        <= DMA_PHASE_AD;
                    rd_override_addr <= ad_src_addr;
                    rd_use_override  <= 1'b1;
                    rd_start         <= 1'b1;
                end else begin
                    dma_phase        <= DMA_PHASE_PAYLOAD;
                    rd_use_override  <= 1'b0;
                    if (total_blocks > 0)
                        rd_start     <= 1'b1;
                end
            end else if (rd_done) begin
                case (dma_phase)
                    DMA_PHASE_AD: begin
                        if (rd_blocks_sent + blocks_per_read < ad_total_blocks) begin
                            // More AD to fetch
                            rd_start       <= 1'b1;
                            rd_blocks_sent <= rd_blocks_sent + blocks_per_read;
                        end else begin
                            // All AD blocks fetched → switch to payload phase
                            rd_blocks_sent   <= 29'd0;
                            dma_phase        <= DMA_PHASE_PAYLOAD;
                            rd_use_override  <= 1'b0;
                            if (total_blocks > 0)
                                rd_start     <= 1'b1;
                        end
                    end
                    DMA_PHASE_PAYLOAD: begin
                        if (rd_blocks_sent + blocks_per_read < total_blocks) begin
                            rd_start       <= 1'b1;
                            rd_blocks_sent <= rd_blocks_sent + blocks_per_read;
                        end else begin
                            status_rd_done <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // BLOCK 2: AD pump — feed AD blocks from RD FIFO to core_ad_in
    //
    // ASCON-128 rate = 64-bit per block. We take 1 FIFO pop (64-bit) and
    // present it as the upper 64-bit of core_ad_in[127:0], lower 64=0.
    // The CONTROLLER absorbs only the rate portion (64-bit for ASCON-128).
    //
    // States:
    //   AD_PMP_IDLE  : waiting for FIFO data (during AD phase only)
    //   AD_PMP_PRES  : presenting block to core, hold 1 cycle for stability
    //   AD_PMP_WAIT  : wait for core to sample AD (CONTROLLER advances state)
    // =========================================================================
    localparam [1:0]
        AD_PMP_IDLE = 2'd0,
        AD_PMP_PRES = 2'd1,
        AD_PMP_WAIT = 2'd2,
        AD_PMP_DONE = 2'd3;

    reg [1:0] ad_pump_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ad_pump_state    <= AD_PMP_DONE;
            core_ad_in       <= 128'h0;
            core_ad_valid    <= 1'b0;
            core_ad_last     <= 1'b0;
            ad_blocks_pumped <= 29'd0;
        end else if (dma_soft_rst) begin
            ad_pump_state    <= AD_PMP_DONE;
            core_ad_in       <= 128'h0;
            core_ad_valid    <= 1'b0;
            core_ad_last     <= 1'b0;
            ad_blocks_pumped <= 29'd0;
        end else begin
            core_ad_valid <= 1'b0;
            core_ad_last  <= 1'b0;

            if (dma_start) begin
                ad_blocks_pumped <= 29'd0;
                ad_pump_state    <= has_ad ? AD_PMP_IDLE : AD_PMP_DONE;
            end

            case (ad_pump_state)
                AD_PMP_IDLE: begin
                    if (rd_fifo_fwft_valid && core_ad_ready && ad_blocks_pumped < ad_total_blocks) begin
                        // FIX-ENDIAN: RAM is little-endian (lower addr → lower AXI bits).
                        // Payload pump already swaps halves: ptext_0=RDATA[31:0], ptext_1=RDATA[63:32].
                        // AD pump must do the same swap so ASCON sees bytes in correct BE order.
                        core_ad_in    <= {{rd_fifo_fwft_dout[31:0], rd_fifo_fwft_dout[63:32]}, 64'h0};
                        ad_pump_state <= AD_PMP_PRES;
                    end
                end

                AD_PMP_PRES: begin
                    core_ad_valid    <= 1'b1;
                    core_ad_last     <= (ad_blocks_pumped + 1 >= ad_total_blocks);
                    ad_blocks_pumped <= ad_blocks_pumped + 1;
                    ad_pump_state    <= AD_PMP_WAIT;
                end

                AD_PMP_WAIT: begin
                    if (ad_blocks_pumped >= ad_total_blocks)
                        ad_pump_state <= AD_PMP_DONE;
                    else
                        ad_pump_state <= AD_PMP_IDLE;
                end

                AD_PMP_DONE: begin
                    core_ad_valid <= 1'b0;
                    core_ad_last  <= 1'b0;
                end

                default: ad_pump_state <= AD_PMP_DONE;
            endcase
        end
    end

    // Separate rd_fifo_pop management — combine AD pump pop with payload pump pop
    // AD pump drives rd_fifo_pop in AD_PMP_PRES; payload pump drives it in PUMP_IDLE.
    // Since they are mutually exclusive phases, no arbitration needed.
    // NOTE: rd_fifo_pop is declared as reg; both AD and payload blocks drive it.
    // Verilog 2001: multiple always blocks driving same reg is illegal unless
    // we use a single always block. Re-factor: move rd_fifo_pop to a wire with mux.
    // (See combined always block below; the two blocks above set rd_fifo_pop but
    //  we consolidate into the pump_state always for payload.)
    // ─── Simplification: use separate reg for each and OR them ────────────────
    // (Both are reset to 0 and only one is active at a time per phase.)

    // =========================================================================
    // BLOCK 3: core_pump (Payload) — FWFT v3.0
    // =========================================================================
    localparam [1:0]
        PUMP_IDLE      = 2'd0,
        PUMP_START     = 2'd1,
        PUMP_WAIT_CORE = 2'd2;

    reg [1:0] pump_state;
    reg       rd_fifo_pop_ad;      // pop from AD pump block
    reg       rd_fifo_pop_payload; // pop from payload pump block

    assign rd_fifo_pop = rd_fifo_pop_ad | rd_fifo_pop_payload;

    // ── Payload pump ──────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pump_state           <= PUMP_IDLE;
            rd_fifo_pop_payload  <= 1'b0;
            core_ptext_0         <= 32'h0;
            core_ptext_1         <= 32'h0;
            core_data_valid      <= 1'b0;
            core_start           <= 1'b0;
            core_data_last       <= 1'b0;
            core_blocks_fed      <= 29'd0;
        end else if (dma_soft_rst) begin
            pump_state           <= PUMP_IDLE;
            rd_fifo_pop_payload  <= 1'b0;
            core_ptext_0         <= 32'h0;
            core_ptext_1         <= 32'h0;
            core_data_valid      <= 1'b0;
            core_start           <= 1'b0;
            core_data_last       <= 1'b0;
            core_blocks_fed      <= 29'd0;
        end else begin
            rd_fifo_pop_payload <= 1'b0;
            core_start          <= 1'b0;

            if (dma_start) begin
                pump_state      <= PUMP_IDLE;
                core_blocks_fed <= 29'd0;
                core_data_valid <= 1'b0;
                core_start      <= 1'b1;  // Kick CONTROLLER INIT immediately at DMA start
            end

            case (pump_state)
                PUMP_IDLE: begin
                    // Only run payload pump during payload phase and AD pump done
                    if (rd_fifo_fwft_valid && dma_busy &&
                        dma_phase == DMA_PHASE_PAYLOAD &&
                        ad_pump_state == AD_PMP_DONE &&
                        core_blocks_fed < total_blocks)
                    begin
                        core_ptext_0        <= rd_fifo_fwft_dout[31:0];
                        core_ptext_1        <= rd_fifo_fwft_dout[63:32];
                        core_data_valid     <= 1'b1;
                        core_data_last      <= (core_blocks_fed + 1 >= total_blocks);
                        core_blocks_fed     <= core_blocks_fed + 1;
                        rd_fifo_pop_payload <= 1'b1;
                        pump_state          <= PUMP_START;
                    end
                end
                PUMP_START: begin
                    // core_start was already fired at dma_start; just proceed.
                    // core_data_ready guard is removed: we must enter PUMP_WAIT_CORE
                    // BEFORE the CONTROLLER reaches S_DATA_LOAD (so we don't miss
                    // the 1-cycle data_out_valid pulse).
                    pump_state <= PUMP_WAIT_CORE;
                end
                PUMP_WAIT_CORE: begin
                    if (core_data_out_valid) begin
                        core_data_valid <= 1'b0;
                        pump_state      <= PUMP_IDLE;
                    end
                end
                default: pump_state <= PUMP_IDLE;
            endcase
        end
    end

    // ── AD pump pop (separate reg to avoid multi-driver) ──────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_fifo_pop_ad <= 1'b0;
        else if (dma_soft_rst)
            rd_fifo_pop_ad <= 1'b0;
        else begin
            rd_fifo_pop_ad <= 1'b0; // default
            if (ad_pump_state == AD_PMP_IDLE && rd_fifo_fwft_valid && core_ad_ready && ad_blocks_pumped < ad_total_blocks)
                rd_fifo_pop_ad <= 1'b1;
        end
    end

    // =========================================================================
    // BLOCK 4: wr_push (CT/Tag → WR FIFO) & Overall DMA Status
    // =========================================================================
    reg [2:0]  push_state;
    reg [31:0] latch_ctext_1;
    reg [31:0] latch_tag_0, latch_tag_1, latch_tag_2, latch_tag_3;
    reg        tag_latch_pending;

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
            latch_tag_0          <= 32'h0;
            latch_tag_1          <= 32'h0;
            latch_tag_2          <= 32'h0;
            latch_tag_3          <= 32'h0;
            tag_latch_pending    <= 1'b0;
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
            tag_latch_pending    <= 1'b0;
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

            if (rd_error || wr_error)
                dma_error <= 1'b1;

            if (wr_fifo_full && (core_data_out_valid || core_tag_valid || push_state != 0 || tag_latch_pending)) begin
                status_fifo_overflow <= 1'b1;
                dma_error            <= 1'b1;
            end else begin
                case (push_state)
                    3'd0: begin
                        if (core_data_out_valid) begin
                            wr_fifo_din   <= core_ctext_0;
                            wr_fifo_push  <= 1'b1;
                            latch_ctext_1 <= core_ctext_1;
                            if (core_tag_valid) begin
                                tag_latch_pending <= 1'b1;
                                latch_tag_0 <= core_tag_0;
                                latch_tag_1 <= core_tag_1;
                                latch_tag_2 <= core_tag_2;
                                latch_tag_3 <= core_tag_3;
                            end
                            push_state    <= 3'd1;
                        end else if (core_tag_valid) begin
                            wr_fifo_din  <= core_tag_1;
                            wr_fifo_push <= 1'b1;
                            latch_tag_0  <= core_tag_0;
                            latch_tag_2  <= core_tag_2;
                            latch_tag_3  <= core_tag_3;
                            tag_latch_pending <= 1'b0;
                            push_state   <= 3'd2;
                        end else if (tag_latch_pending) begin
                            wr_fifo_din  <= latch_tag_1;
                            wr_fifo_push <= 1'b1;
                            tag_latch_pending <= 1'b0;
                            push_state   <= 3'd2;
                        end
                    end
                    3'd1: begin
                        wr_fifo_din  <= latch_ctext_1;
                        wr_fifo_push <= 1'b1;
                        if (core_tag_valid) begin
                            tag_latch_pending <= 1'b1;
                            latch_tag_0 <= core_tag_0;
                            latch_tag_1 <= core_tag_1;
                            latch_tag_2 <= core_tag_2;
                            latch_tag_3 <= core_tag_3;
                        end
                        push_state   <= 3'd0;
                    end
                    3'd2: begin
                        wr_fifo_din  <= latch_tag_0;
                        wr_fifo_push <= 1'b1;
                        push_state   <= 3'd3;
                    end
                    3'd3: begin
                        wr_fifo_din  <= latch_tag_3;
                        wr_fifo_push <= 1'b1;
                        push_state   <= 3'd4;
                    end
                    3'd4: begin
                        wr_fifo_din  <= latch_tag_2;
                        wr_fifo_push <= 1'b1;
                        push_state   <= 3'd0;
                    end
                    default: push_state <= 3'd0;
                endcase
            end

            if (wr_done) begin
                wr_beats_done <= wr_beats_done + 1'b1;
                if (wr_beats_done + 1'b1 == expected_wr_beats) begin
                    status_wr_done <= 1'b1;
                    dma_busy       <= 1'b0;
                    dma_done       <= 1'b1;
                end
            end
        end
    end

endmodule
