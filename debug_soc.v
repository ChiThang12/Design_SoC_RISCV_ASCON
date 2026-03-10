`timescale 1ns/1ps
`include "soc_top.v"

// ============================================================================
//  run_soc_ascon_debug.v  --  Enhanced Debug Testbench  v5.0
//  Thêm log chi tiết để xác định lỗi:
//    [A] RESET PHASE log
//    [B] PC jump log — mọi lần PC thay đổi đột ngột (branch/jump)
//    [C] ASCON register map log — decode tên register khi CPU ghi vào S2
//    [D] AXI handshake log nâng cao — phát hiện deadlock/stuck valid
//    [E] DCache miss stall tracker — log khi miss > N cycle
//    [F] CPU NOP storm detector — cảnh báo khi chỉ có NOP quá lâu
//    [G] ASCON STATUS poll tracker — log mỗi lần CPU đọc ASCON status
//    [H] Reset watchdog — phát hiện CPU không thoát reset
//    [I] soc_top internal $display hooks (thêm vào soc_top bằng cờ `DEBUG_SOC)
// ============================================================================

// ── Tuning knobs ──────────────────────────────────────────────────────────────
`define LOG_LEVEL       2   // 1=quan trọng, 2=verbose, 3=trace
`define TIMEOUT         200000
`define HALT_STABLE     60
`define DMEM_DUMP_BASE  32'h10000000
`define DMEM_DUMP_WORDS 32
`define DMEM_ROW_WORDS  4
`define MATCH2_THRESH   200
`define MATCH4_THRESH   200

// ── Debug thresholds mới ──────────────────────────────────────────────────────
`define DCACHE_MISS_WARN  50    // Warn nếu DCache miss stall > N cycles
`define NOP_STORM_THRESH  500   // Warn nếu CPU toàn NOP > N cycles
`define STUCK_VALID_WARN  100   // Warn nếu valid HIGH mà ready LOW > N cycles
`define ASCON_IDLE_WARN   300   // Warn nếu sau START mà không có DONE trong N cycles
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
// SIGNAL TAPS (giữ nguyên từ v4.1)
// ============================================================================
wire [31:0] pc_if     = soc.cpu.pc_if;
wire [31:0] instr_if  = soc.cpu.instr_if;
wire        stall_if  = soc.cpu.stall_if;

wire [31:0] ic_cpu_addr  = soc.cpu_imem_addr;
wire        ic_cpu_req   = soc.cpu_imem_valid;
wire [31:0] ic_cpu_rdata = soc.cpu_imem_rdata;
wire        ic_cpu_ready = soc.cpu_imem_ready;

wire [31:0] dc_addr  = soc.cpu_dcache_addr;
wire [31:0] dc_wdata = soc.cpu_dcache_wdata;
wire [3:0]  dc_wstrb = soc.cpu_dcache_wstrb;
wire        dc_req   = soc.cpu_dcache_req;
wire        dc_we    = soc.cpu_dcache_we;
wire [31:0] dc_rdata = soc.cpu_dcache_rdata;
wire        dc_ready = soc.cpu_dcache_ready;

// M0 (ICache)
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

// M1 (DCache)
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

// M2 (ASCON DMA)
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

// Slaves S0-S3
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

// Crossbar decode
wire [2:0]  xbar_m0_ar_sel = soc.xbar.m0_ar_slave_sel;
wire [2:0]  xbar_m0_aw_sel = soc.xbar.m0_aw_slave_sel;
wire [2:0]  xbar_m1_ar_sel = soc.xbar.m1_ar_slave_sel;
wire [2:0]  xbar_m1_aw_sel = soc.xbar.m1_aw_slave_sel;
wire [2:0]  xbar_m2_ar_sel = soc.xbar.m2_ar_slave_sel;
wire [2:0]  xbar_m2_aw_sel = soc.xbar.m2_aw_slave_sel;

wire [1:0]  xbar_s0_rd_arb = soc.xbar.mux_s0.rd_arb;
wire [1:0]  xbar_s0_wr_arb = soc.xbar.mux_s0.wr_arb;
wire [1:0]  xbar_s1_rd_arb = soc.xbar.mux_s1.rd_arb;
wire [1:0]  xbar_s1_wr_arb = soc.xbar.mux_s1.wr_arb;
wire [1:0]  xbar_s2_rd_arb = soc.xbar.mux_s2.rd_arb;
wire [1:0]  xbar_s3_rd_arb = soc.xbar.mux_s3.rd_arb;

// DMEM write tap
wire        ram_wr_en   = soc.dmem.dmem.burst_wr_valid;
wire [31:0] ram_wr_addr = soc.dmem.dmem.wr_effective_addr;
wire [31:0] ram_wr_data = soc.dmem.dmem.burst_wr_data;
wire [3:0]  ram_wr_strb = soc.dmem.dmem.burst_wr_strb;

// LSU Store Buffer
wire        lsu_sb_empty   = soc.cpu.lsu_unit.sb_empty;
wire [2:0]  lsu_sb_count   = soc.cpu.lsu_unit.sb_count[2:0];
wire        lsu_drain_idle = (soc.cpu.lsu_unit.drain_state == 1'b0);

// ASCON taps
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

// ── NEW: debug counters ───────────────────────────────────────────────────────
integer dcache_miss_stall_cnt;  // số cycle liên tiếp DCache stall
integer nop_storm_cnt;          // số cycle liên tiếp chỉ có NOP
integer m0_stuck_cnt;           // cycle m0_arvalid HIGH mà m0_arready LOW
integer m1_ar_stuck_cnt;
integer m1_aw_stuck_cnt;
integer m2_ar_stuck_cnt;
integer m2_aw_stuck_cnt;
integer s1_ar_stuck_cnt;
integer s1_aw_stuck_cnt;
integer s2_ar_stuck_cnt;
integer s2_aw_stuck_cnt;
integer ascon_wait_done_cnt;    // số cycle chờ DONE sau START
integer ascon_poll_cnt;         // số lần CPU poll status register
integer pc_jump_cnt;
reg [31:0] last_jump_from;
reg [31:0] last_jump_to;

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
// (2) Instruction Retire & Stall + PC Jump Tracker
// ============================================================================
reg prev_stall;
reg [31:0] pc_prev_cycle;

always @(posedge clk) begin
    if (!rst_n) begin
        prev_stall     <= 0;
        pc_prev_cycle  <= 0;
        nop_storm_cnt   = 0;
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

        // [F] NOP storm: quá nhiều NOP liên tiếp (bao gồm stall NOPs)
        if (instr_if === 32'h00000013) begin
            nop_storm_cnt = nop_storm_cnt + 1;
            if (nop_storm_cnt == `NOP_STORM_THRESH)
                $display("[%6d] [WARN][NOP_STORM] CPU đang execute NOP liên tục %0d cycles! pc=0x%08h  -- có thể fetch lỗi hoặc IMEM trả về 0",
                         cycle_count, `NOP_STORM_THRESH, pc_if);
        end else begin
            nop_storm_cnt = 0;
        end

        // [B] PC jump: phát hiện nhảy lớn (branch/jal/jalr)
        if (!stall_if && pc_if !== 32'h0 && pc_prev_cycle !== 32'h0) begin
            if (pc_if !== pc_prev_cycle + 4 && pc_if !== pc_prev_cycle) begin
                pc_jump_cnt    = pc_jump_cnt + 1;
                last_jump_from = pc_prev_cycle;
                last_jump_to   = pc_if;
                if (`LOG_LEVEL >= 2)
                    $display("[%6d] [JMP #%0d] 0x%08h → 0x%08h  (delta=%0d)",
                             cycle_count, pc_jump_cnt,
                             pc_prev_cycle, pc_if,
                             $signed({1'b0, pc_if}) - $signed({1'b0, pc_prev_cycle}));
            end
        end
        pc_prev_cycle <= pc_if;

        if (`LOG_LEVEL >= 3 && instr_if !== 32'h0)
            $display("[%6d] PC=0x%08h  INSTR=0x%08h%s",
                     cycle_count, pc_if, instr_if,
                     stall_if ? "  [STALL]" : "");

        prev_stall <= stall_if;
    end
end

// ============================================================================
// (3) DCache Load/Store Logger + Miss Stall Tracker
// ============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        dcache_miss_stall_cnt = 0;
    end else begin
        // [E] DCache miss tracker: req HIGH nhưng ready LOW
        if (dc_req && !dc_ready) begin
            dcache_miss_stall_cnt = dcache_miss_stall_cnt + 1;
            if (dcache_miss_stall_cnt == `DCACHE_MISS_WARN)
                $display("[%6d] [WARN][DCACHE_MISS] DCache stall đã %0d cycles!  addr=0x%08h  we=%0d  -- DMEM chưa phản hồi?",
                         cycle_count, `DCACHE_MISS_WARN, dc_addr, dc_we);
            if (dcache_miss_stall_cnt > 0 && (dcache_miss_stall_cnt % 500 == 0))
                $display("[%6d] [WARN][DCACHE_MISS] Stall tiếp tục: %0d cycles  addr=0x%08h  m1_arvalid=%0d m1_arready=%0d  m1_awvalid=%0d m1_awready=%0d",
                         cycle_count, dcache_miss_stall_cnt, dc_addr,
                         m1_arvalid, m1_arready, m1_awvalid, m1_awready);
        end else begin
            if (dcache_miss_stall_cnt >= `DCACHE_MISS_WARN)
                $display("[%6d] [INFO][DCACHE_MISS] Stall kết thúc sau %0d cycles  addr=0x%08h",
                         cycle_count, dcache_miss_stall_cnt, dc_addr);
            dcache_miss_stall_cnt = 0;
        end

        // Normal store/load log
        if (dc_req && dc_ready) begin
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
end

// ============================================================================
// (4) M0 (ICache) AXI Logger + Stuck Detector
// ============================================================================
reg [31:0] m0_ar_addr_lat;
always @(posedge clk) begin
    if (!rst_n) begin
        m0_stuck_cnt = 0;
    end else begin
        // Stuck: m0_arvalid HIGH mà m0_arready LOW
        if (m0_arvalid && !m0_arready) begin
            m0_stuck_cnt = m0_stuck_cnt + 1;
            if (m0_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] M0(ICache) ARVALID stuck HIGH %0d cycles!  addr=0x%08h  xbar_sel=S%0d(%s)  -- IMEM không nhận request?",
                         cycle_count, `STUCK_VALID_WARN,
                         m0_araddr, xbar_m0_ar_sel, slave_name(xbar_m0_ar_sel));
        end else begin
            m0_stuck_cnt = 0;
        end

        if (m0_arvalid && m0_arready) begin
            m0_ar_burst_cnt = m0_ar_burst_cnt + 1;
            m0_ar_start     = cycle_count;
            m0_ar_addr_lat  <= m0_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M0-AR] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m0_araddr, m0_arlen,
                         xbar_m0_ar_sel, slave_name(xbar_m0_ar_sel));
            if (xbar_m0_ar_sel !== 3'd0 && `LOG_LEVEL >= 1)
                $display("[%6d] [WARN] M0(ICache) AR -> S%0d(%s) thay vì S0! addr=0x%08h  -- sai địa chỉ fetch?",
                         cycle_count, xbar_m0_ar_sel, slave_name(xbar_m0_ar_sel), m0_araddr);
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
                $display("[%6d] [!!!] DECERR M0 READ addr=0x%08h  -- IMEM address map sai?", cycle_count, m0_ar_addr_lat);
            end
        end
        if (m0_bvalid && m0_bresp == 2'b11) begin
            decerr_cnt = decerr_cnt + 1;
            $display("[%6d] [!!!] DECERR M0 WRITE addr=0x%08h (ICache không nên write!)",
                     cycle_count, m0_awaddr);
        end
    end
end

// ============================================================================
// (5) M1 (DCache) AXI Logger + Stuck Detector
// ============================================================================
reg [31:0] m1_ar_addr_saved;
reg [31:0] m1_aw_addr_saved;
always @(posedge clk) begin
    if (!rst_n) begin
        m1_ar_stuck_cnt = 0;
        m1_aw_stuck_cnt = 0;
    end else begin
        // Stuck detect AR
        if (m1_arvalid && !m1_arready) begin
            m1_ar_stuck_cnt = m1_ar_stuck_cnt + 1;
            if (m1_ar_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] M1(DCache) ARVALID stuck %0d cycles!  addr=0x%08h  S%0d(%s)",
                         cycle_count, `STUCK_VALID_WARN,
                         m1_araddr, xbar_m1_ar_sel, slave_name(xbar_m1_ar_sel));
        end else m1_ar_stuck_cnt = 0;

        // Stuck detect AW
        if (m1_awvalid && !m1_awready) begin
            m1_aw_stuck_cnt = m1_aw_stuck_cnt + 1;
            if (m1_aw_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] M1(DCache) AWVALID stuck %0d cycles!  addr=0x%08h  S%0d(%s)",
                         cycle_count, `STUCK_VALID_WARN,
                         m1_awaddr, xbar_m1_aw_sel, slave_name(xbar_m1_aw_sel));
        end else m1_aw_stuck_cnt = 0;

        if (m1_arvalid && m1_arready) begin
            m1_ar_burst_cnt  = m1_ar_burst_cnt + 1;
            m1_ar_start      = cycle_count;
            m1_ar_addr_saved <= m1_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AR] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m1_araddr, m1_arlen,
                         xbar_m1_ar_sel, slave_name(xbar_m1_ar_sel));
            if (xbar_m1_ar_sel == 3'd0)
                $display("[%6d] [WARN] M1(DCache) AR -> S0(IMEM)! addr=0x%08h  -- CPU đọc nhầm vùng IMEM?", cycle_count, m1_araddr);
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
                $display("[%6d] [!!!] DECERR M1 READ addr=0x%08h  -- địa chỉ ngoài map?", cycle_count, m1_ar_addr_saved);
            end
        end
        if (m1_awvalid && m1_awready) begin
            m1_aw_burst_cnt  = m1_aw_burst_cnt + 1;
            m1_aw_start      = cycle_count;
            m1_aw_addr_saved <= m1_awaddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AW] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m1_awaddr, m1_awlen,
                         xbar_m1_aw_sel, slave_name(xbar_m1_aw_sel));
        end
        if (m1_wvalid && m1_wready) begin
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [M1-W ] data=0x%08h  strb=%b%s",
                         cycle_count, m1_wdata, m1_wstrb,
                         m1_wlast ? "  [LAST]" : "");
            if (m1_wlast) begin
                m1_wr_lat_sum = m1_wr_lat_sum + (cycle_count - m1_aw_start + 1);
                m1_wr_lat_cnt = m1_wr_lat_cnt + 1;
            end
        end
        if (m1_bvalid && m1_bready) begin
            if (m1_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M1 WRITE addr=0x%08h", cycle_count, m1_aw_addr_saved);
            end
        end
    end
end

// ============================================================================
// (6) M2 (ASCON DMA) AXI Logger + Stuck Detector
// ============================================================================
reg [31:0] m2_ar_addr_saved;
reg [31:0] m2_aw_addr_saved;
always @(posedge clk) begin
    if (!rst_n) begin
        m2_ar_stuck_cnt = 0;
        m2_aw_stuck_cnt = 0;
    end else begin
        if (m2_arvalid && !m2_arready) begin
            m2_ar_stuck_cnt = m2_ar_stuck_cnt + 1;
            if (m2_ar_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] M2(DMA) ARVALID stuck %0d cycles!  addr=0x%08h  -- DMEM bị block bởi M0/M1?",
                         cycle_count, `STUCK_VALID_WARN, m2_araddr);
        end else m2_ar_stuck_cnt = 0;

        if (m2_awvalid && !m2_awready) begin
            m2_aw_stuck_cnt = m2_aw_stuck_cnt + 1;
            if (m2_aw_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] M2(DMA) AWVALID stuck %0d cycles!  addr=0x%08h",
                         cycle_count, `STUCK_VALID_WARN, m2_awaddr);
        end else m2_aw_stuck_cnt = 0;

        if (m2_arvalid && m2_arready) begin
            m2_ar_burst_cnt  = m2_ar_burst_cnt + 1;
            m2_ar_start      = cycle_count;
            m2_ar_addr_saved <= m2_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M2-AR] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m2_araddr, m2_arlen,
                         xbar_m2_ar_sel, slave_name(xbar_m2_ar_sel));
        end
        if (m2_rvalid && m2_rready) begin
            if (m2_rlast) begin
                m2_rd_lat_sum = m2_rd_lat_sum + (cycle_count - m2_ar_start + 1);
                m2_rd_lat_cnt = m2_rd_lat_cnt + 1;
            end
            if (m2_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M2 READ addr=0x%08h  -- DMA src address sai?", cycle_count, m2_ar_addr_saved);
            end
        end
        if (m2_awvalid && m2_awready) begin
            m2_aw_burst_cnt  = m2_aw_burst_cnt + 1;
            m2_aw_start      = cycle_count;
            m2_aw_addr_saved <= m2_awaddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M2-AW] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m2_awaddr, m2_awlen,
                         xbar_m2_aw_sel, slave_name(xbar_m2_aw_sel));
        end
        if (m2_wvalid && m2_wready) begin
            if (m2_wlast) begin
                m2_wr_lat_sum = m2_wr_lat_sum + (cycle_count - m2_aw_start + 1);
                m2_wr_lat_cnt = m2_wr_lat_cnt + 1;
            end
        end
        if (m2_bvalid && m2_bready) begin
            if (m2_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M2 WRITE addr=0x%08h  -- DMA dst address sai?", cycle_count, m2_aw_addr_saved);
            end
        end
    end
end

// ============================================================================
// (7) Slave Access Logger + Stuck Detector
//     [C] ASCON register decode: biết CPU đang ghi register nào
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        // S1 stuck
        if (s1_arvalid && !s1_arready) begin
            s1_ar_stuck_cnt = s1_ar_stuck_cnt + 1;
            if (s1_ar_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] S1(DMEM) ARREADY stuck LOW %0d cycles!  addr=0x%08h",
                         cycle_count, `STUCK_VALID_WARN, s1_araddr);
        end else s1_ar_stuck_cnt = 0;

        if (s1_awvalid && !s1_awready) begin
            s1_aw_stuck_cnt = s1_aw_stuck_cnt + 1;
            if (s1_aw_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] S1(DMEM) AWREADY stuck LOW %0d cycles!  addr=0x%08h",
                         cycle_count, `STUCK_VALID_WARN, s1_awaddr);
        end else s1_aw_stuck_cnt = 0;

        // S2 stuck
        if (s2_arvalid && !soc.s2_arready) begin
            s2_ar_stuck_cnt = s2_ar_stuck_cnt + 1;
            if (s2_ar_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] S2(ASCON) ARREADY stuck LOW %0d cycles!  addr=0x%08h offset=0x%03h  -- ASCON slave busy?",
                         cycle_count, `STUCK_VALID_WARN, s2_araddr, s2_araddr[11:0]);
        end else s2_ar_stuck_cnt = 0;

        if (s2_awvalid && !soc.s2_awready) begin
            s2_aw_stuck_cnt = s2_aw_stuck_cnt + 1;
            if (s2_aw_stuck_cnt == `STUCK_VALID_WARN)
                $display("[%6d] [WARN][STUCK] S2(ASCON) AWREADY stuck LOW %0d cycles!  addr=0x%08h  -- ASCON slave busy?",
                         cycle_count, `STUCK_VALID_WARN, s2_awaddr);
        end else s2_aw_stuck_cnt = 0;

        // S0 access
        if (s0_arvalid && s0_arready) begin
            s0_ar_cnt = s0_ar_cnt + 1;
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [S0-IMEM] READ   addr=0x%08h  len=%0d",
                         cycle_count, s0_araddr, s0_arlen);
        end

        // S1 access
        if (s1_arvalid && s1_arready) begin
            s1_ar_cnt = s1_ar_cnt + 1;
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [S1-DMEM] READ   addr=0x%08h",
                         cycle_count, s1_araddr);
        end
        if (s1_awvalid && s1_awready) begin
            s1_aw_cnt = s1_aw_cnt + 1;
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [S1-DMEM] WRITE  addr=0x%08h  data=0x%08h",
                         cycle_count, s1_awaddr, s1_wdata);
        end

        // [C] S2 ASCON: decode tên register
        if (s2_arvalid) begin
            s2_access_cnt = s2_access_cnt + 1;
            ascon_poll_cnt = ascon_poll_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S2-ASCON] READ   addr=0x%08h  reg=%-12s  (poll #%0d)",
                         cycle_count, s2_araddr,
                         ascon_reg_name(s2_araddr[11:0]),
                         ascon_poll_cnt);
        end
        if (s2_awvalid) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S2-ASCON] WRITE  addr=0x%08h  reg=%-12s  data=0x%08h",
                         cycle_count, s2_awaddr,
                         ascon_reg_name(s2_awaddr[11:0]),
                         s2_wdata);
        end

        // S3 access (always DECERR → luôn log)
        if (s3_arvalid) begin
            s3_access_cnt = s3_access_cnt + 1;
            $display("[%6d] [!!!][S3-SOCCTRL] READ  addr=0x%08h  -- DECERR! CPU đọc vùng chưa implement",
                     cycle_count, s3_araddr);
        end
        if (s3_awvalid) begin
            s3_access_cnt = s3_access_cnt + 1;
            $display("[%6d] [!!!][S3-SOCCTRL] WRITE addr=0x%08h  data=0x%08h  -- DECERR! CPU ghi vùng chưa implement",
                     cycle_count, s3_awaddr, soc.s3_wdata);
        end
    end
end

// ============================================================================
// (8) ASCON IP Event Logger + Wait-for-done Tracker
// ============================================================================
reg prev_ascon_dma_done_st;
reg prev_ascon_core_done;
reg prev_ascon_dma_error;
reg prev_ascon_irq;
reg ascon_waiting_done;

always @(posedge clk) begin
    if (!rst_n) begin
        prev_ascon_dma_done_st <= 1'b0;
        prev_ascon_core_done   <= 1'b0;
        prev_ascon_dma_error   <= 1'b0;
        prev_ascon_irq         <= 1'b0;
        ascon_waiting_done     <= 1'b0;
        ascon_wait_done_cnt     = 0;
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
            ascon_waiting_done <= 1'b1;
            ascon_wait_done_cnt = 0;
            $display("[%6d] [ASCON] CORE START  #%0d  dma_en=%0d  key/nonce đã set?",
                     cycle_count, ascon_start_cnt, ascon_reg_dma_en);
        end

        if (ascon_dma_start) begin
            ascon_dma_start_cnt = ascon_dma_start_cnt + 1;
            $display("[%6d] [ASCON] DMA  START  #%0d  src=0x%08h  dst=0x%08h  len=%0d  dma_en=%0d",
                     cycle_count, ascon_dma_start_cnt,
                     ascon_dma_src_r, ascon_dma_dst_r, ascon_dma_len_r, ascon_reg_dma_en);
        end

        // Chờ DONE timer
        if (ascon_waiting_done && (ascon_core_busy || ascon_dma_busy)) begin
            ascon_wait_done_cnt = ascon_wait_done_cnt + 1;
            if (ascon_wait_done_cnt == `ASCON_IDLE_WARN)
                $display("[%6d] [WARN][ASCON] Đã chờ DONE %0d cycles sau START!  STATUS=0x%08h  core_busy=%0d  dma_busy=%0d",
                         cycle_count, `ASCON_IDLE_WARN,
                         ascon_status_word, ascon_core_busy, ascon_dma_busy);
        end

        if (ascon_dma_done_st && !prev_ascon_dma_done_st) begin
            ascon_dma_done_cnt = ascon_dma_done_cnt + 1;
            ascon_waiting_done <= 1'b0;
            $display("[%6d] [ASCON] DMA  DONE  #%0d  STATUS=0x%08h  (waited %0d cycles)",
                     cycle_count, ascon_dma_done_cnt, ascon_status_word, ascon_wait_done_cnt);
        end

        if (ascon_core_done && !prev_ascon_core_done) begin
            ascon_done_cnt = ascon_done_cnt + 1;
            ascon_waiting_done <= 1'b0;
            $display("[%6d] [ASCON] CORE DONE  #%0d  (waited %0d cycles)",
                     cycle_count, ascon_done_cnt, ascon_wait_done_cnt);
        end

        if (ascon_dma_error && !prev_ascon_dma_error) begin
            ascon_error_cnt = ascon_error_cnt + 1;
            $display("[%6d] [!!!]  ASCON DMA ERROR  STATUS=0x%08h  src=0x%08h  dst=0x%08h  len=%0d",
                     cycle_count, ascon_status_word,
                     ascon_dma_src_r, ascon_dma_dst_r, ascon_dma_len_r);
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
        if (pc_if === prev_pc && instr_if !== 32'h00000013
            && !dc_req
            && lsu_sb_empty) begin
            halt_cnt <= halt_cnt + 1;
            if (halt_cnt == 5)
                $display("[%6d] [INFO] PC đang dừng tại 0x%08h  instr=0x%08h  -- halt loop?",
                         cycle_count, pc_if, instr_if);
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
// [H] Reset watchdog: cảnh báo nếu CPU không fetch lệnh sau reset
// ============================================================================
integer post_reset_nofetch_cnt;
reg     reset_released;
always @(posedge clk) begin
    if (!rst_n) begin
        post_reset_nofetch_cnt = 0;
        reset_released <= 0;
    end else begin
        if (!reset_released) begin
            reset_released <= 1;
            $display("[%6d] [INFO][RESET] rst_n deasserted — CPU bắt đầu chạy", cycle_count);
        end
        if (ic_cpu_req === 1'b0) begin
            post_reset_nofetch_cnt = post_reset_nofetch_cnt + 1;
            if (post_reset_nofetch_cnt == 20)
                $display("[%6d] [WARN][RESET] CPU chưa có IMEM request sau %0d cycles!  pc=0x%08h  stall_if=%0d  -- CPU bị treo sau reset?",
                         cycle_count, post_reset_nofetch_cnt, pc_if, stall_if);
        end else begin
            if (post_reset_nofetch_cnt >= 20)
                $display("[%6d] [INFO][RESET] CPU bắt đầu fetch  pc=0x%08h  (sau %0d idle cycles)",
                         cycle_count, ic_cpu_addr, post_reset_nofetch_cnt);
            post_reset_nofetch_cnt = 0;
        end
    end
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
    // new
    dcache_miss_stall_cnt = 0; nop_storm_cnt      = 0;
    m0_stuck_cnt        = 0;
    m1_ar_stuck_cnt     = 0;   m1_aw_stuck_cnt    = 0;
    m2_ar_stuck_cnt     = 0;   m2_aw_stuck_cnt    = 0;
    s1_ar_stuck_cnt     = 0;   s1_aw_stuck_cnt    = 0;
    s2_ar_stuck_cnt     = 0;   s2_aw_stuck_cnt    = 0;
    ascon_wait_done_cnt = 0;   ascon_poll_cnt     = 0;
    pc_jump_cnt         = 0;
    last_jump_from      = 0;   last_jump_to       = 0;
    post_reset_nofetch_cnt = 0; reset_released    = 0;

    for (i = 0; i < 256; i = i + 1) begin sb_addr[i] = 0; sb_data[i] = 0; end
    for (i = 0; i < 8;   i = i + 1) pc_ring[i] = 0;

    print_banner();

    rst_n = 0;
    $display("[     0] [RESET] rst_n asserted LOW...");
    repeat(12) @(posedge clk);
    rst_n = 1;
    $display("[    12] [RESET] rst_n deasserted HIGH, waiting 5 cycles...");
    repeat(5)  @(posedge clk);

    if (`LOG_LEVEL >= 1)
        $display("[%6d] Execution started  pc=0x%08h\n", cycle_count, pc_if);

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
        for (idx = 0; idx < sb_cnt; idx = idx + 1) begin
            if (sb_addr[idx] === al && sb_data[idx] !== got) begin
                sb_errors = sb_errors + 1;
                $display("[%6d] [!!!][RAW] addr=0x%08h  expected=0x%08h  got=0x%08h  -- RAW hazard?",
                         cycle_count, al, sb_data[idx], got);
            end
        end
    end
endtask

// ============================================================================
// REPORT
// ============================================================================
task print_banner;
    begin
        $display("");
        $display("=================================================================");
        $display("  SoC + ASCON Debug Testbench  v5.0");
        $display("  LOG_LEVEL=%0d  TIMEOUT=%0d  DCACHE_MISS_WARN=%0d",
                 `LOG_LEVEL, `TIMEOUT, `DCACHE_MISS_WARN);
        $display("=================================================================");
        $display("");
    end
endtask

task print_report;
    input [127:0] reason;
    integer j, k, nz;
    reg [31:0] wv;
    begin
        $display("");
        $display("=================================================================");
        $display("  SIMULATION ENDED: %s", reason);
        $display("=================================================================");

        $display("");
        $display("+--- (1) EXECUTION SUMMARY -------------------------------------+");
        $display("|  Stop reason         : %s", reason);
        $display("|  Total cycles        : %0d", cycle_count);
        $display("|  Instructions retired: %0d", instr_retired);
        $display("|  Stall cycles        : %0d  (max run: %0d)", stall_cycles, max_stall_run);
        $display("|  PC jumps detected   : %0d  (last: 0x%08h → 0x%08h)",
                 pc_jump_cnt, last_jump_from, last_jump_to);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (2) CACHE STATISTICS ---------------------------------------+");
        $display("|  ICache hits/misses  : %0d / %0d", icache_hits, icache_misses);
        $display("|  DCache hits/misses  : %0d / %0d", dcache_hits, dcache_misses);
        $display("|  DCache writes       : %0d", dcache_writes);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (3) AXI BUS SUMMARY ----------------------------------------+");
        $display("|  M0(ICache)  AR bursts : %0d   avg lat: %0d",
                 m0_ar_burst_cnt,
                 m0_rd_lat_cnt > 0 ? m0_rd_lat_sum / m0_rd_lat_cnt : 0);
        $display("|  M1(DCache)  AR bursts : %0d   avg lat: %0d",
                 m1_ar_burst_cnt,
                 m1_rd_lat_cnt > 0 ? m1_rd_lat_sum / m1_rd_lat_cnt : 0);
        $display("|  M1(DCache)  AW bursts : %0d   avg lat: %0d",
                 m1_aw_burst_cnt,
                 m1_wr_lat_cnt > 0 ? m1_wr_lat_sum / m1_wr_lat_cnt : 0);
        $display("|  M2(DMA)     AR bursts : %0d   avg lat: %0d",
                 m2_ar_burst_cnt,
                 m2_rd_lat_cnt > 0 ? m2_rd_lat_sum / m2_rd_lat_cnt : 0);
        $display("|  M2(DMA)     AW bursts : %0d   avg lat: %0d",
                 m2_aw_burst_cnt,
                 m2_wr_lat_cnt > 0 ? m2_wr_lat_sum / m2_wr_lat_cnt : 0);
        $display("|  S0(IMEM)    AR access : %0d", s0_ar_cnt);
        $display("|  S1(DMEM)    AR access : %0d  AW access: %0d", s1_ar_cnt, s1_aw_cnt);
        $display("|  S2(ASCON)   accesses  : %0d  (polls: %0d)", s2_access_cnt, ascon_poll_cnt);
        $display("|  S3(SOCCTRL) accesses  : %0d  %s",
                 s3_access_cnt, s3_access_cnt > 0 ? "[!!!] DECERR accesses!" : "(OK)");
        $display("|  Arb conflicts        : %0d", xbar_conflict_cnt);
        if (decerr_cnt > 0)
            $display("|  [!!!] DECERR count   : %0d  <- unmapped address!", decerr_cnt);
        else
            $display("|  DECERR count         : 0  (OK)");
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (4) ASCON IP SUMMARY ---------------------------------------+");
        $display("|  core_start  pulses  : %0d", ascon_start_cnt);
        $display("|  dma_start   pulses  : %0d", ascon_dma_start_cnt);
        $display("|  core_done   events  : %0d", ascon_done_cnt);
        $display("|  dma_done    events  : %0d", ascon_dma_done_cnt);
        $display("|  irq         events  : %0d", ascon_irq_cnt);
        $display("|  dma_error   events  : %0d  %s",
                 ascon_error_cnt, ascon_error_cnt == 0 ? "(OK)" : "[!!!] CHECK DMA");
        $display("|  STATUS at halt      : 0x%08h", ascon_status_word);
        $display("|    core_busy=%0d  core_done=%0d  dma_busy=%0d  dma_done=%0d  err=%0d",
                 ascon_core_busy, ascon_core_done, ascon_dma_busy,
                 ascon_dma_done_st, ascon_dma_error);
        $display("|  DMA config at halt  : src=0x%08h  dst=0x%08h  len=%0d",
                 ascon_dma_src_r, ascon_dma_dst_r, ascon_dma_len_r);
        if (ascon_dma_done_cnt > 0)
            $display("|  [OK] DMA encryption completed");
        else if (ascon_start_cnt == 0)
            $display("|  [???] ASCON chưa được START — CPU chưa ghi CTRL register?");
        else if (ascon_error_cnt > 0)
            $display("|  [!!!] DMA error — kiểm tra M2 routing và địa chỉ DMEM");
        else
            $display("|  [?] DMA không hoàn thành — kiểm tra CTRL.START và DMA_EN");
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (5) MEMORY ACCESS SUMMARY ----------------------------------+");
        $display("|  CPU Loads           : %0d", dmem_rd_cnt);
        $display("|  CPU Stores          : %0d", dmem_wr_cnt);
        $display("|  Post-halt SB drain  : %0d stores", post_halt_stores);
        $display("|  RAW hazard errors   : %0d  %s",
                 sb_errors, sb_errors == 0 ? "(OK)" : "[!!!] DATA ERRORS");
        $display("|  LSU SB remaining    : %0d entries at halt", lsu_sb_count);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (6) REGISTER FILE ------------------------------------------+");
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
        $display("+--- (8) STORE SCOREBOARD (%0d entries, %0d errors) ---------------+",
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
        $display("  SoC + ASCON Debug done.  %0d cycles @ 100 MHz = %.2f us",
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
        $display("+--- (7) DMEM SNAPSHOT [0x%08h..0x%08h] (%0d words) -----------+",
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

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================
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

// [C] ASCON register name decode (offset trong 4KB slave window)
// Tên dựa theo convention phổ biến — điều chỉnh theo ascon_top.v thực tế
function [95:0] ascon_reg_name;
    input [11:0] offset;
    begin
        case (offset)
            12'h000: ascon_reg_name = "CTRL        ";
            12'h004: ascon_reg_name = "STATUS      ";
            12'h008: ascon_reg_name = "KEY0        ";
            12'h00C: ascon_reg_name = "KEY1        ";
            12'h010: ascon_reg_name = "KEY2        ";
            12'h014: ascon_reg_name = "KEY3        ";
            12'h018: ascon_reg_name = "NONCE0      ";
            12'h01C: ascon_reg_name = "NONCE1      ";
            12'h020: ascon_reg_name = "NONCE2      ";
            12'h024: ascon_reg_name = "NONCE3      ";
            12'h028: ascon_reg_name = "DATA_IN0    ";
            12'h02C: ascon_reg_name = "DATA_IN1    ";
            12'h030: ascon_reg_name = "DATA_IN2    ";
            12'h034: ascon_reg_name = "DATA_IN3    ";
            12'h038: ascon_reg_name = "DATA_OUT0   ";
            12'h03C: ascon_reg_name = "DATA_OUT1   ";
            12'h040: ascon_reg_name = "DATA_OUT2   ";
            12'h044: ascon_reg_name = "DATA_OUT3   ";
            12'h048: ascon_reg_name = "DMA_SRC     ";
            12'h04C: ascon_reg_name = "DMA_DST     ";
            12'h050: ascon_reg_name = "DMA_LEN     ";
            12'h054: ascon_reg_name = "DMA_CTRL    ";
            12'h058: ascon_reg_name = "IRQ_EN      ";
            12'h05C: ascon_reg_name = "IRQ_STATUS  ";
            default: ascon_reg_name = "UNKNOWN     ";
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