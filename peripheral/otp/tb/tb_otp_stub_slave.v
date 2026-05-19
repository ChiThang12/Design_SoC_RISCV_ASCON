`timescale 1ns/1ps

// ============================================================================
// tb_otp_stub_slave.v  —  Testbench for otp_stub_slave
// ============================================================================

`include "peripheral/otp/otp_stub_slave.v"

module tb_otp_stub_slave;

parameter CLK_PERIOD = 10;

parameter ADDR_WIDTH = 32;
parameter DATA_WIDTH = 32;
parameter ID_WIDTH   = 4;

parameter BASE       = 32'h6000_0000;

// ---- Clock & Reset ----
reg clk;
reg rst_n;

initial clk = 1'b0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---- AXI signals ----
reg  [ID_WIDTH-1:0]   awid;
reg  [ADDR_WIDTH-1:0] awaddr;
reg  [7:0]            awlen;
reg  [2:0]            awsize;
reg  [1:0]            awburst;
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
reg                   arvalid;
wire                  arready;

wire [ID_WIDTH-1:0]   rid;
wire [DATA_WIDTH-1:0] rdata;
wire [1:0]            rresp;
wire                  rlast;
wire                  rvalid;
reg                   rready;

// ---- DUT ----
otp_stub_slave #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH)
) u_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .s_arid    (arid),
    .s_araddr  (araddr),
    .s_arlen   (arlen),
    .s_arsize  (arsize),
    .s_arburst (arburst),
    .s_arvalid (arvalid),
    .s_arready (arready),
    .s_rid     (rid),
    .s_rdata   (rdata),
    .s_rresp   (rresp),
    .s_rlast   (rlast),
    .s_rvalid  (rvalid),
    .s_rready  (rready),
    .s_awid    (awid),
    .s_awaddr  (awaddr),
    .s_awlen   (awlen),
    .s_awvalid (awvalid),
    .s_awready (awready),
    .s_wdata   (wdata),
    .s_wstrb   (wstrb),
    .s_wlast   (wlast),
    .s_wvalid  (wvalid),
    .s_wready  (wready),
    .s_bid     (bid),
    .s_bresp   (bresp),
    .s_bvalid  (bvalid),
    .s_bready  (bready)
);

// ---- Waveform & Timeout ----
initial begin
    $dumpfile("tb_otp_stub_slave.vcd");
    $dumpvars(0, tb_otp_stub_slave);
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
        awburst=2'b01; awvalid=1'b1;
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
        arburst=2'b01; arvalid=1'b1;
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

reg [31:0] rd_data;
task read_reg;
    input  [7:0]  off;
    output [31:0] dat;
    begin axi_read(4'h2, BASE|{24'h0,off}, dat); end
endtask

task write_reg;
    input [7:0]  off;
    input [31:0] dat;
    input [3:0]  strb;
    begin axi_write(4'h1, BASE|{24'h0,off}, dat, strb); end
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
        awid=0; awaddr=0; awlen=0; awsize=3'b010; awburst=2'b01;
        wdata=0; wstrb=4'hF; wlast=0;
        arid=0; araddr=0; arlen=0; arsize=3'b010; arburst=2'b01;
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
    $display("=== START: tb_otp_stub_slave ===");
    $display("======================================================");

    do_reset;

    $display("\n--- TC01: Read Device ID and Version ---");
    read_reg(8'h00, rd_data); check_eq(rd_data, 32'hA5C0_CAFE, "DEVICE_ID");
    read_reg(8'h04, rd_data); check_eq(rd_data, 32'h0000_0001, "OTP_VER");

    $display("\n--- TC02: Read Unprogrammed Region ---");
    read_reg(8'h08, rd_data); check_eq(rd_data, 32'hDEAD_BEEF, "Offset 0x08");
    read_reg(8'hFC, rd_data); check_eq(rd_data, 32'hDEAD_BEEF, "Offset 0xFC");

    $display("\n--- TC03: Write Ignored ---");
    write_reg(8'h08, 32'h1234_5678, 4'hF);
    read_reg(8'h08, rd_data); check_eq(rd_data, 32'hDEAD_BEEF, "Offset 0x08 remains unprogrammed after write");

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
