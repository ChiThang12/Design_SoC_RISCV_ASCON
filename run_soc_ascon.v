`timescale 1ns/1ps
`include "soc_top.v"

// ============================================================================
//  run_soc.v  --  Universal Debug Testbench  v4.1
//  Cập nhật signal paths cho soc_top (soc_top.v)
// ============================================================================
//
//  Thay đổi so với v4.0 gốc:
//    [1] DUT: riscv_ascon_soc_top_v3 -> soc_top
//    [2] Sửa tất cả instance paths cho đúng tên trong soc_top:
//          cpu core  : soc.cpu
//          icache    : soc.u_icache
//          dcache    : soc.u_dcache
//          crossbar  : soc.xbar
//          imem      : soc.imem
//          dmem      : soc.dmem
//          ascon     : soc.u_ascon_ip
//          wconv     : soc.u_wconv
//    [3] M0/M1/M2/S0-S3 taps: dùng alias wires trong soc_top
//          (soc.m0_*, soc.m1_*, soc.m2_*, soc.s0_*, ...)
//    [4] Sửa ascon path: soc.u_ascon_ip.u_slave.*
//    [5] Sửa dmem tap: soc.dmem.dmem.*
//    [6] Sửa lsu tap: soc.cpu.lsu_unit.*
//    [7] Sửa xbar tap: soc.xbar.*_slave_sel
//    [8] Thêm icache/dcache/dcache_writes từ soc port trực tiếp
// ============================================================================

// ── Tuning knobs ──────────────────────────────────────────────────────────────
`define LOG_LEVEL       2
`define TIMEOUT         200000      // tăng lên cho ASCON DMA (encrypt large buffer)
`define HALT_STABLE     60
`define DMEM_DUMP_BASE  32'h10000000
`define DMEM_DUMP_WORDS 32
`define DMEM_ROW_WORDS  4
// Ngưỡng loop detection — đủ lớn để không false-positive với poll loops
// (chờ DCache refill, chờ ASCON IRQ, chờ DMA done, v.v.)
`define MATCH2_THRESH   200
`define MATCH4_THRESH   200
// ─────────────────────────────────────────────────────────────────────────────

module run_soc;

// ============================================================================
// Clock & Reset
// ============================================================================
parameter CLK_PERIOD = 10;
reg clk, rst_n;
initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT — soc_top
// ============================================================================
wire [31:0] icache_hits, icache_misses;
wire [31:0] dcache_hits, dcache_misses, dcache_writes;
wire        ascon_irq;

soc_top soc (
    .clk           (clk),
    .rst_n         (rst_n),
    .icache_hits   (icache_hits),
    .icache_misses (icache_misses),
    .dcache_hits   (dcache_hits),
    .dcache_misses (dcache_misses),
    .dcache_writes (dcache_writes),
    .ascon_irq     (ascon_irq)
);

// ============================================================================
// SIGNAL TAPS
// ============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// [A] CPU Pipeline  — soc.cpu (instance name = 'cpu' trong soc_top)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] pc_if     = soc.cpu.pc_if;
wire [31:0] instr_if  = soc.cpu.instr_if;
wire        stall_if  = soc.cpu.stall_if;

// ─────────────────────────────────────────────────────────────────────────────
// [B] CPU <-> ICache  — wires trong soc_top
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] ic_cpu_addr  = soc.cpu_imem_addr;
wire        ic_cpu_req   = soc.cpu_imem_valid;
wire [31:0] ic_cpu_rdata = soc.cpu_imem_rdata;
wire        ic_cpu_ready = soc.cpu_imem_ready;

// ─────────────────────────────────────────────────────────────────────────────
// [C] CPU <-> DCache  — wires trong soc_top
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] dc_addr  = soc.cpu_dcache_addr;
wire [31:0] dc_wdata = soc.cpu_dcache_wdata;
wire [3:0]  dc_wstrb = soc.cpu_dcache_wstrb;
wire        dc_req   = soc.cpu_dcache_req;
wire        dc_we    = soc.cpu_dcache_we;
wire [31:0] dc_rdata = soc.cpu_dcache_rdata;
wire        dc_ready = soc.cpu_dcache_ready;

// ─────────────────────────────────────────────────────────────────────────────
// [D] M0 (ICache) -> Crossbar  — alias wires trong soc_top
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m0_arid    = soc.m0_arid;
wire [31:0] m0_araddr  = soc.m0_araddr;
wire [7:0]  m0_arlen   = soc.m0_arlen;
wire [2:0]  m0_arsize  = soc.m0_arsize;
wire [1:0]  m0_arburst = soc.m0_arburst;
wire        m0_arvalid = soc.m0_arvalid;
wire        m0_arready = soc.m0_arready;
wire [3:0]  m0_rid     = soc.m0_rid;
wire [31:0] m0_rdata   = soc.m0_rdata;
wire [1:0]  m0_rresp   = soc.m0_rresp;
wire        m0_rlast   = soc.m0_rlast;
wire        m0_rvalid  = soc.m0_rvalid;
wire        m0_rready  = soc.m0_rready;
wire        m0_awvalid = soc.m0_awvalid;
wire [31:0] m0_awaddr  = soc.m0_awaddr;
wire [1:0]  m0_bresp   = soc.m0_bresp;
wire        m0_bvalid  = soc.m0_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [E] M1 (DCache) -> Crossbar
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m1_arid    = soc.m1_arid;
wire [31:0] m1_araddr  = soc.m1_araddr;
wire [7:0]  m1_arlen   = soc.m1_arlen;
wire [2:0]  m1_arsize  = soc.m1_arsize;
wire [1:0]  m1_arburst = soc.m1_arburst;
wire        m1_arvalid = soc.m1_arvalid;
wire        m1_arready = soc.m1_arready;
wire [3:0]  m1_rid     = soc.m1_rid;
wire [31:0] m1_rdata   = soc.m1_rdata;
wire [1:0]  m1_rresp   = soc.m1_rresp;
wire        m1_rlast   = soc.m1_rlast;
wire        m1_rvalid  = soc.m1_rvalid;
wire        m1_rready  = soc.m1_rready;
wire [3:0]  m1_awid    = soc.m1_awid;
wire [31:0] m1_awaddr  = soc.m1_awaddr;
wire [7:0]  m1_awlen   = soc.m1_awlen;
wire [2:0]  m1_awsize  = soc.m1_awsize;
wire [1:0]  m1_awburst = soc.m1_awburst;
wire        m1_awvalid = soc.m1_awvalid;
wire        m1_awready = soc.m1_awready;
wire [31:0] m1_wdata   = soc.m1_wdata;
wire [3:0]  m1_wstrb   = soc.m1_wstrb;
wire        m1_wlast   = soc.m1_wlast;
wire        m1_wvalid  = soc.m1_wvalid;
wire        m1_wready  = soc.m1_wready;
wire [3:0]  m1_bid     = soc.m1_bid;
wire [1:0]  m1_bresp   = soc.m1_bresp;
wire        m1_bvalid  = soc.m1_bvalid;
wire        m1_bready  = soc.m1_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [F] M2 (ascon_dma / wconv output) -> Crossbar
//     Tap vào wconv_m_* alias trong soc_top (32-bit crossbar side)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m2_arid    = soc.m2_arid;
wire [31:0] m2_araddr  = soc.m2_araddr;
wire [7:0]  m2_arlen   = soc.m2_arlen;
wire [2:0]  m2_arsize  = soc.m2_arsize;
wire [1:0]  m2_arburst = soc.m2_arburst;
wire        m2_arvalid = soc.m2_arvalid;
wire        m2_arready = soc.m2_arready;
wire [3:0]  m2_rid     = soc.m2_rid;
wire [31:0] m2_rdata   = soc.m2_rdata;
wire [1:0]  m2_rresp   = soc.m2_rresp;
wire        m2_rlast   = soc.m2_rlast;
wire        m2_rvalid  = soc.m2_rvalid;
wire        m2_rready  = soc.m2_rready;
wire [3:0]  m2_awid    = soc.m2_awid;
wire [31:0] m2_awaddr  = soc.m2_awaddr;
wire [7:0]  m2_awlen   = soc.m2_awlen;
wire [2:0]  m2_awsize  = soc.m2_awsize;
wire [1:0]  m2_awburst = soc.m2_awburst;
wire        m2_awvalid = soc.m2_awvalid;
wire        m2_awready = soc.m2_awready;
wire [31:0] m2_wdata   = soc.m2_wdata;
wire [3:0]  m2_wstrb   = soc.m2_wstrb;
wire        m2_wlast   = soc.m2_wlast;
wire        m2_wvalid  = soc.m2_wvalid;
wire        m2_wready  = soc.m2_wready;
wire [3:0]  m2_bid     = soc.m2_bid;
wire [1:0]  m2_bresp   = soc.m2_bresp;
wire        m2_bvalid  = soc.m2_bvalid;
wire        m2_bready  = soc.m2_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [G] Crossbar -> S0 (IMEM)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  s0_arid    = soc.s0_arid;
wire [31:0] s0_araddr  = soc.s0_araddr;
wire [7:0]  s0_arlen   = soc.s0_arlen;
wire        s0_arvalid = soc.s0_arvalid;
wire        s0_arready = soc.s0_arready;
wire [3:0]  s0_rid     = soc.s0_rid;
wire [31:0] s0_rdata   = soc.s0_rdata;
wire [1:0]  s0_rresp   = soc.s0_rresp;
wire        s0_rlast   = soc.s0_rlast;
wire        s0_rvalid  = soc.s0_rvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [H] Crossbar -> S1 (DMEM)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  s1_arid    = soc.s1_arid_nc;
wire [31:0] s1_araddr  = soc.s1_araddr;
wire [7:0]  s1_arlen   = soc.s1_arlen;
wire        s1_arvalid = soc.s1_arvalid;
wire        s1_arready = soc.s1_arready;
wire [3:0]  s1_rid     = soc.s1_rid_nc;
wire [31:0] s1_rdata   = soc.s1_rdata;
wire [1:0]  s1_rresp   = soc.s1_rresp;
wire        s1_rlast   = soc.s1_rlast;
wire        s1_rvalid  = soc.s1_rvalid;
wire [3:0]  s1_awid    = soc.s1_awid_nc;
wire [31:0] s1_awaddr  = soc.s1_awaddr;
wire        s1_awvalid = soc.s1_awvalid;
wire        s1_awready = soc.s1_awready;
wire [31:0] s1_wdata   = soc.s1_wdata;
wire [3:0]  s1_wstrb   = soc.s1_wstrb;
wire        s1_wlast   = soc.s1_wlast;
wire        s1_wvalid  = soc.s1_wvalid;
wire        s1_wready  = soc.s1_wready;
wire [1:0]  s1_bresp   = soc.s1_bresp;
wire        s1_bvalid  = soc.s1_bvalid;
wire        s1_bready  = soc.s1_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [I] Crossbar -> S2 (ascon_ip_top) & S3 (SoC Ctrl)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s2_araddr  = soc.s2_araddr;
wire        s2_arvalid = soc.s2_arvalid;
wire [31:0] s2_awaddr  = soc.s2_awaddr;
wire        s2_awvalid = soc.s2_awvalid;
wire [31:0] s2_wdata   = soc.s2_wdata;
wire        s2_wvalid  = soc.s2_wvalid;
wire [1:0]  s2_rresp   = soc.s2_rresp;
wire [31:0] s2_rdata   = soc.s2_rdata;
wire        s2_rvalid  = soc.s2_rvalid;

wire [31:0] s3_araddr  = soc.s3_araddr;
wire        s3_arvalid = soc.s3_arvalid;
wire [31:0] s3_awaddr  = soc.s3_awaddr;
wire        s3_awvalid = soc.s3_awvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [J] Crossbar internal — address decode (3M x 4S)
//     Instance name: soc.xbar  (axi4_crossbar_3m4s)
// ─────────────────────────────────────────────────────────────────────────────
wire [2:0]  xbar_m0_ar_sel = soc.xbar.m0_ar_slave_sel;
wire [2:0]  xbar_m0_aw_sel = soc.xbar.m0_aw_slave_sel;
wire [2:0]  xbar_m1_ar_sel = soc.xbar.m1_ar_slave_sel;
wire [2:0]  xbar_m1_aw_sel = soc.xbar.m1_aw_slave_sel;
wire [2:0]  xbar_m2_ar_sel = soc.xbar.m2_ar_slave_sel;
wire [2:0]  xbar_m2_aw_sel = soc.xbar.m2_aw_slave_sel;

// ─────────────────────────────────────────────────────────────────────────────
// [K] Crossbar internal — arbitration FSM
// ─────────────────────────────────────────────────────────────────────────────
wire [1:0]  xbar_s0_rd_arb = soc.xbar.mux_s0.rd_arb;
wire [1:0]  xbar_s0_wr_arb = soc.xbar.mux_s0.wr_arb;
wire [1:0]  xbar_s1_rd_arb = soc.xbar.mux_s1.rd_arb;
wire [1:0]  xbar_s1_wr_arb = soc.xbar.mux_s1.wr_arb;
wire [1:0]  xbar_s2_rd_arb = soc.xbar.mux_s2.rd_arb;
wire [1:0]  xbar_s3_rd_arb = soc.xbar.mux_s3.rd_arb;

// ─────────────────────────────────────────────────────────────────────────────
// [L] DMEM write tap — soc.dmem (instance name = 'dmem' trong soc_top)
// ─────────────────────────────────────────────────────────────────────────────
wire        ram_wr_en   = soc.dmem.dmem.burst_wr_valid;
wire [31:0] ram_wr_addr = soc.dmem.dmem.wr_effective_addr;
wire [31:0] ram_wr_data = soc.dmem.dmem.burst_wr_data;
wire [3:0]  ram_wr_strb = soc.dmem.dmem.burst_wr_strb;

// ─────────────────────────────────────────────────────────────────────────────
// [M] LSU Store Buffer — soc.cpu.lsu_unit
// ─────────────────────────────────────────────────────────────────────────────
wire        lsu_sb_empty   = soc.cpu.lsu_unit.sb_empty;
wire [2:0]  lsu_sb_count   = soc.cpu.lsu_unit.sb_count[2:0];
wire        lsu_drain_idle = (soc.cpu.lsu_unit.drain_state == 1'b0);

// ─────────────────────────────────────────────────────────────────────────────
// [N] ASCON IP internal taps — soc.u_ascon_ip.u_slave.*
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] ascon_status_word = soc.u_ascon_ip.u_slave.status_word;
wire        ascon_core_busy   = soc.u_ascon_ip.u_slave.core_busy;
wire        ascon_core_done   = soc.u_ascon_ip.u_slave.core_done;
wire        ascon_dma_busy    = soc.u_ascon_ip.u_slave.dma_busy;
wire        ascon_dma_done_st = soc.u_ascon_ip.u_slave.status_dma_done;
wire        ascon_dma_error   = soc.u_ascon_ip.u_slave.status_dma_error;
wire        ascon_core_start  = soc.u_ascon_ip.u_slave.core_start;
wire        ascon_dma_start   = soc.u_ascon_ip.u_slave.dma_start;
wire        ascon_soft_rst    = soc.u_ascon_ip.u_slave.core_soft_rst;
wire [31:0] ascon_dma_src_r   = soc.u_ascon_ip.u_slave.reg_dma_src;
wire [31:0] ascon_dma_dst_r   = soc.u_ascon_ip.u_slave.reg_dma_dst;
wire [31:0] ascon_dma_len_r   = soc.u_ascon_ip.u_slave.reg_dma_len;
wire        ascon_reg_dma_en  = soc.u_ascon_ip.u_slave.reg_dma_en;

// ============================================================================
// Counters & State
// ============================================================================
integer cycle_count;
integer instr_retired;
integer stall_cycles;
integer flush_cycles;
integer dmem_rd_cnt;
integer dmem_wr_cnt;
integer post_halt_stores;
integer raw_hazard_cnt;
integer sb_cnt;
integer sb_errors;
integer cur_stall_run;
integer max_stall_run;

integer m0_ar_burst_cnt;
integer m1_ar_burst_cnt;
integer m1_aw_burst_cnt;
integer m2_ar_burst_cnt;
integer m2_aw_burst_cnt;

integer s0_ar_cnt;
integer s1_ar_cnt;
integer s1_aw_cnt;
integer s2_access_cnt;
integer s3_access_cnt;
integer decerr_cnt;
integer xbar_conflict_cnt;

integer ascon_start_cnt;
integer ascon_dma_start_cnt;
integer ascon_done_cnt;
integer ascon_dma_done_cnt;
integer ascon_irq_cnt;
integer ascon_error_cnt;

integer m0_ar_start;
integer m1_ar_start;
integer m1_aw_start;
integer m2_ar_start;
integer m2_aw_start;
integer m0_rd_lat_sum, m0_rd_lat_cnt;
integer m1_rd_lat_sum, m1_rd_lat_cnt;
integer m1_wr_lat_sum, m1_wr_lat_cnt;
integer m2_rd_lat_sum, m2_rd_lat_cnt;
integer m2_wr_lat_sum, m2_wr_lat_cnt;

reg [31:0] prev_pc;
integer    halt_cnt;
reg        program_done;

reg [31:0] pc_ring [0:7];
integer    ring_ptr;
integer    match2, match3, match4;

reg [31:0] sb_addr [0:255];
reg [31:0] sb_data [0:255];

// ============================================================================
// Waveform dump
// ============================================================================
initial begin
    $dumpfile("waveform_soc.vcd");
    $dumpvars(0, run_soc);
end

// ============================================================================
// (1) Cycle Counter
// ============================================================================
always @(posedge clk) begin
    if (rst_n) cycle_count = cycle_count + 1;
end

// ============================================================================
// (2) Instruction Retire & Stall
// ============================================================================
reg prev_stall;
always @(posedge clk) begin
    if (!rst_n) begin
        prev_stall <= 0;
    end else begin
        if (!stall_if && instr_if !== 32'h0)
            instr_retired = instr_retired + 1;

        if (stall_if) begin
            stall_cycles  = stall_cycles + 1;
            cur_stall_run = cur_stall_run + 1;
            if (cur_stall_run > max_stall_run) max_stall_run = cur_stall_run;
        end else begin
            cur_stall_run = 0;
        end

        if (`LOG_LEVEL >= 3 && instr_if !== 32'h0)
            $display("[%6d] PC=0x%08h  INSTR=0x%08h%s",
                     cycle_count, pc_if, instr_if,
                     stall_if ? "  [STALL]" : "");

        prev_stall <= stall_if;
    end
end

// ============================================================================
// (3) DCache Load/Store Logger
// ============================================================================
always @(posedge clk) begin
    if (rst_n && dc_req && dc_ready) begin
        if (dc_we) begin
            if (!program_done) begin
                dmem_wr_cnt = dmem_wr_cnt + 1;
                sb_update(dc_addr, dc_wdata, dc_wstrb);
                if (`LOG_LEVEL >= 2)
                    $display("[%6d] [ST] addr=0x%08h  data=0x%08h  strb=%b",
                             cycle_count, dc_addr, dc_wdata, dc_wstrb);
            end else begin
                post_halt_stores = post_halt_stores + 1;
            end
        end else begin
            dmem_rd_cnt = dmem_rd_cnt + 1;
            sb_check(dc_addr, dc_rdata);
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [LD] addr=0x%08h  data=0x%08h",
                         cycle_count, dc_addr, dc_rdata);
        end
    end
end

// ============================================================================
// (4) M0 (ICache) AXI Logger
// ============================================================================
reg [31:0] m0_ar_addr_lat;
always @(posedge clk) begin
    if (rst_n) begin
        if (m0_arvalid && m0_arready) begin
            m0_ar_burst_cnt = m0_ar_burst_cnt + 1;
            m0_ar_start     = cycle_count;
            m0_ar_addr_lat  <= m0_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M0-AR] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m0_araddr, m0_arlen,
                         xbar_m0_ar_sel, slave_name(xbar_m0_ar_sel));
            if (xbar_m0_ar_sel !== 3'd0 && `LOG_LEVEL >= 1)
                $display("[%6d] [WARN] M0(ICache) AR -> S%0d(%s) instead of S0!",
                         cycle_count, xbar_m0_ar_sel, slave_name(xbar_m0_ar_sel));
        end
        if (m0_rvalid && m0_rready) begin
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [M0-R ] data=0x%08h  rresp=%0d%s",
                         cycle_count, m0_rdata, m0_rresp,
                         m0_rlast ? "  [LAST]" : "");
            if (m0_rlast) begin
                m0_rd_lat_sum = m0_rd_lat_sum + (cycle_count - m0_ar_start + 1);
                m0_rd_lat_cnt = m0_rd_lat_cnt + 1;
            end
            if (m0_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M0 READ addr=0x%08h", cycle_count, m0_ar_addr_lat);
            end
        end
        if (m0_bvalid && m0_bresp == 2'b11) begin
            decerr_cnt = decerr_cnt + 1;
            $display("[%6d] [!!!] DECERR M0 WRITE addr=0x%08h (ICache should not write!)",
                     cycle_count, m0_awaddr);
        end
    end
end

// ============================================================================
// (5) M1 (DCache) AXI Logger
// ============================================================================
reg [31:0] m1_ar_addr_saved;
reg [31:0] m1_aw_addr_saved;
always @(posedge clk) begin
    if (rst_n) begin
        if (m1_arvalid && m1_arready) begin
            m1_ar_burst_cnt  = m1_ar_burst_cnt + 1;
            m1_ar_start      = cycle_count;
            m1_ar_addr_saved <= m1_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AR] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m1_araddr, m1_arlen,
                         xbar_m1_ar_sel, slave_name(xbar_m1_ar_sel));
            if (xbar_m1_ar_sel == 3'd0)
                $display("[%6d] [WARN] M1(DCache) AR -> S0(IMEM)! addr=0x%08h", cycle_count, m1_araddr);
        end
        if (m1_rvalid && m1_rready) begin
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [M1-R ] data=0x%08h  rresp=%0d%s",
                         cycle_count, m1_rdata, m1_rresp,
                         m1_rlast ? "  [LAST]" : "");
            if (m1_rlast) begin
                m1_rd_lat_sum = m1_rd_lat_sum + (cycle_count - m1_ar_start + 1);
                m1_rd_lat_cnt = m1_rd_lat_cnt + 1;
            end
            if (m1_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M1 READ addr=0x%08h", cycle_count, m1_ar_addr_saved);
            end
        end
        if (m1_awvalid && m1_awready) begin
            m1_aw_burst_cnt  = m1_aw_burst_cnt + 1;
            m1_aw_start      = cycle_count;
            m1_aw_addr_saved <= m1_awaddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AW] addr=0x%08h  -> S%0d(%s)",
                         cycle_count, m1_awaddr,
                         xbar_m1_aw_sel, slave_name(xbar_m1_aw_sel));
        end
        if (m1_wvalid && m1_wready && `LOG_LEVEL >= 3)
            $display("[%6d] [M1-W ] data=0x%08h  strb=%b%s",
                     cycle_count, m1_wdata, m1_wstrb,
                     m1_wlast ? "  [LAST]" : "");
        if (m1_bvalid && m1_bready) begin
            m1_wr_lat_sum = m1_wr_lat_sum + (cycle_count - m1_aw_start + 1);
            m1_wr_lat_cnt = m1_wr_lat_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-B ] bresp=%0d  lat=%0d cyc",
                         cycle_count, m1_bresp, cycle_count - m1_aw_start + 1);
            if (m1_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M1 WRITE addr=0x%08h", cycle_count, m1_awaddr);
            end
        end
    end
end

// ============================================================================
// (6) M2 (ascon_dma) AXI Logger
// ============================================================================
reg [31:0] m2_ar_addr_saved;
reg [31:0] m2_aw_addr_saved;
always @(posedge clk) begin
    if (rst_n) begin
        if (m2_arvalid && m2_arready) begin
            m2_ar_burst_cnt  = m2_ar_burst_cnt + 1;
            m2_ar_start      = cycle_count;
            m2_ar_addr_saved <= m2_araddr;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [M2-AR] ascon_dma FETCH  addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m2_araddr, m2_arlen,
                         xbar_m2_ar_sel, slave_name(xbar_m2_ar_sel));
            if (xbar_m2_ar_sel !== 3'd1)
                $display("[%6d] [WARN] M2(ascon_dma) AR -> S%0d (expected S1/DMEM)!",
                         cycle_count, xbar_m2_ar_sel);
        end
        if (m2_rvalid && m2_rready) begin
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M2-R ] data=0x%08h  rresp=%0d%s",
                         cycle_count, m2_rdata, m2_rresp,
                         m2_rlast ? "  [LAST]" : "");
            if (m2_rlast) begin
                m2_rd_lat_sum = m2_rd_lat_sum + (cycle_count - m2_ar_start + 1);
                m2_rd_lat_cnt = m2_rd_lat_cnt + 1;
            end
            if (m2_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M2 READ addr=0x%08h", cycle_count, m2_ar_addr_saved);
            end
        end
        if (m2_awvalid && m2_awready) begin
            m2_aw_burst_cnt  = m2_aw_burst_cnt + 1;
            m2_aw_start      = cycle_count;
            m2_aw_addr_saved <= m2_awaddr;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [M2-AW] ascon_dma STORE  addr=0x%08h  -> S%0d(%s)",
                         cycle_count, m2_awaddr,
                         xbar_m2_aw_sel, slave_name(xbar_m2_aw_sel));
            if (xbar_m2_aw_sel !== 3'd1)
                $display("[%6d] [WARN] M2(ascon_dma) AW -> S%0d (expected S1/DMEM)!",
                         cycle_count, xbar_m2_aw_sel);
        end
        if (m2_wvalid && m2_wready && `LOG_LEVEL >= 2)
            $display("[%6d] [M2-W ] data=0x%08h  strb=%b%s",
                     cycle_count, m2_wdata, m2_wstrb,
                     m2_wlast ? "  [LAST]" : "");
        if (m2_bvalid && m2_bready) begin
            m2_wr_lat_sum = m2_wr_lat_sum + (cycle_count - m2_aw_start + 1);
            m2_wr_lat_cnt = m2_wr_lat_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [M2-B ] ascon_dma WRITE done  bresp=%0d  lat=%0d cyc",
                         cycle_count, m2_bresp, cycle_count - m2_aw_start + 1);
            if (m2_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M2 WRITE addr=0x%08h", cycle_count, m2_awaddr);
            end
        end
    end
end

// ============================================================================
// (7) Per-Slave Traffic Counter + S2/S3 Alert
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        if (s0_arvalid && s0_arready) s0_ar_cnt = s0_ar_cnt + 1;
        if (s1_arvalid && s1_arready) s1_ar_cnt = s1_ar_cnt + 1;
        if (s1_awvalid && s1_awready) s1_aw_cnt = s1_aw_cnt + 1;

        if (s2_arvalid) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S2-ASCON] READ   addr=0x%08h  offset=0x%03h",
                         cycle_count, s2_araddr, s2_araddr[11:0]);
        end
        if (s2_awvalid) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S2-ASCON] WRITE  addr=0x%08h  offset=0x%03h  data=0x%08h",
                         cycle_count, s2_awaddr, s2_awaddr[11:0], s2_wdata);
        end

        if (s3_arvalid) begin
            s3_access_cnt = s3_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S3-SOCCTRL] READ  addr=0x%08h", cycle_count, s3_araddr);
        end
        if (s3_awvalid) begin
            s3_access_cnt = s3_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S3-SOCCTRL] WRITE addr=0x%08h", cycle_count, s3_awaddr);
        end
    end
end

// ============================================================================
// (8) ASCON IP Event Logger
// Dùng prev_* registers thay cho $past() (không hỗ trợ trong Verilog/Icarus)
// ============================================================================
reg prev_ascon_dma_done_st;
reg prev_ascon_core_done;
reg prev_ascon_dma_error;
reg prev_ascon_irq;

always @(posedge clk) begin
    if (!rst_n) begin
        prev_ascon_dma_done_st <= 1'b0;
        prev_ascon_core_done   <= 1'b0;
        prev_ascon_dma_error   <= 1'b0;
        prev_ascon_irq         <= 1'b0;
    end else begin
        prev_ascon_dma_done_st <= ascon_dma_done_st;
        prev_ascon_core_done   <= ascon_core_done;
        prev_ascon_dma_error   <= ascon_dma_error;
        prev_ascon_irq         <= ascon_irq;
    end
end

always @(posedge clk) begin
    if (rst_n) begin
        if (ascon_soft_rst)
            $display("[%6d] [ASCON] SOFT_RST asserted", cycle_count);

        if (ascon_core_start) begin
            ascon_start_cnt = ascon_start_cnt + 1;
            $display("[%6d] [ASCON] CORE START  #%0d  dma_en=%0d",
                     cycle_count, ascon_start_cnt, ascon_reg_dma_en);
        end

        if (ascon_dma_start) begin
            ascon_dma_start_cnt = ascon_dma_start_cnt + 1;
            $display("[%6d] [ASCON] DMA  START  #%0d  src=0x%08h  dst=0x%08h  len=%0d",
                     cycle_count, ascon_dma_start_cnt,
                     ascon_dma_src_r, ascon_dma_dst_r, ascon_dma_len_r);
        end

        // Rising edge detection thay cho $past()
        if (ascon_dma_done_st && !prev_ascon_dma_done_st) begin
            ascon_dma_done_cnt = ascon_dma_done_cnt + 1;
            $display("[%6d] [ASCON] DMA  DONE  #%0d  STATUS=0x%08h",
                     cycle_count, ascon_dma_done_cnt, ascon_status_word);
        end

        if (ascon_core_done && !prev_ascon_core_done) begin
            ascon_done_cnt = ascon_done_cnt + 1;
            $display("[%6d] [ASCON] CORE DONE  #%0d", cycle_count, ascon_done_cnt);
        end

        if (ascon_dma_error && !prev_ascon_dma_error) begin
            ascon_error_cnt = ascon_error_cnt + 1;
            $display("[%6d] [!!!]  ASCON DMA ERROR  STATUS=0x%08h",
                     cycle_count, ascon_status_word);
        end

        if (ascon_irq && !prev_ascon_irq) begin
            ascon_irq_cnt = ascon_irq_cnt + 1;
            $display("[%6d] [ASCON] IRQ raised  #%0d  STATUS=0x%08h",
                     cycle_count, ascon_irq_cnt, ascon_status_word);
        end
    end
end

// ============================================================================
// (9) Crossbar Arbitration Conflict Detector
// ============================================================================
always @(posedge clk) begin
    if (rst_n && `LOG_LEVEL >= 2) begin
        if (m0_arvalid && !m0_arready &&
            m1_arvalid && (xbar_m1_ar_sel == xbar_m0_ar_sel)) begin
            xbar_conflict_cnt = xbar_conflict_cnt + 1;
            $display("[%6d] [ARB] S%0d RD conflict: M0=0x%08h M1=0x%08h  M1 stalled",
                     cycle_count, xbar_m0_ar_sel, m0_araddr, m1_araddr);
        end
        if (m1_awvalid && !m1_awready) begin
            xbar_conflict_cnt = xbar_conflict_cnt + 1;
            $display("[%6d] [ARB] S1 WR stall: M1=0x%08h  arb=%0d",
                     cycle_count, m1_awaddr, xbar_s1_wr_arb);
        end
    end
end

// ============================================================================
// (10) Halt / Loop Detection
// ============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        halt_cnt <= 0; ring_ptr <= 0;
        match2 <= 0; match3 <= 0; match4 <= 0;
    end else if (cycle_count > 30) begin

        // HALT: PC không đổi VÀ không phải NOP VÀ không phải đang stall vì memory
        // Guard: nếu DCache đang miss hoặc LSU SB chưa drain → không count halt
        if (pc_if === prev_pc && instr_if !== 32'h00000013
            && !dc_req          // CPU không đang request memory
            && lsu_sb_empty) begin  // LSU store buffer đã drain
            halt_cnt <= halt_cnt + 1;
            if (halt_cnt >= `HALT_STABLE && !program_done) begin
                program_done = 1;
                print_report("HALT LOOP");
                #(CLK_PERIOD * 2);
                $finish;
            end
        end else begin
            halt_cnt <= 0;
        end

        if (pc_if === pc_ring[(ring_ptr + 6) % 8]) begin
            match2 = match2 + 1;
            if (match2 >= `MATCH2_THRESH && !program_done) begin
                program_done = 1;
                print_report("2-CYCLE LOOP");
                #(CLK_PERIOD * 2); $finish;
            end
        end else match2 = 0;

        if (pc_if === pc_ring[(ring_ptr + 4) % 8]) begin
            match4 = match4 + 1;
            if (match4 >= `MATCH4_THRESH && !program_done) begin
                program_done = 1;
                print_report("4-CYCLE LOOP");
                #(CLK_PERIOD * 2); $finish;
            end
        end else match4 = 0;

        pc_ring[ring_ptr] <= pc_if;
        ring_ptr <= (ring_ptr + 1) % 8;
        prev_pc  <= pc_if;
    end
end

// ============================================================================
// (11) Watchdog
// ============================================================================
initial begin
    #(CLK_PERIOD * `TIMEOUT);
    if (!program_done) begin
        program_done = 1;
        print_report("TIMEOUT");
    end
    $finish;
end

// ============================================================================
// Main Sequence
// ============================================================================
integer i;
initial begin
    cycle_count         = 0;   instr_retired      = 0;
    stall_cycles        = 0;   flush_cycles       = 0;
    dmem_rd_cnt         = 0;   dmem_wr_cnt        = 0;
    post_halt_stores    = 0;   raw_hazard_cnt     = 0;
    sb_cnt              = 0;   sb_errors          = 0;
    cur_stall_run       = 0;   max_stall_run      = 0;
    program_done        = 0;   prev_pc            = 0;
    halt_cnt            = 0;   ring_ptr           = 0;
    match2 = 0; match3 = 0; match4 = 0;
    m0_ar_burst_cnt     = 0;
    m1_ar_burst_cnt     = 0;   m1_aw_burst_cnt    = 0;
    m2_ar_burst_cnt     = 0;   m2_aw_burst_cnt    = 0;
    s0_ar_cnt           = 0;
    s1_ar_cnt           = 0;   s1_aw_cnt          = 0;
    s2_access_cnt       = 0;   s3_access_cnt      = 0;
    decerr_cnt          = 0;   xbar_conflict_cnt  = 0;
    m0_ar_start         = 0;
    m1_ar_start         = 0;   m1_aw_start        = 0;
    m2_ar_start         = 0;   m2_aw_start        = 0;
    m0_rd_lat_sum       = 0;   m0_rd_lat_cnt      = 0;
    m1_rd_lat_sum       = 0;   m1_rd_lat_cnt      = 0;
    m1_wr_lat_sum       = 0;   m1_wr_lat_cnt      = 0;
    m2_rd_lat_sum       = 0;   m2_rd_lat_cnt      = 0;
    m2_wr_lat_sum       = 0;   m2_wr_lat_cnt      = 0;
    ascon_start_cnt     = 0;   ascon_dma_start_cnt= 0;
    ascon_done_cnt      = 0;   ascon_dma_done_cnt = 0;
    ascon_irq_cnt       = 0;   ascon_error_cnt    = 0;

    for (i = 0; i < 256; i = i + 1) begin sb_addr[i] = 0; sb_data[i] = 0; end
    for (i = 0; i < 8;   i = i + 1) pc_ring[i] = 0;

    print_banner();

    rst_n = 0;
    repeat(12) @(posedge clk);
    rst_n = 1;
    repeat(5)  @(posedge clk);

    if (`LOG_LEVEL >= 1)
        $display("[%6d] Execution started\n", cycle_count);

    wait(program_done);
end

// ============================================================================
// SCOREBOARD TASKS
// ============================================================================
task sb_update;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    reg [31:0] al;
    integer    idx, found;
    reg [31:0] merged;
    begin
        al = {addr[31:2], 2'b00}; found = -1;
        for (idx = 0; idx < sb_cnt; idx = idx + 1)
            if (sb_addr[idx] === al) found = idx;
        merged = (found >= 0) ? sb_data[found] : 32'h0;
        if (strb[0]) merged[ 7: 0] = data[ 7: 0];
        if (strb[1]) merged[15: 8] = data[15: 8];
        if (strb[2]) merged[23:16] = data[23:16];
        if (strb[3]) merged[31:24] = data[31:24];
        if (found >= 0) sb_data[found] = merged;
        else if (sb_cnt < 256) begin
            sb_addr[sb_cnt] = al; sb_data[sb_cnt] = merged;
            sb_cnt = sb_cnt + 1;
        end
    end
endtask

task sb_check;
    input [31:0] addr;
    input [31:0] got;
    reg [31:0] al;
    integer idx;
    begin
        al = {addr[31:2], 2'b00};
        for (idx = 0; idx < sb_cnt; idx = idx + 1)
            if (sb_addr[idx] === al && sb_data[idx] !== got) begin
                sb_errors = sb_errors + 1;
                $display("[%6d] [ERR-RAW] addr=0x%08h  exp=0x%08h  got=0x%08h",
                         cycle_count, al, sb_data[idx], got);
            end
    end
endtask

// ============================================================================
// PRINT TASKS
// ============================================================================

task print_banner;
    begin
        $display("");
        $display("+=================================================================+");
        $display("|   RISC-V SoC  +  ASCON IP  --  Debug Testbench  v4.1           |");
        $display("|   ICache | DCache | AXI4 Crossbar 3Mx4S | ascon_ip_top | 100MHz|");
        $display("+-----------------------------------------------------------------+");
        $display("|   Masters:  M0=ICache  M1=DCache  M2=ascon_dma (via wconv)     |");
        $display("|   Address Map:                                                  |");
        $display("|     S0  IMEM     0x0000_0000 - 0x0000_FFFF  (64 KB)            |");
        $display("|     S1  DMEM     0x1000_0000 - 0x1000_FFFF  (64 KB)            |");
        $display("|     S2  ASCON    0x2000_0000 - 0x2000_0FFF  ( 4 KB)            |");
        $display("|     S3  SoCCtrl  0x3000_0000 - 0x3000_0FFF  ( 4 KB)            |");
        $display("+-----------------------------------------------------------------+");
        $display("|   Width Converter: ASCON M_AXI 64-bit -> Crossbar M2 32-bit    |");
        $display("+-----------------------------------------------------------------+");
        $display("|   LOG_LEVEL=%0d   TIMEOUT=%0d cyc   HALT_STABLE=%0d cyc        |",
                 `LOG_LEVEL, `TIMEOUT, `HALT_STABLE);
        $display("+=================================================================+");
        $display("");
    end
endtask

task print_report;
    input [127:0] reason;
    integer j, k, nz;
    real cpi, ipc, eff, ic_rate, dc_rate;
    integer ic_total, dc_total;
    reg [31:0] ret, wv;
    begin
        ret = soc.cpu.register_file.registers[10];

        $display("");
        $display("+=================================================================+");
        $display("|  STOP: %-57s|", reason);
        $display("+=================================================================+");

        $display("");
        $display("+--- (1) PROGRAM RESULT -----------------------------------------+");
        $display("|  a0 (x10) = 0x%08h  =  %0d  (signed: %0d)",
                 ret, ret, $signed(ret));
        $display("|  Binary   = %032b", ret);
        if (ret === 32'h0)
            $display("|  RESULT OK  (a0 == 0)");
        else
            $display("|  a0 != 0 -- kiem tra firmware");
        $display("|  Final PC = 0x%08h", pc_if);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (2) PERFORMANCE --------------------------------------------+");
        if (instr_retired > 0) begin
            cpi = cycle_count * 1.0 / instr_retired;
            ipc = instr_retired * 1.0 / cycle_count;
            eff = ipc * 100.0;
            $display("|  Cycles        : %0d", cycle_count);
            $display("|  Instructions  : %0d", instr_retired);
            $display("|  CPI           : %.3f  (ideal = 1.000)", cpi);
            $display("|  IPC           : %.3f", ipc);
            $display("|  Pipeline eff  : %.1f%%", eff);
            $display("|  Stall cycles  : %0d  (%.1f%%)",
                     stall_cycles, stall_cycles * 100.0 / cycle_count);
            $display("|  Max stall run : %0d cycles", max_stall_run);
            if      (eff >= 90.0) $display("|  Rating : ***** EXCELLENT  (>=90%%)");
            else if (eff >= 75.0) $display("|  Rating : ****  GOOD       (>=75%%)");
            else if (eff >= 55.0) $display("|  Rating : ***   FAIR       (>=55%%)");
            else                  $display("|  Rating : **    NEEDS WORK (<55%%)");
        end else
            $display("|  No instructions retired.");
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (3) CACHE STATISTICS ---------------------------------------+");
        ic_total = icache_hits + icache_misses;
        dc_total = dcache_hits + dcache_misses;
        ic_rate  = (ic_total > 0) ? icache_hits * 100.0 / ic_total : 0.0;
        dc_rate  = (dc_total > 0) ? dcache_hits * 100.0 / dc_total : 0.0;
        $display("|  ICache : hits=%-6d  misses=%-6d  hit%%=%.1f%%",
                 icache_hits, icache_misses, ic_rate);
        $display("|  DCache : hits=%-6d  misses=%-6d  hit%%=%.1f%%  writes=%0d",
                 dcache_hits, dcache_misses, dc_rate, dcache_writes);
        if (m0_rd_lat_cnt > 0)
            $display("|  ICache refill avg lat : %.1f cyc  (%0d bursts)",
                     m0_rd_lat_sum * 1.0 / m0_rd_lat_cnt, m0_rd_lat_cnt);
        if (m1_rd_lat_cnt > 0)
            $display("|  DCache refill avg lat : %.1f cyc  (%0d bursts)",
                     m1_rd_lat_sum * 1.0 / m1_rd_lat_cnt, m1_rd_lat_cnt);
        if (m1_wr_lat_cnt > 0)
            $display("|  DCache write avg lat  : %.1f cyc  (%0d bursts)",
                     m1_wr_lat_sum * 1.0 / m1_wr_lat_cnt, m1_wr_lat_cnt);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (4) AXI4 CROSSBAR TRAFFIC (3M x 4S) -----------------------+");
        $display("|  Master 0 (ICache)    :  AR bursts = %0d", m0_ar_burst_cnt);
        $display("|  Master 1 (DCache)    :  AR bursts = %0d   AW bursts = %0d",
                 m1_ar_burst_cnt, m1_aw_burst_cnt);
        $display("|  Master 2 (ascon_dma) :  AR bursts = %0d   AW bursts = %0d",
                 m2_ar_burst_cnt, m2_aw_burst_cnt);
        if (m2_rd_lat_cnt > 0)
            $display("|    DMA fetch avg lat : %.1f cyc  (%0d bursts)",
                     m2_rd_lat_sum * 1.0 / m2_rd_lat_cnt, m2_rd_lat_cnt);
        if (m2_wr_lat_cnt > 0)
            $display("|    DMA store avg lat : %.1f cyc  (%0d bursts)",
                     m2_wr_lat_sum * 1.0 / m2_wr_lat_cnt, m2_wr_lat_cnt);
        $display("|  Slave 0  IMEM        :  AR = %0d", s0_ar_cnt);
        $display("|  Slave 1  DMEM        :  AR = %0d   AW = %0d", s1_ar_cnt, s1_aw_cnt);
        $display("|  Slave 2  ASCON       :  accesses = %0d", s2_access_cnt);
        $display("|  Slave 3  SoC Ctrl    :  accesses = %0d", s3_access_cnt);
        $display("|  Arb conflicts        :  %0d", xbar_conflict_cnt);
        if (decerr_cnt > 0)
            $display("|  [!!!] DECERR count   :  %0d  <- unmapped address!", decerr_cnt);
        else
            $display("|  DECERR count         :  0  (OK)");
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (5) ASCON IP SUMMARY ---------------------------------------+");
        $display("|  core_start  pulses  : %0d", ascon_start_cnt);
        $display("|  dma_start   pulses  : %0d", ascon_dma_start_cnt);
        $display("|  core_done   events  : %0d", ascon_done_cnt);
        $display("|  dma_done    events  : %0d", ascon_dma_done_cnt);
        $display("|  irq         events  : %0d", ascon_irq_cnt);
        $display("|  dma_error   events  : %0d  %s",
                 ascon_error_cnt, ascon_error_cnt == 0 ? "(OK)" : "[!!!] CHECK DMA");
        $display("|  DMA config at halt  : src=0x%08h  dst=0x%08h  len=%0d",
                 ascon_dma_src_r, ascon_dma_dst_r, ascon_dma_len_r);
        $display("|  STATUS at halt      : 0x%08h", ascon_status_word);
        $display("|    core_busy=%0d  core_done=%0d  dma_busy=%0d  dma_done=%0d  err=%0d",
                 ascon_core_busy, ascon_core_done, ascon_dma_busy,
                 ascon_dma_done_st, ascon_dma_error);
        if (ascon_dma_done_cnt > 0)
            $display("|  [OK] DMA encryption completed successfully");
        else if (ascon_error_cnt > 0)
            $display("|  [!!!] DMA error occurred -- check M2 routing and DMEM address");
        else
            $display("|  [?] DMA did not complete -- check CTRL.START and DMA_EN");
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (6) MEMORY ACCESS SUMMARY ----------------------------------+");
        $display("|  CPU Loads           : %0d", dmem_rd_cnt);
        $display("|  CPU Stores          : %0d", dmem_wr_cnt);
        $display("|  Post-halt SB drain  : %0d stores", post_halt_stores);
        $display("|  RAW hazard errors   : %0d  %s",
                 sb_errors, sb_errors == 0 ? "(OK)" : "[!!!] DATA ERRORS");
        $display("|  LSU SB remaining    : %0d entries at halt", lsu_sb_count);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (7) REGISTER FILE ------------------------------------------+");
        $display("|  Reg   ABI     Hex          Decimal (signed)");
        $display("|  -----------------------------------------");
        nz = 0;
        for (j = 0; j < 32; j = j + 1) begin
            wv = soc.cpu.register_file.registers[j];
            if (wv !== 32'h0 || j == 2 || j == 10) begin
                nz = nz + 1;
                $display("|  x%-2d  %-5s   0x%08h   %0d",
                         j, abi_name(j), wv, $signed(wv));
            end
        end
        if (nz == 0) $display("|  (all zero)");
        $display("+----------------------------------------------------------------+");

        print_dmem_snapshot();

        $display("");
        $display("+--- (9) STORE SCOREBOARD (%0d entries, %0d errors) ---------------+",
                 sb_cnt, sb_errors);
        k = 0;
        for (j = 0; j < sb_cnt && j < 48; j = j + 1) begin
            if (sb_data[j] !== 32'h0) begin
                $display("|  [0x%08h] = 0x%08h  (%0d)",
                         sb_addr[j], sb_data[j], sb_data[j]);
                k = k + 1;
            end
        end
        if (k == 0) $display("|  (no non-zero stores recorded)");
        if (sb_cnt > 48) $display("|  ... (%0d more entries)", sb_cnt - 48);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("=================================================================");
        $display("  SoC + ASCON IP done.  %0d cycles @ 100 MHz = %.2f us",
                 cycle_count, cycle_count * 10.0 / 1000.0);
        $display("=================================================================");
        $display("");
    end
endtask

task print_dmem_snapshot;
    integer wi, col, j;
    reg [31:0] base, addr, wval;
    reg        found;
    reg [31:0] word_addr;
    reg [7:0]  byte_val;
    reg [1:0]  byte_off;
    integer    k;
    begin
        base = `DMEM_DUMP_BASE;
        $display("");
        $display("+--- (8) DMEM SNAPSHOT [0x%08h..0x%08h] (%0d words) -----------+",
                 base, base + `DMEM_DUMP_WORDS * 4 - 1, `DMEM_DUMP_WORDS);
        $display("|  Address       +0          +4          +8          +C");
        $display("|  ---------------------------------------------------------");

        for (wi = 0; wi < `DMEM_DUMP_WORDS; wi = wi + `DMEM_ROW_WORDS) begin
            addr = base + wi * 4;
            $write("|  0x%08h  ", addr);
            for (col = 0; col < `DMEM_ROW_WORDS; col = col + 1) begin
                wval = 32'h0; found = 0;
                for (j = 0; j < sb_cnt; j = j + 1) begin
                    if (sb_addr[j] === (base + (wi + col) * 4)) begin
                        wval  = sb_data[j];
                        found = 1;
                    end
                end
                $write("0x%08h  ", wval);
            end
            $display("");
        end

        $display("|");
        $display("|  ASCII view (from scoreboard):");
        $write("|  ");
        for (wi = 0; wi < `DMEM_DUMP_WORDS * 4; wi = wi + 1) begin
            word_addr = base + (wi / 4) * 4;
            byte_off  = wi[1:0];
            byte_val  = 8'h2E;
            for (k = 0; k < sb_cnt; k = k + 1) begin
                if (sb_addr[k] === word_addr) begin
                    case (byte_off)
                        2'd0: byte_val = sb_data[k][ 7: 0];
                        2'd1: byte_val = sb_data[k][15: 8];
                        2'd2: byte_val = sb_data[k][23:16];
                        2'd3: byte_val = sb_data[k][31:24];
                    endcase
                end
            end
            if (byte_val >= 8'h20 && byte_val <= 8'h7E) $write("%s", byte_val);
            else                                          $write(".");
            if ((wi & 15) == 15 && wi < `DMEM_DUMP_WORDS*4-1) begin
                $display(""); $write("|  ");
            end
        end
        $display("");
        $display("+----------------------------------------------------------------+");
    end
endtask

function [63:0] slave_name;
    input [2:0] sel;
    begin
        case (sel)
            3'd0:    slave_name = "IMEM    ";
            3'd1:    slave_name = "DMEM    ";
            3'd2:    slave_name = "ASCON   ";
            3'd3:    slave_name = "SoCCtrl ";
            default: slave_name = "DECERR  ";
        endcase
    end
endfunction

function [39:0] abi_name;
    input integer r;
    begin
        case (r)
            0:  abi_name = "zero ";   1:  abi_name = "ra   ";
            2:  abi_name = "sp   ";   3:  abi_name = "gp   ";
            4:  abi_name = "tp   ";   5:  abi_name = "t0   ";
            6:  abi_name = "t1   ";   7:  abi_name = "t2   ";
            8:  abi_name = "s0/fp";   9:  abi_name = "s1   ";
            10: abi_name = "a0   ";   11: abi_name = "a1   ";
            12: abi_name = "a2   ";   13: abi_name = "a3   ";
            14: abi_name = "a4   ";   15: abi_name = "a5   ";
            16: abi_name = "a6   ";   17: abi_name = "a7   ";
            18: abi_name = "s2   ";   19: abi_name = "s3   ";
            20: abi_name = "s4   ";   21: abi_name = "s5   ";
            22: abi_name = "s6   ";   23: abi_name = "s7   ";
            24: abi_name = "s8   ";   25: abi_name = "s9   ";
            26: abi_name = "s10  ";   27: abi_name = "s11  ";
            28: abi_name = "t3   ";   29: abi_name = "t4   ";
            30: abi_name = "t5   ";   31: abi_name = "t6   ";
            default: abi_name = "???  ";
        endcase
    end
endfunction

endmodule