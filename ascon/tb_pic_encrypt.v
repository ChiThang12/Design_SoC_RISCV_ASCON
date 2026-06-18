`timescale 1ns/1ps
// ============================================================================
// Testbench : tb_pic_encrypt.v
// Target    : ASCON IP DMA mode — encrypt 8x8 grayscale image (64 bytes)
// Standard  : Verilog-2005, iverilog compatible
//
// KEY   = 000102030405060708090A0B0C0D0E0F
// NONCE = 101112131415161718191A1B1C1D1E1F
// PT    = 8x8 gradient image, 64 bytes
// Mode  : DMA only (CTRL = 0x5), WR_FIFO_DEPTH = 32
// ============================================================================
`include "ascon/ascon_top.v"
`include "memory/data_mem_axi_slave.v"
`include "axi_width_converter_64to32.v"

module tb_pic_encrypt;

    localparam S_AW = 32, S_DW = 32, S_IW = 4;
    localparam M_AW = 32, M_DW = 64, M_IW = 4;
    localparam CLK_PERIOD_NS = 10;

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

    // ---- AXI4-Full Master (DMA) ----------------------------------------------
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

    // ---- DUT (WR_FIFO_DEPTH = 32 để chứa 8 CT blocks + TAG = 20 beats) -----
    ascon_ip_top #(
        .G_COMB_RND_128 (6), .G_COMB_RND_128A (4),
        .G_SBOX_PIPELINE (0), .G_DUAL_RATE (1), .G_AXI_DATA_W (64),
        .S_ADDR_WIDTH (S_AW), .S_DATA_WIDTH (S_DW), .S_ID_WIDTH (S_IW),
        .M_ADDR_WIDTH (M_AW), .M_DATA_WIDTH (M_DW), .M_ID_WIDTH (M_IW),
        .RD_FIFO_DEPTH (8), .WR_FIFO_DEPTH (32)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .S_AXI_AWID     (S_AXI_AWID),   .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWLEN    (S_AXI_AWLEN),   .S_AXI_AWSIZE  (S_AXI_AWSIZE),
        .S_AXI_AWBURST  (S_AXI_AWBURST), .S_AXI_AWPROT  (S_AXI_AWPROT),
        .S_AXI_AWVALID  (S_AXI_AWVALID), .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA    (S_AXI_WDATA),   .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WLAST    (S_AXI_WLAST),   .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY   (S_AXI_WREADY),
        .S_AXI_BID      (S_AXI_BID),     .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID   (S_AXI_BVALID),  .S_AXI_BREADY  (S_AXI_BREADY),
        .S_AXI_ARID     (S_AXI_ARID),    .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARLEN    (S_AXI_ARLEN),   .S_AXI_ARSIZE  (S_AXI_ARSIZE),
        .S_AXI_ARBURST  (S_AXI_ARBURST), .S_AXI_ARPROT  (S_AXI_ARPROT),
        .S_AXI_ARVALID  (S_AXI_ARVALID), .S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RID      (S_AXI_RID),     .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP    (S_AXI_RRESP),   .S_AXI_RLAST   (S_AXI_RLAST),
        .S_AXI_RVALID   (S_AXI_RVALID),  .S_AXI_RREADY  (S_AXI_RREADY),
        .M_AXI_AWID     (M_AXI_AWID),    .M_AXI_AWADDR  (M_AXI_AWADDR),
        .M_AXI_AWLEN    (M_AXI_AWLEN),   .M_AXI_AWSIZE  (M_AXI_AWSIZE),
        .M_AXI_AWBURST  (M_AXI_AWBURST), .M_AXI_AWCACHE (M_AXI_AWCACHE),
        .M_AXI_AWPROT   (M_AXI_AWPROT),  .M_AXI_AWVALID (M_AXI_AWVALID),
        .M_AXI_AWREADY  (M_AXI_AWREADY),
        .M_AXI_WDATA    (M_AXI_WDATA),   .M_AXI_WSTRB   (M_AXI_WSTRB),
        .M_AXI_WLAST    (M_AXI_WLAST),   .M_AXI_WVALID  (M_AXI_WVALID),
        .M_AXI_WREADY   (M_AXI_WREADY),
        .M_AXI_BID      (M_AXI_BID),     .M_AXI_BRESP   (M_AXI_BRESP),
        .M_AXI_BVALID   (M_AXI_BVALID),  .M_AXI_BREADY  (M_AXI_BREADY),
        .M_AXI_ARID     (M_AXI_ARID),    .M_AXI_ARADDR  (M_AXI_ARADDR),
        .M_AXI_ARLEN    (M_AXI_ARLEN),   .M_AXI_ARSIZE  (M_AXI_ARSIZE),
        .M_AXI_ARBURST  (M_AXI_ARBURST), .M_AXI_ARCACHE (M_AXI_ARCACHE),
        .M_AXI_ARPROT   (M_AXI_ARPROT),  .M_AXI_ARVALID (M_AXI_ARVALID),
        .M_AXI_ARREADY  (M_AXI_ARREADY),
        .M_AXI_RID      (M_AXI_RID),     .M_AXI_RDATA   (M_AXI_RDATA),
        .M_AXI_RRESP    (M_AXI_RRESP),   .M_AXI_RLAST   (M_AXI_RLAST),
        .M_AXI_RVALID   (M_AXI_RVALID),  .M_AXI_RREADY  (M_AXI_RREADY),
        .o_tag          (o_tag),
        .o_tag_valid    (o_tag_valid),
        .o_busy         (o_busy),
        .irq            (irq)
    );

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

    // ---- AXI RAM 32-bit (16KB covers 0x1000, 0x2000, 0x3000) ---------------
    data_mem_axi4_slave #(
        .ADDR_WIDTH(M_AW), .DATA_WIDTH(32), .ID_WIDTH(M_IW), .MEM_SIZE(16384)
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

    // ---- DMA addresses -------------------------------------------------------
    localparam DMA_AD_BASE = 32'h0000_1000;
    localparam DMA_PT_BASE = 32'h0000_2000;
    localparam DMA_CT_BASE = 32'h0000_3000;

    // ---- Registers -----------------------------------------------------------
    integer fd, count, i;
    reg [31:0]   tv_mode, tv_ad_len, tv_pt_len;
    reg [127:0]  tv_key, tv_nonce, tv_tag;
    reg [1023:0] tv_ad, tv_pt, tv_ct;
    reg [127:0]  tmp_tag;
    reg [1023:0] tmp_ct;
    reg [1023:0] ct_mask;
    reg [31:0]   axi_rd;
    reg [31:0]   word_lo, word_hi;
    integer      pass_count, fail_count;
    integer      hw_start_time, hw_end_time, hw_cycles;
    integer      tput_kbs;
    integer      throwaway;
    reg [8191:0] line_str;

    // =========================================================================
    // Tasks (copied từ tb_ascon_top.v)
    // =========================================================================

    task do_reset;
        begin
            rst_n = 0;
            repeat (4) @(posedge clk);
            rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

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

    task load_ram;
        input [31:0]   base_addr;
        input [31:0]   byte_len;
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

    task dma_setup_full;
        input [127:0] key, nonce;
        input [31:0]  ad_len;
        input [31:0]  pt_len;
        reg   [31:0]  burst_calc;
        begin
            axi_write(32'h010, key[127:96]);
            axi_write(32'h014, key[95:64]);
            axi_write(32'h018, key[63:32]);
            axi_write(32'h01C, key[31:0]);
            axi_write(32'h024, nonce[127:96]);
            axi_write(32'h028, nonce[95:64]);
            axi_write(32'h02C, nonce[63:32]);
            axi_write(32'h030, nonce[31:0]);
            axi_write(32'h000, 32'h0);          // MODE = Encrypt
            axi_write(32'h120, DMA_AD_BASE);    // AD_ADDR
            axi_write(32'h124, ad_len);         // AD_LEN
            axi_write(32'h100, DMA_PT_BASE);    // SRC_ADDR
            axi_write(32'h104, DMA_CT_BASE);    // DST_ADDR
            axi_write(32'h108, pt_len);         // BYTE_LEN
            axi_write(32'h03C, pt_len);         // DATA_LEN
            burst_calc = (pt_len >> 3);
            burst_calc = (burst_calc > 0) ? burst_calc - 1 : 0;
            burst_calc = (burst_calc > 3) ? 3 : burst_calc;
            axi_write(32'h114, burst_calc);     // BURST_LEN = 3 (4 beats/burst)
        end
    endtask

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
    // Main test
    // =========================================================================

    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("=== ASCON Image Encryption HW Test ===");
        $display("Image  : 8x8 grayscale, 64 bytes, DMA mode");

        do_reset;

        fd = $fopen("pic_test_vectors.hex", "r");
        if (fd == 0) begin
            $display("[ERROR] Cannot open pic_test_vectors.hex");
            $finish;
        end

        // Skip comment lines
        while (!$feof(fd)) begin
            count = $fscanf(fd, "%d %h %h %h %h %h %h %h %h\n",
                            tv_mode, tv_key, tv_nonce, tv_ad_len, tv_ad,
                            tv_pt_len, tv_pt, tv_ct, tv_tag);
            if (count == 9) begin
                // Load image into RAM
                load_ram(DMA_PT_BASE, tv_pt_len, tv_pt);

                // Configure DMA
                dma_setup_full(tv_key, tv_nonce, tv_ad_len, tv_pt_len);

                // Start DMA and measure time
                hw_start_time = $time;
                axi_write(32'h020, 32'h5);  // CTRL = DMA_EN | CORE_START
                wait_dma_done;
                hw_end_time = $time;

                hw_cycles  = (hw_end_time - hw_start_time) / CLK_PERIOD_NS;
                tput_kbs   = 6_400_000 / hw_cycles;

                // Read TAG from AXI registers
                axi_read(32'h048); tmp_tag[127:96] = axi_rd;
                axi_read(32'h04C); tmp_tag[95:64]  = axi_rd;
                axi_read(32'h050); tmp_tag[63:32]  = axi_rd;
                axi_read(32'h054); tmp_tag[31:0]   = axi_rd;

                // Reconstruct CT from backdoor RAM
                tmp_ct = 1024'h0;
                for (i = 0; i < tv_pt_len/8; i = i + 1) begin
                    word_lo = u_ram.dmem.memory[(DMA_CT_BASE/4) + i*2];
                    word_hi = u_ram.dmem.memory[(DMA_CT_BASE/4) + i*2 + 1];
                    tmp_ct = tmp_ct | ({960'h0, {word_lo, word_hi}} << ((tv_pt_len - 8 - i*8)*8));
                end

                // Compare TAG
                if (tmp_tag === tv_tag) begin
                    $display("[PASS] TAG matches : %h", tmp_tag);
                    pass_count = pass_count + 1;
                end else begin
                    $display("[FAIL] TAG mismatch! Got %h", tmp_tag);
                    $display("                    Exp %h", tv_tag);
                    fail_count = fail_count + 1;
                end

                // Compare CT
                ct_mask = (tv_pt_len*8 >= 1024) ? {1024{1'b1}} :
                          ((1024'b1 << (tv_pt_len*8)) - 1);
                if ((tmp_ct & ct_mask) === (tv_ct & ct_mask)) begin
                    $display("[PASS] CT matches (64 bytes)");
                    pass_count = pass_count + 1;
                end else begin
                    $display("[FAIL] CT mismatch!");
                    $display("  Got: %h", (tmp_ct & ct_mask));
                    $display("  Exp: %h", (tv_ct  & ct_mask));
                    fail_count = fail_count + 1;
                end

                // Throughput report
                $display("HW cycles : %0d", hw_cycles);
                $display("HW time   : %0d ns  (%0d us)", hw_cycles*CLK_PERIOD_NS, hw_cycles*CLK_PERIOD_NS/1000);
                $display("HW tput   : %0d KB/s  (%0d.%02d MB/s  %0d Mbps)",
                         tput_kbs, tput_kbs/1000, (tput_kbs%1000)/10, tput_kbs*8/1000);

            end else begin
                throwaway = $fgets(line_str, fd);
            end
        end

        $fclose(fd);

        $display("=== RESULT: pass=%0d  fail=%0d ===", pass_count, fail_count);
        if (fail_count == 0 && pass_count == 2)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== SOME TESTS FAILED ===");
        $finish;
    end

    initial begin
        #500_000_000;
        $display("[WATCHDOG] 500ms timeout");
        $finish;
    end

endmodule
