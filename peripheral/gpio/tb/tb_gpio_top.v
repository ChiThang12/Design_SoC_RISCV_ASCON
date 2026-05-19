`timescale 1ns/1ps

// ============================================================================
// tb_gpio_top.v  —  Testbench for gpio_top
// ============================================================================

`include "peripheral/gpio/gpio_top.v"

module tb_gpio_top;

parameter CLK_PERIOD = 10;
parameter CLK_AON_PERIOD = 32;

parameter ADDR_WIDTH = 32;
parameter DATA_WIDTH = 32;
parameter ID_WIDTH   = 4;
parameter GPIO_WIDTH = 32;

parameter BASE         = 32'h5001_0000;
parameter REG_DIR      = 8'h00;
parameter REG_DOUT     = 8'h04;
parameter REG_DIN      = 8'h08;
parameter REG_IRQ_EN   = 8'h0C;
parameter REG_IRQ_STAT = 8'h10;
parameter REG_IRQ_MODE = 8'h14;
parameter REG_IRQ_POL  = 8'h18;

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

// ---- GPIO Pads ----
wire [GPIO_WIDTH-1:0] gpio_out;
wire [GPIO_WIDTH-1:0] gpio_oe;
reg  [GPIO_WIDTH-1:0] gpio_in;

// ---- IRQ ----
wire gpio_irq;
reg  gpio_irq_latched;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) gpio_irq_latched <= 1'b0;
    else if (gpio_irq) gpio_irq_latched <= 1'b1;
end

wire gpio_wake_armed_o;
reg  wake_ack;
wire gpio_wake_req;

// ---- DUT ----
gpio_top #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH),
    .GPIO_WIDTH(GPIO_WIDTH)
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

    .gpio_out      (gpio_out),
    .gpio_oe       (gpio_oe),
    .gpio_in       (gpio_in),

    .gpio_irq      (gpio_irq),
    .gpio_wake_armed_o(gpio_wake_armed_o),

    .clk_aon       (clk_aon),
    .aon_rst_n     (aon_rst_n),
    .wake_ack      (wake_ack),
    .gpio_wake_req (gpio_wake_req)
);

// ---- Waveform & Timeout ----
initial begin
    $dumpfile("tb_gpio_top.vcd");
    $dumpvars(0, tb_gpio_top);
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
        gpio_in = 0;
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
    $display("=== START: tb_gpio_top ===");
    $display("======================================================");

    do_reset;

    $display("\n--- TC01: Initial Reset Values ---");
    read_reg(REG_DIR, rd_data);      check_eq(rd_data, 32'h0, "DIR reset value");
    read_reg(REG_DOUT, rd_data);     check_eq(rd_data, 32'h0, "DOUT reset value");
    read_reg(REG_IRQ_EN, rd_data);   check_eq(rd_data, 32'h0, "IRQ_EN reset value");
    read_reg(REG_IRQ_STAT, rd_data); check_eq(rd_data, 32'h0, "IRQ_STAT reset value");
    read_reg(REG_IRQ_MODE, rd_data); check_eq(rd_data, 32'h0, "IRQ_MODE reset value");
    read_reg(REG_IRQ_POL, rd_data);  check_eq(rd_data, 32'h0, "IRQ_POL reset value");
    check_eq(gpio_irq, 32'h0, "gpio_irq reset value");

    $display("\n--- TC02: Output Control (DIR & DOUT) ---");
    write_reg(REG_DIR, 32'h0000_FFFF, 4'hF);
    write_reg(REG_DOUT, 32'h0000_A5A5, 4'hF);
    repeat(3) @(posedge clk);
    check_eq(gpio_oe,  32'h0000_FFFF, "gpio_oe matches DIR");
    check_eq(gpio_out & 32'h0000_FFFF, 32'h0000_A5A5, "gpio_out matches DOUT for outputs");
    
    $display("\n--- TC03: Input Sync (DIN) ---");
    gpio_in = 32'hDEAD_BEEF;
    repeat(5) @(posedge clk); // Allow 2-FF sync
    read_reg(REG_DIN, rd_data);
    check_eq(rd_data, 32'hDEAD_BEEF, "DIN correctly synchronizes gpio_in");

    $display("\n--- TC04: Edge IRQ Generation ---");
    // Enable IRQ on GPIO 0 and 1
    write_reg(REG_IRQ_EN, 32'h0000_0003, 4'hF);
    // Mode = edge for bit 0, 1
    write_reg(REG_IRQ_MODE, 32'h0000_0003, 4'hF);
    // Pol = rising edge for bit 0, falling edge for bit 1
    write_reg(REG_IRQ_POL, 32'h0000_0001, 4'hF);
    
    gpio_in = 32'h0000_0002; // Initial state: bit 0 is low, bit 1 is high
    repeat(5) @(posedge clk);
    check_eq(gpio_irq, 32'h0, "No IRQ initially");
    
    // Toggle bit 0 to high (rising edge) and bit 1 to low (falling edge)
    gpio_in = 32'h0000_0001;
    repeat(5) @(posedge clk);
    
    read_reg(REG_IRQ_STAT, rd_data);
    check_eq(rd_data, 32'h0000_0003, "IRQ_STAT caught rising edge on bit 0 and falling on bit 1");
    check_eq({31'd0, gpio_irq_latched}, 32'h1, "gpio_irq pulsed");

    $display("\n--- TC05: IRQ Clear (W1C) ---");
    write_reg(REG_IRQ_STAT, 32'h0000_0001, 4'hF); // Clear bit 0
    repeat(3) @(posedge clk);
    read_reg(REG_IRQ_STAT, rd_data);
    check_eq(rd_data, 32'h0000_0002, "IRQ_STAT bit 0 cleared, bit 1 remains");
    
    write_reg(REG_IRQ_STAT, 32'h0000_0002, 4'hF); // Clear bit 1
    repeat(3) @(posedge clk);
    read_reg(REG_IRQ_STAT, rd_data);
    check_eq(rd_data, 32'h0, "IRQ_STAT bit 1 cleared");

    $display("\n--- TC06: AON Wake Mechanism ---");
    // Clear the wake request from TC04 first
    @(posedge clk_aon); wake_ack = 1'b1;
    @(posedge clk_aon); wake_ack = 1'b0;
    repeat(5) @(posedge clk_aon);
    
    check_eq({31'd0, gpio_wake_req}, 32'h0, "gpio_wake_req initially 0");
    // Any edge on any enabled IRQ pin triggers wake request
    gpio_in = 32'h0000_0000;
    repeat(10) @(posedge clk_aon);
    gpio_in = 32'h0000_0001; // bit 0 edge
    repeat(10) @(posedge clk_aon);
    check_eq(gpio_wake_req, 32'h1, "gpio_wake_req asserted on edge");
    
    @(posedge clk_aon);
    wake_ack = 1'b1;
    @(posedge clk_aon);
    wake_ack = 1'b0;
    repeat(5) @(posedge clk_aon);
    check_eq(gpio_wake_req, 32'h0, "gpio_wake_req cleared by wake_ack");

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
