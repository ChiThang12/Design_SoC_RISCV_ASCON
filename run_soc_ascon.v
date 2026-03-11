`timescale 1ns/1ps
`include "soc_top.v"

// ============================================================================
//  run_soc.v  —  Universal Debug Testbench  v5.0
//  Cập nhật hoàn toàn cho soc_top.v (3M x 5S: IMEM/DMEM/ASCON/SoCCtrl/CLINT)
//
//  Thay đổi so với v4.1:
//    [1]  DUT port: ext_rst_n, soft_rst_pulse (không có stat ports — lấy qua hier)
//    [2]  Instance names đúng với soc_top.v:
//           CPU      : soc.u_cpu
//           ICache   : soc.u_icache
//           DCache   : soc.u_dcache
//           Crossbar : soc.u_crossbar
//           IMEM     : soc.u_imem
//           DMEM     : soc.u_dmem
//           ASCON    : soc.u_ascon
//           WConv    : soc.u_width_conv
//           CLINT    : soc.u_clint
//           SoCCtrl  : soc.u_soc_ctrl
//    [3]  Wire names đúng với soc_top.v internal wires:
//           icache_imem_rdata / icache_imem_ready (không phải cpu_imem_rdata)
//           dcache_cpu_rdata  / dcache_cpu_ready
//    [4]  Thêm S4 (CLINT) taps: mtime, timer_irq, sw_irq
//    [5]  Thêm SoC Ctrl taps: irq_out, soft_rst_pulse
//    [6]  Thêm CLINT internal: mtime_lo/hi, mtimecmp_lo/hi, msip
//    [7]  Thêm DMA 64-bit raw wires (trước width converter)
//    [8]  Thêm prescaler tap: mtime_tick
//    [9]  slave_name cập nhật đủ 5 slave + DECERR
//    [10] Halt guard: dùng đúng wire names
// ============================================================================

// ── Tuning knobs ──────────────────────────────────────────────────────────────
`define LOG_LEVEL       2
`define TIMEOUT         200000
`define HALT_STABLE     60
`define DMEM_DUMP_BASE  32'h10000000
`define DMEM_DUMP_WORDS 32
`define DMEM_ROW_WORDS  4
`define MATCH2_THRESH   200
`define MATCH4_THRESH   200
// ─────────────────────────────────────────────────────────────────────────────

module run_soc;

// ============================================================================
// Clock & Reset
// ============================================================================
parameter CLK_PERIOD = 10;   // 100 MHz
reg clk, rst_n_r;
initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT — soc_top
// soc_top chỉ có: clk, ext_rst_n, soft_rst_pulse
// Statistics và signals khác lấy qua hierarchical reference
// ============================================================================
wire soft_rst_pulse;

soc_top soc (
    .clk           (clk),
    .ext_rst_n     (rst_n_r),
    .soft_rst_pulse(soft_rst_pulse)
);

// ============================================================================
// SIGNAL TAPS — lấy trực tiếp từ soc_top internal wires/instances
// ============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// [A] CPU Pipeline  (instance: soc.u_cpu)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] pc_if     = soc.u_cpu.pc_if;
wire [31:0] instr_if  = soc.u_cpu.instr_if;
wire        stall_if  = soc.u_cpu.stall_if;

// ─────────────────────────────────────────────────────────────────────────────
// [B] CPU ↔ ICache  (internal wires của soc_top)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] ic_cpu_addr  = soc.cpu_imem_addr;
wire        ic_cpu_req   = soc.cpu_imem_valid;
wire [31:0] ic_cpu_rdata = soc.icache_imem_rdata;   // tên đúng trong soc_top
wire        ic_cpu_ready = soc.icache_imem_ready;   // tên đúng trong soc_top

// ─────────────────────────────────────────────────────────────────────────────
// [C] CPU ↔ DCache  (internal wires của soc_top)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] dc_addr  = soc.cpu_dcache_addr;
wire [31:0] dc_wdata = soc.cpu_dcache_wdata;
wire [3:0]  dc_wstrb = soc.cpu_dcache_wstrb;
wire        dc_req   = soc.cpu_dcache_req;
wire        dc_we    = soc.cpu_dcache_we;
wire [31:0] dc_rdata = soc.dcache_cpu_rdata;        // tên đúng trong soc_top
wire        dc_ready = soc.dcache_cpu_ready;        // tên đúng trong soc_top

// ─────────────────────────────────────────────────────────────────────────────
// [D] M0 (ICache) → Crossbar  (soc_top wires: m0_*)
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
// [E] M1 (DCache) → Crossbar  (soc_top wires: m1_*)
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
// [F] M2 (DMA via width converter) → Crossbar  (soc_top wires: m2_*)
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
// [G] DMA raw 64-bit wires (ASCON M_AXI trước width converter)
//     Dùng để debug width converter và DMA burst
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  dma_awid    = soc.dma_awid;
wire [31:0] dma_awaddr  = soc.dma_awaddr;
wire [7:0]  dma_awlen   = soc.dma_awlen;
wire        dma_awvalid = soc.dma_awvalid;
wire        dma_awready = soc.dma_awready;
wire [63:0] dma_wdata   = soc.dma_wdata;
wire [7:0]  dma_wstrb   = soc.dma_wstrb;
wire        dma_wlast   = soc.dma_wlast;
wire        dma_wvalid  = soc.dma_wvalid;
wire        dma_wready  = soc.dma_wready;
wire [1:0]  dma_bresp   = soc.dma_bresp;
wire        dma_bvalid  = soc.dma_bvalid;
wire [3:0]  dma_arid    = soc.dma_arid;
wire [31:0] dma_araddr  = soc.dma_araddr;
wire [7:0]  dma_arlen   = soc.dma_arlen;
wire        dma_arvalid = soc.dma_arvalid;
wire        dma_arready = soc.dma_arready;
wire [63:0] dma_rdata   = soc.dma_rdata;
wire [1:0]  dma_rresp   = soc.dma_rresp;
wire        dma_rlast   = soc.dma_rlast;
wire        dma_rvalid  = soc.dma_rvalid;
wire        dma_rready  = soc.dma_rready;

// ─────────────────────────────────────────────────────────────────────────────
// [H] Crossbar → S0 (IMEM)
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
wire        s0_rready  = soc.s0_rready;

// ─────────────────────────────────────────────────────────────────────────────
// [I] Crossbar → S1 (DMEM)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  s1_arid    = soc.s1_arid;
wire [31:0] s1_araddr  = soc.s1_araddr;
wire [7:0]  s1_arlen   = soc.s1_arlen;
wire        s1_arvalid = soc.s1_arvalid;
wire        s1_arready = soc.s1_arready;
wire [3:0]  s1_rid     = soc.s1_rid;
wire [31:0] s1_rdata   = soc.s1_rdata;
wire [1:0]  s1_rresp   = soc.s1_rresp;
wire        s1_rlast   = soc.s1_rlast;
wire        s1_rvalid  = soc.s1_rvalid;
wire        s1_rready  = soc.s1_rready;
wire [3:0]  s1_awid    = soc.s1_awid;
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
// [J] Crossbar → S2 (ASCON slave)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s2_araddr  = soc.s2_araddr;
wire        s2_arvalid = soc.s2_arvalid;
wire        s2_arready = soc.s2_arready;
wire [31:0] s2_rdata   = soc.s2_rdata;
wire [1:0]  s2_rresp   = soc.s2_rresp;
wire        s2_rvalid  = soc.s2_rvalid;
wire [31:0] s2_awaddr  = soc.s2_awaddr;
wire        s2_awvalid = soc.s2_awvalid;
wire        s2_awready = soc.s2_awready;
wire [31:0] s2_wdata   = soc.s2_wdata;
wire        s2_wvalid  = soc.s2_wvalid;
wire [1:0]  s2_bresp   = soc.s2_bresp;
wire        s2_bvalid  = soc.s2_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [K] Crossbar → S3 (SoC Ctrl)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s3_araddr  = soc.s3_araddr;
wire        s3_arvalid = soc.s3_arvalid;
wire [31:0] s3_awaddr  = soc.s3_awaddr;
wire        s3_awvalid = soc.s3_awvalid;
wire [31:0] s3_wdata   = soc.s3_wdata;
wire        s3_wvalid  = soc.s3_wvalid;
wire [31:0] s3_rdata   = soc.s3_rdata;
wire        s3_rvalid  = soc.s3_rvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [L] Crossbar → S4 (CLINT)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s4_araddr  = soc.s4_araddr;
wire        s4_arvalid = soc.s4_arvalid;
wire [31:0] s4_awaddr  = soc.s4_awaddr;
wire        s4_awvalid = soc.s4_awvalid;
wire [31:0] s4_wdata   = soc.s4_wdata;
wire        s4_wvalid  = soc.s4_wvalid;
wire [31:0] s4_rdata   = soc.s4_rdata;
wire        s4_rvalid  = soc.s4_rvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [M] CLINT internal — mtime, mtimecmp, msip, IRQ outputs
//     (instance: soc.u_clint)
// ─────────────────────────────────────────────────────────────────────────────
wire        mtime_tick   = soc.mtime_tick;          // prescaler output
wire        timer_irq    = soc.timer_irq;           // clint → cpu
wire        sw_irq       = soc.sw_irq;              // clint → cpu
wire        ext_irq      = soc.external_irq;        // soc_ctrl → cpu

// CLINT register internals (nếu clint expose ra)
wire [31:0] clint_mtime_lo    = soc.u_clint.S_AXI_ARADDR; // placeholder — đổi nếu clint expose
wire        clint_timer_out   = soc.u_clint.timer_irq;
wire        clint_sw_out      = soc.u_clint.sw_irq;

// ─────────────────────────────────────────────────────────────────────────────
// [N] SoC Ctrl internal — irq_out, soft_rst_pulse, status
//     (instance: soc.u_soc_ctrl)
// ─────────────────────────────────────────────────────────────────────────────
wire        soc_ctrl_irq_out     = soc.u_soc_ctrl.irq_out;
wire        soc_ctrl_soft_rst    = soc.u_soc_ctrl.soft_rst_pulse;
// Statistics wires từ soc_top
wire [31:0] icache_stat_hits     = soc.icache_stat_hits;
wire [31:0] icache_stat_misses   = soc.icache_stat_misses;
wire [31:0] dcache_stat_hits     = soc.dcache_stat_hits;
wire [31:0] dcache_stat_misses   = soc.dcache_stat_misses;
wire [31:0] dcache_stat_writes   = soc.dcache_stat_writes;

// ─────────────────────────────────────────────────────────────────────────────
// [O] ASCON IP internal  (instance: soc.u_ascon)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] ascon_status_word  = soc.u_ascon.u_slave.status_word;
wire        ascon_core_busy    = soc.u_ascon.u_slave.core_busy;
wire        ascon_core_done    = soc.u_ascon.u_slave.core_done;
wire        ascon_dma_busy     = soc.u_ascon.u_slave.dma_busy;
wire        ascon_dma_done_st  = soc.u_ascon.u_slave.status_dma_done;
wire        ascon_dma_error    = soc.u_ascon.u_slave.status_dma_error;
wire        ascon_core_start   = soc.u_ascon.u_slave.core_start;
wire        ascon_dma_start    = soc.u_ascon.u_slave.dma_start;
wire        ascon_soft_rst     = soc.u_ascon.u_slave.core_soft_rst;
wire [31:0] ascon_dma_src_r    = soc.u_ascon.u_slave.reg_dma_src;
wire [31:0] ascon_dma_dst_r    = soc.u_ascon.u_slave.reg_dma_dst;
wire [31:0] ascon_dma_len_r    = soc.u_ascon.u_slave.reg_dma_len;
wire        ascon_reg_dma_en   = soc.u_ascon.u_slave.reg_dma_en;
wire        ascon_irq_wire     = soc.ascon_irq;     // wire trong soc_top

// ─────────────────────────────────────────────────────────────────────────────
// [P] LSU Store Buffer  (instance: soc.u_cpu)
// ─────────────────────────────────────────────────────────────────────────────
wire        lsu_sb_empty   = soc.u_cpu.lsu_unit.sb_empty;
wire [2:0]  lsu_sb_count   = soc.u_cpu.lsu_unit.sb_count[2:0];
wire        lsu_drain_idle = (soc.u_cpu.lsu_unit.drain_state == 1'b0);

// ─────────────────────────────────────────────────────────────────────────────
// [Q] DMEM write tap  (instance: soc.u_dmem)
// ─────────────────────────────────────────────────────────────────────────────
wire        ram_wr_en   = soc.u_dmem.dmem.burst_wr_valid;
wire [31:0] ram_wr_addr = soc.u_dmem.dmem.wr_effective_addr;
wire [31:0] ram_wr_data = soc.u_dmem.dmem.burst_wr_data;
wire [3:0]  ram_wr_strb = soc.u_dmem.dmem.burst_wr_strb;

// ============================================================================
// Counters & State
// ============================================================================
integer cycle_count;
integer instr_retired;
integer stall_cycles;
integer dmem_rd_cnt;
integer dmem_wr_cnt;
integer post_halt_stores;
integer sb_errors;
integer cur_stall_run;
integer max_stall_run;

integer m0_ar_burst_cnt;
integer m1_ar_burst_cnt, m1_aw_burst_cnt;
integer m2_ar_burst_cnt, m2_aw_burst_cnt;
integer dma_raw_ar_cnt,  dma_raw_aw_cnt;   // 64-bit side của width conv

integer s0_ar_cnt;
integer s1_ar_cnt, s1_aw_cnt;
integer s2_access_cnt;
integer s3_access_cnt;
integer s4_access_cnt;                     // CLINT accesses
integer decerr_cnt;
integer xbar_conflict_cnt;

integer ascon_start_cnt;
integer ascon_dma_start_cnt;
integer ascon_done_cnt;
integer ascon_dma_done_cnt;
integer ascon_irq_cnt;
integer ascon_error_cnt;

integer clint_timer_irq_cnt;              // lần timer_irq được raise
integer clint_sw_irq_cnt;                 // lần sw_irq được raise
integer soft_rst_cnt;                     // lần soft_rst_pulse

integer m0_ar_start;
integer m1_ar_start, m1_aw_start;
integer m2_ar_start, m2_aw_start;
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
integer    match2, match4;

reg [31:0] sb_addr [0:255];
reg [31:0] sb_data [0:255];
integer    sb_cnt;

// Edge detection registers
reg prev_ascon_dma_done_st;
reg prev_ascon_core_done;
reg prev_ascon_dma_error;
reg prev_ascon_irq;
reg prev_timer_irq;
reg prev_sw_irq;
reg prev_soft_rst;

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
    if (rst_n_r) cycle_count = cycle_count + 1;
end

// ============================================================================
// (2) Instruction Retire & Stall
// ============================================================================
always @(posedge clk) begin
    if (rst_n_r) begin
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
    end
end

// ============================================================================
// (3) DCache Load/Store Logger + Scoreboard
// ============================================================================
always @(posedge clk) begin
    if (rst_n_r && dc_req && dc_ready) begin
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
reg [31:0] m0_ar_addr_saved;
always @(posedge clk) begin
    if (rst_n_r) begin
        if (m0_arvalid && m0_arready) begin
            m0_ar_burst_cnt = m0_ar_burst_cnt + 1;
            m0_ar_start     = cycle_count;
            m0_ar_addr_saved <= m0_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M0-AR] addr=0x%08h  len=%0d  size=%0d",
                         cycle_count, m0_araddr, m0_arlen, m0_arsize);
            if (m0_araddr[31:16] !== 16'h0000 && `LOG_LEVEL >= 1)
                $display("[%6d] [WARN] M0(ICache) AR outside IMEM range! addr=0x%08h",
                         cycle_count, m0_araddr);
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
                $display("[%6d] [!!!] DECERR M0 READ addr=0x%08h", cycle_count, m0_ar_addr_saved);
            end
        end
        // ICache không nên ghi — cảnh báo nếu thấy
        if (m0_awvalid && `LOG_LEVEL >= 1)
            $display("[%6d] [WARN] M0(ICache) AW asserted! addr=0x%08h  (ICache should NOT write)",
                     cycle_count, m0_awaddr);
        if (m0_bvalid && m0_bresp == 2'b11) begin
            decerr_cnt = decerr_cnt + 1;
            $display("[%6d] [!!!] DECERR M0 WRITE addr=0x%08h", cycle_count, m0_awaddr);
        end
    end
end

// ============================================================================
// (5) M1 (DCache) AXI Logger
// ============================================================================
reg [31:0] m1_ar_addr_saved;
reg [31:0] m1_aw_addr_saved;
always @(posedge clk) begin
    if (rst_n_r) begin
        if (m1_arvalid && m1_arready) begin
            m1_ar_burst_cnt  = m1_ar_burst_cnt + 1;
            m1_ar_start      = cycle_count;
            m1_ar_addr_saved <= m1_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AR] addr=0x%08h  len=%0d  size=%0d  -> %s",
                         cycle_count, m1_araddr, m1_arlen, m1_arsize,
                         slave_name_of_addr(m1_araddr));
            if (m1_araddr[31:16] == 16'h0000 && `LOG_LEVEL >= 1)
                $display("[%6d] [WARN] M1(DCache) AR -> IMEM range! addr=0x%08h",
                         cycle_count, m1_araddr);
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
                $display("[%6d] [M1-AW] addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m1_awaddr, m1_awlen,
                         slave_name_of_addr(m1_awaddr));
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
                $display("[%6d] [!!!] DECERR M1 WRITE addr=0x%08h", cycle_count, m1_aw_addr_saved);
            end
        end
    end
end

// ============================================================================
// (6) M2 (DMA 32-bit / width converter output) AXI Logger
// ============================================================================
reg [31:0] m2_ar_addr_saved;
reg [31:0] m2_aw_addr_saved;
always @(posedge clk) begin
    if (rst_n_r) begin
        if (m2_arvalid && m2_arready) begin
            m2_ar_burst_cnt  = m2_ar_burst_cnt + 1;
            m2_ar_start      = cycle_count;
            m2_ar_addr_saved <= m2_araddr;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [M2-AR] DMA FETCH  addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m2_araddr, m2_arlen,
                         slave_name_of_addr(m2_araddr));
            if (m2_araddr[31:16] !== 16'h1000 && `LOG_LEVEL >= 1)
                $display("[%6d] [WARN] M2(DMA) AR outside DMEM range! addr=0x%08h",
                         cycle_count, m2_araddr);
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
                $display("[%6d] [M2-AW] DMA STORE  addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m2_awaddr, m2_awlen,
                         slave_name_of_addr(m2_awaddr));
            if (m2_awaddr[31:16] !== 16'h1000 && `LOG_LEVEL >= 1)
                $display("[%6d] [WARN] M2(DMA) AW outside DMEM range! addr=0x%08h",
                         cycle_count, m2_awaddr);
        end
        if (m2_wvalid && m2_wready && `LOG_LEVEL >= 2)
            $display("[%6d] [M2-W ] data=0x%08h  strb=%b%s",
                     cycle_count, m2_wdata, m2_wstrb,
                     m2_wlast ? "  [LAST]" : "");
        if (m2_bvalid && m2_bready) begin
            m2_wr_lat_sum = m2_wr_lat_sum + (cycle_count - m2_aw_start + 1);
            m2_wr_lat_cnt = m2_wr_lat_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [M2-B ] DMA WRITE done  bresp=%0d  lat=%0d cyc",
                         cycle_count, m2_bresp, cycle_count - m2_aw_start + 1);
            if (m2_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M2 WRITE addr=0x%08h", cycle_count, m2_aw_addr_saved);
            end
        end
    end
end

// ============================================================================
// (7) DMA 64-bit raw side logger (trước width converter)
//     Dùng để debug width converter hoạt động đúng không
// ============================================================================
always @(posedge clk) begin
    if (rst_n_r) begin
        if (dma_arvalid && dma_arready) begin
            dma_raw_ar_cnt = dma_raw_ar_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [DMA64-AR] addr=0x%08h  len=%0d  (64-bit side)",
                         cycle_count, dma_araddr, dma_arlen);
        end
        if (dma_awvalid && dma_awready) begin
            dma_raw_aw_cnt = dma_raw_aw_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [DMA64-AW] addr=0x%08h  len=%0d  (64-bit side)",
                         cycle_count, dma_awaddr, dma_awlen);
        end
        if (dma_rvalid && dma_rready && `LOG_LEVEL >= 3)
            $display("[%6d] [DMA64-R ] data=0x%016h  rresp=%0d%s",
                     cycle_count, dma_rdata, dma_rresp,
                     dma_rlast ? "  [LAST]" : "");
        if (dma_wvalid && dma_wready && `LOG_LEVEL >= 3)
            $display("[%6d] [DMA64-W ] data=0x%016h  strb=%b%s",
                     cycle_count, dma_wdata, dma_wstrb,
                     dma_wlast ? "  [LAST]" : "");
    end
end

// ============================================================================
// (8) Per-Slave Traffic Counter
// ============================================================================
always @(posedge clk) begin
    if (rst_n_r) begin
        if (s0_arvalid && s0_arready) s0_ar_cnt = s0_ar_cnt + 1;
        if (s1_arvalid && s1_arready) s1_ar_cnt = s1_ar_cnt + 1;
        if (s1_awvalid && s1_awready) s1_aw_cnt = s1_aw_cnt + 1;

        if (s2_arvalid) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S2-ASCON] READ   offset=0x%03h",
                         cycle_count, s2_araddr[11:0]);
        end
        if (s2_awvalid) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S2-ASCON] WRITE  offset=0x%03h  data=0x%08h",
                         cycle_count, s2_awaddr[11:0], s2_wdata);
        end
        if (s3_arvalid) begin
            s3_access_cnt = s3_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S3-SOCCTRL] READ  addr=0x%08h", cycle_count, s3_araddr);
        end
        if (s3_awvalid) begin
            s3_access_cnt = s3_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S3-SOCCTRL] WRITE addr=0x%08h  data=0x%08h",
                         cycle_count, s3_awaddr, s3_wdata);
        end
        if (s4_arvalid) begin
            s4_access_cnt = s4_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S4-CLINT] READ  addr=0x%08h  offset=0x%05h",
                         cycle_count, s4_araddr, s4_araddr[19:0]);
        end
        if (s4_awvalid) begin
            s4_access_cnt = s4_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S4-CLINT] WRITE addr=0x%08h  offset=0x%05h  data=0x%08h",
                         cycle_count, s4_awaddr, s4_awaddr[19:0], s4_wdata);
        end
    end
end

// ============================================================================
// (9) ASCON IP Event Logger
// ============================================================================
always @(posedge clk) begin
    if (!rst_n_r) begin
        prev_ascon_dma_done_st <= 1'b0;
        prev_ascon_core_done   <= 1'b0;
        prev_ascon_dma_error   <= 1'b0;
        prev_ascon_irq         <= 1'b0;
    end else begin
        prev_ascon_dma_done_st <= ascon_dma_done_st;
        prev_ascon_core_done   <= ascon_core_done;
        prev_ascon_dma_error   <= ascon_dma_error;
        prev_ascon_irq         <= ascon_irq_wire;
    end
end

always @(posedge clk) begin
    if (rst_n_r) begin
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

        if (ascon_dma_done_st && !prev_ascon_dma_done_st) begin
            ascon_dma_done_cnt = ascon_dma_done_cnt + 1;
            $display("[%6d] [ASCON] DMA  DONE  #%0d  STATUS=0x%08h",
                     cycle_count, ascon_dma_done_cnt, ascon_status_word);
        end

        if (ascon_core_done && !prev_ascon_core_done) begin
            ascon_done_cnt = ascon_done_cnt + 1;
            $display("[%6d] [ASCON] CORE DONE  #%0d  STATUS=0x%08h",
                     cycle_count, ascon_done_cnt, ascon_status_word);
        end

        if (ascon_dma_error && !prev_ascon_dma_error) begin
            ascon_error_cnt = ascon_error_cnt + 1;
            $display("[%6d] [!!!]  ASCON DMA ERROR  STATUS=0x%08h",
                     cycle_count, ascon_status_word);
        end

        if (ascon_irq_wire && !prev_ascon_irq) begin
            ascon_irq_cnt = ascon_irq_cnt + 1;
            $display("[%6d] [ASCON] IRQ raised  #%0d  STATUS=0x%08h",
                     cycle_count, ascon_irq_cnt, ascon_status_word);
        end
    end
end

// ============================================================================
// (10) CLINT & Interrupt Event Logger
// ============================================================================
always @(posedge clk) begin
    if (!rst_n_r) begin
        prev_timer_irq <= 1'b0;
        prev_sw_irq    <= 1'b0;
        prev_soft_rst  <= 1'b0;
    end else begin
        prev_timer_irq <= timer_irq;
        prev_sw_irq    <= sw_irq;
        prev_soft_rst  <= soft_rst_pulse;
    end
end

always @(posedge clk) begin
    if (rst_n_r) begin
        if (timer_irq && !prev_timer_irq) begin
            clint_timer_irq_cnt = clint_timer_irq_cnt + 1;
            $display("[%6d] [CLINT] TIMER_IRQ raised  #%0d",
                     cycle_count, clint_timer_irq_cnt);
        end
        if (sw_irq && !prev_sw_irq) begin
            clint_sw_irq_cnt = clint_sw_irq_cnt + 1;
            $display("[%6d] [CLINT] SW_IRQ raised  #%0d",
                     cycle_count, clint_sw_irq_cnt);
        end
        if (soft_rst_pulse && !prev_soft_rst) begin
            soft_rst_cnt = soft_rst_cnt + 1;
            $display("[%6d] [SOCCTRL] SOFT_RST_PULSE asserted  #%0d",
                     cycle_count, soft_rst_cnt);
        end
        if (ext_irq && `LOG_LEVEL >= 2)
            $display("[%6d] [IRQ] external_irq HIGH (ascon IRQ → CPU)",
                     cycle_count);
    end
end

// ============================================================================
// (11) Halt / Loop Detection
// ============================================================================
always @(posedge clk) begin
    if (!rst_n_r) begin
        halt_cnt <= 0; ring_ptr <= 0;
        match2 <= 0; match4 <= 0;
    end else if (cycle_count > 30) begin

        // HALT: PC không đổi, không phải NOP, CPU không đang wait memory
        if (pc_if === prev_pc
            && instr_if !== 32'h00000013    // không phải NOP
            && !dc_req                       // DCache không pending
            && lsu_sb_empty) begin           // LSU SB đã drain
            halt_cnt <= halt_cnt + 1;
            if (halt_cnt >= `HALT_STABLE && !program_done) begin
                program_done = 1;
                print_report("HALT LOOP DETECTED");
                #(CLK_PERIOD * 2);
                $finish;
            end
        end else begin
            halt_cnt <= 0;
        end

        // 2-cycle loop detection
        if (pc_if === pc_ring[(ring_ptr + 6) % 8]) begin
            match2 = match2 + 1;
            if (match2 >= `MATCH2_THRESH && !program_done) begin
                program_done = 1;
                print_report("2-CYCLE LOOP DETECTED");
                #(CLK_PERIOD * 2); $finish;
            end
        end else match2 = 0;

        // 4-cycle loop detection
        if (pc_if === pc_ring[(ring_ptr + 4) % 8]) begin
            match4 = match4 + 1;
            if (match4 >= `MATCH4_THRESH && !program_done) begin
                program_done = 1;
                print_report("4-CYCLE LOOP DETECTED");
                #(CLK_PERIOD * 2); $finish;
            end
        end else match4 = 0;

        pc_ring[ring_ptr] <= pc_if;
        ring_ptr <= (ring_ptr + 1) % 8;
        prev_pc  <= pc_if;
    end
end

// ============================================================================
// (12) Watchdog
// ============================================================================
initial begin
    #(CLK_PERIOD * `TIMEOUT);
    if (!program_done) begin
        program_done = 1;
        print_report("WATCHDOG TIMEOUT");
    end
    $finish;
end

// ============================================================================
// Main Sequence
// ============================================================================
integer i;
initial begin
    // Init tất cả counters
    cycle_count          = 0;   instr_retired       = 0;
    stall_cycles         = 0;   dmem_rd_cnt         = 0;
    dmem_wr_cnt          = 0;   post_halt_stores     = 0;
    sb_errors            = 0;   sb_cnt              = 0;
    cur_stall_run        = 0;   max_stall_run       = 0;
    program_done         = 0;   prev_pc             = 0;
    halt_cnt             = 0;   ring_ptr            = 0;
    match2 = 0; match4 = 0;
    m0_ar_burst_cnt      = 0;
    m1_ar_burst_cnt      = 0;   m1_aw_burst_cnt     = 0;
    m2_ar_burst_cnt      = 0;   m2_aw_burst_cnt     = 0;
    dma_raw_ar_cnt       = 0;   dma_raw_aw_cnt      = 0;
    s0_ar_cnt            = 0;
    s1_ar_cnt            = 0;   s1_aw_cnt           = 0;
    s2_access_cnt        = 0;   s3_access_cnt       = 0;
    s4_access_cnt        = 0;
    decerr_cnt           = 0;   xbar_conflict_cnt   = 0;
    m0_ar_start          = 0;
    m1_ar_start          = 0;   m1_aw_start         = 0;
    m2_ar_start          = 0;   m2_aw_start         = 0;
    m0_rd_lat_sum        = 0;   m0_rd_lat_cnt       = 0;
    m1_rd_lat_sum        = 0;   m1_rd_lat_cnt       = 0;
    m1_wr_lat_sum        = 0;   m1_wr_lat_cnt       = 0;
    m2_rd_lat_sum        = 0;   m2_rd_lat_cnt       = 0;
    m2_wr_lat_sum        = 0;   m2_wr_lat_cnt       = 0;
    ascon_start_cnt      = 0;   ascon_dma_start_cnt = 0;
    ascon_done_cnt       = 0;   ascon_dma_done_cnt  = 0;
    ascon_irq_cnt        = 0;   ascon_error_cnt     = 0;
    clint_timer_irq_cnt  = 0;   clint_sw_irq_cnt    = 0;
    soft_rst_cnt         = 0;

    for (i = 0; i < 256; i = i + 1) begin sb_addr[i] = 0; sb_data[i] = 0; end
    for (i = 0; i < 8;   i = i + 1) pc_ring[i] = 0;

    print_banner();

    rst_n_r = 0;
    repeat(12) @(posedge clk);
    rst_n_r = 1;
    repeat(5)  @(posedge clk);

    if (`LOG_LEVEL >= 1)
        $display("[%6d] Reset released — Execution started\n", cycle_count);

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
// HELPER FUNCTIONS
// ============================================================================
function [63:0] slave_name_of_addr;
    input [31:0] addr;
    begin
        if      (addr[31:16] == 16'h0000)            slave_name_of_addr = "IMEM    ";
        else if (addr[31:16] == 16'h1000)            slave_name_of_addr = "DMEM    ";
        else if (addr[31:12] == 20'h20000)           slave_name_of_addr = "ASCON   ";
        else if (addr[31:12] == 20'h30000)           slave_name_of_addr = "SoCCtrl ";
        else if (addr[31:16] == 16'h4000)            slave_name_of_addr = "CLINT   ";
        else                                         slave_name_of_addr = "DECERR! ";
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

// ============================================================================
// PRINT REPORT
// ============================================================================
task print_report;
    input [127:0] reason;
    integer j, k, nz;
    real cpi, ipc, eff, ic_rate, dc_rate;
    integer ic_total, dc_total;
    reg [31:0] ret, wv;
    begin
        ret = soc.u_cpu.register_file.registers[10];

        $display("");
        $display("+=================================================================+");
        $display("|  STOP: %-57s|", reason);
        $display("+=================================================================+");

        // ── (1) Result ───────────────────────────────────────────────────────
        $display("");
        $display("+--- (1) PROGRAM RESULT -----------------------------------------+");
        $display("|  a0 (x10) = 0x%08h  =  %0d  (signed: %0d)",
                 ret, ret, $signed(ret));
        $display("|  Binary   = %032b", ret);
        if (ret === 32'h0)
            $display("|  [OK]  a0 == 0");
        else
            $display("|  [!!]  a0 != 0  -- firmware may have set error code");
        $display("|  Final PC = 0x%08h", pc_if);
        $display("+----------------------------------------------------------------+");

        // ── (2) Performance ──────────────────────────────────────────────────
        $display("");
        $display("+--- (2) PERFORMANCE --------------------------------------------+");
        if (instr_retired > 0) begin
            cpi = cycle_count * 1.0 / instr_retired;
            ipc = instr_retired * 1.0 / cycle_count;
            eff = ipc * 100.0;
            $display("|  Cycles           : %0d", cycle_count);
            $display("|  Instructions     : %0d", instr_retired);
            $display("|  CPI              : %.3f  (ideal = 1.000)", cpi);
            $display("|  IPC              : %.3f", ipc);
            $display("|  Pipeline eff     : %.1f%%", eff);
            $display("|  Stall cycles     : %0d  (%.1f%%)",
                     stall_cycles, stall_cycles * 100.0 / cycle_count);
            $display("|  Max stall run    : %0d cycles", max_stall_run);
            $display("|  Time @ 100 MHz   : %.2f us", cycle_count * 10.0 / 1000.0);
            if      (eff >= 90.0) $display("|  Rating : ***** EXCELLENT  (>=90%%)");
            else if (eff >= 75.0) $display("|  Rating : ****  GOOD       (>=75%%)");
            else if (eff >= 55.0) $display("|  Rating : ***   FAIR       (>=55%%)");
            else                  $display("|  Rating : **    NEEDS WORK (<55%%)");
        end else
            $display("|  No instructions retired.");
        $display("+----------------------------------------------------------------+");

        // ── (3) Cache Statistics ─────────────────────────────────────────────
        $display("");
        $display("+--- (3) CACHE STATISTICS ---------------------------------------+");
        ic_total = icache_stat_hits + icache_stat_misses;
        dc_total = dcache_stat_hits + dcache_stat_misses;
        ic_rate  = (ic_total > 0) ? icache_stat_hits * 100.0 / ic_total : 0.0;
        dc_rate  = (dc_total > 0) ? dcache_stat_hits * 100.0 / dc_total : 0.0;
        $display("|  ICache : hits=%-6d  misses=%-6d  total=%-6d  hit%%=%.1f%%",
                 icache_stat_hits, icache_stat_misses, ic_total, ic_rate);
        $display("|  DCache : hits=%-6d  misses=%-6d  total=%-6d  hit%%=%.1f%%  writes=%0d",
                 dcache_stat_hits, dcache_stat_misses, dc_total, dc_rate, dcache_stat_writes);
        if (m0_rd_lat_cnt > 0)
            $display("|  ICache refill avg lat : %.1f cyc  (%0d bursts)",
                     m0_rd_lat_sum * 1.0 / m0_rd_lat_cnt, m0_rd_lat_cnt);
        if (m1_rd_lat_cnt > 0)
            $display("|  DCache refill avg lat : %.1f cyc  (%0d bursts)",
                     m1_rd_lat_sum * 1.0 / m1_rd_lat_cnt, m1_rd_lat_cnt);
        if (m1_wr_lat_cnt > 0)
            $display("|  DCache write  avg lat : %.1f cyc  (%0d bursts)",
                     m1_wr_lat_sum * 1.0 / m1_wr_lat_cnt, m1_wr_lat_cnt);
        $display("+----------------------------------------------------------------+");

        // ── (4) AXI Crossbar Traffic ─────────────────────────────────────────
        $display("");
        $display("+--- (4) AXI4 CROSSBAR TRAFFIC  (3M x 5S) ----------------------+");
        $display("|  Master 0 (ICache)       :  AR=%0d", m0_ar_burst_cnt);
        $display("|  Master 1 (DCache)       :  AR=%0d   AW=%0d",
                 m1_ar_burst_cnt, m1_aw_burst_cnt);
        $display("|  Master 2 (DMA 32-bit)   :  AR=%0d   AW=%0d",
                 m2_ar_burst_cnt, m2_aw_burst_cnt);
        $display("|  DMA raw  (64-bit side)  :  AR=%0d   AW=%0d  (width conv input)",
                 dma_raw_ar_cnt, dma_raw_aw_cnt);
        if (m2_rd_lat_cnt > 0)
            $display("|    DMA fetch avg lat : %.1f cyc  (%0d bursts)",
                     m2_rd_lat_sum * 1.0 / m2_rd_lat_cnt, m2_rd_lat_cnt);
        if (m2_wr_lat_cnt > 0)
            $display("|    DMA store avg lat : %.1f cyc  (%0d bursts)",
                     m2_wr_lat_sum * 1.0 / m2_wr_lat_cnt, m2_wr_lat_cnt);
        $display("|  ─────────────────────────────────────────────────────────── |");
        $display("|  S0  IMEM              :  AR=%0d", s0_ar_cnt);
        $display("|  S1  DMEM              :  AR=%0d   AW=%0d", s1_ar_cnt, s1_aw_cnt);
        $display("|  S2  ASCON             :  accesses=%0d", s2_access_cnt);
        $display("|  S3  SoC Ctrl          :  accesses=%0d", s3_access_cnt);
        $display("|  S4  CLINT             :  accesses=%0d", s4_access_cnt);
        $display("|  Arb conflicts         :  %0d", xbar_conflict_cnt);
        if (decerr_cnt > 0)
            $display("|  [!!!] DECERR count  :  %0d  <- unmapped address access!", decerr_cnt);
        else
            $display("|  DECERR count        :  0  (OK)");
        $display("+----------------------------------------------------------------+");

        // ── (5) ASCON Summary ────────────────────────────────────────────────
        $display("");
        $display("+--- (5) ASCON IP SUMMARY ---------------------------------------+");
        $display("|  core_start  pulses  : %0d", ascon_start_cnt);
        $display("|  dma_start   pulses  : %0d", ascon_dma_start_cnt);
        $display("|  core_done   events  : %0d", ascon_done_cnt);
        $display("|  dma_done    events  : %0d", ascon_dma_done_cnt);
        $display("|  irq         events  : %0d", ascon_irq_cnt);
        $display("|  dma_error   events  : %0d  %s",
                 ascon_error_cnt, ascon_error_cnt == 0 ? "(OK)" : "[!!!] CHECK DMA ROUTING");
        $display("|  DMA config at halt  : src=0x%08h  dst=0x%08h  len=%0d",
                 ascon_dma_src_r, ascon_dma_dst_r, ascon_dma_len_r);
        $display("|  STATUS at halt      : 0x%08h", ascon_status_word);
        $display("|    core_busy=%0d  core_done=%0d  dma_busy=%0d  dma_done=%0d  err=%0d",
                 ascon_core_busy, ascon_core_done, ascon_dma_busy,
                 ascon_dma_done_st, ascon_dma_error);
        if      (ascon_dma_done_cnt > 0) $display("|  [OK]  DMA encryption completed");
        else if (ascon_error_cnt    > 0) $display("|  [!!!] DMA error — check M2 routing and DMEM addr");
        else                             $display("|  [?]   DMA not completed — check CTRL.START / DMA_EN");
        $display("+----------------------------------------------------------------+");

        // ── (6) Interrupt / CLINT Summary ───────────────────────────────────
        $display("");
        $display("+--- (6) INTERRUPT SUMMARY (CLINT + SoC Ctrl) ------------------+");
        $display("|  timer_irq raises    : %0d", clint_timer_irq_cnt);
        $display("|  sw_irq    raises    : %0d", clint_sw_irq_cnt);
        $display("|  external_irq (ascon): %0d  (via soc_ctrl IRQ_MASK)", ascon_irq_cnt);
        $display("|  soft_rst_pulse      : %0d", soft_rst_cnt);
        $display("|  mtime_tick period   : 100 cycles  (1 MHz prescaler @ 100 MHz)");
        $display("+----------------------------------------------------------------+");

        // ── (7) Memory Access Summary ────────────────────────────────────────
        $display("");
        $display("+--- (7) MEMORY ACCESS SUMMARY ----------------------------------+");
        $display("|  CPU Loads           : %0d", dmem_rd_cnt);
        $display("|  CPU Stores          : %0d", dmem_wr_cnt);
        $display("|  Post-halt SB drain  : %0d stores", post_halt_stores);
        $display("|  RAW hazard errors   : %0d  %s",
                 sb_errors, sb_errors == 0 ? "(OK)" : "[!!!] DATA ERRORS DETECTED");
        $display("|  LSU SB remaining    : %0d entries at halt", lsu_sb_count);
        $display("+----------------------------------------------------------------+");

        // ── (8) Register File ────────────────────────────────────────────────
        $display("");
        $display("+--- (8) REGISTER FILE ------------------------------------------+");
        $display("|  Reg   ABI     Hex          Decimal (signed)");
        $display("|  -----------------------------------------");
        nz = 0;
        for (j = 0; j < 32; j = j + 1) begin
            wv = soc.u_cpu.register_file.registers[j];
            if (wv !== 32'h0 || j == 2 || j == 10) begin
                nz = nz + 1;
                $display("|  x%-2d  %-5s   0x%08h   %0d",
                         j, abi_name(j), wv, $signed(wv));
            end
        end
        if (nz == 0) $display("|  (all zero)");
        $display("+----------------------------------------------------------------+");

        // ── (9) DMEM Snapshot ────────────────────────────────────────────────
        print_dmem_snapshot();

        // ── (10) Store Scoreboard ────────────────────────────────────────────
        $display("");
        $display("+--- (10) STORE SCOREBOARD (%0d entries, %0d errors) ─────────────+",
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
        if (sb_cnt > 48) $display("|  ... (%0d more entries truncated)", sb_cnt - 48);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("=================================================================");
        $display("  RISC-V SoC + ASCON IP  |  %0d cycles @ 100 MHz = %.2f us",
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
        $display("+--- (9) DMEM SNAPSHOT [0x%08h..0x%08h] (%0d words) ──────────+",
                 base, base + `DMEM_DUMP_WORDS * 4 - 1, `DMEM_DUMP_WORDS);
        $display("|  Address       +0          +4          +8          +C");
        $display("|  ---------------------------------------------------------");

        for (wi = 0; wi < `DMEM_DUMP_WORDS; wi = wi + `DMEM_ROW_WORDS) begin
            addr = base + wi * 4;
            $write("|  0x%08h  ", addr);
            for (col = 0; col < `DMEM_ROW_WORDS; col = col + 1) begin
                wval = 32'h0; found = 0;
                for (j = 0; j < sb_cnt; j = j + 1)
                    if (sb_addr[j] === (base + (wi + col) * 4)) begin
                        wval = sb_data[j]; found = 1;
                    end
                $write("0x%08h  ", wval);
            end
            $display("");
        end

        $display("|");
        $display("|  ASCII view:");
        $write("|  ");
        for (wi = 0; wi < `DMEM_DUMP_WORDS * 4; wi = wi + 1) begin
            word_addr = base + (wi / 4) * 4;
            byte_off  = wi[1:0];
            byte_val  = 8'h2E;
            for (k = 0; k < sb_cnt; k = k + 1)
                if (sb_addr[k] === word_addr)
                    case (byte_off)
                        2'd0: byte_val = sb_data[k][ 7: 0];
                        2'd1: byte_val = sb_data[k][15: 8];
                        2'd2: byte_val = sb_data[k][23:16];
                        2'd3: byte_val = sb_data[k][31:24];
                    endcase
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

task print_banner;
    begin
        $display("");
        $display("+=================================================================+");
        $display("|   RISC-V SoC  +  ASCON IP  --  Debug Testbench  v5.0           |");
        $display("|   ICache | DCache | AXI4 Crossbar 3Mx5S | ascon_ip | 100MHz    |");
        $display("+-----------------------------------------------------------------+");
        $display("|   Masters:  M0=ICache  M1=DCache  M2=DMA(via width_conv 64>32) |");
        $display("|   Address Map:                                                  |");
        $display("|     S0  IMEM     0x0000_0000 - 0x0000_FFFF  (64 KB, ROM)       |");
        $display("|     S1  DMEM     0x1000_0000 - 0x1000_FFFF  (64 KB, RAM)       |");
        $display("|     S2  ASCON    0x2000_0000 - 0x2000_0FFF  ( 4 KB)            |");
        $display("|     S3  SoCCtrl  0x3000_0000 - 0x3000_0FFF  ( 4 KB)            |");
        $display("|     S4  CLINT    0x4000_0000 - 0x4000_FFFF  (64 KB)            |");
        $display("+-----------------------------------------------------------------+");
        $display("|   Instances in soc_top:                                         |");
        $display("|     u_cpu  u_icache  u_dcache  u_crossbar  u_imem  u_dmem       |");
        $display("|     u_ascon  u_width_conv  u_clint  u_soc_ctrl                  |");
        $display("+-----------------------------------------------------------------+");
        $display("|   LOG_LEVEL=%0d   TIMEOUT=%0d cyc   HALT_STABLE=%0d cyc         |",
                 `LOG_LEVEL, `TIMEOUT, `HALT_STABLE);
        $display("+=================================================================+");
        $display("");
    end
endtask

endmodule