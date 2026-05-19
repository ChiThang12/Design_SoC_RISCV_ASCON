`timescale 1ns/1ps

// ============================================================================
// tb_timer_top.v  —  Testbench for timer_top
// ============================================================================

`include "peripheral/timer/timer_top.v"

module tb_timer_top;

parameter CLK_PERIOD = 10;
parameter CLK_AON_PERIOD = 32;

parameter ADDR_WIDTH = 32;
parameter DATA_WIDTH = 32;
parameter ID_WIDTH   = 4;

parameter BASE         = 32'h5003_0000;
parameter REG_T0_CTRL   = 8'h00;
parameter REG_T0_LOAD   = 8'h04;
parameter REG_T0_COUNT  = 8'h08;
parameter REG_T0_STATUS = 8'h0C;
parameter REG_T1_CTRL   = 8'h10;
parameter REG_T1_LOAD   = 8'h14;
parameter REG_T1_COUNT  = 8'h18;
parameter REG_T1_STATUS = 8'h1C;
parameter REG_WDT_CTRL  = 8'h20;
parameter REG_WDT_LOAD  = 8'h24;
parameter REG_WDT_FEED  = 8'h28;
parameter REG_WDT_STAT  = 8'h2C;

// ---- Clock & Reset ----
reg clk, clk_aon;
reg rst_n, aon_rst_n;

initial clk = 1'b0;
always #(CLK_PERIOD/2) clk = ~clk;

initial clk_aon = 1'b0;
always #(CLK_AON_PERIOD/2) clk_aon = ~clk_aon;

// ---- AXI signals ----
reg  [ID_WIDTH-1:0]   awid;
reg  [ADDR_WIDTH-1:0] awaddr;
reg  [7:0]            awlen;
reg  [2:0]            awsize;
reg  [1:0]            awburst;
reg  [2:0]            awprot;
reg                   awvalid;
wire                  awready;

reg  [DATA_WIDTH-1:0] wdata;
reg  [3:0]            wstrb;
reg                   wlast;
reg                   wvalid;
wire                  wready;

wire [ID_WIDTH-1:0]   bid;
wire [1:0]            bresp;
wire                  bvalid;
reg                   bready;

reg  [ID_WIDTH-1:0]   arid;
reg  [ADDR_WIDTH-1:0] araddr;
reg  [7:0]            arlen;
reg  [2:0]            arsize;
reg  [1:0]            arburst;
reg  [2:0]            arprot;
reg                   arvalid;
wire                  arready;

wire [ID_WIDTH-1:0]   rid;
wire [DATA_WIDTH-1:0] rdata;
wire [1:0]            rresp;
wire                  rlast;
wire                  rvalid;
reg                   rready;

// ---- IRQ ----
wire timer0_irq, timer1_irq, wdt_irq;
wire wdt_rst_req, timer_active_o;
reg  wake_ack;
wire timer_wake_req;

reg t0_irq_latched, t1_irq_latched, wdt_irq_latched;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        t0_irq_latched <= 1'b0;
        t1_irq_latched <= 1'b0;
        wdt_irq_latched<= 1'b0;
    end else begin
        if (timer0_irq) t0_irq_latched <= 1'b1;
        if (timer1_irq) t1_irq_latched <= 1'b1;
        if (wdt_irq)    wdt_irq_latched<= 1'b1;
    end
end

// ---- DUT ----
timer_top #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH)
) u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .S_AXI_AWID    (awid),
    .S_AXI_AWADDR  (awaddr),
    .S_AXI_AWLEN   (awlen),
    .S_AXI_AWSIZE  (awsize),
    .S_AXI_AWBURST (awburst),
    .S_AXI_AWPROT  (awprot),
    .S_AXI_AWVALID (awvalid),
    .S_AXI_AWREADY (awready),
    .S_AXI_WDATA   (wdata),
    .S_AXI_WSTRB   (wstrb),
    .S_AXI_WLAST   (wlast),
    .S_AXI_WVALID  (wvalid),
    .S_AXI_WREADY  (wready),
    .S_AXI_BID     (bid),
    .S_AXI_BRESP   (bresp),
    .S_AXI_BVALID  (bvalid),
    .S_AXI_BREADY  (bready),
    .S_AXI_ARID    (arid),
    .S_AXI_ARADDR  (araddr),
    .S_AXI_ARLEN   (arlen),
    .S_AXI_ARSIZE  (arsize),
    .S_AXI_ARBURST (arburst),
    .S_AXI_ARPROT  (arprot),
    .S_AXI_ARVALID (arvalid),
    .S_AXI_ARREADY (arready),
    .S_AXI_RID     (rid),
    .S_AXI_RDATA   (rdata),
    .S_AXI_RRESP   (rresp),
    .S_AXI_RLAST   (rlast),
    .S_AXI_RVALID  (rvalid),
    .S_AXI_RREADY  (rready),

    .timer0_irq    (timer0_irq),
    .timer1_irq    (timer1_irq),
    .wdt_irq       (wdt_irq),

    .wdt_rst_req   (wdt_rst_req),
    .timer_active_o(timer_active_o),

    .clk_aon       (clk_aon),
    .aon_rst_n     (aon_rst_n),
    .wake_ack      (wake_ack),
    .timer_wake_req(timer_wake_req)
);

// ---- Waveform & Timeout ----
initial begin
    $dumpfile("tb_timer_top.vcd");
    $dumpvars(0, tb_timer_top);
end
initial begin
    #(1_000_000);  // 1ms timeout
    $display("[FAIL] SIMULATION TIMEOUT!");
    $finish;
end

// ============================================================
// Score
// ============================================================
integer pass_count;
integer fail_count;

// ============================================================
// BFM Tasks
// ============================================================
task axi_write;
    input [3:0]  t_id;
    input [31:0] t_addr;
    input [31:0] t_data;
    input [3:0]  t_strb;
    begin
        @(posedge clk); #1;
        awid=t_id; awaddr=t_addr; awlen=8'h0; awsize=3'b010;
        awburst=2'b01; awprot=3'b000; awvalid=1'b1;
        wait(awready===1'b1); @(posedge clk); #1; awvalid=1'b0;
        wdata=t_data; wstrb=t_strb; wlast=1'b1; wvalid=1'b1;
        wait(wready===1'b1);  @(posedge clk); #1; wvalid=1'b0; wlast=1'b0;
        bready=1'b1;
        wait(bvalid===1'b1);
        if (bid !== t_id) begin
            $display("[FAIL] AXI BID=%0d != AWID=%0d", bid, t_id);
            fail_count = fail_count+1;
        end
        if (bresp !== 2'b00) begin
            $display("[FAIL] AXI BRESP=%02b addr=0x%08h", bresp, t_addr);
            fail_count = fail_count+1;
        end
        @(posedge clk); #1; bready=1'b0;
        @(posedge clk); #1;
    end
endtask

task axi_read;
    input  [3:0]  t_id;
    input  [31:0] t_addr;
    output [31:0] t_data;
    begin
        @(posedge clk); #1;
        arid=t_id; araddr=t_addr; arlen=8'h0; arsize=3'b010;
        arburst=2'b01; arprot=3'b000; arvalid=1'b1;
        wait(arready===1'b1); @(posedge clk); #1; arvalid=1'b0;
        rready=1'b1;
        wait(rvalid===1'b1);
        t_data=rdata;
        if (rid !== t_id) begin
            $display("[FAIL] AXI RID=%0d != ARID=%0d", rid, t_id);
            fail_count = fail_count+1;
        end
        if (rresp !== 2'b00) begin
            $display("[FAIL] AXI RRESP=%02b addr=0x%08h", rresp, t_addr);
            fail_count = fail_count+1;
        end
        if (rlast !== 1'b1) begin
            $display("[FAIL] AXI RLAST=0 on single beat");
            fail_count = fail_count+1;
        end
        @(posedge clk); #1; rready=1'b0;
        @(posedge clk); #1;
    end
endtask

task write_reg;
    input [7:0]  off;
    input [31:0] dat;
    input [3:0]  strb;
    begin axi_write(4'h1, BASE|{24'h0,off}, dat, strb); end
endtask

reg [31:0] rd_data;
task read_reg;
    input  [7:0]  off;
    output [31:0] dat;
    begin axi_read(4'h2, BASE|{24'h0,off}, dat); end
endtask

task check_eq;
    input [31:0]   actual;
    input [31:0]   expected;
    input [8*48-1:0] name;
    begin
        if (actual === expected) begin
            $display("[PASS] %s: 0x%08h", name, actual);
            pass_count = pass_count+1;
        end else begin
            $display("[FAIL] %s: got=0x%08h exp=0x%08h", name, actual, expected);
            fail_count = fail_count+1;
        end
    end
endtask

task do_reset;
    begin
        rst_n=1'b0; aon_rst_n=1'b0; wake_ack=1'b0;
        awvalid=1'b0; wvalid=1'b0; bready=1'b0;
        arvalid=1'b0; rready=1'b0;
        awid=0; awaddr=0; awlen=0; awsize=3'b010; awburst=2'b01; awprot=0;
        wdata=0; wstrb=4'hF; wlast=0;
        arid=0; araddr=0; arlen=0; arsize=3'b010; arburst=2'b01; arprot=0;
        repeat(10) @(posedge clk);
        rst_n=1'b1; aon_rst_n=1'b1;
        repeat(5)  @(posedge clk);
    end
endtask

// ============================================================
// MAIN TEST
// ============================================================
initial begin
    pass_count=0; fail_count=0;
    $display("======================================================");
    $display("=== START: tb_timer_top ===");
    $display("======================================================");

    do_reset;

    $display("\n--- TC01: Initial Reset Values ---");
    read_reg(REG_T0_CTRL, rd_data); check_eq(rd_data, 32'h0, "T0_CTRL reset");
    read_reg(REG_T1_CTRL, rd_data); check_eq(rd_data, 32'h0, "T1_CTRL reset");
    read_reg(REG_WDT_CTRL, rd_data); check_eq(rd_data, 32'h0, "WDT_CTRL reset");

    $display("\n--- TC02: Timer0 One-Shot Down-count ---");
    t0_irq_latched = 0;
    write_reg(REG_T0_LOAD, 32'd10, 4'hF);
    // CTRL: en=1, auto_reload=0, irq_en=1, count_dir=0 (down) -> 0x5
    write_reg(REG_T0_CTRL, 32'h5, 4'hF);
    repeat(12) @(posedge clk);
    read_reg(REG_T0_COUNT, rd_data);
    check_eq(rd_data, 32'd0, "T0_COUNT reached 0 and stopped");
    check_eq({31'd0, t0_irq_latched}, 32'h1, "T0 IRQ pulsed");
    read_reg(REG_T0_STATUS, rd_data);
    check_eq(rd_data, 32'h1, "T0 timeout_flag set");
    // Disable T0 so timeout_flag can be cleared
    write_reg(REG_T0_CTRL, 32'h0, 4'hF);
    // Clear flag
    write_reg(REG_T0_STATUS, 32'h1, 4'hF);
    repeat(2) @(posedge clk);
    read_reg(REG_T0_STATUS, rd_data);
    check_eq(rd_data, 32'h0, "T0 timeout_flag cleared");

    $display("\n--- TC03: Timer1 Auto-reload Down-count ---");
    t1_irq_latched = 0;
    write_reg(REG_T1_LOAD, 32'd5, 4'hF);
    // CTRL: en=1, auto_reload=1, irq_en=1, count_dir=0 (down) -> 0x7
    write_reg(REG_T1_CTRL, 32'h7, 4'hF);
    repeat(14) @(posedge clk);
    read_reg(REG_T1_COUNT, rd_data);
    if (rd_data != 32'd0 && rd_data <= 32'd5) begin
        $display("[PASS] T1_COUNT is auto-reloading properly: %0d", rd_data);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] T1_COUNT auto-reload failed: %0d", rd_data);
        fail_count = fail_count + 1;
    end
    check_eq({31'd0, t1_irq_latched}, 32'h1, "T1 IRQ pulsed");
    // disable timer1
    write_reg(REG_T1_CTRL, 32'h0, 4'hF);
    // Clear T1 flag
    write_reg(REG_T1_STATUS, 32'h1, 4'hF);

    $display("\n--- TC04: WDT Count and Feed ---");
    wdt_irq_latched = 0;
    write_reg(REG_WDT_LOAD, 32'd20, 4'hF);
    // CTRL: en=1, irq_en=1 -> 0x3
    write_reg(REG_WDT_CTRL, 32'h3, 4'hF);
    repeat(10) @(posedge clk);
    write_reg(REG_WDT_FEED, 32'hDEAD_FEED, 4'hF); // feed watchdog
    repeat(15) @(posedge clk);
    check_eq({31'd0, wdt_rst_req}, 32'h0, "WDT not reset yet due to feed");
    repeat(10) @(posedge clk);
    check_eq({31'd0, wdt_rst_req}, 32'h1, "WDT triggered reset");
    check_eq({31'd0, wdt_irq_latched}, 32'h1, "WDT IRQ pulsed");

    // disable WDT
    write_reg(REG_WDT_CTRL, 32'h0, 4'hF);
    // Clear WDT flag
    write_reg(REG_WDT_STAT, 32'h1, 4'hF);
    
    // Wait for the cleared flags to propagate through the CDC to clk_aon domain
    repeat(4) @(posedge clk_aon);

    $display("\n--- TC05: Timer Wake Mechanism ---");
    // wake_req was set by the previous timeouts and held because wake_ack wasn't sent
    check_eq({31'd0, timer_wake_req}, 32'h1, "timer_wake_req is asserted due to timeout");
    @(posedge clk_aon); wake_ack = 1'b1;
    @(posedge clk_aon); wake_ack = 1'b0;
    repeat(5) @(posedge clk_aon);
    check_eq({31'd0, timer_wake_req}, 32'h0, "timer_wake_req cleared by wake_ack");

    $display("\n======================================================");
    $display("  PASS: %0d  FAIL: %0d", pass_count, fail_count);
    if (fail_count == 0)
        $display("  *** ALL TESTS PASSED ***");
    else
        $display("  *** %0d FAILED ***", fail_count);
    $display("======================================================");
    $finish;
end

endmodule
