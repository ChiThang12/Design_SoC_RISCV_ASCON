`timescale 1ns/1ps

// ============================================================================
// tb_spi_top.v  —  Testbench for spi_top
// ============================================================================

`include "peripheral/spi/spi_top.v"

module tb_spi_top;

parameter CLK_PERIOD = 10;

parameter AXI_ADDR_WIDTH = 32;
parameter AXI_DATA_WIDTH = 32;
parameter AXI_ID_WIDTH   = 4;

parameter BASE         = 32'h5002_0000;
parameter REG_TX_DATA  = 8'h00;
parameter REG_RX_DATA  = 8'h04;
parameter REG_STATUS   = 8'h08;
parameter REG_CTRL     = 8'h0C;
parameter REG_DIVIDER  = 8'h10;
parameter REG_IRQ_STAT = 8'h14;
parameter REG_CS_CTRL  = 8'h18;

// ---- Clock & Reset ----
reg clk;
reg rst_n;

initial clk = 1'b0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---- AXI signals ----
reg  [AXI_ID_WIDTH-1:0]   awid;
reg  [AXI_ADDR_WIDTH-1:0] awaddr;
reg  [7:0]                awlen;
reg  [2:0]                awsize;
reg  [1:0]                awburst;
reg  [2:0]                awprot;
reg                       awvalid;
wire                      awready;

reg  [AXI_DATA_WIDTH-1:0] wdata;
reg  [3:0]                wstrb;
reg                       wlast;
reg                       wvalid;
wire                      wready;

wire [AXI_ID_WIDTH-1:0]   bid;
wire [1:0]                bresp;
wire                      bvalid;
reg                       bready;

reg  [AXI_ID_WIDTH-1:0]   arid;
reg  [AXI_ADDR_WIDTH-1:0] araddr;
reg  [7:0]                arlen;
reg  [2:0]                arsize;
reg  [1:0]                arburst;
reg  [2:0]                arprot;
reg                       arvalid;
wire                      arready;

wire [AXI_ID_WIDTH-1:0]   rid;
wire [AXI_DATA_WIDTH-1:0] rdata;
wire [1:0]                rresp;
wire                      rlast;
wire                      rvalid;
reg                       rready;

// ---- SPI pads ----
wire       sck;
wire       mosi;
wire       miso;
wire [3:0] cs_n;

// Loopback
assign miso = mosi;

// ---- IRQ & DMA ----
wire irq_out;
wire tx_dma_req;
wire rx_dma_req;

reg irq_latched;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) irq_latched <= 1'b0;
    else if (irq_out) irq_latched <= 1'b1;
end

// ---- DUT ----
spi_top #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .TX_FIFO_DEPTH(16),
    .RX_FIFO_DEPTH(16),
    .CS_WIDTH(4)
) u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axi_awid    (awid),
    .s_axi_awaddr  (awaddr),
    .s_axi_awlen   (awlen),
    .s_axi_awsize  (awsize),
    .s_axi_awburst (awburst),
    .s_axi_awvalid (awvalid),
    .s_axi_awready (awready),
    .s_axi_wdata   (wdata),
    .s_axi_wstrb   (wstrb),
    .s_axi_wlast   (wlast),
    .s_axi_wvalid  (wvalid),
    .s_axi_wready  (wready),
    .s_axi_bid     (bid),
    .s_axi_bresp   (bresp),
    .s_axi_bvalid  (bvalid),
    .s_axi_bready  (bready),
    .s_axi_arid    (arid),
    .s_axi_araddr  (araddr),
    .s_axi_arlen   (arlen),
    .s_axi_arsize  (arsize),
    .s_axi_arburst (arburst),
    .s_axi_arvalid (arvalid),
    .s_axi_arready (arready),
    .s_axi_rid     (rid),
    .s_axi_rdata   (rdata),
    .s_axi_rresp   (rresp),
    .s_axi_rlast   (rlast),
    .s_axi_rvalid  (rvalid),
    .s_axi_rready  (rready),

    .sck           (sck),
    .mosi          (mosi),
    .miso          (miso),
    .cs_n          (cs_n),

    .irq_out       (irq_out),
    .tx_dma_req    (tx_dma_req),
    .rx_dma_req    (rx_dma_req)
);

// ---- Waveform & Timeout ----
initial begin
    $dumpfile("tb_spi_top.vcd");
    $dumpvars(0, tb_spi_top);
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
        rst_n=1'b0;
        awvalid=1'b0; wvalid=1'b0; bready=1'b0;
        arvalid=1'b0; rready=1'b0;
        awid=0; awaddr=0; awlen=0; awsize=3'b010; awburst=2'b01; awprot=0;
        wdata=0; wstrb=4'hF; wlast=0;
        arid=0; araddr=0; arlen=0; arsize=3'b010; arburst=2'b01; arprot=0;
        repeat(10) @(posedge clk);
        rst_n=1'b1;
        repeat(5)  @(posedge clk);
    end
endtask

// ============================================================
// MAIN TEST
// ============================================================
initial begin
    pass_count=0; fail_count=0;
    $display("======================================================");
    $display("=== START: tb_spi_top ===");
    $display("======================================================");

    do_reset;

    $display("\n--- TC01: Initial Reset Values ---");
    read_reg(REG_CTRL, rd_data); check_eq(rd_data, 32'h40, "CTRL reset (cs_auto=1)");
    read_reg(REG_DIVIDER, rd_data); check_eq(rd_data, 32'h4, "DIVIDER reset");
    read_reg(REG_STATUS, rd_data); check_eq(rd_data, 32'h0A, "STATUS reset (tx_empty=1, rx_empty=1)");
    read_reg(REG_CS_CTRL, rd_data); check_eq(rd_data, 32'hF, "CS_CTRL reset (all high)");
    check_eq({31'd0, tx_dma_req}, 32'h1, "TX DMA REQ=1 (fifo empty)");
    check_eq({31'd0, rx_dma_req}, 32'h0, "RX DMA REQ=0 (fifo empty)");

    $display("\n--- TC02: Write TX FIFO ---");
    write_reg(REG_TX_DATA, 32'hAA, 4'hF);
    repeat(3) @(posedge clk);
    read_reg(REG_STATUS, rd_data);
    // status[3] = rx_empty(1), status[1] = tx_empty(0) => 00_1000 = 0x08
    check_eq(rd_data, 32'h08, "STATUS after TX push (tx_empty=0)");
    
    $display("\n--- TC03: SPI Loopback Transfer ---");
    irq_latched = 0;
    // Set DIVIDER=1 (SCK = clk/4)
    write_reg(REG_DIVIDER, 32'h1, 4'hF);
    // Set CTRL: spi_en=1, cs_auto=1, cpol=0, cpha=0, rx_irq_en=1, tx_irq_en=1
    // Bit 7: en=1
    // Bit 6: cs_auto=1
    // Bit 5: cpol=0
    // Bit 4: cpha=0
    // Bit 1: rx_irq_en=1
    // Bit 0: tx_irq_en=1
    // -> 0xC3
    write_reg(REG_CTRL, 32'hC3, 4'hF);
    
    // Wait for transfer to complete (1 byte = 8 bits, each bit 4 cycles = 32 cycles + overhead)
    repeat(50) @(posedge clk);
    
    read_reg(REG_STATUS, rd_data);
    // tx_empty(1), rx_empty(0) => 00_0010 = 0x02
    check_eq(rd_data, 32'h02, "STATUS after transfer (rx has data, tx empty)");
    check_eq({31'd0, irq_latched}, 32'h1, "IRQ pulsed");
    
    read_reg(REG_RX_DATA, rd_data);
    check_eq(rd_data, 32'hAA, "RX DATA matches sent TX DATA (loopback)");

    read_reg(REG_STATUS, rd_data);
    // rx_empty(1), tx_empty(1) => 00_1010 = 0x0A
    check_eq(rd_data, 32'h0A, "STATUS after pop (both empty)");

    $display("\n--- TC04: Clear IRQ (W1C) ---");
    read_reg(REG_IRQ_STAT, rd_data);
    check_eq(rd_data, 32'h3, "IRQ_STAT = 3 (rx_valid and tx_empty)");
    
    write_reg(REG_IRQ_STAT, 32'h3, 4'hF);
    repeat(3) @(posedge clk);
    read_reg(REG_IRQ_STAT, rd_data);
    check_eq(rd_data, 32'h0, "IRQ_STAT cleared");

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
