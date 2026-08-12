`timescale 1ns/1ps

`include "soc_hs.v"

`ifndef TEST_HEX
`define TEST_HEX "gnu_toolchain/tests_dualcore/test_dualcore_basic.hex"
`endif

`ifndef SCENARIO_NAME
`define SCENARIO_NAME "dualcore_basic"
`endif

`ifndef EXPECT_SIG0
`define EXPECT_SIG0 32'hD00D_CAFE
`endif

`ifndef EXPECT_SIG1
`define EXPECT_SIG1 32'h1357_9BDF
`endif

`ifndef HEARTBEAT_MIN
`define HEARTBEAT_MIN 16
`endif

`ifndef DC_REQ_MIN
`define DC_REQ_MIN 8
`endif

`ifndef AUX0_CHECK_ENABLE
`define AUX0_CHECK_ENABLE 0
`endif

`ifndef AUX1_CHECK_ENABLE
`define AUX1_CHECK_ENABLE 0
`endif

`ifndef EXPECT_AUX0
`define EXPECT_AUX0 32'h0000_0000
`endif

`ifndef EXPECT_AUX1
`define EXPECT_AUX1 32'h0000_0000
`endif

`ifndef GPIO_CHECK_ENABLE
`define GPIO_CHECK_ENABLE 0
`endif

`ifndef EXPECT_GPIO
`define EXPECT_GPIO 32'h0000_0000
`endif

`ifndef DMA_CONTEXT_CHECK_ENABLE
`define DMA_CONTEXT_CHECK_ENABLE 0
`endif

`ifndef EXPECT_DMA_CONTEXT
`define EXPECT_DMA_CONTEXT 1'b0
`endif

`ifndef TIMEOUT_CYCLES
`define TIMEOUT_CYCLES 400000
`endif

module tb_soc_dualcore_suite;

parameter CLK_PERIOD = 10;

reg clk;
reg por_n;
reg ext_rst_n;
reg jtag_tck;
reg jtag_tms;
reg jtag_tdi;
wire jtag_tdo;
wire uart_tx;
wire spi_sck;
wire spi_mosi;
wire spi_cs_n;
wire wdt_rst_req;
wire [31:0] gpio;

localparam [31:0] EXPECT_SIG0_VALUE = `EXPECT_SIG0;
localparam [31:0] EXPECT_SIG1_VALUE = `EXPECT_SIG1;
localparam [31:0] RESULT_RUNNING    = 32'hCAFE_0001;
localparam [31:0] RESULT_FAIL       = 32'hDEAD_0001;
localparam integer HEARTBEAT_TARGET = `HEARTBEAT_MIN;
localparam integer DC_REQ_TARGET    = `DC_REQ_MIN;
localparam integer TIMEOUT_TARGET   = `TIMEOUT_CYCLES;
localparam integer AUX0_CHECK       = `AUX0_CHECK_ENABLE;
localparam integer AUX1_CHECK       = `AUX1_CHECK_ENABLE;
localparam [31:0] EXPECT_AUX0_VALUE = `EXPECT_AUX0;
localparam [31:0] EXPECT_AUX1_VALUE = `EXPECT_AUX1;
localparam integer GPIO_CHECK       = `GPIO_CHECK_ENABLE;
localparam [31:0] EXPECT_GPIO_VALUE = `EXPECT_GPIO;
localparam integer DMA_CONTEXT_CHECK = `DMA_CONTEXT_CHECK_ENABLE;
localparam         EXPECT_DMA_CONTEXT_VALUE = `EXPECT_DMA_CONTEXT;

integer cycles;
integer core0_dc_req_count;
integer core1_dc_req_count;
reg prev_core0_dc_req;
reg prev_core1_dc_req;
reg pass_reported;
reg dma_context_seen;

`ifdef H3_BENCH_TRACE
localparam [31:0] H3_STAGE_SWITCH_BEGIN = 32'd10;
localparam [31:0] H3_STAGE_SWITCH_DONE  = 32'd19;
localparam [31:0] H3_STAGE_CTX0_RUN     = 32'd20;
localparam [31:0] H3_STAGE_CTX0_DONE    = 32'd21;
localparam [31:0] H3_STAGE_CTX1_RUN     = 32'd30;
localparam [31:0] H3_STAGE_CTX1_DONE    = 32'd31;
integer h3_ctx_change_count;
integer h3_ctx_window_count;
integer h3_ctx_interval_count;
integer h3_ctx_last_cycle;
integer h3_ctx_delta_sum;
integer h3_ctx_delta_min;
integer h3_ctx_delta_max;
reg     h3_prev_context_sel;
reg     h3_prev_core_start;
reg     h3_prev_core_done;
reg     h3_core_active;
reg     h3_core_context;
integer h3_core_start_cycle;
integer h3_core_op_count;
integer h3_core_latency_sum;
integer h3_core_latency_min;
integer h3_core_latency_max;
integer h3_latency;
real    h3_core_tput_mbps;
real    h3_avg_core_latency;
real    h3_avg_ctx_switch_interval;
`endif

wire core0_dc_req;
wire core1_dc_req;

wire [31:0] dcache0_writes;
wire [31:0] dcache1_writes;
wire [31:0] dcache0_hits;
wire [31:0] dcache1_hits;
wire [31:0] dcache0_peer_snoop_reqs;
wire [31:0] dcache1_peer_snoop_reqs;
wire [31:0] dcache0_peer_snoop_hits;
wire [31:0] dcache1_peer_snoop_hits;
wire [31:0] dcache0_c2c_forwards;
wire [31:0] dcache1_c2c_forwards;
wire [31:0] dcache0_c2c_fill_cycles;
wire [31:0] dcache1_c2c_fill_cycles;
wire [31:0] dcache0_mem_refills;
wire [31:0] dcache1_mem_refills;

wire [31:0] dmem_sig0;
wire [31:0] dmem_sig1;
wire [31:0] dmem_count;
wire [31:0] dmem_heartbeat;
wire [31:0] dmem_result;
wire [31:0] dmem_aux0;
wire [31:0] dmem_aux1;

assign core0_dc_req = chip.u_soc_top.cpu_dcache_req;
assign core1_dc_req = chip.u_soc_top.cpu1_dcache_req;
assign dcache0_writes = chip.u_soc_top.dcache0_stat_writes;
assign dcache1_writes = chip.u_soc_top.dcache1_stat_writes;
assign dcache0_hits = chip.u_soc_top.dcache0_stat_hits;
assign dcache1_hits = chip.u_soc_top.dcache1_stat_hits;
assign dcache0_peer_snoop_reqs = chip.u_soc_top.dcache0_stat_peer_snoop_reqs;
assign dcache1_peer_snoop_reqs = chip.u_soc_top.dcache1_stat_peer_snoop_reqs;
assign dcache0_peer_snoop_hits = chip.u_soc_top.dcache0_stat_peer_snoop_hits;
assign dcache1_peer_snoop_hits = chip.u_soc_top.dcache1_stat_peer_snoop_hits;
assign dcache0_c2c_forwards = chip.u_soc_top.dcache0_stat_c2c_forwards;
assign dcache1_c2c_forwards = chip.u_soc_top.dcache1_stat_c2c_forwards;
assign dcache0_c2c_fill_cycles = chip.u_soc_top.dcache0_stat_c2c_fill_cycles;
assign dcache1_c2c_fill_cycles = chip.u_soc_top.dcache1_stat_c2c_fill_cycles;
assign dcache0_mem_refills = chip.u_soc_top.dcache0_stat_mem_refills;
assign dcache1_mem_refills = chip.u_soc_top.dcache1_stat_mem_refills;
assign dmem_sig0 = chip.u_soc_top.u_dmem.dmem.memory[0];
assign dmem_sig1 = chip.u_soc_top.u_dmem.dmem.memory[1];
assign dmem_count = chip.u_soc_top.u_dmem.dmem.memory[2];
assign dmem_heartbeat = chip.u_soc_top.u_dmem.dmem.memory[3];
assign dmem_result = chip.u_soc_top.u_dmem.dmem.memory[4];
assign dmem_aux0 = chip.u_soc_top.u_dmem.dmem.memory[5];
assign dmem_aux1 = chip.u_soc_top.u_dmem.dmem.memory[6];

initial clk = 1'b0;
always #(CLK_PERIOD/2) clk = ~clk;

soc_hs #(
    .SIM_MODE(1),
    .IMEM_INIT_FILE(`TEST_HEX)
) chip (
    .clk_in      (clk),
    .por_n       (por_n),
    .ext_rst_n   (ext_rst_n),
    .uart_tx     (uart_tx),
    .uart_rx     (1'b1),
    .tck         (jtag_tck),
    .tms         (jtag_tms),
    .tdi         (jtag_tdi),
    .tdo         (jtag_tdo),
    .spi_sck     (spi_sck),
    .spi_mosi    (spi_mosi),
    .spi_miso    (1'b1),
    .spi_cs_n    (spi_cs_n),
    .gpio        (gpio),
    .wdt_rst_req (wdt_rst_req)
);

initial begin
    por_n              = 1'b0;
    ext_rst_n          = 1'b0;
    jtag_tck           = 1'b0;
    jtag_tms           = 1'b1;
    jtag_tdi           = 1'b0;
    cycles             = 0;
    core0_dc_req_count = 0;
    core1_dc_req_count = 0;
    prev_core0_dc_req  = 1'b0;
    prev_core1_dc_req  = 1'b0;
    pass_reported      = 1'b0;
    dma_context_seen    = 1'b0;
`ifdef H3_BENCH_TRACE
    h3_ctx_change_count = 0;
    h3_ctx_window_count = 0;
    h3_ctx_interval_count = 0;
    h3_ctx_last_cycle = 0;
    h3_ctx_delta_sum = 0;
    h3_ctx_delta_min = 32'h7fff_ffff;
    h3_ctx_delta_max = 0;
    h3_prev_context_sel = 1'b0;
    h3_prev_core_start = 1'b0;
    h3_prev_core_done = 1'b0;
    h3_core_active = 1'b0;
    h3_core_context = 1'b0;
    h3_core_start_cycle = 0;
    h3_core_op_count = 0;
    h3_core_latency_sum = 0;
    h3_core_latency_min = 32'h7fff_ffff;
    h3_core_latency_max = 0;
    h3_latency = 0;
    h3_core_tput_mbps = 0.0;
    h3_avg_core_latency = 0.0;
    h3_avg_ctx_switch_interval = 0.0;
`endif

    repeat (20) @(posedge clk);
    ext_rst_n = 1'b1;
    repeat (12) @(posedge clk);
    por_n = 1'b1;
end

`ifdef BASELINE_REG_TRACE
always @(posedge clk) begin
    if (chip.u_soc_top.s2_awvalid && chip.u_soc_top.s2_awready) begin
        $display("[BASE-TRACE] cycle=%0d AW addr=%08x wr_state=%0d awready=%0b wready=%0b",
                 cycles,
                 chip.u_soc_top.s2_awaddr,
                 chip.u_soc_top.u_ascon.u_slave.wr_state,
                 chip.u_soc_top.s2_awready,
                 chip.u_soc_top.s2_wready);
    end
    if (chip.u_soc_top.s2_wvalid && chip.u_soc_top.s2_wready) begin
        $display("[BASE-TRACE] cycle=%0d W data=%08x strb=%0h last=%0b wr_state=%0d lat_addr=%03x core_start=%0b core_busy=%0b",
                 cycles,
                 chip.u_soc_top.s2_wdata,
                 chip.u_soc_top.s2_wstrb,
                 chip.u_soc_top.s2_wlast,
                 chip.u_soc_top.u_ascon.u_slave.wr_state,
                 chip.u_soc_top.u_ascon.u_slave.wr_addr_lat,
                 chip.u_soc_top.u_ascon.u_slave.core_start,
                 chip.u_soc_top.u_ascon.core_busy_w);
    end
    if (chip.u_soc_top.s2_bvalid && chip.u_soc_top.s2_bready) begin
        $display("[BASE-TRACE] cycle=%0d B resp=%0b wr_state=%0d core_start=%0b core_start_mux=%0b core_busy=%0b core_done=%0b status=%08x",
                 cycles,
                 chip.u_soc_top.s2_bresp,
                 chip.u_soc_top.u_ascon.u_slave.wr_state,
                 chip.u_soc_top.u_ascon.u_slave.core_start,
                 chip.u_soc_top.u_ascon.core_start_mux,
                 chip.u_soc_top.u_ascon.core_busy_w,
                 chip.u_soc_top.u_ascon.core_done_w,
                 chip.u_soc_top.u_ascon.u_slave.status_word);
    end
    if (chip.u_soc_top.s2_arvalid && chip.u_soc_top.s2_arready) begin
        $display("[BASE-TRACE] cycle=%0d AR addr=%08x rd_state=%0d status=%08x",
                 cycles,
                 chip.u_soc_top.s2_araddr,
                 chip.u_soc_top.u_ascon.u_slave.rd_state,
                 chip.u_soc_top.u_ascon.u_slave.status_word);
    end
    if (chip.u_soc_top.s2_rvalid && chip.u_soc_top.s2_rready) begin
        $display("[BASE-TRACE] cycle=%0d R data=%08x last=%0b rd_state=%0d core_busy=%0b core_done=%0b status=%08x",
                 cycles,
                 chip.u_soc_top.s2_rdata,
                 chip.u_soc_top.s2_rlast,
                 chip.u_soc_top.u_ascon.u_slave.rd_state,
                 chip.u_soc_top.u_ascon.core_busy_w,
                 chip.u_soc_top.u_ascon.core_done_w,
                 chip.u_soc_top.u_ascon.u_slave.status_word);
    end
end
`endif

always @(posedge clk) begin
    cycles <= cycles + 1;

    if (!prev_core0_dc_req && core0_dc_req)
        core0_dc_req_count <= core0_dc_req_count + 1;
    if (!prev_core1_dc_req && core1_dc_req)
        core1_dc_req_count <= core1_dc_req_count + 1;

    prev_core0_dc_req <= core0_dc_req;
    prev_core1_dc_req <= core1_dc_req;

    if (DMA_CONTEXT_CHECK &&
        chip.u_soc_top.u_ascon.dma_busy_w &&
        chip.u_soc_top.u_ascon.dma_context_id_active_w == EXPECT_DMA_CONTEXT_VALUE)
        dma_context_seen <= 1'b1;

`ifdef H3_BENCH_TRACE
    if (chip.u_soc_top.u_ascon.u_slave.reg_context_sel != h3_prev_context_sel) begin
        h3_ctx_change_count = h3_ctx_change_count + 1;
        if (dmem_count == H3_STAGE_SWITCH_BEGIN) begin
            h3_ctx_window_count = h3_ctx_window_count + 1;
            if (h3_ctx_window_count > 1) begin
                h3_latency = cycles - h3_ctx_last_cycle;
                h3_ctx_interval_count = h3_ctx_interval_count + 1;
                h3_ctx_delta_sum = h3_ctx_delta_sum + h3_latency;
                if (h3_latency < h3_ctx_delta_min)
                    h3_ctx_delta_min = h3_latency;
                if (h3_latency > h3_ctx_delta_max)
                    h3_ctx_delta_max = h3_latency;
                $display("[H3-BENCH] context_switch idx=%0d window_idx=%0d cycle=%0d context=%0d interval_cycles=%0d",
                         h3_ctx_change_count,
                         h3_ctx_window_count,
                         cycles,
                         chip.u_soc_top.u_ascon.u_slave.reg_context_sel,
                         h3_latency);
            end else begin
                $display("[H3-BENCH] context_switch idx=%0d window_idx=%0d cycle=%0d context=%0d interval_cycles=N/A",
                         h3_ctx_change_count,
                         h3_ctx_window_count,
                         cycles,
                         chip.u_soc_top.u_ascon.u_slave.reg_context_sel);
            end
        end else begin
            $display("[H3-BENCH] context_switch idx=%0d cycle=%0d context=%0d interval_cycles=N/A stage=%0d",
                     h3_ctx_change_count,
                     cycles,
                     chip.u_soc_top.u_ascon.u_slave.reg_context_sel,
                     dmem_count);
        end
        h3_ctx_last_cycle = cycles;
        h3_prev_context_sel = chip.u_soc_top.u_ascon.u_slave.reg_context_sel;
    end

    if (!h3_prev_core_start && chip.u_soc_top.u_ascon.core_start_mux &&
        (dmem_count == H3_STAGE_CTX0_RUN || dmem_count == H3_STAGE_CTX1_RUN)) begin
        h3_core_active = 1'b1;
        h3_core_context = chip.u_soc_top.u_ascon.u_slave.reg_context_active;
        h3_core_start_cycle = cycles;
        $display("[H3-BENCH] core_start cycle=%0d context=%0d",
                 cycles, h3_core_context);
    end

    if (!h3_prev_core_done && chip.u_soc_top.u_ascon.core_done_w && h3_core_active) begin
        h3_latency = cycles - h3_core_start_cycle;
        h3_core_op_count = h3_core_op_count + 1;
        h3_core_latency_sum = h3_core_latency_sum + h3_latency;
        if (h3_latency < h3_core_latency_min)
            h3_core_latency_min = h3_latency;
        if (h3_latency > h3_core_latency_max)
            h3_core_latency_max = h3_latency;
        h3_core_tput_mbps = (64.0 * 100.0) / h3_latency;
        $display("[H3-BENCH] core_done op=%0d cycle=%0d context=%0d active_cycles=%0d throughput_mbps=%0.2f",
                 h3_core_op_count,
                 cycles,
                 h3_core_context,
                 h3_latency,
                 h3_core_tput_mbps);
        h3_core_active = 1'b0;
    end

    h3_prev_core_start = chip.u_soc_top.u_ascon.core_start_mux;
    h3_prev_core_done = chip.u_soc_top.u_ascon.core_done_w;
`endif

    if (dmem_result == RESULT_FAIL) begin
        $display("[FAIL] %s firmware reported RESULT_FAIL at cycle %0d", `SCENARIO_NAME, cycles);
        $display("  sig0=%08x sig1=%08x heartbeat=%0d count=%0d aux0=%08x aux1=%08x gpio=%08x",
                 dmem_sig0, dmem_sig1, dmem_heartbeat, dmem_count, dmem_aux0, dmem_aux1, gpio);
        $display("  dmem ct/tag: ct0=%08x ct1=%08x tag0=%08x tag1=%08x tag2=%08x tag3=%08x",
                 chip.u_soc_top.u_dmem.dmem.memory[168],
                 chip.u_soc_top.u_dmem.dmem.memory[169],
                 chip.u_soc_top.u_dmem.dmem.memory[170],
                 chip.u_soc_top.u_dmem.dmem.memory[171],
                 chip.u_soc_top.u_dmem.dmem.memory[172],
                 chip.u_soc_top.u_dmem.dmem.memory[173]);
        $finish;
    end

    if (!pass_reported &&
        dmem_sig0 == EXPECT_SIG0_VALUE &&
        dmem_sig1 == EXPECT_SIG1_VALUE &&
        dmem_result == RESULT_RUNNING &&
        dmem_heartbeat >= HEARTBEAT_TARGET &&
        (!AUX0_CHECK || dmem_aux0 == EXPECT_AUX0_VALUE) &&
        (!AUX1_CHECK || dmem_aux1 == EXPECT_AUX1_VALUE) &&
        (!GPIO_CHECK || gpio == EXPECT_GPIO_VALUE) &&
        (!DMA_CONTEXT_CHECK || dma_context_seen) &&
        core0_dc_req_count >= DC_REQ_TARGET &&
        core1_dc_req_count >= DC_REQ_TARGET &&
        dcache0_writes != 0 &&
        dcache1_writes != 0 &&
        (dcache0_hits != 0 || dcache1_hits != 0)) begin
        pass_reported <= 1'b1;
        $display("[PASS] %s", `SCENARIO_NAME);
        $display("  cycles=%0d", cycles);
        $display("  heartbeat=%0d shared_count=%0d", dmem_heartbeat, dmem_count);
        $display("  aux0=%08x aux1=%08x", dmem_aux0, dmem_aux1);
        $display("  core0_dc_req_count=%0d core1_dc_req_count=%0d", core0_dc_req_count, core1_dc_req_count);
        $display("  dcache0 writes=%0d hits=%0d", dcache0_writes, dcache0_hits);
        $display("  dcache1 writes=%0d hits=%0d", dcache1_writes, dcache1_hits);
        $display("  dcache0 peer_snp_reqs=%0d peer_snp_hits=%0d c2c_fwds=%0d c2c_fill_cycles=%0d mem_refills=%0d",
                 dcache0_peer_snoop_reqs, dcache0_peer_snoop_hits,
                 dcache0_c2c_forwards, dcache0_c2c_fill_cycles, dcache0_mem_refills);
        $display("  dcache1 peer_snp_reqs=%0d peer_snp_hits=%0d c2c_fwds=%0d c2c_fill_cycles=%0d mem_refills=%0d",
                 dcache1_peer_snoop_reqs, dcache1_peer_snoop_hits,
                 dcache1_c2c_forwards, dcache1_c2c_fill_cycles, dcache1_mem_refills);
`ifdef H3_BENCH_TRACE
        if (h3_core_op_count != 0) begin
            h3_avg_core_latency = h3_core_latency_sum;
            h3_avg_core_latency = h3_avg_core_latency / h3_core_op_count;
            $display("  h3_core_ops=%0d avg_active_cycles=%0.2f min=%0d max=%0d avg_active_throughput_mbps=%0.2f",
                     h3_core_op_count,
                     h3_avg_core_latency,
                     h3_core_latency_min,
                     h3_core_latency_max,
                     (64.0 * 100.0) / h3_avg_core_latency);
        end
        if (h3_ctx_interval_count != 0) begin
            h3_avg_ctx_switch_interval = h3_ctx_delta_sum;
            h3_avg_ctx_switch_interval = h3_avg_ctx_switch_interval / h3_ctx_interval_count;
            $display("  h3_context_switches=%0d measured_intervals=%0d avg_mmio_interval_cycles=%0.2f min=%0d max=%0d rtl_select_latency_cycles=1",
                     h3_ctx_window_count,
                     h3_ctx_interval_count,
                     h3_avg_ctx_switch_interval,
                     h3_ctx_delta_min,
                     h3_ctx_delta_max);
        end
`endif
        $finish;
    end

    if (cycles > TIMEOUT_TARGET) begin
        $display("[FAIL] %s timeout waiting for dual-core progress", `SCENARIO_NAME);
        $display("  sig0=%08x sig1=%08x result=%08x heartbeat=%0d count=%0d aux0=%08x aux1=%08x",
                 dmem_sig0, dmem_sig1, dmem_result, dmem_heartbeat, dmem_count, dmem_aux0, dmem_aux1);
        $display("  gpio=%08x", gpio);
        $display("  core0_dc_req_count=%0d core1_dc_req_count=%0d", core0_dc_req_count, core1_dc_req_count);
        $display("  dcache0 writes=%0d hits=%0d", dcache0_writes, dcache0_hits);
        $display("  dcache1 writes=%0d hits=%0d", dcache1_writes, dcache1_hits);
        $display("  dcache0 peer_snp_reqs=%0d peer_snp_hits=%0d c2c_fwds=%0d c2c_fill_cycles=%0d mem_refills=%0d",
                 dcache0_peer_snoop_reqs, dcache0_peer_snoop_hits,
                 dcache0_c2c_forwards, dcache0_c2c_fill_cycles, dcache0_mem_refills);
        $display("  dcache1 peer_snp_reqs=%0d peer_snp_hits=%0d c2c_fwds=%0d c2c_fill_cycles=%0d mem_refills=%0d",
                 dcache1_peer_snoop_reqs, dcache1_peer_snoop_hits,
                 dcache1_c2c_forwards, dcache1_c2c_fill_cycles, dcache1_mem_refills);
        $display("  cpu/dcache: c0_pc=%08x c1_pc=%08x c0_dc_state=%0d c0_cur=%08x c0_fence=%0b c1_dc_state=%0d c1_cur=%08x c1_fence=%0b",
                 chip.u_soc_top.u_cpu.pc_if,
                 chip.u_soc_top.u_cpu1.pc_if,
                 chip.u_soc_top.u_dcache.controller_inst.state,
                 chip.u_soc_top.u_dcache.controller_inst.cur_addr,
                 chip.u_soc_top.cpu_dcache_fence_type,
                 chip.u_soc_top.u_dcache1.controller_inst.state,
                 chip.u_soc_top.u_dcache1.controller_inst.cur_addr,
                 chip.u_soc_top.cpu1_dcache_fence_type);
        $display("  ascon: dma_en=%0b dma_start=%0b dma_busy=%0b dma_done=%0b dma_err=%0b core_start=%0b core_busy=%0b core_done=%0b core_dv=%0b core_do_v=%0b tag_v=%0b",
                 chip.u_soc_top.u_ascon.slave_dma_en,
                 chip.u_soc_top.u_ascon.slave_dma_start,
                 chip.u_soc_top.u_ascon.dma_busy_w,
                 chip.u_soc_top.u_ascon.dma_done_w,
                 chip.u_soc_top.u_ascon.dma_error_w,
                 chip.u_soc_top.u_ascon.core_start_mux,
                 chip.u_soc_top.u_ascon.core_busy_w,
                 chip.u_soc_top.u_ascon.core_done_w,
                 chip.u_soc_top.u_ascon.core_data_valid,
                 chip.u_soc_top.u_ascon.core_data_out_valid_w,
                 chip.u_soc_top.u_ascon.core_tag_valid_w);
        $display("  ascon dma: ctrl_phase=%0d pump=%0d ad_pump=%0d push=%0d rd_busy=%0b rd_done=%0b rd_err=%0b wr_busy=%0b wr_done=%0b wr_err=%0b rd_fifo_valid=%0b wr_count=%0d",
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.dma_phase,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.pump_state,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.ad_pump_state,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.push_state,
                 chip.u_soc_top.u_ascon.u_dma.rd_busy_w,
                 chip.u_soc_top.u_ascon.u_dma.rd_done_w,
                 chip.u_soc_top.u_ascon.u_dma.rd_error_w,
                 chip.u_soc_top.u_ascon.u_dma.wr_busy_w,
                 chip.u_soc_top.u_ascon.u_dma.wr_done_w,
                 chip.u_soc_top.u_ascon.u_dma.wr_error_w,
                 chip.u_soc_top.u_ascon.u_dma.rd_fifo_fwft_valid,
                 chip.u_soc_top.u_ascon.u_dma.wr_fifo_count);
        $display("  ascon fsm counters: byte_len=%0d total_blocks=%0d core_blocks_fed=%0d rd_blocks_sent=%0d ad_blocks=%0d status_rd_done=%0b status_wr_done=%0b",
                 chip.u_soc_top.u_ascon.u_dma.byte_len,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.total_blocks,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.core_blocks_fed,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.rd_blocks_sent,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.ad_blocks_pumped,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.status_rd_done,
                 chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.status_wr_done);
        $display("  ascon slave status: status_word=%08x status_dma_done=%0b status_done=%0b status_dma_error=%0b",
                 chip.u_soc_top.u_ascon.u_slave.status_word,
                 chip.u_soc_top.u_ascon.u_slave.status_dma_done,
                 chip.u_soc_top.u_ascon.u_slave.status_done,
                 chip.u_soc_top.u_ascon.u_slave.status_dma_error);
        $display("  dmem ct/tag: ct0=%08x ct1=%08x tag0=%08x tag1=%08x tag2=%08x tag3=%08x",
                 chip.u_soc_top.u_dmem.dmem.memory[168],
                 chip.u_soc_top.u_dmem.dmem.memory[169],
                 chip.u_soc_top.u_dmem.dmem.memory[170],
                 chip.u_soc_top.u_dmem.dmem.memory[171],
                 chip.u_soc_top.u_dmem.dmem.memory[172],
                 chip.u_soc_top.u_dmem.dmem.memory[173]);
`ifdef USE_ASCON_BASELINE
        $display("  baseline saved s0: ct0=%08x ct1=%08x tag0=%08x tag1=%08x tag2=%08x tag3=%08x",
                 chip.u_soc_top.u_dmem.dmem.memory[224],
                 chip.u_soc_top.u_dmem.dmem.memory[225],
                 chip.u_soc_top.u_dmem.dmem.memory[226],
                 chip.u_soc_top.u_dmem.dmem.memory[227],
                 chip.u_soc_top.u_dmem.dmem.memory[228],
                 chip.u_soc_top.u_dmem.dmem.memory[229]);
`endif
`ifdef USE_ASCON_BASELINE
        $display("  ascon rd/wr engines: rd_state=%0d work=%08x snoop_v/r/resp=%0b/%0b/%0b wr_state=%0d wr_req=%08x snoop_v/r/resp=%0b/%0b/%0b",
                 chip.u_soc_top.u_ascon.u_dma.u_rd_engine.state,
                 chip.u_soc_top.u_ascon.u_dma.u_rd_engine.work_addr,
                 chip.u_soc_top.u_ascon.u_dma.rd_snoop_req_valid,
                 chip.u_soc_top.u_ascon.u_dma.rd_snoop_req_ready,
                 chip.u_soc_top.u_ascon.u_dma.rd_snoop_resp_valid,
                 chip.u_soc_top.u_ascon.u_dma.u_wr_engine.state,
                 chip.u_soc_top.u_ascon.u_dma.u_wr_engine.snoop_req_addr,
                 chip.u_soc_top.u_ascon.u_dma.wr_snoop_req_valid,
                 chip.u_soc_top.u_ascon.u_dma.wr_snoop_req_ready,
                 chip.u_soc_top.u_ascon.u_dma.wr_snoop_resp_valid);
`else
        $display("  ascon rd/wr engines: rd_state=%0d work=%08x snoop_v/r/resp=%0b/%0b/%0b wr_state=%0d inv=%08x snoop_v/r/resp=%0b/%0b/%0b",
                 chip.u_soc_top.u_ascon.u_dma.u_rd_engine.state,
                 chip.u_soc_top.u_ascon.u_dma.u_rd_engine.work_addr,
                 chip.u_soc_top.u_ascon.u_dma.rd_snoop_req_valid,
                 chip.u_soc_top.u_ascon.u_dma.rd_snoop_req_ready,
                 chip.u_soc_top.u_ascon.u_dma.rd_snoop_resp_valid,
                 chip.u_soc_top.u_ascon.u_dma.u_wr_engine.state,
                 chip.u_soc_top.u_ascon.u_dma.u_wr_engine.inv_addr,
                 chip.u_soc_top.u_ascon.u_dma.wr_snoop_req_valid,
                 chip.u_soc_top.u_ascon.u_dma.wr_snoop_req_ready,
                 chip.u_soc_top.u_ascon.u_dma.wr_snoop_resp_valid);
`endif
        $display("  snoop cpu0: state=%0d miss_valid=%0b miss_ready=%0b miss_resp=%0b dc_req_valid=%0b dc_req_ready=%0b dc_resp=%0b",
                 chip.u_soc_top.u_dcache.controller_inst.state,
                 chip.u_soc_top.cpu0_miss_snoop_req_valid,
                 chip.u_soc_top.cpu0_miss_snoop_req_ready,
                 chip.u_soc_top.cpu0_miss_snoop_resp_valid,
                 chip.u_soc_top.dc0_snoop_req_valid,
                 chip.u_soc_top.dc0_snoop_req_ready,
                 chip.u_soc_top.dc0_snoop_resp_valid);
        $display("  snoop cpu1: state=%0d miss_valid=%0b miss_ready=%0b miss_resp=%0b dc_req_valid=%0b dc_req_ready=%0b dc_resp=%0b",
                 chip.u_soc_top.u_dcache1.controller_inst.state,
                 chip.u_soc_top.cpu1_miss_snoop_req_valid,
                 chip.u_soc_top.cpu1_miss_snoop_req_ready,
                 chip.u_soc_top.cpu1_miss_snoop_resp_valid,
                 chip.u_soc_top.dc1_snoop_req_valid,
                 chip.u_soc_top.dc1_snoop_req_ready,
                 chip.u_soc_top.dc1_snoop_resp_valid);
        $finish;
    end
end

`ifdef DEBUG_SNOOP_TRACE
always @(posedge clk) begin
    if (por_n && ext_rst_n) begin
        if (chip.u_soc_top.cpu0_miss_snoop_req_valid ||
            chip.u_soc_top.cpu1_miss_snoop_req_valid ||
            chip.u_soc_top.cpu0_miss_snoop_resp_valid ||
            chip.u_soc_top.cpu1_miss_snoop_resp_valid ||
            chip.u_soc_top.dc0_snoop_req_valid ||
            chip.u_soc_top.dc1_snoop_req_valid ||
            chip.u_soc_top.dc0_snoop_resp_valid ||
            chip.u_soc_top.dc1_snoop_resp_valid) begin
            $display("[SNOOP %0d] c0_miss v/r/resp=%0b/%0b/%0b c1_miss v/r/resp=%0b/%0b/%0b bus_state=%0d arb_wait=%0b dc0 v/r/resp=%0b/%0b/%0b dc1 v/r/resp=%0b/%0b/%0b st0=%0d st1=%0d",
                     cycles,
                     chip.u_soc_top.cpu0_miss_snoop_req_valid,
                     chip.u_soc_top.cpu0_miss_snoop_req_ready,
                     chip.u_soc_top.cpu0_miss_snoop_resp_valid,
                     chip.u_soc_top.cpu1_miss_snoop_req_valid,
                     chip.u_soc_top.cpu1_miss_snoop_req_ready,
                     chip.u_soc_top.cpu1_miss_snoop_resp_valid,
                     chip.u_soc_top.u_dcache_snoop_bus.state,
                     chip.u_soc_top.u_dcache_snoop_arb.wait_resp_r,
                     chip.u_soc_top.dc0_snoop_req_valid,
                     chip.u_soc_top.dc0_snoop_req_ready,
                     chip.u_soc_top.dc0_snoop_resp_valid,
                     chip.u_soc_top.dc1_snoop_req_valid,
                     chip.u_soc_top.dc1_snoop_req_ready,
                     chip.u_soc_top.dc1_snoop_resp_valid,
                     chip.u_soc_top.u_dcache.controller_inst.state,
                     chip.u_soc_top.u_dcache1.controller_inst.state);
        end
    end
end
`endif

endmodule
