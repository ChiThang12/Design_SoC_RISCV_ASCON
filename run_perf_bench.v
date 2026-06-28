`timescale 1ns/1ps

`include "soc_hs.v"

// ============================================================================
//  run_perf_bench.v — ASCON Performance Baseline Testbench
//
//  Firmware : gnu_toolchain/tests/test_ascon_bench.hex
//             (CPU-direct + DMA 1-block + DMA 16-block encryption)
//
//  Metrics  :
//    [FW]  CPU cycles, DMA cycles, throughput (Mbps), latency
//    [TB]  Total cycles, instr retired, stall, cache hit-rate,
//          AXI transaction count per master, ASCON events
//
//  Build:
//    cd gnu_toolchain
//    ./compile_c_to_hex.sh -i tests/test_ascon_bench.c \
//                           -o tests/test_ascon_bench.hex -O 1
//
//  Run:
//    ~/workflow/urun_verilog.sh run_perf_bench.v
//    rtk read run_perf_bench.log
// ============================================================================

`ifndef IMEM_INIT_FILE
  `define IMEM_INIT_FILE "gnu_toolchain/tests/test_ascon_bench.hex"
`endif

`define TIMEOUT   10000000
`define BAUD_DIV  868
`define CLK_MHZ   100

module run_perf_bench;

parameter CLK_PERIOD = 10;

// ── Clock & Reset ──────────────────────────────────────────────────────────────
reg clk;
reg por_n_r;
reg ext_rst_n_r;

initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ── JTAG (idle) ────────────────────────────────────────────────────────────────
reg  jtag_tck_r;
reg  jtag_tms_r;
reg  jtag_tdi_r;
wire jtag_tdo_w;

// ── UART ───────────────────────────────────────────────────────────────────────
wire uart_tx_w;
assign uart_rx_w = 1'b1;

// ── GPIO ───────────────────────────────────────────────────────────────────────
wire [31:0] gpio_w;
reg  [31:0] gpio_in_r;
assign gpio_w = gpio_in_r;

// ── WDT ────────────────────────────────────────────────────────────────────────
wire wdt_rst_req_w;

// ── DUT ────────────────────────────────────────────────────────────────────────
soc_hs #(.SIM_MODE(1), .IMEM_INIT_FILE(`IMEM_INIT_FILE)) chip (
    .clk_in     (clk),
    .por_n      (por_n_r),
    .ext_rst_n  (ext_rst_n_r),
    .uart_tx    (uart_tx_w),
    .uart_rx    (uart_rx_w),
    .tck        (jtag_tck_r),
    .tms        (jtag_tms_r),
    .tdi        (jtag_tdi_r),
    .tdo        (jtag_tdo_w),
    .spi_sck    (),
    .spi_mosi   (),
    .spi_miso   (1'b1),
    .spi_cs_n   (),
    .gpio       (gpio_w),
    .wdt_rst_req(wdt_rst_req_w)
);

// ============================================================================
// RTL Wire Taps
// ============================================================================

// ── CPU Pipeline ───────────────────────────────────────────────────────────────
wire [31:0] pc_if    = chip.u_soc_top.u_cpu.pc_if;
wire [31:0] instr_if = chip.u_soc_top.u_cpu.instr_if;
wire        stall_if = chip.u_soc_top.u_cpu.stall_if;

// ── Cache Stats ────────────────────────────────────────────────────────────────
wire [31:0] ic_hits_w  = chip.u_soc_top.icache_stat_hits;
wire [31:0] ic_miss_w  = chip.u_soc_top.icache_stat_misses;
wire [31:0] dc_hits_w  = chip.u_soc_top.dcache_stat_hits;
wire [31:0] dc_miss_w  = chip.u_soc_top.dcache_stat_misses;
wire [31:0] dc_wr_w    = chip.u_soc_top.dcache_stat_writes;

// ── Reset / Boot ───────────────────────────────────────────────────────────────
wire fabric_rst_n_w = chip.u_soc_top.fabric_rst_n;
wire cpu_rst_n_w    = chip.u_soc_top.cpu_rst_n;
wire boot_done_w    = chip.u_soc_top.boot_done;

// ── Status — for halt detection ──────────────────────────────────────────────────
wire        uart_active_w   = chip.u_soc_top.uart_active;
wire        lsu_idle_w      = chip.u_soc_top.u_cpu.lsu_idle;
wire        dcache_req_w    = chip.u_soc_top.cpu_dcache_req;
wire        dcache_ready_w  = chip.u_soc_top.dcache_cpu_ready;

// ── ASCON Internal ─────────────────────────────────────────────────────────────
wire        ascon_core_start = chip.u_soc_top.u_ascon.u_slave.core_start;
wire        ascon_core_done  = chip.u_soc_top.u_ascon.u_slave.core_done;
wire        ascon_dma_start  = chip.u_soc_top.u_ascon.u_slave.dma_start;
wire        ascon_dma_done   = chip.u_soc_top.u_ascon.u_slave.status_dma_done;
wire        ascon_error      = chip.u_soc_top.u_ascon.u_slave.status_dma_error |
                               chip.u_soc_top.u_ascon.u_slave.status_error;
wire [31:0] ascon_src        = chip.u_soc_top.u_ascon.u_slave.reg_dma_src;
wire [31:0] ascon_dst        = chip.u_soc_top.u_ascon.u_slave.reg_dma_dst;
wire [31:0] ascon_len        = chip.u_soc_top.u_ascon.u_slave.reg_dma_len;

// ── AXI Master Transactions ────────────────────────────────────────────────────
wire m0_ar_fire = chip.u_soc_top.m0_arvalid && chip.u_soc_top.m0_arready;
wire m1_ar_fire = chip.u_soc_top.m1_arvalid && chip.u_soc_top.m1_arready;
wire m1_aw_fire = chip.u_soc_top.m1_awvalid && chip.u_soc_top.m1_awready;
wire m2_ar_fire = chip.u_soc_top.m2_arvalid && chip.u_soc_top.m2_arready;
wire m2_aw_fire = chip.u_soc_top.m2_awvalid && chip.u_soc_top.m2_awready;

// ============================================================================
// TB Counters
// ============================================================================
integer cycle_count;
integer tb_instr_cnt;
integer tb_stall_cnt;
reg     program_done;
reg [31:0] prev_pc;
integer    halt_cnt;

integer m0_ar_cnt, m1_ar_cnt, m1_aw_cnt, m2_ar_cnt, m2_aw_cnt;

reg prev_ascon_core_start, prev_ascon_core_done;
reg prev_ascon_dma_start,  prev_ascon_dma_done;
reg prev_ascon_error;
integer ascon_core_start_cnt, ascon_core_done_cnt;
integer ascon_dma_start_cnt,  ascon_dma_done_cnt;
integer ascon_error_cnt;
integer ascon_dma_start_cyc [0:15];
integer ascon_dma_done_cyc  [0:15];

// ============================================================================
// Cycle Counter
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r) cycle_count = cycle_count + 1;
end

// ============================================================================
// Instruction Retire + Stall Counter
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r && cpu_rst_n_w) begin
        if (!stall_if && instr_if !== 32'h0)
            tb_instr_cnt = tb_instr_cnt + 1;
        if (stall_if)
            tb_stall_cnt = tb_stall_cnt + 1;
    end
end

// ============================================================================
// AXI Transaction Counters
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (m0_ar_fire) m0_ar_cnt = m0_ar_cnt + 1;
        if (m1_ar_fire) m1_ar_cnt = m1_ar_cnt + 1;
        if (m1_aw_fire) m1_aw_cnt = m1_aw_cnt + 1;
        if (m2_ar_fire) m2_ar_cnt = m2_ar_cnt + 1;
        if (m2_aw_fire) m2_aw_cnt = m2_aw_cnt + 1;
    end
end

// ============================================================================
// ASCON Event Counters
// ============================================================================
always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        prev_ascon_core_start <= 1'b0;
        prev_ascon_core_done  <= 1'b0;
        prev_ascon_dma_start  <= 1'b0;
        prev_ascon_dma_done   <= 1'b0;
        prev_ascon_error      <= 1'b0;
    end else begin
        prev_ascon_core_start <= ascon_core_start;
        prev_ascon_core_done  <= ascon_core_done;
        prev_ascon_dma_start  <= ascon_dma_start;
        prev_ascon_dma_done   <= ascon_dma_done;
        prev_ascon_error      <= ascon_error;
    end
end

always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (ascon_core_start && !prev_ascon_core_start) begin
            ascon_core_start_cnt = ascon_core_start_cnt + 1;
            $display("[%7d] [ASCON] CORE START #%0d", cycle_count, ascon_core_start_cnt);
        end
        if (ascon_core_done && !prev_ascon_core_done) begin
            ascon_core_done_cnt = ascon_core_done_cnt + 1;
            $display("[%7d] [ASCON] CORE DONE  #%0d", cycle_count, ascon_core_done_cnt);
        end
        if (ascon_dma_start && !prev_ascon_dma_start) begin
            if (ascon_dma_start_cnt < 16) begin
                ascon_dma_start_cyc[ascon_dma_start_cnt] = cycle_count;
            end
            ascon_dma_start_cnt = ascon_dma_start_cnt + 1;
            $display("[%7d] [ASCON] DMA START #%0d  src=0x%08h  dst=0x%08h  len=%0d",
                     cycle_count, ascon_dma_start_cnt, ascon_src, ascon_dst, ascon_len);
        end
        if (ascon_dma_done && !prev_ascon_dma_done) begin
            if (ascon_dma_done_cnt < 16) begin
                ascon_dma_done_cyc[ascon_dma_done_cnt] = cycle_count;
            end
            ascon_dma_done_cnt = ascon_dma_done_cnt + 1;
            $display("[%7d] [ASCON] DMA DONE  #%0d", cycle_count, ascon_dma_done_cnt);
        end
        if (ascon_error && !prev_ascon_error) begin
            ascon_error_cnt = ascon_error_cnt + 1;
            $display("[%7d] [ASCON] ERROR    #%0d", cycle_count, ascon_error_cnt);
        end
    end
end

// ============================================================================
// Halt Detection — halt khi CPU idle (không DCache/LSU/UART activity)
// ============================================================================
always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        halt_cnt <= 0;
    end else if (cycle_count > 50 && cpu_rst_n_w && !program_done) begin
        if (!dcache_req_w && lsu_idle_w && !uart_active_w) begin
            halt_cnt <= halt_cnt + 1;
            if (halt_cnt >= 80) begin
                program_done = 1;
                print_report("HALT LOOP");
                #(CLK_PERIOD * 2); $finish;
            end
        end else begin
            halt_cnt <= 0;
        end
    end
end

// ============================================================================
// Watchdog
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
// Waveform
// ============================================================================
initial begin
    $dumpfile("waveform_perf_bench.vcd");
    $dumpvars(0, run_perf_bench);
end


// ============================================================================
// UART Monitor — 8N1
// ============================================================================
time baud_half;
time baud_full;

reg [7:0] uart_line_buf [0:127];
integer   uart_line_len;
integer   uart_byte_cnt;
integer   uart_pass_cnt;
integer   uart_fail_cnt;

initial begin
    baud_half    = (`BAUD_DIV * CLK_PERIOD) / 2;
    baud_full    =  `BAUD_DIV * CLK_PERIOD;
    uart_line_len = 0;
    uart_byte_cnt = 0;

    forever begin
        @(negedge uart_tx_w);
        #(baud_half + baud_full);

        begin : uart_frame
            reg [7:0] rx_byte;
            integer   b;
            rx_byte = 8'h00;
            for (b = 0; b < 8; b = b + 1) begin
                rx_byte[b] = uart_tx_w;
                if (b < 7) #baud_full;
            end
            #baud_full;

            uart_byte_cnt = uart_byte_cnt + 1;

            if (rx_byte == 8'h0A) begin
                parse_uart_line();
                uart_line_len = 0;
            end else if (rx_byte != 8'h0D) begin
                if (uart_line_len < 127) begin
                    uart_line_buf[uart_line_len] = rx_byte;
                    uart_line_len = uart_line_len + 1;
                end
            end
        end
    end
end

task parse_uart_line;
    integer k;
    reg match_pass, match_fail;
    begin
        $write("[%7d] [UART] ", cycle_count);
        for (k = 0; k < uart_line_len; k = k + 1)
            $write("%s", uart_line_buf[k]);
        $display("");

        match_pass = (uart_line_len >= 6 &&
                      uart_line_buf[0]=="[" && uart_line_buf[1]=="P" &&
                      uart_line_buf[2]=="A" && uart_line_buf[3]=="S" &&
                      uart_line_buf[4]=="S" && uart_line_buf[5]=="]");
        match_fail = (uart_line_len >= 6 &&
                      uart_line_buf[0]=="[" && uart_line_buf[1]=="F" &&
                      uart_line_buf[2]=="A" && uart_line_buf[3]=="I" &&
                      uart_line_buf[4]=="L" && uart_line_buf[5]=="]");

        if (match_pass) uart_pass_cnt = uart_pass_cnt + 1;
        if (match_fail) uart_fail_cnt = uart_fail_cnt + 1;
    end
endtask

// ============================================================================
// Performance Report
// ============================================================================
task print_report;
    input [255:0] reason;
    reg [31:0] ic_total, dc_total;
    integer j;
    real cpi, ipc, ic_rate, dc_rate;
    integer bw_cycles;
    real bw_bpc, bw_mbps;
    begin
        ic_total = ic_hits_w + ic_miss_w;
        dc_total = dc_hits_w + dc_miss_w;
        cpi = (tb_instr_cnt > 0) ? (1.0 * cycle_count / tb_instr_cnt) : 0.0;
        ipc = (cycle_count > 0) ? (1.0 * tb_instr_cnt / cycle_count) : 0.0;
        ic_rate = (ic_total > 0) ? (100.0 * ic_hits_w / ic_total) : 0.0;
        dc_rate = (dc_total > 0) ? (100.0 * dc_hits_w / dc_total) : 0.0;

        $display("");
        $display("+=================================================================+");
        $display("|         ASCON PERFORMANCE BENCHMARK REPORT                       |");
        $display("|  Stop: %-53s|", reason);
        $display("+=================================================================+");

        $display("");
        $display("+--- (1) TEST RESULT -----------------------------------------------+");
        $display("|  [PASS] count: %0d    [FAIL] count: %0d", uart_pass_cnt, uart_fail_cnt);
        if (uart_pass_cnt > 0 && uart_fail_cnt == 0)
            $display("|  [OK]  ALL TESTS PASSED");
        else if (uart_fail_cnt > 0)
            $display("|  [!!]  SOME TESTS FAILED");
        $display("|  a0 (x10)   = 0x%08h", chip.u_soc_top.u_cpu.register_file.registers[10]);
        $display("|  Final PC   = 0x%08h", pc_if);
        $display("|  DCache state=%0d other_state=%b",
                 chip.u_soc_top.u_dcache.controller_inst.state,
                 chip.u_soc_top.u_dcache.controller_inst.DCACHE_STATE_IDLE);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (2) CPU PERFORMANCE -------------------------------------------+");
        $display("|  Sim cycles     : %0d  (@ %0d MHz = %.2f us)",
                 cycle_count, `CLK_MHZ, cycle_count * 10.0 / 1000.0);
        $display("|  Instructions   : %0d", tb_instr_cnt);
        $display("|  Stall cycles   : %0d  (%.1f%%)",
                 tb_stall_cnt, cycle_count > 0 ? 100.0 * tb_stall_cnt / cycle_count : 0.0);
        $display("|  CPI            : %.2f", cpi);
        $display("|  IPC            : %.2f", ipc);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (3) CACHE STATS -----------------------------------------------+");
        $display("|  ICache  hits=%-8d  misses=%-8d  total=%-8d  rate=%.1f%%",
                 ic_hits_w, ic_miss_w, ic_total, ic_rate);
        $display("|  DCache  hits=%-8d  misses=%-8d  total=%-8d  rate=%.1f%%  writes=%0d",
                 dc_hits_w, dc_miss_w, dc_total, dc_rate, dc_wr_w);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (4) AXI BUS TRANSACTIONS --------------------------------------+");
        $display("|  Master       AR cnt    AW cnt");
        $display("|  M0 (ICache)  %-8d  %-8d", m0_ar_cnt, 0);
        $display("|  M1 (DCache)  %-8d  %-8d", m1_ar_cnt, m1_aw_cnt);
        $display("|  M2 (ASCON)   %-8d  %-8d", m2_ar_cnt, m2_aw_cnt);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("+--- (5) ASCON EVENTS ----------------------------------------------+");
        $display("|  Core start   : %0d", ascon_core_start_cnt);
        $display("|  Core done    : %0d", ascon_core_done_cnt);
        $display("|  DMA start    : %0d", ascon_dma_start_cnt);
        $display("|  DMA done     : %0d", ascon_dma_done_cnt);
        $display("|  Errors       : %0d", ascon_error_cnt);
        $display("+----------------------------------------------------------------+");

        if (ascon_dma_start_cnt > 0 && ascon_dma_done_cnt > 0) begin
            $display("");
            $display("+--- (6) DMA BANDWIDTH -------------------------------------------+");
            $display("|  Op#  Bytes    Cycles    Bits/Cycle    Mbps@100MHz");
            $display("|  -------------------------------------------------------");
            for (j = 0; j < ascon_dma_done_cnt && j < 16; j = j + 1) begin
                bw_cycles = ascon_dma_done_cyc[j] - ascon_dma_start_cyc[j];
                bw_bpc    = (bw_cycles > 0) ? (1.0 * ascon_len * 8 / bw_cycles) : 0.0;
                bw_mbps   = bw_bpc * 100.0;
                $display("|  %-4d  %-7d  %-8d  %-14.4f  %-14.2f",
                         j+1, ascon_len, bw_cycles, bw_bpc, bw_mbps);
            end
            $display("+----------------------------------------------------------------+");
        end

        $display("");
        $display("+--- (7) UART OUTPUT SUMMARY ----------------------------------------+");
        $display("|  Bytes transmitted: %0d", uart_byte_cnt);
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("====================================================================");
        $display("  ASCON Baseline Performance Measurement Complete");
        $display("  %0d cycles @ %0d MHz = %.2f us",
                 cycle_count, `CLK_MHZ, cycle_count * 10.0 / 1000.0);
        $display("====================================================================");
        $display("");
    end
endtask

// ============================================================================
// Main Sequence — Reset + Boot
// ============================================================================
integer _j;
initial begin
    jtag_tck_r    = 1'b0;
    jtag_tms_r    = 1'b1;
    jtag_tdi_r    = 1'b0;
    gpio_in_r     = 32'h0;
    cycle_count   = 0;
    tb_instr_cnt  = 0;
    tb_stall_cnt  = 0;
    program_done  = 0;
    prev_pc       = 32'h0;
    halt_cnt      = 0;
    uart_line_len = 0;
    uart_byte_cnt = 0;
    uart_pass_cnt = 0;
    uart_fail_cnt = 0;
    m0_ar_cnt = 0; m1_ar_cnt = 0; m1_aw_cnt = 0; m2_ar_cnt = 0; m2_aw_cnt = 0;
    ascon_core_start_cnt = 0; ascon_core_done_cnt = 0;
    ascon_dma_start_cnt  = 0; ascon_dma_done_cnt  = 0;
    ascon_error_cnt      = 0;

    for (_j = 0; _j < 128; _j = _j + 1) uart_line_buf[_j] = 8'h00;

    $display("════════════════════════════════════════════════════════");
    $display("  run_perf_bench.v — ASCON Performance Baseline TB");
    $display("  IMEM: %s", `IMEM_INIT_FILE);
    $display("  CLK : %0d MHz    TIMEOUT: %0d cycles", `CLK_MHZ, `TIMEOUT);
    $display("════════════════════════════════════════════════════════");

    // Reset sequence
    por_n_r     = 1'b0;
    ext_rst_n_r = 1'b0;
    repeat(20) @(posedge clk);

    ext_rst_n_r = 1'b1;
    $display("[%7d] ext_rst_n released", cycle_count);

    repeat(1020) @(posedge clk);

    por_n_r = 1'b1;
    $display("[%7d] por_n released — waiting fabric_rst_n...", cycle_count);

    @(posedge fabric_rst_n_w);
    $display("[%7d] fabric_rst_n released — boot_ctrl loading IMEM...", cycle_count);

    @(posedge boot_done_w);
    $display("[%7d] boot_done — waiting cpu_rst_n...", cycle_count);

    @(posedge cpu_rst_n_w);
    repeat(3) @(posedge clk);
    $display("[%7d] cpu_rst_n released — CPU executing\n", cycle_count);

    wait(program_done);
end

endmodule
