`timescale 1ns/1ps

// =============================================================================
// tb_soc_ctrl_slave.v  —  Testbench for soc_ctrl_slave
// DUT : soc_ctrl_slave (S3 @ 0x3000_0000)
//
// Test cases:
//   TC01  Reset state — AWREADY/WREADY/ARREADY=1, BVALID/RVALID=0, CYCLE_CNT~0
//   TC02  SYS_ID read (RO = 0xA5C0_0001)
//   TC03  SYS_CTRL reads 0 (WO register)
//   TC04  IRQ_MASK write + readback (RW)
//   TC05  IRQ_STATUS sticky set via ascon_irq rising edge
//   TC06  IRQ_STATUS W1C clear
//   TC07  CYCLE_CNT increments every cycle
//   TC08  CYCLE_CNT resets on soft_rst (SYS_CTRL[0]=1)
//   TC09  soft_rst_pulse single-cycle effect (CYCLE_CNT drops after rst)
//   TC10  Cache counter forwarding (icache/dcache hit/miss/write)
//   TC11  Reserved address read returns 0, OKAY
//   TC12  Reserved address write returns OKAY
//   TC13  Write to RO register returns SLVERR
//   TC14  BID/RID echo (AWID latched as BID, ARID as RID)
//   TC15  AW before W (normal order)
//   TC16  W before AW (reversed order)
//   TC17  Back-to-back reads
//   TC18  Back-to-back writes
//   TC19  BREADY backpressure (BREADY de-asserted)
//   TC20  RREADY backpressure (RREADY de-asserted)
//   TC21  Write then read in close succession (no deadlock)
//   TC22  Multiple ascon_irq pulses: re-sets sticky after W1C
//   TC23  IRQ_MASK=0 does NOT suppress sticky set
//   TC24  RLAST always 1
//   TC25  RRESP always OKAY for any valid/reserved address
//
// Run:
//   ~/workflow/urun_verilog.sh controller/tb/tb_soc_ctrl_slave.v
//   rtk read controller/tb/tb_soc_ctrl_slave.log
// =============================================================================

`include "controller/soc_ctrl_slave.v"

module tb_soc_ctrl_slave;

parameter ADDR_WIDTH = 32;
parameter DATA_WIDTH = 32;
parameter ID_WIDTH   = 4;
parameter CLK_PERIOD = 10;

parameter BASE            = 32'h3000_0000;
parameter REG_SYS_ID      = 12'h000;
parameter REG_SYS_CTRL    = 12'h004;
parameter REG_IRQ_STATUS  = 12'h008;
parameter REG_IRQ_MASK    = 12'h00C;
parameter REG_ICACHE_HITS = 12'h010;
parameter REG_ICACHE_MISS = 12'h014;
parameter REG_DCACHE_HITS = 12'h018;
parameter REG_DCACHE_MISS = 12'h01C;
parameter REG_DCACHE_WR   = 12'h020;
parameter REG_CYCLE_CNT   = 12'h024;
parameter REG_HART_ID     = 12'h028;
parameter REG_PERF_CTRL   = 12'h02C;

// ---------------------------------------------------------------------------
// DUT signals
// ---------------------------------------------------------------------------
reg                    clk, rst_n;

reg  [ID_WIDTH-1:0]    m_awid;
reg  [ADDR_WIDTH-1:0]  m_awaddr;
reg  [7:0]             m_awlen;
reg  [2:0]             m_awsize;
reg  [1:0]             m_awburst;
reg  [2:0]             m_awprot;
reg                    m_awvalid;
wire                   m_awready;

reg  [DATA_WIDTH-1:0]  m_wdata;
reg  [DATA_WIDTH/8-1:0] m_wstrb;
reg                    m_wlast;
reg                    m_wvalid;
wire                   m_wready;

wire [ID_WIDTH-1:0]    m_bid;
wire [1:0]             m_bresp;
wire                   m_bvalid;
reg                    m_bready;

reg  [ID_WIDTH-1:0]    m_arid;
reg  [ADDR_WIDTH-1:0]  m_araddr;
reg  [7:0]             m_arlen;
reg  [2:0]             m_arsize;
reg  [1:0]             m_arburst;
reg  [2:0]             m_arprot;
reg                    m_arvalid;
wire                   m_arready;

wire [ID_WIDTH-1:0]    m_rid;
wire [DATA_WIDTH-1:0]  m_rdata;
wire [1:0]             m_rresp;
wire                   m_rlast;
wire                   m_rvalid;
reg                    m_rready;

// SoC status
reg  [31:0] icache_hits, icache_misses, dcache_hits, dcache_misses, dcache_writes;
reg         ascon_irq, uart_irq, gpio_irq, spi_irq, timer_irq, wdt_irq;
reg         perf_stall_in, perf_instr_ret_in;

wire        irq_out_w, soft_rst_pulse_w;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
soc_ctrl_slave #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH  (ID_WIDTH)
) dut (
    .clk             (clk),
    .rst_n           (rst_n),

    .S_AXI_AWID      (m_awid),
    .S_AXI_AWADDR    (m_awaddr),
    .S_AXI_AWLEN     (m_awlen),
    .S_AXI_AWSIZE    (m_awsize),
    .S_AXI_AWBURST   (m_awburst),
    .S_AXI_AWPROT    (m_awprot),
    .S_AXI_AWVALID   (m_awvalid),
    .S_AXI_AWREADY   (m_awready),

    .S_AXI_WDATA     (m_wdata),
    .S_AXI_WSTRB     (m_wstrb),
    .S_AXI_WLAST     (m_wlast),
    .S_AXI_WVALID    (m_wvalid),
    .S_AXI_WREADY    (m_wready),

    .S_AXI_BID       (m_bid),
    .S_AXI_BRESP     (m_bresp),
    .S_AXI_BVALID    (m_bvalid),
    .S_AXI_BREADY    (m_bready),

    .S_AXI_ARID      (m_arid),
    .S_AXI_ARADDR    (m_araddr),
    .S_AXI_ARLEN     (m_arlen),
    .S_AXI_ARSIZE    (m_arsize),
    .S_AXI_ARBURST   (m_arburst),
    .S_AXI_ARPROT    (m_arprot),
    .S_AXI_ARVALID   (m_arvalid),
    .S_AXI_ARREADY   (m_arready),

    .S_AXI_RID       (m_rid),
    .S_AXI_RDATA     (m_rdata),
    .S_AXI_RRESP     (m_rresp),
    .S_AXI_RLAST     (m_rlast),
    .S_AXI_RVALID    (m_rvalid),
    .S_AXI_RREADY    (m_rready),

    .icache_hits     (icache_hits),
    .icache_misses   (icache_misses),
    .dcache_hits     (dcache_hits),
    .dcache_misses   (dcache_misses),
    .dcache_writes   (dcache_writes),

    .ascon_irq       (ascon_irq),
    .uart_irq        (uart_irq),
    .gpio_irq        (gpio_irq),
    .spi_irq         (spi_irq),
    .timer_irq       (timer_irq),
    .wdt_irq         (wdt_irq),

    .perf_stall_in      (perf_stall_in),
    .perf_instr_ret_in  (perf_instr_ret_in),

    .irq_out         (irq_out_w),
    .soft_rst_pulse  (soft_rst_pulse_w)
);

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---------------------------------------------------------------------------
// VCD
// ---------------------------------------------------------------------------
initial begin
    $dumpfile("tb_soc_ctrl_slave.vcd");
    $dumpvars(0, tb_soc_ctrl_slave);
end

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
integer pass_cnt, fail_cnt;

task check;
    input [127:0] name;
    input [31:0]  got;
    input [31:0]  exp;
    begin
        if (got === exp) begin
            $display("[PASS] %0s  got=0x%08h", name, got);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0s  got=0x%08h  exp=0x%08h  <--", name, got, exp);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task check1;
    input [127:0] name;
    input         got;
    input         exp;
    begin
        if (got === exp) begin
            $display("[PASS] %0s  got=%b", name, got);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0s  got=%b  exp=%b  <--", name, got, exp);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// AXI BFM tasks
// ---------------------------------------------------------------------------
task axi_idle;
    begin
        m_awid<=0; m_awaddr<=0; m_awlen<=0; m_awsize<=3'b010;
        m_awburst<=2'b01; m_awprot<=0; m_awvalid<=0;
        m_wdata<=0; m_wstrb<=4'hF; m_wlast<=1; m_wvalid<=0;
        m_bready<=1;
        m_arid<=0; m_araddr<=0; m_arlen<=0; m_arsize<=3'b010;
        m_arburst<=2'b01; m_arprot<=0; m_arvalid<=0;
        m_rready<=1;
    end
endtask

// Single-beat write; AW and W driven simultaneously
task axi_write;
    input  [ID_WIDTH-1:0]   tid;
    input  [ADDR_WIDTH-1:0] addr;
    input  [DATA_WIDTH-1:0] data;
    input  [3:0]             strb;
    output [1:0]             resp;
    begin : aw_task
        reg aw_d, w_d;
        aw_d = 0; w_d = 0;
        @(negedge clk);
        m_awid<=tid; m_awaddr<=addr; m_awlen<=0; m_awsize<=3'b010;
        m_awburst<=2'b01; m_awprot<=0; m_awvalid<=1;
        m_wdata<=data; m_wstrb<=strb; m_wlast<=1; m_wvalid<=1;
        @(posedge clk);
        while (!(aw_d && w_d)) begin
            if (m_awvalid && m_awready) aw_d = 1;
            if (m_wvalid  && m_wready)  w_d  = 1;
            @(negedge clk);
            if (aw_d) m_awvalid<=0;
            if (w_d)  m_wvalid <=0;
            if (!(aw_d && w_d)) @(posedge clk);
        end
        @(negedge clk); m_awvalid<=0; m_wvalid<=0;
        @(posedge clk); while (!m_bvalid) @(posedge clk);
        resp = m_bresp;
        @(negedge clk);
    end
endtask

// W channel driven 3 cycles before AW
task axi_write_w_first;
    input  [ID_WIDTH-1:0]   tid;
    input  [ADDR_WIDTH-1:0] addr;
    input  [DATA_WIDTH-1:0] data;
    input  [3:0]             strb;
    output [1:0]             resp;
    begin
        @(negedge clk);
        m_wdata<=data; m_wstrb<=strb; m_wlast<=1; m_wvalid<=1;
        @(posedge clk); while (!m_wready) @(posedge clk);
        @(negedge clk); m_wvalid<=0;
        repeat(3) @(posedge clk);
        @(negedge clk);
        m_awid<=tid; m_awaddr<=addr; m_awlen<=0; m_awsize<=3'b010;
        m_awburst<=2'b01; m_awprot<=0; m_awvalid<=1;
        @(posedge clk); while (!m_awready) @(posedge clk);
        @(negedge clk); m_awvalid<=0;
        @(posedge clk); while (!m_bvalid) @(posedge clk);
        resp = m_bresp;
        @(negedge clk);
    end
endtask

// Single-beat read
task axi_read;
    input  [ID_WIDTH-1:0]   tid;
    input  [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data;
    output [1:0]             resp;
    begin
        @(negedge clk);
        m_arid<=tid; m_araddr<=addr; m_arlen<=0; m_arsize<=3'b010;
        m_arburst<=2'b01; m_arprot<=0; m_arvalid<=1;
        @(posedge clk); while (!m_arready) @(posedge clk);
        @(negedge clk); m_arvalid<=0;
        @(posedge clk); while (!m_rvalid) @(posedge clk);
        data = m_rdata; resp = m_rresp;
        @(negedge clk);
    end
endtask

// Read with RREADY held low for rready_delay cycles after RVALID
task axi_read_bp;
    input  [ID_WIDTH-1:0]   tid;
    input  [ADDR_WIDTH-1:0] addr;
    input  [31:0]            rready_delay;
    output [DATA_WIDTH-1:0] data;
    output [1:0]             resp;
    begin : rbp
        integer cnt;
        @(negedge clk); m_rready<=0;
        m_arid<=tid; m_araddr<=addr; m_arlen<=0; m_arsize<=3'b010;
        m_arburst<=2'b01; m_arprot<=0; m_arvalid<=1;
        @(posedge clk); while (!m_arready) @(posedge clk);
        @(negedge clk); m_arvalid<=0;
        @(posedge clk); while (!m_rvalid) @(posedge clk);
        for (cnt = 0; cnt < rready_delay; cnt = cnt + 1) @(posedge clk);
        @(negedge clk); m_rready<=1;
        @(posedge clk); while (!m_rvalid) @(posedge clk);
        data = m_rdata; resp = m_rresp;
        @(negedge clk); m_rready<=1;
    end
endtask

// Write with BREADY held low for bready_delay cycles after BVALID
task axi_write_bp;
    input  [ID_WIDTH-1:0]   tid;
    input  [ADDR_WIDTH-1:0] addr;
    input  [DATA_WIDTH-1:0] data;
    input  [3:0]             strb;
    input  [31:0]            bready_delay;
    output [1:0]             resp;
    begin : wbp
        reg aw_d, w_d;
        integer cnt;
        aw_d = 0; w_d = 0;
        @(negedge clk); m_bready<=0;
        m_awid<=tid; m_awaddr<=addr; m_awlen<=0; m_awsize<=3'b010;
        m_awburst<=2'b01; m_awprot<=0; m_awvalid<=1;
        m_wdata<=data; m_wstrb<=strb; m_wlast<=1; m_wvalid<=1;
        @(posedge clk);
        while (!(aw_d && w_d)) begin
            if (m_awvalid && m_awready) aw_d = 1;
            if (m_wvalid  && m_wready)  w_d  = 1;
            @(negedge clk);
            if (aw_d) m_awvalid<=0;
            if (w_d)  m_wvalid <=0;
            if (!(aw_d && w_d)) @(posedge clk);
        end
        @(negedge clk); m_awvalid<=0; m_wvalid<=0;
        @(posedge clk); while (!m_bvalid) @(posedge clk);
        for (cnt = 0; cnt < bready_delay; cnt = cnt + 1) @(posedge clk);
        @(negedge clk); m_bready<=1;
        @(posedge clk); while (!m_bvalid) @(posedge clk);
        resp = m_bresp;
        @(negedge clk); m_bready<=1;
    end
endtask

task clk_delay;
    input [31:0] n;
    begin : cd
        integer i;
        for (i = 0; i < n; i = i + 1) @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Shared result regs
// ---------------------------------------------------------------------------
reg [31:0] rdata_val;
reg [1:0]  resp_val;
integer    cnt_before, cnt_after;

// ---------------------------------------------------------------------------
// Main test
// ---------------------------------------------------------------------------
integer i;

initial begin
    pass_cnt = 0; fail_cnt = 0;
    axi_idle;
    icache_hits = 0; icache_misses = 0;
    dcache_hits = 0; dcache_misses = 0; dcache_writes = 0;
    ascon_irq = 0; uart_irq = 0; gpio_irq = 0;
    spi_irq = 0; timer_irq = 0; wdt_irq = 0;
    perf_stall_in = 0; perf_instr_ret_in = 0;

    rst_n = 0;
    repeat(5) @(posedge clk);
    @(negedge clk); rst_n = 1;

    $display("");
    $display("=========================================================");
    $display("  A10 — soc_ctrl_slave Testbench");
    $display("=========================================================");

    // =========================================================================
    // TC01 — Reset state
    // =========================================================================
    $display("\n--- TC01: Reset state ---");
    @(posedge clk);
    check1("RST AWREADY",  dut.S_AXI_AWREADY, 1'b1);
    check1("RST WREADY",   dut.S_AXI_WREADY,  1'b1);
    check1("RST BVALID",   dut.S_AXI_BVALID,  1'b0);
    check1("RST ARREADY",  dut.S_AXI_ARREADY, 1'b1);
    check1("RST RVALID",   dut.S_AXI_RVALID,  1'b0);
    if (dut.cycle_cnt_r < 5) begin
        $display("[PASS] RST CYCLE_CNT near-zero  got=%0d", dut.cycle_cnt_r);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL] RST CYCLE_CNT too large  got=%0d", dut.cycle_cnt_r);
        fail_cnt = fail_cnt + 1;
    end
    // irq_status_r is 6-bit
    if (dut.irq_status_r === 6'd0) begin
        $display("[PASS] RST IRQ_STATUS=0");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL] RST IRQ_STATUS != 0  got=%0b", dut.irq_status_r);
        fail_cnt = fail_cnt + 1;
    end

    // =========================================================================
    // TC02 — SYS_ID read
    // =========================================================================
    $display("\n--- TC02: SYS_ID read ---");
    axi_read(4'h1, BASE + REG_SYS_ID, rdata_val, resp_val);
    check("SYS_ID value",  rdata_val, 32'hA5C0_0001);
    check("SYS_ID RRESP",  {30'd0, resp_val}, 32'd0);

    // =========================================================================
    // TC03 — SYS_CTRL reads 0
    // =========================================================================
    $display("\n--- TC03: SYS_CTRL reads 0 ---");
    axi_read(4'h2, BASE + REG_SYS_CTRL, rdata_val, resp_val);
    check("SYS_CTRL rd 0", rdata_val, 32'd0);

    // =========================================================================
    // TC04 — IRQ_MASK write + readback
    // =========================================================================
    $display("\n--- TC04: IRQ_MASK RW ---");
    axi_write(4'h3, BASE + REG_IRQ_MASK, 32'h0000_0001, 4'hF, resp_val);
    check("IRQ_MASK wr resp", {30'd0, resp_val}, 32'd0);
    axi_read(4'h3, BASE + REG_IRQ_MASK, rdata_val, resp_val);
    check("IRQ_MASK rd 1",    rdata_val[0], 1'b1);
    axi_write(4'h3, BASE + REG_IRQ_MASK, 32'h0, 4'hF, resp_val);
    axi_read(4'h3, BASE + REG_IRQ_MASK, rdata_val, resp_val);
    check("IRQ_MASK rd 0",    rdata_val[0], 1'b0);

    // =========================================================================
    // TC05 — IRQ_STATUS sticky via ascon_irq rising edge
    // =========================================================================
    $display("\n--- TC05: IRQ_STATUS sticky set ---");
    axi_read(4'h1, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("IRQ_STAT before",  rdata_val[0], 1'b0);
    @(negedge clk); ascon_irq = 1;
    clk_delay(2);
    @(negedge clk); ascon_irq = 0;
    clk_delay(2);
    axi_read(4'h1, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("IRQ_STAT sticky",  rdata_val[0], 1'b1);
    clk_delay(5);
    axi_read(4'h1, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("IRQ_STAT stays",   rdata_val[0], 1'b1);

    // =========================================================================
    // TC06 — IRQ_STATUS W1C clear
    // =========================================================================
    $display("\n--- TC06: IRQ_STATUS W1C ---");
    axi_write(4'h5, BASE + REG_IRQ_STATUS, 32'h0000_0001, 4'hF, resp_val);
    check("W1C wr resp",  {30'd0, resp_val}, 32'd0);
    clk_delay(2);
    axi_read(4'h5, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("IRQ_STAT clrd", rdata_val[0], 1'b0);

    // =========================================================================
    // TC07 — CYCLE_CNT increments
    // =========================================================================
    $display("\n--- TC07: CYCLE_CNT increment ---");
    axi_read(4'h1, BASE + REG_CYCLE_CNT, rdata_val, resp_val);
    cnt_before = rdata_val;
    clk_delay(10);
    axi_read(4'h1, BASE + REG_CYCLE_CNT, rdata_val, resp_val);
    cnt_after = rdata_val;
    if (cnt_after > cnt_before) begin
        $display("[PASS] CYCLE_CNT increment before=%0d after=%0d", cnt_before, cnt_after);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL] CYCLE_CNT not incrementing before=%0d after=%0d", cnt_before, cnt_after);
        fail_cnt = fail_cnt + 1;
    end

    // =========================================================================
    // TC08 — CYCLE_CNT resets via SYS_CTRL[0]
    // =========================================================================
    $display("\n--- TC08: CYCLE_CNT resets on soft_rst ---");
    clk_delay(50);
    axi_read(4'h1, BASE + REG_CYCLE_CNT, rdata_val, resp_val);
    cnt_before = rdata_val;
    axi_write(4'h1, BASE + REG_SYS_CTRL, 32'h0000_0001, 4'hF, resp_val);
    clk_delay(3);
    axi_read(4'h1, BASE + REG_CYCLE_CNT, rdata_val, resp_val);
    cnt_after = rdata_val;
    if (cnt_after < cnt_before) begin
        $display("[PASS] CYCLE_CNT reset before=%0d after=%0d", cnt_before, cnt_after);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL] CYCLE_CNT not reset before=%0d after=%0d", cnt_before, cnt_after);
        fail_cnt = fail_cnt + 1;
    end

    // =========================================================================
    // TC09 — soft_rst_pulse single-cycle effect
    // =========================================================================
    $display("\n--- TC09: soft_rst_pulse single-cycle ---");
    begin : tc09
        integer pre, post;
        axi_read(4'h1, BASE + REG_CYCLE_CNT, rdata_val, resp_val);
        pre = rdata_val;
        clk_delay(5);
        axi_write(4'hA, BASE + REG_SYS_CTRL, 32'h0000_0001, 4'hF, resp_val);
        clk_delay(3);
        axi_read(4'h1, BASE + REG_CYCLE_CNT, rdata_val, resp_val);
        post = rdata_val;
        if (post < 20 && pre > post) begin
            $display("[PASS] soft_rst single-cycle  pre=%0d post=%0d", pre, post);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] soft_rst unexpected  pre=%0d post=%0d (exp post<20)", pre, post);
            fail_cnt = fail_cnt + 1;
        end
    end

    // =========================================================================
    // TC10 — Cache counter forwarding
    // =========================================================================
    $display("\n--- TC10: Cache counters forwarding ---");
    icache_hits   = 32'hDEAD_1111;
    icache_misses = 32'hDEAD_2222;
    dcache_hits   = 32'hDEAD_3333;
    dcache_misses = 32'hDEAD_4444;
    dcache_writes = 32'hDEAD_5555;
    clk_delay(2);
    axi_read(4'h1, BASE + REG_ICACHE_HITS, rdata_val, resp_val);
    check("ICACHE_HITS fwd",  rdata_val, 32'hDEAD_1111);
    axi_read(4'h1, BASE + REG_ICACHE_MISS, rdata_val, resp_val);
    check("ICACHE_MISS fwd",  rdata_val, 32'hDEAD_2222);
    axi_read(4'h1, BASE + REG_DCACHE_HITS, rdata_val, resp_val);
    check("DCACHE_HITS fwd",  rdata_val, 32'hDEAD_3333);
    axi_read(4'h1, BASE + REG_DCACHE_MISS, rdata_val, resp_val);
    check("DCACHE_MISS fwd",  rdata_val, 32'hDEAD_4444);
    axi_read(4'h1, BASE + 12'h020, rdata_val, resp_val);
    check("DCACHE_WR fwd",    rdata_val, 32'hDEAD_5555);

    // =========================================================================
    // TC11 — Reserved address reads 0, RRESP=OKAY
    // =========================================================================
    $display("\n--- TC11: Reserved addr reads 0 ---");
    axi_read(4'h1, BASE + 32'hFFC, rdata_val, resp_val);
    check("RSVD data=0",  rdata_val, 32'd0);
    check("RSVD RRESP OK",{30'd0, resp_val}, 32'd0);
    axi_read(4'h1, BASE + 32'h100, rdata_val, resp_val);
    check("RSVD mid=0",   rdata_val, 32'd0);

    // =========================================================================
    // TC12 — Reserved address write returns OKAY
    // =========================================================================
    $display("\n--- TC12: Reserved addr write OKAY ---");
    axi_write(4'h1, BASE + 32'h500, 32'hCAFE_CAFE, 4'hF, resp_val);
    check("RSVD wr OKAY", {30'd0, resp_val}, 32'd0);

    // =========================================================================
    // TC13 — Write to RO register returns SLVERR
    // =========================================================================
    $display("\n--- TC13: Write RO -> SLVERR ---");
    axi_write(4'h2, BASE + REG_SYS_ID, 32'hDEAD_DEAD, 4'hF, resp_val);
    check("SYS_ID wr SLVERR",  {30'd0, resp_val}, 32'h2);
    axi_write(4'h2, BASE + REG_ICACHE_HITS, 32'hDEAD_DEAD, 4'hF, resp_val);
    check("ICACHE_HITS SLVERR",{30'd0, resp_val}, 32'h2);
    axi_write(4'h2, BASE + REG_CYCLE_CNT, 32'hDEAD_DEAD, 4'hF, resp_val);
    check("CYCLE_CNT SLVERR",  {30'd0, resp_val}, 32'h2);
    // Verify SYS_ID unchanged
    axi_read(4'h1, BASE + REG_SYS_ID, rdata_val, resp_val);
    check("SYS_ID unchanged",  rdata_val, 32'hA5C0_0001);

    // =========================================================================
    // TC14 — BID/RID echo
    // =========================================================================
    $display("\n--- TC14: BID/RID echo ---");
    axi_write(4'hA, BASE + REG_IRQ_MASK, 32'h1, 4'hF, resp_val);
    check("BID echo 0xA", {28'd0, dut.aw_id_lat}, 32'hA);
    axi_read(4'hB, BASE + REG_SYS_ID, rdata_val, resp_val);
    check("SYS_ID rd",    rdata_val, 32'hA5C0_0001);
    check("RID echo 0xB", {28'd0, dut.ar_id_lat}, 32'hB);

    // =========================================================================
    // TC15 — AW before W
    // =========================================================================
    $display("\n--- TC15: AW before W ---");
    axi_write(4'h1, BASE + REG_IRQ_MASK, 32'h1, 4'hF, resp_val);
    check("AWfirst OKAY", {30'd0, resp_val}, 32'd0);
    axi_read(4'h1, BASE + REG_IRQ_MASK, rdata_val, resp_val);
    check("AWfirst rd",   rdata_val[0], 1'b1);

    // =========================================================================
    // TC16 — W before AW
    // =========================================================================
    $display("\n--- TC16: W before AW ---");
    axi_write(4'h1, BASE + REG_IRQ_MASK, 32'h0, 4'hF, resp_val);
    axi_write_w_first(4'h7, BASE + REG_IRQ_MASK, 32'h1, 4'hF, resp_val);
    check("Wfirst OKAY",  {30'd0, resp_val}, 32'd0);
    axi_read(4'h1, BASE + REG_IRQ_MASK, rdata_val, resp_val);
    check("Wfirst rd",    rdata_val[0], 1'b1);

    // =========================================================================
    // TC17 — Back-to-back reads
    // =========================================================================
    $display("\n--- TC17: Back-to-back reads ---");
    axi_read(4'h1, BASE + REG_SYS_ID,    rdata_val, resp_val);
    check("BBrd[0] SYS_ID", rdata_val, 32'hA5C0_0001);
    axi_read(4'h2, BASE + REG_IRQ_MASK,  rdata_val, resp_val);
    check("BBrd[1] MASK",   rdata_val[0], 1'b1);
    axi_read(4'h3, BASE + REG_IRQ_STATUS,rdata_val, resp_val);
    check("BBrd[2] IRQ_ST", rdata_val[0], 1'b0);

    // =========================================================================
    // TC18 — Back-to-back writes
    // =========================================================================
    $display("\n--- TC18: Back-to-back writes ---");
    axi_write(4'h1, BASE + REG_IRQ_MASK, 32'h0, 4'hF, resp_val);
    check("BBwr[0] OKAY", {30'd0, resp_val}, 32'd0);
    axi_write(4'h2, BASE + REG_IRQ_MASK, 32'h1, 4'hF, resp_val);
    check("BBwr[1] OKAY", {30'd0, resp_val}, 32'd0);
    axi_read(4'h1, BASE + REG_IRQ_MASK,  rdata_val, resp_val);
    check("BBwr result",  rdata_val[0], 1'b1);

    // =========================================================================
    // TC19 — BREADY backpressure
    // =========================================================================
    $display("\n--- TC19: BREADY backpressure ---");
    axi_write_bp(4'h3, BASE + REG_IRQ_MASK, 32'h0, 4'hF, 5, resp_val);
    check("BP_B OKAY",   {30'd0, resp_val}, 32'd0);
    axi_read(4'h1, BASE + REG_IRQ_MASK, rdata_val, resp_val);
    check("BP_B result", rdata_val[0], 1'b0);

    // =========================================================================
    // TC20 — RREADY backpressure
    // =========================================================================
    $display("\n--- TC20: RREADY backpressure ---");
    axi_read_bp(4'h5, BASE + REG_SYS_ID, 5, rdata_val, resp_val);
    check("BP_R SYS_ID", rdata_val, 32'hA5C0_0001);
    check("BP_R RRESP",  {30'd0, resp_val}, 32'd0);

    // =========================================================================
    // TC21 — Write + read close succession
    // =========================================================================
    $display("\n--- TC21: Write+read succession ---");
    axi_write(4'h1, BASE + REG_IRQ_MASK, 32'h1, 4'hF, resp_val);
    check("SIM wr OKAY", {30'd0, resp_val}, 32'd0);
    axi_read(4'h2, BASE + REG_SYS_ID, rdata_val, resp_val);
    check("SIM rd SYS_ID",rdata_val, 32'hA5C0_0001);

    // =========================================================================
    // TC22 — Multiple IRQ pulses: re-sets after W1C
    // =========================================================================
    $display("\n--- TC22: Multiple IRQ pulses ---");
    axi_write(4'h1, BASE + REG_IRQ_STATUS, 32'h1, 4'hF, resp_val);
    clk_delay(2);
    axi_read(4'h1, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("TC22 cleared", rdata_val[0], 1'b0);
    @(negedge clk); ascon_irq = 1; clk_delay(2); @(negedge clk); ascon_irq = 0; clk_delay(2);
    axi_read(4'h1, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("TC22 1st set", rdata_val[0], 1'b1);
    axi_write(4'h1, BASE + REG_IRQ_STATUS, 32'h1, 4'hF, resp_val);
    clk_delay(2);
    axi_read(4'h1, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("TC22 clrd",    rdata_val[0], 1'b0);
    @(negedge clk); ascon_irq = 1; clk_delay(2); @(negedge clk); ascon_irq = 0; clk_delay(2);
    axi_read(4'h1, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("TC22 2nd set", rdata_val[0], 1'b1);

    // =========================================================================
    // TC23 — IRQ_MASK=0 does NOT suppress sticky
    // =========================================================================
    $display("\n--- TC23: MASK=0 does not suppress sticky ---");
    axi_write(4'h1, BASE + REG_IRQ_STATUS, 32'h1, 4'hF, resp_val);
    axi_write(4'h1, BASE + REG_IRQ_MASK,   32'h0, 4'hF, resp_val);
    clk_delay(2);
    @(negedge clk); ascon_irq = 1; clk_delay(2); @(negedge clk); ascon_irq = 0; clk_delay(2);
    axi_read(4'h1, BASE + REG_IRQ_STATUS, rdata_val, resp_val);
    check("MASK=0 sticky", rdata_val[0], 1'b1);

    // =========================================================================
    // TC24 — RLAST always 1
    // =========================================================================
    $display("\n--- TC24: RLAST always 1 ---");
    begin : tc24
        integer rlast_ok;
        rlast_ok = 1;
        axi_read(4'h1, BASE + REG_SYS_ID,    rdata_val, resp_val);
        if (m_rlast !== 1'b1) rlast_ok = 0;
        axi_read(4'h1, BASE + REG_CYCLE_CNT, rdata_val, resp_val);
        if (m_rlast !== 1'b1) rlast_ok = 0;
        axi_read(4'h1, BASE + 32'h200,       rdata_val, resp_val);
        if (m_rlast !== 1'b1) rlast_ok = 0;
        check("RLAST always 1", rlast_ok, 1);
    end

    // =========================================================================
    // TC25 — RRESP always OKAY
    // =========================================================================
    $display("\n--- TC25: RRESP always OKAY ---");
    begin : tc25
        integer rresp_ok;
        rresp_ok = 1;
        axi_read(4'h1, BASE + REG_SYS_ID,  rdata_val, resp_val);
        if (resp_val !== 2'b00) rresp_ok = 0;
        axi_read(4'h1, BASE + 32'hFFC,     rdata_val, resp_val);
        if (resp_val !== 2'b00) rresp_ok = 0;
        axi_read(4'h1, BASE + REG_IRQ_MASK,rdata_val, resp_val);
        if (resp_val !== 2'b00) rresp_ok = 0;
        check("RRESP always 00", rresp_ok, 1);
    end

    // =========================================================================
    // HART_ID read (TC bonus)
    // =========================================================================
    $display("\n--- TC bonus: HART_ID read ---");
    axi_read(4'h1, BASE + REG_HART_ID, rdata_val, resp_val);
    check("HART_ID=0", rdata_val, 32'd0);

    // =========================================================================
    // Summary
    // =========================================================================
    $display("");
    $display("=========================================================");
    $display("  PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("  *** ALL A10 TESTS PASSED ***");
    else
        $display("  *** %0d FAILED — check log above ***", fail_cnt);
    $display("=========================================================");
    clk_delay(10);
    $finish;
end

// Watchdog
initial begin
    #1000000;
    $display("[WATCHDOG] timeout (1ms) — AXI deadlock?");
    $finish;
end

endmodule
