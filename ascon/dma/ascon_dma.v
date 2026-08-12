`timescale 1ns/1ps

// ============================================================================
// Module  : ascon_dma
// Project : ASCON Crypto Accelerator IP
// Version : 2.0  (v4.0 AD fetch phase: thêm AD DMA channel dùng chung AXI Master)
//
// Description:
//   ASCON-dedicated DMA engine. Orchestrates the full data movement pipeline:
//     DDR → (AXI4 read) → RD FIFO → ascon_CORE → WR FIFO → (AXI4 write) → DDR
//
//   Register map (offset within ascon_axi_slave space, base 0x2000_0000):
//     0x100  DMA_SRC_ADDR   R/W  Source address (plaintext in DDR)
//     0x104  DMA_DST_ADDR   R/W  Destination address (ctext+tag out)
//     0x108  DMA_BYTE_LEN   R/W  Bytes to read (Phase 1: always 8)
//     0x10C  DMA_CTRL       R/W  [0]=START [1]=SOFT_RST [2]=RD_ONLY [3]=WR_ONLY
//     0x110  DMA_STATUS     RO   [0]=BUSY [1]=DONE [2]=RD_DONE [3]=WR_DONE
//                                [4]=RD_ERROR [5]=WR_ERROR [6]=FIFO_OVERFLOW
//     0x114  DMA_BURST_LEN  R/W  [7:0] AXI burst length (0=1 beat)
//     0x118  DMA_ERR_ADDR   RO   Address that caused AXI error (debug)
//
//   Register values are driven from ascon_reg_bank via the control interface.
//   This module has NO internal AXI slave — all registers live in ascon_reg_bank.
//
// Hierarchy:
//   ascon_dma
//   ├── dma_ctrl_fsm         — top control FSM (sequences all phases)
//   ├── dma_read_engine      — AXI4 master read (fetch plaintext)
//   ├── dma_write_engine     — AXI4 master write (store ctext + tag)
//   ├── sync_fifo (rd_fifo)  — 4 × 64-bit RD FIFO
//   └── sync_fifo (wr_fifo)  — WR_FIFO_DEPTH × 32-bit WR FIFO
//
// External interfaces:
//   Control   : from ascon_axi_slave (reg_bank) — src_addr, dst_addr, byte_len,
//               dma_start, dma_soft_rst, burst_len, dma_busy, dma_done, dma_error
//   Core      : to/from ascon_CORE
//   AXI4 Full : M_AXI_* master interface (connects to crossbar / memory)
//
// Phase 1 constraints:
//   - Single 64-bit block (8 bytes plaintext)
//   - 1-beat AXI read (ARLEN=0), 3-beat AXI write (AWLEN=2)
//   - No concurrent read/write; strictly sequential
//   - No unaligned access handling (driver must ensure 8-byte alignment)
//
// Firmware driver notes (DO NOT CHANGE without updating firmware):
//   1. Write DMA_SRC_ADDR (0x100), DMA_DST_ADDR (0x104), DMA_BYTE_LEN (0x108)
//      each separated by a STATUS read fence (AXI ordering)
//   2. Write DMA_CTRL (0x10C) bit[0]=1 to START — this is SEPARATE from
//      ASCON core CTRL at offset 0x000. Driver MUST write 0x10C, NOT 0x000.
//   3. Poll DMA_STATUS (0x110) bit[1]=DONE or bit[4:5]=ERROR
//      NOTE: CPU-side STATUS mirror is at 0x004 bits[3:2] (dma_done/dma_busy)
//            in ascon_reg_bank. Firmware polls 0x20000004 bits[3:2].
//   4. Data coherency: CPU must ensure plaintext is in DMEM SRAM (not only
//      in DCache) before DMA start. Use non-cacheable writes (MMIO path) or
//      explicit cache flush. DMA bypasses DCache and reads SRAM directly.
// ============================================================================

`include "ascon/dma/rtl/sync_fifo.v"
`include "ascon/dma/rtl/dma_read_engine.v"
`include "ascon/dma/rtl/dma_write_inval_range.v"
`include "ascon/dma/rtl/dma_write_engine.v"
`include "ascon/dma/rtl/dma_pingpong_bank_state.v"
`include "ascon/dma/rtl/dma_read_refill_policy.v"
`include "ascon/dma/rtl/dma_write_drain_policy.v"
`include "ascon/dma/rtl/dma_read_bank_credit_planner.v"
`include "ascon/dma/rtl/dma_write_bank_credit_planner.v"
`include "ascon/dma/rtl/dma_payload_feeder.v"
`include "ascon/dma/rtl/dma_runtime_counters.v"
`include "ascon/dma/rtl/dma_read_scheduler.v"
`include "ascon/dma/rtl/dma_completion_scoreboard.v"
`include "ascon/dma/rtl/dma_ingress_buffer_mgr.v"
`include "ascon/dma/rtl/dma_egress_buffer_mgr.v"
`include "ascon/dma/rtl/dma_ctrl_fsm.v"
`include "ascon/dma/rtl/dma_atu.v"
`include "ascon/dma/rtl/dma_snoop_arb.v"
`include "ascon/dma/rtl/dma_err_latch.v"

module ascon_dma #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH = 64,   // AXI4 Master data bus width
    parameter AXI_ID_WIDTH   = 4,
    parameter RD_FIFO_DEPTH  = 8,    // entries per ping-pong bank (64-bit each)
    parameter WR_FIFO_DEPTH  = 512   // entries (32-bit each); supports coherent sweep up to 1KB payload
) (
    input  wire  clk,
    input  wire  rst_n,

    // =========================================================================
    // Control interface (from ascon_reg_bank via ascon_axi_slave)
    // =========================================================================
    input  wire [ADDR_WIDTH-1:0]  src_addr,      // DMA_SRC_ADDR (plaintext)
    input  wire [ADDR_WIDTH-1:0]  dst_addr,      // DMA_DST_ADDR (ciphertext+tag output)
    input  wire [31:0]            byte_len,      // DMA_BYTE_LEN (plaintext bytes)
    input  wire [7:0]             burst_len,     // DMA_BURST_LEN[7:0]

    // ── AD parameters (v2.0) ────────────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0]  ad_src_addr,   // AD_ADDR register: source of AD in memory
    input  wire [31:0]            ad_len,        // AD_LEN register: AD byte length (0=no AD)
    input  wire [ADDR_WIDTH-1:0]  atu_base,      // ATU physical base
    input  wire [ADDR_WIDTH-1:0]  atu_window,    // ATU window size / enable range
    input  wire [1:0]             coh_ctrl,      // [0]=read snoop, [1]=write invalidate
    input  wire [0:0]             context_id,    // H3 context sideband from register bank

    input  wire                   dma_start,     // from DMA_CTRL[0] pulse
    input  wire                   dma_soft_rst,  // from DMA_CTRL[1] pulse

    // Status outputs
    output wire                   dma_busy,
    output wire                   dma_done,
    output wire                   dma_error,

    output wire                   status_rd_done,
    output wire                   status_wr_done,
    output wire                   status_rd_error,
    output wire                   status_wr_error,
    output wire                   status_fifo_overflow,
    output wire [0:0]             context_id_active,

    // DMA_ERR_ADDR (0x118) — address that caused AXI error
    output wire [ADDR_WIDTH-1:0]  dma_err_addr,

    // =========================================================================
    // Interface to ascon_CORE — Payload (PT/CT)
    // =========================================================================
    output wire [31:0]            core_ptext_0,
    output wire [31:0]            core_ptext_1,
    output wire                   core_data_valid,
    input  wire                   core_data_ready,
    output wire                   core_start,
    output wire                   core_data_last,
    input  wire                   core_busy,
    input  wire                   core_done,
    input  wire                   core_data_out_valid,
    input  wire                   core_tag_valid,

    // ── Interface to ascon_CORE — AD (v2.0) ──────────────────────────────────
    output wire [127:0]           core_ad_in,    // AD block to core (upper 64-bit valid)
    output wire                   core_ad_valid, // AD block valid pulse
    output wire                   core_ad_last,  // last AD block flag
    input  wire                   core_ad_ready, // CONTROLLER in S_AD_LOAD (gate AD pump)

    // Results from core
    input  wire [31:0]            core_ctext_0,
    input  wire [31:0]            core_ctext_1,
    input  wire [31:0]            core_tag_0,
    input  wire [31:0]            core_tag_1,
    input  wire [31:0]            core_tag_2,
    input  wire [31:0]            core_tag_3,

    // =========================================================================
    // AXI4-Full Master Interface (to crossbar / DMEM / external memory)
    // =========================================================================

    // Write Address Channel
    output wire [AXI_ID_WIDTH-1:0]       M_AXI_AWID,
    output wire [ADDR_WIDTH-1:0]         M_AXI_AWADDR,
    output wire [7:0]                    M_AXI_AWLEN,
    output wire [2:0]                    M_AXI_AWSIZE,
    output wire [1:0]                    M_AXI_AWBURST,
    output wire [3:0]                    M_AXI_AWCACHE,
    output wire [2:0]                    M_AXI_AWPROT,
    output wire                          M_AXI_AWVALID,
    input  wire                          M_AXI_AWREADY,

    // Write Data Channel
    output wire [AXI_DATA_WIDTH-1:0]     M_AXI_WDATA,
    output wire [AXI_DATA_WIDTH/8-1:0]   M_AXI_WSTRB,
    output wire                          M_AXI_WLAST,
    output wire                          M_AXI_WVALID,
    input  wire                          M_AXI_WREADY,

    // Write Response Channel
    input  wire [AXI_ID_WIDTH-1:0]       M_AXI_BID,
    input  wire [1:0]                    M_AXI_BRESP,
    input  wire                          M_AXI_BVALID,
    output wire                          M_AXI_BREADY,

    // Read Address Channel
    output wire [AXI_ID_WIDTH-1:0]       M_AXI_ARID,
    output wire [ADDR_WIDTH-1:0]         M_AXI_ARADDR,
    output wire [7:0]                    M_AXI_ARLEN,
    output wire [2:0]                    M_AXI_ARSIZE,
    output wire [1:0]                    M_AXI_ARBURST,
    output wire [3:0]                    M_AXI_ARCACHE,
    output wire [2:0]                    M_AXI_ARPROT,
    output wire                          M_AXI_ARVALID,
    input  wire                          M_AXI_ARREADY,

    // Read Data Channel
    input  wire [AXI_ID_WIDTH-1:0]       M_AXI_RID,
    input  wire [AXI_DATA_WIDTH-1:0]     M_AXI_RDATA,
    input  wire [1:0]                    M_AXI_RRESP,
    input  wire                          M_AXI_RLAST,
    input  wire                          M_AXI_RVALID,
    output wire                          M_AXI_RREADY,

    // Optional sideband snoop interface to DCache
    output wire [ADDR_WIDTH-1:0]         DC_SNOOP_ADDR,
    output wire [1:0]                    DC_SNOOP_CMD,
    output wire                          DC_SNOOP_REQ_VALID,
    input  wire                          DC_SNOOP_REQ_READY,
    input  wire                          DC_SNOOP_RESP_VALID,
    input  wire                          DC_SNOOP_RESP_HIT,
    input  wire [127:0]                 DC_SNOOP_RESP_DATA
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // RD FIFO (64-bit wide, 4 deep)
    wire [63:0] rd_fifo_din;
    wire        rd_fifo_push;
    wire        rd_fifo_full;
    wire [63:0] rd_fifo_dout;
    wire        rd_fifo_pop;
    wire        rd_fifo_empty;
    wire        rd_buf_active_bank;
    wire        rd_buf_fill_bank;
    wire        rd_buf_drain_ready;
    wire        rd_buf_fill_ready;
    wire        rd_buf_swap_pulse;

    wire [31:0] wr_fifo_din;
    wire        wr_fifo_push;
    wire        wr_fifo_full;
    wire [31:0] wr_fifo_dout;
    wire        wr_fifo_pop;
    wire        wr_fifo_empty;
    wire        wr_buf_active_bank;
    wire        wr_buf_fill_bank;
    wire        wr_buf_drain_ready;
    wire        wr_buf_fill_ready;
    wire        wr_buf_swap_pulse;
    wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_count;
    wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_drain_count;
    wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_fill_count;
    wire [$clog2(WR_FIFO_DEPTH):0] wr_fifo_count;
    wire [$clog2(WR_FIFO_DEPTH):0] wr_fifo_drain_count;
    wire [$clog2(WR_FIFO_DEPTH):0] wr_fifo_fill_count;

    // FWFT (combinational) outputs for zero-latency reads
    wire [63:0] rd_fifo_fwft_dout;
    wire        rd_fifo_fwft_valid;
    wire [31:0] wr_fifo_fwft_dout;
    wire        wr_fifo_fwft_valid;

    // Total write beats = (byte_len / 8) blocks + 2 TAG beats (128-bit tag = 4 words = 2 beats)
    wire [28:0] total_wr_beats_w = byte_len[31:3] + 29'd2;

    // Read engine ↔ ctrl_fsm
    wire        rd_start_w;
    wire        rd_busy_w;
    wire        rd_done_w;
    wire        rd_error_w;
    wire [ADDR_WIDTH-1:0] rd_err_addr_w;

    // Write engine ↔ ctrl_fsm
    wire        wr_busy_w;
    wire        wr_done_w;
    wire        wr_error_w;
    wire [ADDR_WIDTH-1:0] wr_err_addr_w;

    // [FIX-RTL-1] dma_ctrl_fsm의 dma_error output을 캡처할 wire
    wire        dma_error_fsm_w;   // FSM internal error flag
    wire [0:0]  context_id_active_w;
    wire        payload_feed_pulse_w;
    wire        payload_chain_pulse_w;
    wire        write_chain_pulse_w;
    wire [31:0] dbg_cnt_rd_issue_w;
    wire [31:0] dbg_cnt_rd_done_w;
    wire [31:0] dbg_cnt_wr_done_w;
    wire [31:0] dbg_cnt_payload_feed_w;
    wire [31:0] dbg_cnt_payload_chain_w;
    wire [31:0] dbg_cnt_write_chain_w;
    wire [31:0] dbg_cnt_ingress_swap_w;
    wire [31:0] dbg_cnt_egress_swap_w;
    wire [31:0] dbg_cnt_busy_cycles_w;
    wire [31:0] dbg_cnt_core_wait_cycles_w;

    // ATU-translated addresses
    wire [ADDR_WIDTH-1:0] src_addr_atu;
    wire [ADDR_WIDTH-1:0] dst_addr_atu;
    wire [ADDR_WIDTH-1:0] ad_src_addr_atu;

    dma_err_latch #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_err_latch (
        .clk            (clk),
        .rst_n          (rst_n),
        .rd_error       (rd_error_w),
        .rd_err_addr    (rd_err_addr_w),
        .wr_error       (wr_error_w),
        .wr_err_addr    (wr_err_addr_w),
        .fsm_error      (dma_error_fsm_w),
        .dma_error      (dma_error),
        .dma_err_addr   (dma_err_addr),
        .status_rd_error(status_rd_error),
        .status_wr_error(status_wr_error)
    );

    // Internal wires for AD src address override to read engine (v2.0)
    wire [31:0]  rd_override_addr_w;
    wire         rd_use_override_w;
    wire [7:0]   rd_burst_len_w;       // [FIX-AD-BURST] per-phase ARLEN from FSM

    wire         coh_read_en  = coh_ctrl[0];
    wire         coh_write_en = coh_ctrl[1];

    wire                         rd_snoop_req_valid;
    wire [1:0]                   rd_snoop_req_cmd;
    wire [ADDR_WIDTH-1:0]        rd_snoop_req_addr;
    wire                         rd_snoop_req_ready;
    wire                         rd_snoop_resp_valid;
    wire                         rd_snoop_resp_hit;
    wire [127:0]                   rd_snoop_resp_data;

    wire                         wr_snoop_req_valid;
    wire [1:0]                   wr_snoop_req_cmd;
    wire [ADDR_WIDTH-1:0]        wr_snoop_req_addr;
    wire                         wr_snoop_req_ready;
    wire                         wr_snoop_resp_valid;
    wire                         wr_snoop_resp_hit;
    wire [127:0]                   wr_snoop_resp_data;

    dma_snoop_arb #(
        .ADDR_WIDTH       (ADDR_WIDTH),
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH),
        .SNOOP_DATA_WIDTH (128)
    ) u_snoop_arb (
        .clk            (clk),
        .rst_n          (rst_n),
        .dma_soft_rst   (dma_soft_rst),
        .rd_req_valid   (rd_snoop_req_valid),
        .rd_req_cmd     (rd_snoop_req_cmd),
        .rd_req_addr    (rd_snoop_req_addr),
        .rd_req_ready   (rd_snoop_req_ready),
        .rd_resp_valid  (rd_snoop_resp_valid),
        .rd_resp_hit    (rd_snoop_resp_hit),
        .rd_resp_data   (rd_snoop_resp_data),
        .wr_req_valid   (wr_snoop_req_valid),
        .wr_req_cmd     (wr_snoop_req_cmd),
        .wr_req_addr    (wr_snoop_req_addr),
        .wr_req_ready   (wr_snoop_req_ready),
        .wr_resp_valid  (wr_snoop_resp_valid),
        .wr_resp_hit    (wr_snoop_resp_hit),
        .wr_resp_data   (wr_snoop_resp_data),
        .DC_SNOOP_ADDR       (DC_SNOOP_ADDR),
        .DC_SNOOP_CMD        (DC_SNOOP_CMD),
        .DC_SNOOP_REQ_VALID  (DC_SNOOP_REQ_VALID),
        .DC_SNOOP_REQ_READY  (DC_SNOOP_REQ_READY),
        .DC_SNOOP_RESP_VALID (DC_SNOOP_RESP_VALID),
        .DC_SNOOP_RESP_HIT   (DC_SNOOP_RESP_HIT),
        .DC_SNOOP_RESP_DATA  (DC_SNOOP_RESP_DATA)
    );

    dma_atu #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_atu (
        .atu_base      (atu_base),
        .atu_window    (atu_window),
        .src_addr      (src_addr),
        .dst_addr      (dst_addr),
        .ad_src_addr   (ad_src_addr),
        .src_addr_atu  (src_addr_atu),
        .dst_addr_atu  (dst_addr_atu),
        .ad_src_addr_atu(ad_src_addr_atu)
    );

    dma_ingress_buffer_mgr #(
        .WIDTH (64),
        .DEPTH (RD_FIFO_DEPTH)
    ) u_ingress_buffer_mgr (
        .clk          (clk),
        .rst_n        (rst_n),
        .dma_start    (dma_start),
        .dma_soft_rst (dma_soft_rst),
        .push_data    (rd_fifo_din),
        .push_valid   (rd_fifo_push),
        .pop_ready    (rd_fifo_pop),
        .pop_data     (rd_fifo_fwft_dout),
        .pop_valid    (rd_fifo_fwft_valid),
        .pop_data_reg (rd_fifo_dout),
        .full         (rd_fifo_full),
        .empty        (rd_fifo_empty),
        .count        (rd_fifo_count),
        .drain_count  (rd_fifo_drain_count),
        .fill_count   (rd_fifo_fill_count),
        .drain_bank_ready(rd_buf_drain_ready),
        .fill_bank_ready (rd_buf_fill_ready),
        .swap_pulse   (rd_buf_swap_pulse),
        .active_bank  (rd_buf_active_bank),
        .fill_bank_sel(rd_buf_fill_bank)
    );

    dma_egress_buffer_mgr #(
        .WIDTH (32),
        .DEPTH (WR_FIFO_DEPTH)
    ) u_egress_buffer_mgr (
        .clk          (clk),
        .rst_n        (rst_n),
        .dma_start    (dma_start),
        .dma_soft_rst (dma_soft_rst),
        .push_data    (wr_fifo_din),
        .push_valid   (wr_fifo_push),
        .pop_ready    (wr_fifo_pop),
        .pop_data     (wr_fifo_fwft_dout),
        .pop_valid    (wr_fifo_fwft_valid),
        .pop_data_reg (wr_fifo_dout),
        .full         (wr_fifo_full),
        .empty        (wr_fifo_empty),
        .count        (wr_fifo_count),
        .drain_count  (wr_fifo_drain_count),
        .fill_count   (wr_fifo_fill_count),
        .drain_bank_ready(wr_buf_drain_ready),
        .fill_bank_ready (wr_buf_fill_ready),
        .swap_pulse   (wr_buf_swap_pulse),
        .active_bank  (wr_buf_active_bank),
        .fill_bank_sel(wr_buf_fill_bank)
    );

    // =========================================================================
    // DMA Control FSM
    // =========================================================================
    dma_ctrl_fsm #(
        .RD_FIFO_DEPTH       (RD_FIFO_DEPTH)
    ) u_ctrl_fsm (
        .clk                 (clk),
        .rst_n               (rst_n),
        .dma_start           (dma_start),
        .dma_soft_rst        (dma_soft_rst),
        .byte_len            (byte_len),
        .burst_len           (burst_len),
        // AD parameters (v2.0)
        .ad_src_addr         (ad_src_addr_atu),
        .ad_len              (ad_len),
        .context_id          (context_id),
        // Status
        .dma_busy            (dma_busy),
        .dma_done            (dma_done),
        .dma_error           (dma_error_fsm_w),
        // Read engine
        .rd_start            (rd_start_w),
        .rd_override_addr    (rd_override_addr_w),  // v2.0
        .rd_use_override     (rd_use_override_w),   // v2.0
        .rd_burst_len        (rd_burst_len_w),      // [FIX-AD-BURST]
        .rd_busy             (rd_busy_w),
        .rd_done             (rd_done_w),
        .rd_error            (rd_error_w),
        // RD FIFO (registered path)
        .rd_fifo_dout        (rd_fifo_dout),
        .rd_fifo_pop         (rd_fifo_pop),
        .rd_fifo_empty       (rd_fifo_empty),
        .rd_fifo_full        (rd_fifo_full),
        .rd_fifo_count       (rd_fifo_count),
        .rd_fifo_fill_count  (rd_fifo_fill_count),
        .rd_fifo_drain_count (rd_fifo_drain_count),
        .rd_buf_active_bank  (rd_buf_active_bank),
        .rd_buf_fill_bank    (rd_buf_fill_bank),
        .rd_buf_drain_ready  (rd_buf_drain_ready),
        .rd_buf_fill_ready   (rd_buf_fill_ready),
        // RD FIFO (FWFT path)
        .rd_fifo_fwft_dout   (rd_fifo_fwft_dout),
        .rd_fifo_fwft_valid  (rd_fifo_fwft_valid),
        // ascon_CORE — Payload
        .core_ptext_0        (core_ptext_0),
        .core_ptext_1        (core_ptext_1),
        .core_data_valid     (core_data_valid),
        .core_data_ready     (core_data_ready),
        .core_start          (core_start),
        .core_data_last      (core_data_last),
        .core_busy           (core_busy),
        .core_done           (core_done),
        .core_data_out_valid (core_data_out_valid),
        .core_tag_valid      (core_tag_valid),
        // ascon_CORE — AD (v2.0)
        .core_ad_in          (core_ad_in),
        .core_ad_valid       (core_ad_valid),
        .core_ad_last        (core_ad_last),
        .core_ad_ready       (core_ad_ready),
        // Results
        .core_ctext_0        (core_ctext_0),
        .core_ctext_1        (core_ctext_1),
        .core_tag_0          (core_tag_0),
        .core_tag_1          (core_tag_1),
        .core_tag_2          (core_tag_2),
        .core_tag_3          (core_tag_3),
        // WR FIFO
        .wr_fifo_din         (wr_fifo_din),
        .wr_fifo_push        (wr_fifo_push),
        .wr_fifo_full        (wr_fifo_full),
        // Write engine
        .wr_busy             (wr_busy_w),
        .wr_done             (wr_done_w),
        .wr_error            (wr_error_w),
        // Status bits
        .status_rd_done      (status_rd_done),
        .status_wr_done      (status_wr_done),
        .status_fifo_overflow(status_fifo_overflow),
        .context_id_active   (context_id_active_w),
        .payload_feed_pulse  (payload_feed_pulse_w),
        .payload_chain_pulse (payload_chain_pulse_w)
    );

    assign context_id_active = context_id_active_w;

    // =========================================================================
    // DMA Read Engine
    // =========================================================================
    // v2.0: read engine src_addr muxed between AD addr (override) and PT addr (default)
    wire [ADDR_WIDTH-1:0] rd_engine_src_addr = rd_use_override_w ? rd_override_addr_w : src_addr_atu;

    dma_read_engine #(
        .ADDR_WIDTH       (ADDR_WIDTH),
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH     (AXI_ID_WIDTH),
        .SNOOP_DATA_WIDTH (128),
        .RD_FIFO_DEPTH    (RD_FIFO_DEPTH)
    ) u_rd_engine (
        .clk            (clk),
        .rst_n          (rst_n),
        // Control — src_addr muxed for AD vs payload (v2.0)
        .src_addr       (rd_engine_src_addr),
        .burst_len      (rd_burst_len_w),     // [FIX-AD-BURST] per-phase ARLEN
        .dma_start      (dma_start),
        .rd_start       (rd_start_w),
        .rd_busy        (rd_busy_w),
        .rd_done        (rd_done_w),
        .rd_error       (rd_error_w),
        .rd_err_addr    (rd_err_addr_w),
        .coherent_read_en(coh_read_en),
        .snoop_req_valid (rd_snoop_req_valid),
        .snoop_req_cmd   (rd_snoop_req_cmd),
        .snoop_req_addr  (rd_snoop_req_addr),
        .snoop_req_ready (rd_snoop_req_ready),
        .snoop_resp_valid(rd_snoop_resp_valid),
        .snoop_resp_hit  (rd_snoop_resp_hit),
        .snoop_resp_data (rd_snoop_resp_data),
        // RD FIFO push
        .fifo_din       (rd_fifo_din),
        .fifo_push      (rd_fifo_push),
        .fifo_full      (rd_fifo_full),
        .fifo_fill_count(rd_fifo_fill_count),
        // AXI4 AR channel
        .M_AXI_ARID     (M_AXI_ARID),
        .M_AXI_ARADDR   (M_AXI_ARADDR),
        .M_AXI_ARLEN    (M_AXI_ARLEN),
        .M_AXI_ARSIZE   (M_AXI_ARSIZE),
        .M_AXI_ARBURST  (M_AXI_ARBURST),
        .M_AXI_ARCACHE  (M_AXI_ARCACHE),
        .M_AXI_ARPROT   (M_AXI_ARPROT),
        .M_AXI_ARVALID  (M_AXI_ARVALID),
        .M_AXI_ARREADY  (M_AXI_ARREADY),
        // AXI4 R channel
        .M_AXI_RID      (M_AXI_RID),
        .M_AXI_RDATA    (M_AXI_RDATA),
        .M_AXI_RRESP    (M_AXI_RRESP),
        .M_AXI_RLAST    (M_AXI_RLAST),
        .M_AXI_RVALID   (M_AXI_RVALID),
        .M_AXI_RREADY   (M_AXI_RREADY)
    );

    // =========================================================================
    // DMA Write Engine
    // =========================================================================
    dma_write_engine #(
        .ADDR_WIDTH       (ADDR_WIDTH),
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH     (AXI_ID_WIDTH),
        .SNOOP_DATA_WIDTH (128),
        .WR_FIFO_DEPTH    (WR_FIFO_DEPTH)
    ) u_wr_engine (
        .clk            (clk),
        .rst_n          (rst_n),
        .dst_addr       (dst_addr_atu),
        .dma_start      (dma_start),
        .total_wr_beats (total_wr_beats_w),
        .wr_busy        (wr_busy_w),
        .wr_done        (wr_done_w),
        .wr_error       (wr_error_w),
        .wr_err_addr    (wr_err_addr_w),
        .coherent_invalidate_en(coh_write_en),
        .snoop_req_valid (wr_snoop_req_valid),
        .snoop_req_cmd   (wr_snoop_req_cmd),
        .snoop_req_addr  (wr_snoop_req_addr),
        .snoop_req_ready (wr_snoop_req_ready),
        .snoop_resp_valid(wr_snoop_resp_valid),
        .snoop_resp_hit  (wr_snoop_resp_hit),
        .snoop_resp_data (wr_snoop_resp_data),
        // WR FIFO pop (registered path)
        .fifo_dout      (wr_fifo_dout),
        .fifo_pop       (wr_fifo_pop),
        .fifo_count     (wr_fifo_count),
        .fifo_drain_count(wr_fifo_drain_count),
        .fifo_fill_count (wr_fifo_fill_count),
        .fifo_active_bank(wr_buf_active_bank),
        .fifo_fill_bank_sel(wr_buf_fill_bank),
        .fifo_drain_bank_ready(wr_buf_drain_ready),
        .fifo_fill_bank_ready (wr_buf_fill_ready),
        .bench_chain_pulse(write_chain_pulse_w),
        // WR FIFO FWFT (combinational path)
        .fifo_fwft_dout (wr_fifo_fwft_dout),
        .fifo_fwft_valid(wr_fifo_fwft_valid),
        // AXI4 AW channel
        .M_AXI_AWID     (M_AXI_AWID),
        .M_AXI_AWADDR   (M_AXI_AWADDR),
        .M_AXI_AWLEN    (M_AXI_AWLEN),
        .M_AXI_AWSIZE   (M_AXI_AWSIZE),
        .M_AXI_AWBURST  (M_AXI_AWBURST),
        .M_AXI_AWCACHE  (M_AXI_AWCACHE),
        .M_AXI_AWPROT   (M_AXI_AWPROT),
        .M_AXI_AWVALID  (M_AXI_AWVALID),
        .M_AXI_AWREADY  (M_AXI_AWREADY),
        // AXI4 W channel
        .M_AXI_WDATA    (M_AXI_WDATA),
        .M_AXI_WSTRB    (M_AXI_WSTRB),
        .M_AXI_WLAST    (M_AXI_WLAST),
        .M_AXI_WVALID   (M_AXI_WVALID),
        .M_AXI_WREADY   (M_AXI_WREADY),
        // AXI4 B channel
        .M_AXI_BID      (M_AXI_BID),
        .M_AXI_BRESP    (M_AXI_BRESP),
        .M_AXI_BVALID   (M_AXI_BVALID),
        .M_AXI_BREADY   (M_AXI_BREADY)
    );

    dma_runtime_counters u_runtime_counters (
        .clk                 (clk),
        .rst_n               (rst_n),
        .dma_start           (dma_start),
        .dma_soft_rst        (dma_soft_rst),
        .dma_busy            (dma_busy),
        .rd_start_pulse      (rd_start_w),
        .rd_done_pulse       (rd_done_w),
        .wr_done_pulse       (wr_done_w),
        .payload_feed_pulse  (payload_feed_pulse_w),
        .payload_chain_pulse (payload_chain_pulse_w),
        .write_chain_pulse   (write_chain_pulse_w),
        .ingress_swap_pulse  (rd_buf_swap_pulse),
        .egress_swap_pulse   (wr_buf_swap_pulse),
        .core_data_valid     (core_data_valid),
        .core_data_out_valid (core_data_out_valid),
        .cnt_rd_issue        (dbg_cnt_rd_issue_w),
        .cnt_rd_done         (dbg_cnt_rd_done_w),
        .cnt_wr_done         (dbg_cnt_wr_done_w),
        .cnt_payload_feed    (dbg_cnt_payload_feed_w),
        .cnt_payload_chain   (dbg_cnt_payload_chain_w),
        .cnt_write_chain     (dbg_cnt_write_chain_w),
        .cnt_ingress_swap    (dbg_cnt_ingress_swap_w),
        .cnt_egress_swap     (dbg_cnt_egress_swap_w),
        .cnt_busy_cycles     (dbg_cnt_busy_cycles_w),
        .cnt_core_wait_cycles(dbg_cnt_core_wait_cycles_w)
    );

endmodule
