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

integer cycles;
integer core0_dc_req_count;
integer core1_dc_req_count;
reg prev_core0_dc_req;
reg prev_core1_dc_req;
reg pass_reported;

wire core0_dc_req = chip.u_soc_top.cpu_dcache_req;
wire core1_dc_req = chip.u_soc_top.cpu1_dcache_req;

wire [31:0] dcache0_writes = chip.u_soc_top.dcache0_stat_writes;
wire [31:0] dcache1_writes = chip.u_soc_top.dcache1_stat_writes;
wire [31:0] dcache0_hits   = chip.u_soc_top.dcache0_stat_hits;
wire [31:0] dcache1_hits   = chip.u_soc_top.dcache1_stat_hits;

wire [31:0] dmem_sig0      = chip.u_soc_top.u_dmem.dmem.memory[0];
wire [31:0] dmem_sig1      = chip.u_soc_top.u_dmem.dmem.memory[1];
wire [31:0] dmem_count     = chip.u_soc_top.u_dmem.dmem.memory[2];
wire [31:0] dmem_heartbeat = chip.u_soc_top.u_dmem.dmem.memory[3];
wire [31:0] dmem_result    = chip.u_soc_top.u_dmem.dmem.memory[4];
wire [31:0] dmem_aux0      = chip.u_soc_top.u_dmem.dmem.memory[5];
wire [31:0] dmem_aux1      = chip.u_soc_top.u_dmem.dmem.memory[6];

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

    repeat (20) @(posedge clk);
    ext_rst_n = 1'b1;
    repeat (12) @(posedge clk);
    por_n = 1'b1;
end

always @(posedge clk) begin
    cycles <= cycles + 1;

    if (!prev_core0_dc_req && core0_dc_req)
        core0_dc_req_count <= core0_dc_req_count + 1;
    if (!prev_core1_dc_req && core1_dc_req)
        core1_dc_req_count <= core1_dc_req_count + 1;

    prev_core0_dc_req <= core0_dc_req;
    prev_core1_dc_req <= core1_dc_req;

    if (dmem_result == RESULT_FAIL) begin
        $display("[FAIL] %s firmware reported RESULT_FAIL at cycle %0d", `SCENARIO_NAME, cycles);
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
        core0_dc_req_count >= DC_REQ_TARGET &&
        core1_dc_req_count >= DC_REQ_TARGET &&
        dcache0_writes != 0 &&
        dcache1_writes != 0 &&
        (dcache0_hits != 0 || dcache1_hits != 0)) begin
        pass_reported <= 1'b1;
        $display("[PASS] %s", `SCENARIO_NAME);
        $display("  heartbeat=%0d shared_count=%0d", dmem_heartbeat, dmem_count);
        $display("  aux0=%08x aux1=%08x", dmem_aux0, dmem_aux1);
        $display("  core0_dc_req_count=%0d core1_dc_req_count=%0d", core0_dc_req_count, core1_dc_req_count);
        $display("  dcache0 writes=%0d hits=%0d", dcache0_writes, dcache0_hits);
        $display("  dcache1 writes=%0d hits=%0d", dcache1_writes, dcache1_hits);
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
