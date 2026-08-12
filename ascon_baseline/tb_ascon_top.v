`timescale 1ns/1ps

// ============================================================================
// Testbench : tb_ascon_top.v
// Target    : ascon_ip_top v5 (bỏ AXI-Stream, fix DMA race)
// Standard  : Verilog-2001, iverilog compatible
//
// Dựa trên kết quả verify từ tb_ascon_CORE:
//   KEY   = 000102030405060708090A0B0C0D0E0F
//   NONCE = 101112131415161718191A1B1C1D1E1F
//   PT    = 6173636F6E  ("ascon", 5 bytes)
//   CT    = a9919fa26e (CPU-Direct, no AD)
//   TAG   = f1a4d483f02f1979dad8aef9985b6148
//
// Tests:
//   TEST 1: CPU-Direct Encrypt (ASCON-128)
//   TEST 2: CPU-Direct Decrypt (self-consistency round-trip)
//   TEST 3: Soft reset clears STATUS[done]
//   TEST 4: Register readback (CTEXT/TAG)
//   TEST 5: IRQ functionality
//   (DMA mode có thể thêm sau)
//
// Compile (không cần ascon_axis_wrapper.v):
//   iverilog -o tb_top.vvp \
//     ascon/rtl/ascon_INITIALIZATION.v ascon/rtl/ascon_STATE_REGISTER.v \
//     ascon/rtl/ascon_DATAPATH.v ascon/rtl/PERMUTATION/ascon_PERMUTATION.v \
//     ascon/rtl/ascon_TAG_GENERATOR.v ascon/rtl/ascon_TAG_COMPARATOR.v \
//     ascon/rtl/ascon_CONTROLLER.v ascon/rtl/ascon_CORE.v \
//     ascon/interface/ascon_axi_slave.v ascon/dma/ascon_dma.v \
//     ascon/rtl/ascon_top.v tb_ascon_top.v
//   vvp tb_top.vvp
// ============================================================================
`timescale 1ns/1ps
`include "ascon_baseline/ascon_top.v"
`include "memory/data_mem_axi_slave.v"
`include "axi_width_converter_64to32.v"

module tb_ascon_top;

    localparam S_AW = 32, S_DW = 32, S_IW = 4;
    localparam M_AW = 32, M_DW = 64, M_IW = 4;

    // ---- Clock & reset -------------------------------------------------------
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // ---- AXI4-Full Slave (CPU) ----------------------------------------------
    reg  [S_IW-1:0]   S_AXI_AWID     = 0;
    reg  [S_AW-1:0]   S_AXI_AWADDR   = 0;
    reg  [7:0]        S_AXI_AWLEN    = 0;
    reg  [2:0]        S_AXI_AWSIZE   = 3'b010;
    reg  [1:0]        S_AXI_AWBURST  = 2'b01;
    reg  [2:0]        S_AXI_AWPROT   = 0;
    reg               S_AXI_AWVALID  = 0;
    wire              S_AXI_AWREADY;
    reg  [S_DW-1:0]   S_AXI_WDATA    = 0;
    reg  [S_DW/8-1:0] S_AXI_WSTRB    = 4'hF;
    reg               S_AXI_WLAST    = 1;
    reg               S_AXI_WVALID   = 0;
    wire              S_AXI_WREADY;
    wire [S_IW-1:0]   S_AXI_BID;
    wire [1:0]        S_AXI_BRESP;
    wire              S_AXI_BVALID;
    reg               S_AXI_BREADY   = 1;
    reg  [S_IW-1:0]   S_AXI_ARID     = 0;
    reg  [S_AW-1:0]   S_AXI_ARADDR   = 0;
    reg  [7:0]        S_AXI_ARLEN    = 0;
    reg  [2:0]        S_AXI_ARSIZE   = 3'b010;
    reg  [1:0]        S_AXI_ARBURST  = 2'b01;
    reg  [2:0]        S_AXI_ARPROT   = 0;
    reg               S_AXI_ARVALID  = 0;
    wire              S_AXI_ARREADY;
    wire [S_IW-1:0]   S_AXI_RID;
    wire [S_DW-1:0]   S_AXI_RDATA;
    wire [1:0]        S_AXI_RRESP;
    wire              S_AXI_RLAST;
    wire              S_AXI_RVALID;
    reg               S_AXI_RREADY   = 1;

    // ---- AXI4-Full Master (DMA) connected to data_mem_axi4_slave ----------
    wire [M_IW-1:0]   M_AXI_AWID, M_AXI_ARID;
    wire [M_AW-1:0]   M_AXI_AWADDR, M_AXI_ARADDR;
    wire [7:0]        M_AXI_AWLEN, M_AXI_ARLEN;
    wire [2:0]        M_AXI_AWSIZE, M_AXI_ARSIZE, M_AXI_AWPROT, M_AXI_ARPROT;
    wire [1:0]        M_AXI_AWBURST, M_AXI_ARBURST;
    wire [3:0]        M_AXI_AWCACHE, M_AXI_ARCACHE;
    wire              M_AXI_AWVALID, M_AXI_ARVALID;
    wire              M_AXI_AWREADY, M_AXI_ARREADY;
    wire [M_DW-1:0]   M_AXI_WDATA;
    wire [M_DW/8-1:0] M_AXI_WSTRB;
    wire              M_AXI_WLAST, M_AXI_WVALID;
    wire              M_AXI_WREADY;
    wire [M_IW-1:0]   M_AXI_BID;
    wire [1:0]        M_AXI_BRESP;
    wire              M_AXI_BVALID;
    wire              M_AXI_BREADY;
    wire [M_IW-1:0]   M_AXI_RID;
    wire [M_DW-1:0]   M_AXI_RDATA;
    wire [1:0]        M_AXI_RRESP;
    wire              M_AXI_RLAST, M_AXI_RVALID;
    wire              M_AXI_RREADY;

    // ---- AXI 32-bit wires between width converter and RAM -------------------
    wire [M_IW-1:0] C32_AWID,  C32_ARID;
    wire [M_AW-1:0] C32_AWADDR,C32_ARADDR;
    wire [7:0]      C32_AWLEN, C32_ARLEN;
    wire [2:0]      C32_AWSIZE,C32_ARSIZE,C32_AWPROT,C32_ARPROT;
    wire [1:0]      C32_AWBURST,C32_ARBURST;
    wire            C32_AWVALID,C32_AWREADY;
    wire [31:0]     C32_WDATA;
    wire [3:0]      C32_WSTRB;
    wire            C32_WLAST, C32_WVALID, C32_WREADY;
    wire [M_IW-1:0] C32_BID,   C32_RID;
    wire [1:0]      C32_BRESP, C32_RRESP;
    wire            C32_BVALID,C32_BREADY;
    wire [31:0]     C32_RDATA;
    wire            C32_RLAST, C32_RVALID,C32_RREADY;

    // ---- Outputs ------------------------------------------------------------
    wire [127:0] o_tag;
    wire         o_tag_valid, o_busy, irq;

    // ---- DUT instantiation (không có AXI-Stream) ----------------------------
    ascon_ip_top #(
        .G_COMB_RND_128 (6), .G_COMB_RND_128A (4),
        .G_SBOX_PIPELINE (0), .G_DUAL_RATE (1), .G_AXI_DATA_W (64),
        .S_ADDR_WIDTH (S_AW), .S_DATA_WIDTH (S_DW), .S_ID_WIDTH (S_IW),
        .M_ADDR_WIDTH (M_AW), .M_DATA_WIDTH (M_DW), .M_ID_WIDTH (M_IW),
        .RD_FIFO_DEPTH (4), .WR_FIFO_DEPTH (8)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),

        .S_AXI_AWID     (S_AXI_AWID),
        .S_AXI_AWADDR   (S_AXI_AWADDR),
        .S_AXI_AWLEN    (S_AXI_AWLEN),
        .S_AXI_AWSIZE   (S_AXI_AWSIZE),
        .S_AXI_AWBURST  (S_AXI_AWBURST),
        .S_AXI_AWPROT   (S_AXI_AWPROT),
        .S_AXI_AWVALID  (S_AXI_AWVALID),
        .S_AXI_AWREADY  (S_AXI_AWREADY),

        .S_AXI_WDATA    (S_AXI_WDATA),
        .S_AXI_WSTRB    (S_AXI_WSTRB),
        .S_AXI_WLAST    (S_AXI_WLAST),
        .S_AXI_WVALID   (S_AXI_WVALID),
        .S_AXI_WREADY   (S_AXI_WREADY),

        .S_AXI_BID      (S_AXI_BID),
        .S_AXI_BRESP    (S_AXI_BRESP),
        .S_AXI_BVALID   (S_AXI_BVALID),
        .S_AXI_BREADY   (S_AXI_BREADY),

        .S_AXI_ARID     (S_AXI_ARID),
        .S_AXI_ARADDR   (S_AXI_ARADDR),
        .S_AXI_ARLEN    (S_AXI_ARLEN),
        .S_AXI_ARSIZE   (S_AXI_ARSIZE),
        .S_AXI_ARBURST  (S_AXI_ARBURST),
        .S_AXI_ARPROT   (S_AXI_ARPROT),
        .S_AXI_ARVALID  (S_AXI_ARVALID),
        .S_AXI_ARREADY  (S_AXI_ARREADY),

        .S_AXI_RID      (S_AXI_RID),
        .S_AXI_RDATA    (S_AXI_RDATA),
        .S_AXI_RRESP    (S_AXI_RRESP),
        .S_AXI_RLAST    (S_AXI_RLAST),
        .S_AXI_RVALID   (S_AXI_RVALID),
        .S_AXI_RREADY   (S_AXI_RREADY),

        .M_AXI_AWID     (M_AXI_AWID),
        .M_AXI_AWADDR   (M_AXI_AWADDR),
        .M_AXI_AWLEN    (M_AXI_AWLEN),
        .M_AXI_AWSIZE   (M_AXI_AWSIZE),
        .M_AXI_AWBURST  (M_AXI_AWBURST),
        .M_AXI_AWCACHE  (M_AXI_AWCACHE),
        .M_AXI_AWPROT   (M_AXI_AWPROT),
        .M_AXI_AWVALID  (M_AXI_AWVALID),
        .M_AXI_AWREADY  (M_AXI_AWREADY),

        .M_AXI_WDATA    (M_AXI_WDATA),
        .M_AXI_WSTRB    (M_AXI_WSTRB),
        .M_AXI_WLAST    (M_AXI_WLAST),
        .M_AXI_WVALID   (M_AXI_WVALID),
        .M_AXI_WREADY   (M_AXI_WREADY),

        .M_AXI_BID      (M_AXI_BID),
        .M_AXI_BRESP    (M_AXI_BRESP),
        .M_AXI_BVALID   (M_AXI_BVALID),
        .M_AXI_BREADY   (M_AXI_BREADY),

        .M_AXI_ARID     (M_AXI_ARID),
        .M_AXI_ARADDR   (M_AXI_ARADDR),
        .M_AXI_ARLEN    (M_AXI_ARLEN),
        .M_AXI_ARSIZE   (M_AXI_ARSIZE),
        .M_AXI_ARBURST  (M_AXI_ARBURST),
        .M_AXI_ARCACHE  (M_AXI_ARCACHE),
        .M_AXI_ARPROT   (M_AXI_ARPROT),
        .M_AXI_ARVALID  (M_AXI_ARVALID),
        .M_AXI_ARREADY  (M_AXI_ARREADY),

        .M_AXI_RID      (M_AXI_RID),
        .M_AXI_RDATA    (M_AXI_RDATA),
        .M_AXI_RRESP    (M_AXI_RRESP),
        .M_AXI_RLAST    (M_AXI_RLAST),
        .M_AXI_RVALID   (M_AXI_RVALID),
        .M_AXI_RREADY   (M_AXI_RREADY),

        .o_tag          (o_tag),
        .o_tag_valid    (o_tag_valid),
        .o_busy         (o_busy),
        .irq            (irq)
    );

    // ---- Internal probes ----------------------------------------------------
    wire [127:0] hw_ct   = dut.core_data_out_w;
    wire         hw_ct_v = dut.core_data_out_valid_w;
    wire [127:0] hw_tag  = dut.core_tag_out_w;
    wire         hw_tag_v= dut.core_tag_valid_w;
    wire         hw_done = dut.core_done_w;
    wire [3:0]   hw_fsm  = dut.u_core_cpu.u_ctrl.state;

    // ---- Width converter: ASCON DMA (64-bit) → RAM (32-bit) ----------------
    axi_width_converter_64to32 #(
        .ADDR_WIDTH(M_AW), .ID_WIDTH(M_IW)
    ) u_conv (
        .clk(clk), .rst_n(rst_n),
        .M_AXI_AWID(M_AXI_AWID),    .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN),  .M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST),.M_AXI_AWCACHE(M_AXI_AWCACHE),
        .M_AXI_AWPROT(M_AXI_AWPROT),.M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA),  .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST),  .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BID(M_AXI_BID),      .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),.M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARID(M_AXI_ARID),    .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),  .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),.M_AXI_ARCACHE(M_AXI_ARCACHE),
        .M_AXI_ARPROT(M_AXI_ARPROT),.M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RID(M_AXI_RID),      .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),  .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),.M_AXI_RREADY(M_AXI_RREADY),
        .S_AXI_AWID(C32_AWID),      .S_AXI_AWADDR(C32_AWADDR),
        .S_AXI_AWLEN(C32_AWLEN),    .S_AXI_AWSIZE(C32_AWSIZE),
        .S_AXI_AWBURST(C32_AWBURST),.S_AXI_AWPROT(C32_AWPROT),
        .S_AXI_AWVALID(C32_AWVALID),.S_AXI_AWREADY(C32_AWREADY),
        .S_AXI_WDATA(C32_WDATA),    .S_AXI_WSTRB(C32_WSTRB),
        .S_AXI_WLAST(C32_WLAST),    .S_AXI_WVALID(C32_WVALID),
        .S_AXI_WREADY(C32_WREADY),
        .S_AXI_BID(C32_BID),        .S_AXI_BRESP(C32_BRESP),
        .S_AXI_BVALID(C32_BVALID),  .S_AXI_BREADY(C32_BREADY),
        .S_AXI_ARID(C32_ARID),      .S_AXI_ARADDR(C32_ARADDR),
        .S_AXI_ARLEN(C32_ARLEN),    .S_AXI_ARSIZE(C32_ARSIZE),
        .S_AXI_ARBURST(C32_ARBURST),.S_AXI_ARPROT(C32_ARPROT),
        .S_AXI_ARVALID(C32_ARVALID),.S_AXI_ARREADY(C32_ARREADY),
        .S_AXI_RID(C32_RID),        .S_AXI_RDATA(C32_RDATA),
        .S_AXI_RRESP(C32_RRESP),    .S_AXI_RLAST(C32_RLAST),
        .S_AXI_RVALID(C32_RVALID),  .S_AXI_RREADY(C32_RREADY)
    );

    // ---- AXI RAM 32-bit connected to width converter output -----------------
    // MEM_SIZE=16384 (16KB) covers DMA_AD=0x1000, DMA_PT=0x2000, DMA_CT=0x3000
    data_mem_axi4_slave #(
        .ADDR_WIDTH(M_AW),
        .DATA_WIDTH(32),
        .ID_WIDTH(M_IW),
        .MEM_SIZE(16384)
    ) u_ram (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWID(C32_AWID),    .S_AXI_AWADDR(C32_AWADDR),
        .S_AXI_AWLEN(C32_AWLEN),  .S_AXI_AWSIZE(C32_AWSIZE),
        .S_AXI_AWBURST(C32_AWBURST),.S_AXI_AWPROT(C32_AWPROT),
        .S_AXI_AWVALID(C32_AWVALID),.S_AXI_AWREADY(C32_AWREADY),
        .S_AXI_WDATA(C32_WDATA),  .S_AXI_WSTRB(C32_WSTRB),
        .S_AXI_WLAST(C32_WLAST),  .S_AXI_WVALID(C32_WVALID),
        .S_AXI_WREADY(C32_WREADY),
        .S_AXI_BID(C32_BID),      .S_AXI_BRESP(C32_BRESP),
        .S_AXI_BVALID(C32_BVALID),.S_AXI_BREADY(C32_BREADY),
        .S_AXI_ARID(C32_ARID),    .S_AXI_ARADDR(C32_ARADDR),
        .S_AXI_ARLEN(C32_ARLEN),  .S_AXI_ARSIZE(C32_ARSIZE),
        .S_AXI_ARBURST(C32_ARBURST),.S_AXI_ARPROT(C32_ARPROT),
        .S_AXI_ARVALID(C32_ARVALID),.S_AXI_ARREADY(C32_ARREADY),
        .S_AXI_RID(C32_RID),      .S_AXI_RDATA(C32_RDATA),
        .S_AXI_RRESP(C32_RRESP),  .S_AXI_RLAST(C32_RLAST),
        .S_AXI_RVALID(C32_RVALID),.S_AXI_RREADY(C32_RREADY)
    );

    // ---- Capture registers --------------------------------------------------
    integer pass_count, fail_count, cyc_start, cyc_total;
    reg [127:0] cap_ct, cap_tag, tag_rd;
    reg [31:0]  axi_rd;

    always @(posedge clk) begin
        if (hw_ct_v)  cap_ct  <= hw_ct;
        if (hw_tag_v) cap_tag <= hw_tag;
    end

    // ---- Variables cho File I/O --------------------------------------------
    integer fd, count, i;
    reg [31:0]  tv_mode, tv_ad_len, tv_pt_len;
    reg [127:0] tv_key, tv_nonce, tv_tag;
    reg [1023:0] tv_ad, tv_pt, tv_ct;
    reg [31:0]   word_data;
    reg [31:0]   word_lo, word_hi;
    
    // RAM addresses for DMA
    localparam DMA_AD_BASE = 32'h0000_1000;
    localparam DMA_PT_BASE = 32'h0000_2000;
    localparam DMA_CT_BASE = 32'h0000_3000;

    // ---- Event monitor ------------------------------------------------------
    always @(posedge clk) begin
        if (hw_ct_v)   $display("  [%5t] core data_out = %h", $time, hw_ct);
        if (hw_tag_v)  $display("  [%5t] core tag_out  = %h", $time, hw_tag);
        if (hw_done)   $display("  [%5t] core DONE", $time);
        if (o_tag_valid) $display("  [%5t] o_tag = %h", $time, o_tag);
        if (irq)       $display("  [%5t] IRQ fired", $time);
    end

    // =========================================================================
    // Tasks
    // =========================================================================

    task do_reset;
        begin
            rst_n = 0;
            repeat (4) @(posedge clk);
            rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    // Ghi 32-bit dữ liệu (AXI4-Full single beat)
    task axi_write;
        input [31:0] addr, data;
        integer t;
        begin
            @(posedge clk); #1;
            S_AXI_AWADDR  = addr;
            S_AXI_AWVALID = 1;
            S_AXI_WDATA   = data;
            S_AXI_WSTRB   = 4'hF;
            S_AXI_WLAST   = 1;
            S_AXI_WVALID  = 1;
            t = 0;
            @(posedge clk); #1;
            while (!(S_AXI_AWREADY & S_AXI_WREADY) && t < 100) begin
                @(posedge clk); #1;
                t = t + 1;
            end
            S_AXI_AWVALID = 0;
            S_AXI_WVALID  = 0;
            t = 0;
            while (!S_AXI_BVALID && t < 100) begin
                @(posedge clk);
                t = t + 1;
            end
            @(posedge clk); #1;
        end
    endtask

    // Đọc 32-bit dữ liệu
    task axi_read;
        input [31:0] addr;
        integer t;
        begin
            @(posedge clk); #1;
            S_AXI_ARADDR  = addr;
            S_AXI_ARVALID = 1;
            t = 0;
            @(posedge clk); #1;
            while (!S_AXI_ARREADY && t < 100) begin
                @(posedge clk); #1;
                t = t + 1;
            end
            S_AXI_ARVALID = 0;
            t = 0;
            while (!S_AXI_RVALID && t < 100) begin
                @(posedge clk);
                t = t + 1;
            end
            axi_rd = S_AXI_RDATA;
            @(posedge clk); #1;
        end
    endtask

    task cpu_setup_full;
        input [127:0] key, nonce;
        input [31:0]  ad_len;
        input [127:0] ad_data; // Max 16 bytes for CPU-Direct
        input [31:0]  pt_len;
        input [63:0]  pt_data; // Max 8 bytes for CPU-Direct
        begin
            // Key
            axi_write(32'h010, key[127:96]);
            axi_write(32'h014, key[95:64]);
            axi_write(32'h018, key[63:32]);
            axi_write(32'h01C, key[31:0]);
            // Nonce
            axi_write(32'h024, nonce[127:96]);
            axi_write(32'h028, nonce[95:64]);
            axi_write(32'h02C, nonce[63:32]);
            axi_write(32'h030, nonce[31:0]);
            // AD
            axi_write(32'h124, ad_len);
            if (ad_len > 0) begin
                axi_write(32'h058, ad_data[127:96]);
                axi_write(32'h05C, ad_data[95:64]);
                axi_write(32'h060, ad_data[63:32]);
                axi_write(32'h064, ad_data[31:0]);
            end
            // PT
            axi_write(32'h03C, pt_len);
            if (pt_len > 0) begin
                axi_write(32'h034, pt_data[63:32]);
                axi_write(32'h038, pt_data[31:0]);
            end
            // Mode = Encrypt (00)
            axi_write(32'h000, 32'h0);
        end
    endtask

    task dma_setup_full;
        input [127:0] key, nonce;
        input [31:0]  ad_len;
        input [31:0]  pt_len;
        reg   [31:0]  burst_calc;
        begin
            // Key & Nonce (cấu hình giống CPU)
            axi_write(32'h010, key[127:96]);
            axi_write(32'h014, key[95:64]);
            axi_write(32'h018, key[63:32]);
            axi_write(32'h01C, key[31:0]);
            axi_write(32'h024, nonce[127:96]);
            axi_write(32'h028, nonce[95:64]);
            axi_write(32'h02C, nonce[63:32]);
            axi_write(32'h030, nonce[31:0]);

            // Mode = Encrypt
            axi_write(32'h000, 32'h0);

            // Cấu hình thanh ghi DMA
            axi_write(32'h120, DMA_AD_BASE); // AD_ADDR
            axi_write(32'h124, ad_len);      // AD_LEN

            axi_write(32'h100, DMA_PT_BASE); // SRC_ADDR
            axi_write(32'h104, DMA_CT_BASE); // DST_ADDR
            axi_write(32'h108, pt_len);      // BYTE_LEN
            axi_write(32'h03C, pt_len);      // DATA_LEN (Bug A fix: sync với cpu_setup_full)
            // BURST_LEN = blocks-1 (1 block = 8 bytes); cap at 3 (4 beats max)
            burst_calc = (pt_len >> 3);
            burst_calc = (burst_calc > 0) ? burst_calc - 1 : 0;
            burst_calc = (burst_calc > 3) ? 3 : burst_calc;
            axi_write(32'h114, burst_calc);
        end
    endtask

    // Chờ core_done bằng cách poll STATUS register qua AXI (bit 0 = done)
    task wait_done;
        integer t;
        begin
            t = 0;
            axi_read(32'h004);
            while (axi_rd[1] == 0 && t < 10000) begin
                @(posedge clk); #1;
                axi_read(32'h004);
                t = t + 1;
            end
            if (t >= 10000) $display("  [TIMEOUT] wait_done");
        end
    endtask

    // Backdoor ghi vào RAM (32-bit per word — memory indexed by 4-byte word)
    task load_ram;
        input [31:0] base_addr;
        input [31:0] byte_len;
        input [1023:0] data;
        integer k;
        reg [31:0] chunk32;
        begin
            for (k = 0; k < byte_len/4; k = k + 1) begin
                chunk32 = (data >> ((byte_len - 4 - k*4)*8)) & 32'hFFFFFFFF;
                u_ram.dmem.memory[(base_addr/4) + k] = chunk32;
            end
        end
    endtask

    // Chờ DMA done bằng poll dma_busy_w (level signal, không miss edge)
    task wait_dma_done;
        integer t;
        begin
            t = 0;
            @(posedge clk); #1;
            while (dut.dma_busy_w && t < 5_000_000) begin
                @(posedge clk); #1;
                t = t + 1;
            end
            if (t >= 5_000_000)
                $display("  [TIMEOUT] wait_dma_done");
        end
    endtask

    // =========================================================================
    // Auto Test Sequence
    // =========================================================================
    reg [127:0]  tmp_tag;
    reg [1023:0] tmp_ct;
    integer      test_idx;
    reg [8191:0] line_str;
    integer      throwaway;
    reg [1023:0] ct_mask;

    initial begin
        $dumpfile("tb_ascon_top.vcd");
        $dumpvars(0, tb_ascon_top);

        pass_count = 0;
        fail_count = 0;
        test_idx = 0;

        $display("================================================================");
        $display("  tb_ascon_top  --  Automated SW-HW Co-Simulation");
        $display("================================================================");
        
        do_reset;

        fd = $fopen("test_vectors.hex", "r");
        if (fd == 0) begin
            $display("ERROR: Cannot open test_vectors.hex");
            $finish;
        end

        // Bỏ qua các dòng comment bắt đầu bằng //
        while (!$feof(fd)) begin
            count = $fscanf(fd, "%d %h %h %h %h %h %h %h %h\n", 
                tv_mode, tv_key, tv_nonce, tv_ad_len, tv_ad, tv_pt_len, tv_pt, tv_ct, tv_tag);
            
            if (count == 9) begin
                test_idx = test_idx + 1;
                $display("\n--- Test %0d: Mode %0d (0=CPU, 1=DMA) | AD=%0dB, PT=%0dB ---", 
                         test_idx, tv_mode, tv_ad_len, tv_pt_len);
                
                // Clear state
                do_reset;
                axi_write(32'h020, 32'h8); // CTRL[3]=ZEROIZE

                if (tv_mode == 0) begin
                    // CPU-DIRECT MODE
                    // Dữ liệu từ file được lưu right-aligned. 
                    // CPU-Direct (ASCON) cần Byte 0 nằm ở vị trí MSB của register.
                    // Do đó cần dịch trái để left-align dữ liệu vào đúng thanh ghi 128-bit / 64-bit.
                    begin : cpu_align
                        reg [127:0] ad_shifted;
                        reg [63:0]  pt_shifted;
                        ad_shifted = (tv_ad_len > 0) ? (tv_ad[127:0] << (128 - tv_ad_len*8)) : 128'h0;
                        pt_shifted = (tv_pt_len > 0) ? (tv_pt[63:0]  << ( 64 - tv_pt_len*8)) : 64'h0;
                        cpu_setup_full(tv_key, tv_nonce, tv_ad_len, ad_shifted, tv_pt_len, pt_shifted);
                    end
                    
                    // Start CORE
                    axi_write(32'h020, 32'h1);
                    wait_done;
                    
                    // Read Tag
                    axi_read(32'h048); tmp_tag[127:96] = axi_rd;
                    axi_read(32'h04C); tmp_tag[95:64]  = axi_rd;
                    axi_read(32'h050); tmp_tag[63:32]  = axi_rd;
                    axi_read(32'h054); tmp_tag[31:0]   = axi_rd;
                    
                    // Read CT
                    axi_read(32'h040); tmp_ct[63:32] = axi_rd;
                    axi_read(32'h044); tmp_ct[31:0]  = axi_rd;
                    
                    // Compare Tag
                    if (tmp_tag === tv_tag) begin
                        pass_count = pass_count + 1;
                        $display("  [PASS] TAG matches");
                    end else begin
                        $display("  [FAIL] TAG mismatch! Got %h, Exp %h", tmp_tag, tv_tag);
                        fail_count = fail_count + 1;
                    end

                end else begin
                    // DMA MODE
                    load_ram(DMA_AD_BASE, tv_ad_len, tv_ad);
                    load_ram(DMA_PT_BASE, tv_pt_len, tv_pt);
                    
                    dma_setup_full(tv_key, tv_nonce, tv_ad_len, tv_pt_len);
                    
                    // Start DMA: CTRL[2]=DMA_EN | CTRL[0]=CORE_START = 0x5
                    axi_write(32'h020, 32'h5);
                    wait_dma_done;
                    
                    // Read Tag
                    axi_read(32'h048); tmp_tag[127:96] = axi_rd;
                    axi_read(32'h04C); tmp_tag[95:64]  = axi_rd;
                    axi_read(32'h050); tmp_tag[63:32]  = axi_rd;
                    axi_read(32'h054); tmp_tag[31:0]   = axi_rd;
                    
                    // Backdoor Read CT from RAM (32-bit memory, width converter
                    // stores low-word first → reconstruct as {hi,lo} per 64-bit block)
                    begin : dbg_ram_dump
                        integer dbg_k;
                        $display("  [DBG RAM] CT_BASE/4=%0d, pt_len=%0d", DMA_CT_BASE/4, tv_pt_len);
                        for (dbg_k = 0; dbg_k < (tv_pt_len/4) + 4; dbg_k = dbg_k + 1)
                            $display("  [DBG RAM] mem[%0d]=%08h", (DMA_CT_BASE/4)+dbg_k,
                                     u_ram.dmem.memory[(DMA_CT_BASE/4)+dbg_k]);
                    end
                    tmp_ct = 1024'h0;
                    for (i = 0; i < tv_pt_len/8; i = i + 1) begin
                        // Width converter writes LOW word (WDATA[31:0]=ctext_word0) to addr+0
                        // and HIGH word (WDATA[63:32]=ctext_word1) to addr+4.
                        // So mem[i*2]=word0 (big-endian first), mem[i*2+1]=word1.
                        word_lo = u_ram.dmem.memory[(DMA_CT_BASE/4) + i*2];     // ctext word 0
                        word_hi = u_ram.dmem.memory[(DMA_CT_BASE/4) + i*2 + 1]; // ctext word 1
                        $display("  [DBG CT] block[%0d] mem[even]=%08h mem[odd]=%08h → {even,odd}=%08h%08h", i, word_lo, word_hi, word_lo, word_hi);
                        tmp_ct = tmp_ct | ({960'h0, {word_lo, word_hi}} << ((tv_pt_len - 8 - i*8)*8));
                    end
                    
                    // Compare Tag
                    if (tmp_tag === tv_tag) begin
                        pass_count = pass_count + 1;
                        $display("  [PASS] TAG matches");
                    end else begin
                        $display("  [FAIL] TAG mismatch! Got %h, Exp %h", tmp_tag, tv_tag);
                        fail_count = fail_count + 1;
                    end
                    
                    // Compare CT
                    if (tv_pt_len > 0) begin
                        // Dùng bitwise AND với mask để so sánh đúng số bit hợp lệ
                        ct_mask = (tv_pt_len*8 >= 1024) ? {1024{1'b1}} : ((1024'b1 << (tv_pt_len*8)) - 1);
                        
                        if ((tmp_ct & ct_mask) === (tv_ct & ct_mask)) begin
                            $display("  [PASS] CT matches");
                        end else begin
                            $display("  [FAIL] CT mismatch! Got %h, Exp %h",
                                (tmp_ct & ct_mask), (tv_ct & ct_mask));
                            fail_count = fail_count + 1;
                        end
                    end
                end
            end else begin
                // Try reading as string if format mismatch (like comments)
                throwaway = $fgets(line_str, fd);
            end
        end

        $fclose(fd);

        $display("\n================================================================");
        $display("  RESULT: %0d TESTS RUN", test_idx);
        $display("  FAILED: %0d", fail_count);
        $display("================================================================");
        if (fail_count == 0 && test_idx > 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** SOME TESTS FAILED ***");
        $display("================================================================");
        $finish;
    end

    initial begin
        #1_000_000_000;  // 1ms global watchdog
        $display("[WATCHDOG] 1ms timeout");
        $finish;
    end

endmodule