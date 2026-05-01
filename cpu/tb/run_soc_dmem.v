`timescale 1ns/1ps

`timescale 1ns/1ps
`include "cpu/cpu_core.v"

// ============================================================================
// tb_dmem_debug.v  —  DMEM / DCache Debug Testbench
// ============================================================================
// Đã map chính xác theo:
//   cpu_core.v (riscv_soc_top_cached)
//   dcache_top.v
//   data_mem_axi_slave.v  (instance: dmem)
//   data_mem_burst.v      (instance: dmem.dmem)
//
// Hierarchy thực tế:
//   soc                          = riscv_soc_top_cached
//   soc.cpu                      = riscv_cpu_core
//   soc.dcache                   = dcache_top
//   soc.dmem                     = data_mem_axi4_slave
//   soc.dmem.dmem                = data_mem_burst  ← RAM array thực
//
// AXI4 wires (khai báo tại cpu_core.v, prefix dcache_*):
//   Write: dcache_awaddr/awvalid/awready | dcache_wdata_axi/wstrb_axi/wlast/wvalid/wready | dcache_bresp/bvalid/bready
//   Read : dcache_araddr/arvalid/arready | dcache_rdata/rresp/rlast/rvalid/rready
//
// LOG FORMAT:
//   [CYC]  [LAYER]       THÔNG TIN CHI TIẾT
//   Layer:
//     CPU-WR / CPU-RD   : CPU ↔ DCache interface (cpu_dcache_*)
//     DC-STATE          : DCache FSM nội bộ (current_addr/data/valid)
//     AXI-AW            : Write Address handshake (DCache→DMEM)
//     AXI-W             : Write Data beat        (DCache→DMEM)
//     AXI-B             : Write Response         (DMEM→DCache)
//     AXI-AR            : Read  Address handshake (DCache→DMEM)
//     AXI-R             : Read  Data beat         (DMEM→DCache)
//     MEM-WR            : Ghi thực vào RAM array  (burst_wr_valid)
//     MEM-RD            : Đọc thực từ RAM array   (burst_rd_valid)
//     SB-ERR            : Scoreboard mismatch     ← LỖI DATA
//     WARN              : Anomaly (timeout, stall, miss liên tiếp)
// ============================================================================

module tb_dmem_debug;

// ============================================================================
// Parameters
// ============================================================================
parameter CLK_PERIOD    = 10;       // 100 MHz — khớp run_soc.v
parameter TIMEOUT       = 20000;    // cycle tối đa
parameter SB_DEPTH      = 256;      // số địa chỉ scoreboard theo dõi
// MEM_SIZE = 1024 bytes (theo data_mem_burst default)
// DMEM address offset = 0x0 (byte address, word index = addr[9:2])
// Vùng data test: RAM_BASE=0x1000 trong linker script
// → word index = 0x1000>>2 = 0x400 → vượt 1KB! (256 words)
// Thực tế data_mem dùng addr[9:2] nên chỉ dùng được 10-bit thấp
// → test phải dùng địa chỉ thấp ≤ 0x3FF (1023 bytes)
// *** CHÚ Ý: Nếu linker dùng RAM_BASE=0x1000, cần sửa data_mem
//     hoặc sửa test C để dùng địa chỉ <= 0x3FF ***
parameter LAT_WARN      = 20;       // cảnh báo latency > N cycles
parameter MISS_WARN     = 5;        // cảnh báo miss liên tiếp > N

// ============================================================================
// Clock & Reset
// ============================================================================
reg clk;
reg rst_n;

initial  clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT
// ============================================================================
wire [31:0] icache_hits, icache_misses;
wire [31:0] dcache_hits, dcache_misses, dcache_writes;

riscv_soc_top_cached soc (
    .clk          (clk),
    .rst_n        (rst_n),
    .icache_hits  (icache_hits),
    .icache_misses(icache_misses),
    .dcache_hits  (dcache_hits),
    .dcache_misses(dcache_misses),
    .dcache_writes(dcache_writes)
);

// ============================================================================
// SIGNAL TAPS — tên chính xác từ cpu_core.v
// ============================================================================

// ── Layer 1: CPU ↔ DCache interface (wire trong soc top-level) ───────────
wire [31:0] cpu_addr   = soc.cpu_dcache_addr;
wire [31:0] cpu_wdata  = soc.cpu_dcache_wdata;
wire [3:0]  cpu_wstrb  = soc.cpu_dcache_wstrb;
wire        cpu_req    = soc.cpu_dcache_req;
wire        cpu_we     = soc.cpu_dcache_we;
wire [31:0] cpu_rdata  = soc.cpu_dcache_rdata;
wire        cpu_ready  = soc.cpu_dcache_ready;

// ── Layer 2: DCache internal debug (current_* từ controller) ────────────
wire [31:0] dc_cur_addr  = soc.dcache_current_addr;
wire [31:0] dc_cur_data  = soc.dcache_current_data;
wire        dc_cur_valid = soc.dcache_current_valid;

// ── Layer 3: AXI4 Write Channels (DCache→DMEM) ──────────────────────────
// AW Channel
wire [31:0] axi_awaddr  = soc.dcache_awaddr;
wire [7:0]  axi_awlen   = soc.dcache_awlen;
wire [2:0]  axi_awsize  = soc.dcache_awsize;
wire [1:0]  axi_awburst = soc.dcache_awburst;
wire        axi_awvalid = soc.dcache_awvalid;
wire        axi_awready = soc.dcache_awready;   // từ dmem

// W Channel — NOTE: wire tên là dcache_wdata_axi, dcache_wstrb_axi
wire [31:0] axi_wdata   = soc.dcache_wdata_axi;
wire [3:0]  axi_wstrb   = soc.dcache_wstrb_axi;
wire        axi_wlast   = soc.dcache_wlast;
wire        axi_wvalid  = soc.dcache_wvalid;
wire        axi_wready  = soc.dcache_wready;    // từ dmem

// B Channel
wire [1:0]  axi_bresp   = soc.dcache_bresp;
wire        axi_bvalid  = soc.dcache_bvalid;
wire        axi_bready  = soc.dcache_bready;

// ── Layer 4: AXI4 Read Channels (DCache→DMEM) ───────────────────────────
// AR Channel
wire [31:0] axi_araddr  = soc.dcache_araddr;
wire [7:0]  axi_arlen   = soc.dcache_arlen;
wire [2:0]  axi_arsize  = soc.dcache_arsize;
wire [1:0]  axi_arburst = soc.dcache_arburst;
wire        axi_arvalid = soc.dcache_arvalid;
wire        axi_arready = soc.dcache_arready;   // từ dmem

// R Channel
wire [31:0] axi_rdata   = soc.dcache_rdata;
wire [1:0]  axi_rresp   = soc.dcache_rresp;
wire        axi_rlast   = soc.dcache_rlast;
wire        axi_rvalid  = soc.dcache_rvalid;
wire        axi_rready  = soc.dcache_rready;

// ── Layer 5: DMEM internal FSM (data_mem_axi4_slave) ─────────────────────
wire [2:0]  dmem_wr_state  = soc.dmem.wr_state;
wire [1:0]  dmem_rd_state  = soc.dmem.rd_state;
wire [31:0] dmem_wr_addr_r = soc.dmem.write_addr;  // addr latched từ AW
wire [31:0] dmem_rd_addr_r = soc.dmem.read_addr;   // addr latched từ AR

// ── Layer 6: RAM array interface (data_mem_burst) ─────────────────────────
wire        ram_wr_valid   = soc.dmem.dmem.burst_wr_valid;
wire        ram_wr_ready   = soc.dmem.dmem.burst_wr_ready;
// FIX: wr_current_addr đổi tên thành wr_effective_addr (wire, không phải reg nữa)
wire [31:0] ram_wr_addr    = soc.dmem.dmem.wr_effective_addr;
wire        ram_rd_req     = soc.dmem.dmem.burst_rd_req;
wire        ram_rd_valid   = soc.dmem.dmem.burst_rd_valid;
wire        ram_rd_last    = soc.dmem.dmem.burst_rd_last;
wire [31:0] ram_rd_cur_addr= soc.dmem.dmem.rd_current_addr;
wire [31:0] ram_rd_data    = soc.dmem.dmem.burst_rd_data;

// ── CPU pipeline ───────────────────────────────────────────────────────────
wire [31:0] pc_cur    = soc.cpu.pc_if;
wire [31:0] instr_cur = soc.cpu.instr_if;

// ============================================================================
// Counters & State
// ============================================================================
integer cycle_count;
integer error_count;
integer program_done;

// Transaction counters
integer cnt_cpu_rd, cnt_cpu_wr;
integer cnt_axi_aw, cnt_axi_w_beat;
integer cnt_axi_b,  cnt_axi_ar, cnt_axi_r_beat;
integer cnt_ram_wr, cnt_ram_rd;

// Latency: CPU req → ready
integer cpu_lat_start;
reg     cpu_lat_pending;
integer cpu_lat_sum, cpu_lat_cnt, cpu_lat_max, cpu_lat_min;

// Latency: AW handshake → B handshake (write round-trip)
integer aw_lat_start;
reg     aw_lat_pending;
integer wr_lat_sum, wr_lat_cnt, wr_lat_max, wr_lat_min;

// Latency: AR handshake → R-last (read round-trip)
integer ar_lat_start;
reg     ar_lat_pending;
integer rd_lat_sum, rd_lat_cnt, rd_lat_max, rd_lat_min;

// AXI stuck detection
integer aw_wait_cnt, ar_wait_cnt, w_wait_cnt;

// Scoreboard: địa chỉ → data ghi gần nhất
reg [31:0] sb_addr [0:SB_DEPTH-1];
reg [31:0] sb_data [0:SB_DEPTH-1];
reg        sb_used [0:SB_DEPTH-1];
integer    sb_cnt;

// Ghi AW addr để ghép với W beats
reg [31:0] pending_aw_addr;
reg        pending_aw_valid;
reg [31:0] w_beat_offset;

// Ghi AR addr để ghép với R beats
reg [31:0] pending_ar_addr;
reg [31:0] r_beat_offset;

// DCache miss liên tiếp
reg [31:0] prev_miss;
integer    miss_run;

// Pipeline stall
integer stall_run;

// Program end
reg [31:0] prev_pc;
integer    stable_cnt;

// ============================================================================
// Waveform
// ============================================================================
initial begin
    $dumpfile("waveform_dmem_debug.vcd");
    $dumpvars(0, tb_dmem_debug);
end

// ============================================================================
// Init & Reset
// ============================================================================
integer ii;
initial begin
    // Init integers
    cycle_count = 0; error_count = 0; program_done = 0;
    cnt_cpu_rd = 0; cnt_cpu_wr = 0;
    cnt_axi_aw = 0; cnt_axi_w_beat = 0;
    cnt_axi_b  = 0; cnt_axi_ar = 0; cnt_axi_r_beat = 0;
    cnt_ram_wr = 0; cnt_ram_rd = 0;
    cpu_lat_start = 0; cpu_lat_pending = 0;
    cpu_lat_sum = 0; cpu_lat_cnt = 0; cpu_lat_max = 0; cpu_lat_min = 999999;
    aw_lat_start = 0; aw_lat_pending = 0;
    wr_lat_sum = 0; wr_lat_cnt = 0; wr_lat_max = 0; wr_lat_min = 999999;
    ar_lat_start = 0; ar_lat_pending = 0;
    rd_lat_sum = 0; rd_lat_cnt = 0; rd_lat_max = 0; rd_lat_min = 999999;
    aw_wait_cnt = 0; ar_wait_cnt = 0; w_wait_cnt = 0;
    sb_cnt = 0;
    pending_aw_valid = 0; pending_aw_addr = 0; w_beat_offset = 0;
    pending_ar_addr = 0; r_beat_offset = 0;
    prev_miss = 0; miss_run = 0;
    stall_run = 0; prev_pc = 0; stable_cnt = 0;

    for (ii = 0; ii < SB_DEPTH; ii = ii + 1) begin
        sb_used[ii] = 0; sb_addr[ii] = 0; sb_data[ii] = 0;
    end

    print_banner();

    rst_n = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5)  @(posedge clk);

    $display("[%5d] [INIT   ] Reset released. Monitoring DMEM transactions...\n", cycle_count);
    print_col_header();

    repeat(TIMEOUT) @(posedge clk);
    $display("\n[TIMEOUT] %0d cycles reached.", TIMEOUT);
    print_final_report();
    $finish;
end

// ============================================================================
// Cycle counter
// ============================================================================
always @(posedge clk)
    if (rst_n) cycle_count = cycle_count + 1;

// ============================================================================
// MONITOR 1: CPU ↔ DCache
// Bắt: cpu_req=1 && cpu_ready=1 (transaction hoàn tất)
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        // Bắt đầu đo latency khi cpu_req lên mà chưa ready
        if (cpu_req && !cpu_lat_pending) begin
            cpu_lat_pending = 1;
            cpu_lat_start   = cycle_count;
        end

        // Transaction hoàn tất
        if (cpu_req && cpu_ready) begin : cpu_done
            integer lat;
            lat             = cycle_count - cpu_lat_start + 1;
            cpu_lat_pending = 0;
            // Cập nhật latency stats
            cpu_lat_sum = cpu_lat_sum + lat;
            cpu_lat_cnt = cpu_lat_cnt + 1;
            if (lat > cpu_lat_max) cpu_lat_max = lat;
            if (lat < cpu_lat_min) cpu_lat_min = lat;

            if (cpu_we) begin
                // ── CPU WRITE ────────────────────────────────────────────
                cnt_cpu_wr = cnt_cpu_wr + 1;
                $display("[%5d] [CPU-WR ] ADDR=0x%08h  WDATA=0x%08h  STRB=%b  LAT=%0d cyc  PC=0x%08h",
                         cycle_count, cpu_addr, cpu_wdata, cpu_wstrb, lat, pc_cur);
                print_strb_detail(cpu_addr, cpu_wdata, cpu_wstrb);
                sb_update(cpu_addr, cpu_wdata, cpu_wstrb);

                if (lat > LAT_WARN)
                    $display("[%5d] [WARN   ] CPU-WR latency HIGH: %0d cycles @ 0x%08h",
                             cycle_count, lat, cpu_addr);
            end else begin
                // ── CPU READ ─────────────────────────────────────────────
                cnt_cpu_rd = cnt_cpu_rd + 1;
                $display("[%5d] [CPU-RD ] ADDR=0x%08h  RDATA=0x%08h              LAT=%0d cyc  PC=0x%08h",
                         cycle_count, cpu_addr, cpu_rdata, lat, pc_cur);
                sb_check(cpu_addr, cpu_rdata);

                if (lat > LAT_WARN)
                    $display("[%5d] [WARN   ] CPU-RD latency HIGH: %0d cycles @ 0x%08h",
                             cycle_count, lat, cpu_addr);
            end
        end else if (!cpu_req) begin
            cpu_lat_pending = 0;
        end
    end
end

// ============================================================================
// MONITOR 2: DCache current_* (controller đang xử lý request gì)
// In khi current_valid lên (edge detect)
// ============================================================================
reg prev_dc_cur_valid;
always @(posedge clk) begin
    if (!rst_n) begin
        prev_dc_cur_valid <= 0;
    end else begin
        if (dc_cur_valid && !prev_dc_cur_valid) begin
            $display("[%5d] [DC-BUSY] Cache controller active: ADDR=0x%08h  DATA=0x%08h",
                     cycle_count, dc_cur_addr, dc_cur_data);
        end
        if (!dc_cur_valid && prev_dc_cur_valid) begin
            $display("[%5d] [DC-DONE] Cache controller idle again", cycle_count);
        end
        prev_dc_cur_valid <= dc_cur_valid;
    end
end

// ============================================================================
// MONITOR 3: AXI4 Write Address Channel (AW)
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        // Stuck detection
        if (axi_awvalid && !axi_awready) begin
            aw_wait_cnt = aw_wait_cnt + 1;
            if (aw_wait_cnt == LAT_WARN)
                $display("[%5d] [WARN   ] AXI-AW stuck %0d cycles, AWADDR=0x%08h",
                         cycle_count, aw_wait_cnt, axi_awaddr);
        end else
            aw_wait_cnt = 0;

        // Handshake
        if (axi_awvalid && axi_awready) begin
            cnt_axi_aw       = cnt_axi_aw + 1;
            pending_aw_addr  = axi_awaddr;
            pending_aw_valid = 1;
            w_beat_offset    = 0;
            aw_lat_pending   = 1;
            aw_lat_start     = cycle_count;

            $display("[%5d] [AXI-AW ] ADDR=0x%08h  LEN=%0d beat(s)  SIZE=2^%0d B  BURST=%s",
                     cycle_count, axi_awaddr, axi_awlen + 1, axi_awsize,
                     burst_str(axi_awburst));
        end
    end
end

// ============================================================================
// MONITOR 4: AXI4 Write Data Channel (W)
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        // Stuck detection
        if (axi_wvalid && !axi_wready) begin
            w_wait_cnt = w_wait_cnt + 1;
            if (w_wait_cnt == LAT_WARN)
                $display("[%5d] [WARN   ] AXI-W  stuck %0d cycles", cycle_count, w_wait_cnt);
        end else
            w_wait_cnt = 0;

        // Handshake beat
        if (axi_wvalid && axi_wready) begin
            cnt_axi_w_beat = cnt_axi_w_beat + 1;

            $display("[%5d] [AXI-W  ] ADDR=0x%08h  DATA=0x%08h  STRB=%b%s",
                     cycle_count,
                     pending_aw_valid ? (pending_aw_addr + w_beat_offset) : 32'hxxxxxxxx,
                     axi_wdata, axi_wstrb,
                     axi_wlast ? "  [LAST]" : "");

            // Scoreboard update từ AXI W (write-through ghi xuống DMEM)
            if (pending_aw_valid)
                sb_update(pending_aw_addr + w_beat_offset, axi_wdata, axi_wstrb);

            if (!axi_wlast)
                w_beat_offset = w_beat_offset + 4;  // INCR burst 32-bit
            else begin
                w_beat_offset    = 0;
                // pending_aw_valid stays 1 until B handshake
            end
        end
    end
end

// ============================================================================
// MONITOR 5: AXI4 Write Response Channel (B)
// ============================================================================
always @(posedge clk) begin
    if (rst_n && axi_bvalid && axi_bready) begin : b_blk
        integer wlat;
        cnt_axi_b      = cnt_axi_b + 1;
        wlat           = cycle_count - aw_lat_start;
        aw_lat_pending = 0;
        pending_aw_valid = 0;

        wr_lat_sum = wr_lat_sum + wlat;
        wr_lat_cnt = wr_lat_cnt + 1;
        if (wlat > wr_lat_max) wr_lat_max = wlat;
        if (wlat < wr_lat_min) wr_lat_min = wlat;

        $display("[%5d] [AXI-B  ] RESP=%s  WR_LATENCY=%0d cyc (AW→B)%s",
                 cycle_count,
                 resp_str(axi_bresp), wlat,
                 (axi_bresp != 2'b00) ? "  *** AXI SLAVE ERROR ***" : "");

        if (axi_bresp != 2'b00) begin
            error_count = error_count + 1;
            $display("[%5d] [SB-ERR ] AXI B channel non-OKAY response: %b", cycle_count, axi_bresp);
        end
    end
end

// ============================================================================
// MONITOR 6: AXI4 Read Address Channel (AR)
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        // Stuck detection
        if (axi_arvalid && !axi_arready) begin
            ar_wait_cnt = ar_wait_cnt + 1;
            if (ar_wait_cnt == LAT_WARN)
                $display("[%5d] [WARN   ] AXI-AR stuck %0d cycles, ARADDR=0x%08h",
                         cycle_count, ar_wait_cnt, axi_araddr);
        end else
            ar_wait_cnt = 0;

        // Handshake
        if (axi_arvalid && axi_arready) begin
            cnt_axi_ar      = cnt_axi_ar + 1;
            pending_ar_addr = axi_araddr;
            r_beat_offset   = 0;
            ar_lat_pending  = 1;
            ar_lat_start    = cycle_count;

            $display("[%5d] [AXI-AR ] ADDR=0x%08h  LEN=%0d beat(s)  SIZE=2^%0d B  BURST=%s",
                     cycle_count, axi_araddr, axi_arlen + 1, axi_arsize,
                     burst_str(axi_arburst));
        end
    end
end

// ============================================================================
// MONITOR 7: AXI4 Read Data Channel (R)
// ============================================================================
always @(posedge clk) begin
    if (rst_n && axi_rvalid && axi_rready) begin : r_blk
        integer rlat;
        cnt_axi_r_beat = cnt_axi_r_beat + 1;

        $display("[%5d] [AXI-R  ] ADDR=0x%08h  DATA=0x%08h  RESP=%s%s",
                 cycle_count,
                 pending_ar_addr + r_beat_offset,
                 axi_rdata,
                 resp_str(axi_rresp),
                 axi_rlast ? "  [LAST]" : "");

        // Scoreboard: kiểm tra refill data từ DMEM có đúng với data đã ghi không
        sb_check_refill(pending_ar_addr + r_beat_offset, axi_rdata);

        if (axi_rresp != 2'b00) begin
            error_count = error_count + 1;
            $display("[%5d] [SB-ERR ] AXI R non-OKAY response @ 0x%08h: %b",
                     cycle_count, pending_ar_addr + r_beat_offset, axi_rresp);
        end

        if (axi_rlast) begin
            rlat           = cycle_count - ar_lat_start;
            ar_lat_pending = 0;
            r_beat_offset  = 0;
            rd_lat_sum = rd_lat_sum + rlat;
            rd_lat_cnt = rd_lat_cnt + 1;
            if (rlat > rd_lat_max) rd_lat_max = rlat;
            if (rlat < rd_lat_min) rd_lat_min = rlat;
            $display("[%5d] [AXI-R  ] Burst complete. RD_LATENCY=%0d cyc (AR→R-last)", cycle_count, rlat);
        end else begin
            r_beat_offset = r_beat_offset + 4;
        end
    end
end

// ============================================================================
// MONITOR 8: RAM Array — actual write vào memory[]
// Tap soc.dmem.dmem.burst_wr_valid
// ============================================================================
always @(posedge clk) begin
    if (rst_n && ram_wr_valid && ram_wr_ready) begin
        cnt_ram_wr = cnt_ram_wr + 1;
        // FIX: dùng ram_wr_addr[31:2] (word index đầy đủ) thay vì [9:2] (chỉ 8 bit → luôn 0x000)
        $display("[%5d] [MEM-WR ] RAM[0x%05h] <= 0x%08h  STRB=%b  (byte addr: 0x%08h)",
                 cycle_count,
                 ram_wr_addr[31:2],         // word index đầy đủ
                 soc.dmem.dmem.burst_wr_data,
                 soc.dmem.dmem.burst_wr_strb,
                 ram_wr_addr);
    end
end

// ============================================================================
// MONITOR 9: RAM Array — actual read từ memory[]
// ============================================================================
reg prev_ram_rd_valid;
always @(posedge clk) begin
    if (!rst_n) begin
        prev_ram_rd_valid <= 0;
    end else begin
        if (ram_rd_valid && prev_ram_rd_valid) begin
            cnt_ram_rd = cnt_ram_rd + 1;
            // FIX: dùng ram_rd_cur_addr[31:2] (word index đầy đủ)
            $display("[%5d] [MEM-RD ] RAM[0x%05h] => 0x%08h%s  (byte addr: 0x%08h)",
                     cycle_count,
                     ram_rd_cur_addr[31:2],
                     ram_rd_data,
                     ram_rd_last ? " [LAST]" : "",
                     ram_rd_cur_addr);
        end
        prev_ram_rd_valid <= ram_rd_valid;
    end
end

// ============================================================================
// MONITOR 10: DCache miss liên tiếp
// ============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        prev_miss <= 0;
        miss_run  <= 0;
    end else begin
        if (dcache_misses > prev_miss) begin
            miss_run = miss_run + 1;
            if (miss_run >= MISS_WARN)
                $display("[%5d] [WARN   ] DCache %0d consecutive misses (total=%0d / hits=%0d)",
                         cycle_count, miss_run, dcache_misses, dcache_hits);
        end else
            miss_run = 0;
        prev_miss <= dcache_misses;
    end
end

// ============================================================================
// MONITOR 11: Pipeline stall
// ============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        stall_run <= 0;
    end else if (soc.cpu.stall_if) begin
        stall_run <= stall_run + 1;
        if (stall_run == 15)
            $display("[%5d] [WARN   ] Pipeline stalled 15+ cycles. PC=0x%08h",
                     cycle_count, pc_cur);
    end else
        stall_run <= 0;
end

// ============================================================================
// MONITOR 12: Program end (halt loop detection)
// ============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        stable_cnt <= 0;
        prev_pc    <= 0;
    end else begin
        if (pc_cur == prev_pc && instr_cur != 32'h0000_0013 && cycle_count > 30) begin
            stable_cnt <= stable_cnt + 1;
            if (stable_cnt >= 30 && !program_done) begin
                program_done = 1;
                $display("\n[%5d] [HALT   ] Halt loop @ PC=0x%08h", cycle_count, pc_cur);
                print_final_report();
                #(CLK_PERIOD * 2);
                $finish;
            end
        end else begin
            stable_cnt <= 0;
        end
        prev_pc <= pc_cur;
    end
end

// ============================================================================
// SCOREBOARD TASKS
// ============================================================================

// sb_update: ghi/merge vào bảng theo byte strobe
task sb_update;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    reg [31:0] aligned;
    integer    idx, found;
    reg [31:0] merged;
    begin
        aligned = {addr[31:2], 2'b00};
        found   = -1;
        for (idx = 0; idx < sb_cnt; idx = idx + 1)
            if (sb_addr[idx] == aligned) found = idx;

        merged = (found >= 0) ? sb_data[found] : 32'h0;
        if (strb[0]) merged[7:0]   = data[7:0];
        if (strb[1]) merged[15:8]  = data[15:8];
        if (strb[2]) merged[23:16] = data[23:16];
        if (strb[3]) merged[31:24] = data[31:24];

        if (found >= 0) begin
            sb_data[found] = merged;
        end else if (sb_cnt < SB_DEPTH) begin
            sb_addr[sb_cnt] = aligned;
            sb_data[sb_cnt] = merged;
            sb_used[sb_cnt] = 1;
            sb_cnt          = sb_cnt + 1;
        end else
            $display("[%5d] [WARN   ] Scoreboard full, entry dropped for 0x%08h", cycle_count, aligned);
    end
endtask

// sb_check: CPU đọc → so sánh với scoreboard
task sb_check;
    input [31:0] addr;
    input [31:0] got;
    reg [31:0] aligned;
    integer idx;
    reg found;
    begin
        aligned = {addr[31:2], 2'b00};
        found   = 0;
        for (idx = 0; idx < sb_cnt; idx = idx + 1) begin
            if (sb_addr[idx] == aligned && sb_used[idx]) begin
                found = 1;
                if (sb_data[idx] !== got) begin
                    error_count = error_count + 1;
                    $display("[%5d] [SB-ERR ] CPU-RD MISMATCH @ 0x%08h", cycle_count, aligned);
                    $display("              Expected : 0x%08h  (%032b)", sb_data[idx], sb_data[idx]);
                    $display("              Got      : 0x%08h  (%032b)", got, got);
                    $display("              XOR diff : 0x%08h", sb_data[idx] ^ got);
                    if (sb_data[idx][7:0]   !== got[7:0]  ) $display("              → Byte[0] exp=0x%02h got=0x%02h", sb_data[idx][7:0],   got[7:0]);
                    if (sb_data[idx][15:8]  !== got[15:8] ) $display("              → Byte[1] exp=0x%02h got=0x%02h", sb_data[idx][15:8],  got[15:8]);
                    if (sb_data[idx][23:16] !== got[23:16]) $display("              → Byte[2] exp=0x%02h got=0x%02h", sb_data[idx][23:16], got[23:16]);
                    if (sb_data[idx][31:24] !== got[31:24]) $display("              → Byte[3] exp=0x%02h got=0x%02h", sb_data[idx][31:24], got[31:24]);
                end
            end
        end
        if (!found)
            $display("[%5d] [SB-NEW ] First read @ 0x%08h = 0x%08h (no prior write seen)",
                     cycle_count, aligned, got);
    end
endtask

// sb_check_refill: data DMEM gửi về DCache khi refill
// Nếu địa chỉ đã từng ghi, data phải khớp
task sb_check_refill;
    input [31:0] addr;
    input [31:0] got;
    reg [31:0] aligned;
    integer idx;
    begin
        aligned = {addr[31:2], 2'b00};
        for (idx = 0; idx < sb_cnt; idx = idx + 1) begin
            if (sb_addr[idx] == aligned && sb_used[idx]) begin
                if (sb_data[idx] !== got) begin
                    error_count = error_count + 1;
                    $display("[%5d] [SB-ERR ] REFILL MISMATCH @ 0x%08h", cycle_count, aligned);
                    $display("              Written : 0x%08h", sb_data[idx]);
                    $display("              Refilled: 0x%08h", got);
                    $display("              → DMEM không giữ đúng data đã ghi qua AXI-W !");
                end
            end
        end
    end
endtask

// ============================================================================
// HELPER FUNCTIONS & TASKS
// ============================================================================

task print_strb_detail;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    begin
        case (strb)
            4'b1111: ; // word — không cần in thêm
            4'b0001: $display("              → sb [addr+0] = 0x%02h", data[7:0]);
            4'b0010: $display("              → sb [addr+1] = 0x%02h", data[15:8]);
            4'b0100: $display("              → sb [addr+2] = 0x%02h", data[23:16]);
            4'b1000: $display("              → sb [addr+3] = 0x%02h", data[31:24]);
            4'b0011: $display("              → sh [addr+0..1] = 0x%04h", data[15:0]);
            4'b1100: $display("              → sh [addr+2..3] = 0x%04h", data[31:16]);
            default:  $display("              → mixed strb=%b data=0x%08h", strb, data);
        endcase
    end
endtask

function [47:0] burst_str;
    input [1:0] burst;
    begin
        case (burst)
            2'b00: burst_str = "FIXED ";
            2'b01: burst_str = "INCR  ";
            2'b10: burst_str = "WRAP  ";
            default: burst_str = "???   ";
        endcase
    end
endfunction

function [47:0] resp_str;
    input [1:0] resp;
    begin
        case (resp)
            2'b00: resp_str = "OKAY  ";
            2'b01: resp_str = "EXOKAY";
            2'b10: resp_str = "SLVERR";
            2'b11: resp_str = "DECERR";
        endcase
    end
endfunction

task print_col_header;
    begin
        $display("%-7s  %-9s  %s", "CYCLE", "LAYER", "DETAIL");
        $display("─────────────────────────────────────────────────────────────────────────────────");
    end
endtask

task print_banner;
    begin
        $display("\n╔══════════════════════════════════════════════════════════════════╗");
        $display("║     tb_dmem_debug  —  DMEM / DCache AXI4 Debug Testbench        ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  DUT  : riscv_soc_top_cached                                    ║");
        $display("║  CPU  : soc.cpu  (riscv_cpu_core)                               ║");
        $display("║  Cache: soc.dcache  (dcache_top, write-through)                 ║");
        $display("║  DMEM : soc.dmem  (data_mem_axi4_slave)                        ║");
        $display("║  RAM  : soc.dmem.dmem  (data_mem_burst, 1KB)                   ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  LAYERS MONITORED:                                              ║");
        $display("║   CPU-WR/RD  cpu_dcache_req/we/ready (Layer 1)                 ║");
        $display("║   DC-BUSY    dcache_current_valid/addr (Layer 2)                ║");
        $display("║   AXI-AW/W/B dcache_awaddr/wdata_axi/bresp (Layer 3)           ║");
        $display("║   AXI-AR/R   dcache_araddr/rdata (Layer 4)                     ║");
        $display("║   MEM-WR/RD  dmem.dmem.burst_wr/rd_valid (Layer 5)             ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  ⚠  KNOWN ISSUE: data_mem_burst dùng addr[9:2]                 ║");
        $display("║     → chỉ hỗ trợ địa chỉ 0x000–0x3FF (1KB)                    ║");
        $display("║     → nếu test C dùng RAM_BASE=0x1000 sẽ bị aliasing!          ║");
        $display("╚══════════════════════════════════════════════════════════════════╝\n");
    end
endtask

// ============================================================================
// FINAL REPORT
// ============================================================================
task print_final_report;
    integer ri;
    real avg_cpu, avg_wr, avg_rd;
    real dc_hit_rate;
    integer total_dc;
    begin
        $display("\n╔══════════════════════════════════════════════════════════════════╗");
        $display("║                     FINAL DEBUG REPORT                          ║");
        $display("╚══════════════════════════════════════════════════════════════════╝\n");

        $display("┌─── TRANSACTION COUNT ────────────────────────────────────────────┐");
        $display("│  CPU-WR : %-6d   CPU-RD : %-6d                              │", cnt_cpu_wr, cnt_cpu_rd);
        $display("│  AXI-AW : %-6d   AXI-W  : %-6d beats                       │", cnt_axi_aw, cnt_axi_w_beat);
        $display("│  AXI-AR : %-6d   AXI-R  : %-6d beats                       │", cnt_axi_ar, cnt_axi_r_beat);
        $display("│  AXI-B  : %-6d                                              │", cnt_axi_b);
        $display("│  RAM-WR : %-6d   RAM-RD : %-6d                              │", cnt_ram_wr, cnt_ram_rd);
        $display("│  Total cycles: %-8d                                      │", cycle_count);
        $display("└──────────────────────────────────────────────────────────────────┘\n");

        $display("┌─── LATENCY ANALYSIS ─────────────────────────────────────────────┐");
        if (cpu_lat_cnt > 0) begin
            avg_cpu = cpu_lat_sum * 1.0 / cpu_lat_cnt;
            $display("│  CPU req→ready : avg=%5.1f  min=%4d  max=%4d  n=%6d        │",
                     avg_cpu, cpu_lat_min, cpu_lat_max, cpu_lat_cnt);
        end
        if (wr_lat_cnt > 0) begin
            avg_wr = wr_lat_sum * 1.0 / wr_lat_cnt;
            $display("│  AXI AW→B      : avg=%5.1f  min=%4d  max=%4d  n=%6d        │",
                     avg_wr, wr_lat_min, wr_lat_max, wr_lat_cnt);
        end
        if (rd_lat_cnt > 0) begin
            avg_rd = rd_lat_sum * 1.0 / rd_lat_cnt;
            $display("│  AXI AR→R-last : avg=%5.1f  min=%4d  max=%4d  n=%6d        │",
                     avg_rd, rd_lat_min, rd_lat_max, rd_lat_cnt);
        end
        $display("└──────────────────────────────────────────────────────────────────┘\n");

        total_dc = dcache_hits + dcache_misses;
        dc_hit_rate = (total_dc > 0) ? (dcache_hits * 100.0 / total_dc) : 0.0;
        $display("┌─── DCACHE STATISTICS ────────────────────────────────────────────┐");
        $display("│  Hits=%0d  Misses=%0d  Writes=%0d  Total=%0d  HitRate=%.1f%%",
                 dcache_hits, dcache_misses, dcache_writes, total_dc, dc_hit_rate);
        $display("└──────────────────────────────────────────────────────────────────┘\n");

        $display("┌─── SCOREBOARD RESULT ────────────────────────────────────────────┐");
        $display("│  Tracked addresses : %-6d                                    │", sb_cnt);
        $display("│  Errors detected   : %-6d  %s                          │",
                 error_count, (error_count == 0) ? "✓ ALL CORRECT" : "✗ DATA ERRORS!");
        $display("└──────────────────────────────────────────────────────────────────┘\n");

        // Dump scoreboard nếu có lỗi
        if (error_count > 0) begin
            $display("┌─── SCOREBOARD DUMP (last written per address) ───────────────────┐");
            for (ri = 0; ri < sb_cnt && ri < 32; ri = ri + 1)
                $display("│  0x%08h → 0x%08h", sb_addr[ri], sb_data[ri]);
            if (sb_cnt > 32)
                $display("│  ... (%0d more)", sb_cnt - 32);
            $display("└──────────────────────────────────────────────────────────────────┘\n");
        end

        $display("┌─── REGISTER FILE ────────────────────────────────────────────────┐");
        for (ri = 0; ri < 32; ri = ri + 1) begin
            if (soc.cpu.register_file.registers[ri] != 0 || ri == 2 || ri == 10) begin
                $display("│  x%-2d = 0x%08h  (%10d)", ri,
                         soc.cpu.register_file.registers[ri],
                         soc.cpu.register_file.registers[ri]);
            end
        end
        $display("│");
        $display("│  a0 (x10) = 0x%08h", soc.cpu.register_file.registers[10]);
        if (soc.cpu.register_file.registers[10] == 0) begin
            $display("│  → ✓ 0x00000000 : ALL C TESTS PASS");
        end else begin
            $display("│  → ✗ Bitmask FAIL:");
            if (soc.cpu.register_file.registers[10] & 32'h01) $display("│     [bit0] TEST1 FAIL — basic sw/lw");
            if (soc.cpu.register_file.registers[10] & 32'h02) $display("│     [bit1] TEST2 FAIL — halfword sh/lhu");
            if (soc.cpu.register_file.registers[10] & 32'h04) $display("│     [bit2] TEST3 FAIL — byte sb/lbu + endian");
            if (soc.cpu.register_file.registers[10] & 32'h08) $display("│     [bit3] TEST4 FAIL — sequential (cache warm)");
            if (soc.cpu.register_file.registers[10] & 32'h10) $display("│     [bit4] TEST5 FAIL — stride (cache miss)");
            if (soc.cpu.register_file.registers[10] & 32'h20) $display("│     [bit5] TEST6 FAIL — ASCON 320-bit block");
            if (soc.cpu.register_file.registers[10] & 32'h40) $display("│     [bit6] TEST7 FAIL — RAW hazard");
            if (soc.cpu.register_file.registers[10] & 32'h80) $display("│     [bit7] TEST8 FAIL — boundary addr");
        end
        $display("└──────────────────────────────────────────────────────────────────┘\n");

        // DMEM FSM state cuối
        $display("┌─── DMEM FSM STATE AT END ────────────────────────────────────────┐");
        $display("│  wr_state = %0d (%s)",
                 dmem_wr_state,
                 (dmem_wr_state == 3'd0) ? "WR_IDLE" :
                 (dmem_wr_state == 3'd1) ? "WR_ADDR" :
                 (dmem_wr_state == 3'd2) ? "WR_BURST" :
                 (dmem_wr_state == 3'd3) ? "WR_RESP" : "???");
        $display("│  rd_state = %0d (%s)",
                 dmem_rd_state,
                 (dmem_rd_state == 2'd0) ? "RD_IDLE" :
                 (dmem_rd_state == 2'd1) ? "RD_BURST" : "???");
        $display("│  write_addr (latched) = 0x%08h", dmem_wr_addr_r);
        $display("│  read_addr  (latched) = 0x%08h", dmem_rd_addr_r);
        $display("└──────────────────────────────────────────────────────────────────┘\n");
    end
endtask

endmodule