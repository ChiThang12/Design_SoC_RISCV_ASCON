// tb_ascon_ip_top_rewrite.v - temporary
`timescale 1ns/1ps
`include "ascon/ascon_top.v"
module tb_ascon_ip_top_rewrite;

    localparam S_AW=32, S_DW=32, S_IW=4;
    localparam M_AW=32, M_DW=64, M_IW=4;

    // ---- Clock & reset -------------------------------------------------------
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    // ---- AXI4-Full Slave -----------------------------------------------------
    reg  [S_IW-1:0]   S_AXI_AWID=0;
    reg  [S_AW-1:0]   S_AXI_AWADDR=0;
    reg  [7:0]        S_AXI_AWLEN=0;
    reg  [2:0]        S_AXI_AWSIZE=3'b010;
    reg  [1:0]        S_AXI_AWBURST=2'b01;
    reg  [2:0]        S_AXI_AWPROT=0;
    reg               S_AXI_AWVALID=0;
    wire              S_AXI_AWREADY;
    reg  [S_DW-1:0]   S_AXI_WDATA=0;
    reg  [S_DW/8-1:0] S_AXI_WSTRB=4'hF;
    reg               S_AXI_WLAST=1;
    reg               S_AXI_WVALID=0;
    wire              S_AXI_WREADY;
    wire [S_IW-1:0]   S_AXI_BID;
    wire [1:0]        S_AXI_BRESP;
    wire              S_AXI_BVALID;
    reg               S_AXI_BREADY=1;
    reg  [S_IW-1:0]   S_AXI_ARID=0;
    reg  [S_AW-1:0]   S_AXI_ARADDR=0;
    reg  [7:0]        S_AXI_ARLEN=0;
    reg  [2:0]        S_AXI_ARSIZE=3'b010;
    reg  [1:0]        S_AXI_ARBURST=2'b01;
    reg  [2:0]        S_AXI_ARPROT=0;
    reg               S_AXI_ARVALID=0;
    wire              S_AXI_ARREADY;
    wire [S_IW-1:0]   S_AXI_RID;
    wire [S_DW-1:0]   S_AXI_RDATA;
    wire [1:0]        S_AXI_RRESP;
    wire              S_AXI_RLAST;
    wire              S_AXI_RVALID;
    reg               S_AXI_RREADY=1;

    // ---- AXI4-Full Master (DMA interface) --------------------------------------
    wire [M_IW-1:0]   M_AXI_AWID,M_AXI_ARID;
    wire [M_AW-1:0]   M_AXI_AWADDR,M_AXI_ARADDR;
    wire [7:0]        M_AXI_AWLEN,M_AXI_ARLEN;
    wire [2:0]        M_AXI_AWSIZE,M_AXI_ARSIZE,M_AXI_AWPROT,M_AXI_ARPROT;
    wire [1:0]        M_AXI_AWBURST,M_AXI_ARBURST;
    wire [3:0]        M_AXI_AWCACHE,M_AXI_ARCACHE;
    wire              M_AXI_AWVALID,M_AXI_ARVALID;
    reg               M_AXI_AWREADY=1,M_AXI_ARREADY=1;
    wire [M_DW-1:0]   M_AXI_WDATA;
    wire [M_DW/8-1:0] M_AXI_WSTRB;
    wire              M_AXI_WLAST,M_AXI_WVALID;
    reg               M_AXI_WREADY=1;
    reg  [M_IW-1:0]   M_AXI_BID=0;
    reg  [1:0]        M_AXI_BRESP=0;
    reg               M_AXI_BVALID=0;
    wire              M_AXI_BREADY;
    reg  [M_IW-1:0]   M_AXI_RID=0;
    reg  [M_DW-1:0]   M_AXI_RDATA=0;
    reg  [1:0]        M_AXI_RRESP=0;
    reg               M_AXI_RLAST=0,M_AXI_RVALID=0;
    wire              M_AXI_RREADY;

    wire [127:0]      o_tag;
    wire              o_tag_valid,o_busy,irq;

    // ---- DUT -----------------------------------------------------------------
    ascon_ip_top #(
        .G_COMB_RND_128(6),.G_COMB_RND_128A(4),
        .G_SBOX_PIPELINE(0),.G_DUAL_RATE(1),.G_AXI_DATA_W(64),
        .S_ADDR_WIDTH(S_AW),.S_DATA_WIDTH(S_DW),.S_ID_WIDTH(S_IW),
        .M_ADDR_WIDTH(M_AW),.M_DATA_WIDTH(M_DW),.M_ID_WIDTH(M_IW),
        .RD_FIFO_DEPTH(4),.WR_FIFO_DEPTH(8)
    ) dut (
        .clk(clk),.rst_n(rst_n),
        .S_AXI_AWID(S_AXI_AWID),.S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWLEN(S_AXI_AWLEN),.S_AXI_AWSIZE(S_AXI_AWSIZE),
        .S_AXI_AWBURST(S_AXI_AWBURST),.S_AXI_AWPROT(S_AXI_AWPROT),
        .S_AXI_AWVALID(S_AXI_AWVALID),.S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),.S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WLAST(S_AXI_WLAST),.S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BID(S_AXI_BID),.S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),.S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARID(S_AXI_ARID),.S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARLEN(S_AXI_ARLEN),.S_AXI_ARSIZE(S_AXI_ARSIZE),
        .S_AXI_ARBURST(S_AXI_ARBURST),.S_AXI_ARPROT(S_AXI_ARPROT),
        .S_AXI_ARVALID(S_AXI_ARVALID),.S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RID(S_AXI_RID),.S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),.S_AXI_RLAST(S_AXI_RLAST),
        .S_AXI_RVALID(S_AXI_RVALID),.S_AXI_RREADY(S_AXI_RREADY),
        .M_AXI_AWID(M_AXI_AWID),.M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN),.M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST),.M_AXI_AWCACHE(M_AXI_AWCACHE),
        .M_AXI_AWPROT(M_AXI_AWPROT),.M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA),.M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST),.M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BID(M_AXI_BID),.M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),.M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARID(M_AXI_ARID),.M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),.M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),.M_AXI_ARCACHE(M_AXI_ARCACHE),
        .M_AXI_ARPROT(M_AXI_ARPROT),.M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RID(M_AXI_RID),.M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),.M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),.M_AXI_RREADY(M_AXI_RREADY),
        .o_tag(o_tag),.o_tag_valid(o_tag_valid),.o_busy(o_busy),.irq(irq)
    );

    // =========================================================================
    // Minimal AXI4 Slave (DDR Simulation for DMA)
    // =========================================================================
    reg [63:0] ddr_mem [0:4095]; // some memory
    
    // AXI Read Channel
    always @(posedge clk) begin
        if (!rst_n) begin
            M_AXI_RVALID <= 0;
            M_AXI_ARREADY <= 1;
            M_AXI_RLAST <= 0;
            M_AXI_RDATA <= 0;
            M_AXI_RID <= 0;
        end else begin
            if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                M_AXI_ARREADY <= 0;
                M_AXI_RVALID <= 1;
                M_AXI_RDATA <= ddr_mem[M_AXI_ARADDR[14:3]]; // 8-byte word addressing
                M_AXI_RLAST <= 1; // ignoring ARLEN for this simple model
                M_AXI_RID   <= M_AXI_ARID;
            end else if (M_AXI_RVALID && M_AXI_RREADY) begin
                M_AXI_RVALID <= 0;
                M_AXI_RLAST <= 0;
                M_AXI_ARREADY <= 1;
            end
        end
    end

    // AXI Write Channel
    reg [31:0] wr_addr_q;
    reg [3:0]  wr_id_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            M_AXI_AWREADY <= 1;
            M_AXI_WREADY <= 1;
            M_AXI_BVALID <= 0;
            M_AXI_BID <= 0;
            wr_addr_q <= 0;
        end else begin
            if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                M_AXI_AWREADY <= 0;
                wr_addr_q <= M_AXI_AWADDR;
                wr_id_q <= M_AXI_AWID;
            end
            if (M_AXI_WVALID && M_AXI_WREADY) begin
                M_AXI_WREADY <= 0;
                ddr_mem[wr_addr_q[14:3]] <= M_AXI_WDATA;
            end
            
            if (!M_AXI_AWREADY && !M_AXI_WREADY && !M_AXI_BVALID) begin
                M_AXI_BVALID <= 1;
                M_AXI_BID <= wr_id_q;
            end else if (M_AXI_BVALID && M_AXI_BREADY) begin
                M_AXI_BVALID <= 0;
                M_AXI_AWREADY <= 1;
                M_AXI_WREADY <= 1;
            end
        end
    end

    // ---- Hierarchical probes -------------------------------------------------
    wire [127:0] hw_ct   = dut.core_data_out_w;
    wire         hw_ct_v = dut.core_data_out_valid_w;
    wire [127:0] hw_tag  = dut.core_tag_out_w;
    wire         hw_tag_v= dut.core_tag_valid_w;
    wire         hw_done = dut.core_done_w;
    wire         dma_done_w = dut.dma_done_w;

    // ---- Expected values -----------------------------------------------------
    localparam [127:0] TEST_KEY   = 128'h000102030405060708090A0B0C0D0E0F;
    localparam [127:0] TEST_NONCE = 128'h101112131415161718191A1B1C1D1E1F;
    localparam [127:0] TEST_AD    = 128'h4153434F4E000000_0000000000000000;
    localparam [127:0] TEST_PT    = 128'h6173636F6E000000_0000000000000000;
    localparam [6:0]   PT_LEN     = 7'd5;
    localparam [39:0]  SW_CT_NOAD  = 40'ha9919fa26e;
    localparam [127:0] SW_TAG_NOAD = 128'hf1a4d483f02f1979dad8aef9985b6148;
    localparam [39:0]  SW_CT       = 40'hbf346c3580;
    localparam [127:0] SW_TAG      = 128'hc45d48d25fb7273d37234eb355825334;

    integer pass_count=0, fail_count=0, cyc_start, cyc_total;
    reg [127:0] cap_ct, cap_tag, tag_rd;
    reg [31:0]  axi_rd;

    always @(posedge clk) begin
        if (hw_ct_v)  cap_ct  <= hw_ct;
        if (hw_tag_v) cap_tag <= hw_tag;
    end

    // =========================================================================
    // Tasks
    // =========================================================================
    task do_reset;
        begin rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk); end
    endtask

    task axi_write;
        input [31:0] addr, data;
        begin
            @(posedge clk);
            S_AXI_AWADDR <= addr; S_AXI_AWVALID <= 1;
            S_AXI_WDATA <= data; S_AXI_WSTRB <= 4'hF; S_AXI_WLAST <= 1; S_AXI_WVALID <= 1;
            
            while (S_AXI_AWVALID || S_AXI_WVALID) begin
                @(posedge clk);
                if (S_AXI_AWVALID && S_AXI_AWREADY) S_AXI_AWVALID <= 0;
                if (S_AXI_WVALID && S_AXI_WREADY)   S_AXI_WVALID <= 0;
            end
            
            while (!S_AXI_BVALID) @(posedge clk);
            S_AXI_BREADY <= 1;
            @(posedge clk);
            S_AXI_BREADY <= 0;
        end
    endtask

    task axi_read;
        input [31:0] addr;
        begin
            @(posedge clk);
            S_AXI_ARADDR <= addr; S_AXI_ARVALID <= 1;
            
            while (S_AXI_ARVALID) begin
                @(posedge clk);
                if (S_AXI_ARVALID && S_AXI_ARREADY) S_AXI_ARVALID <= 0;
            end
            
            while (!S_AXI_RVALID) @(posedge clk);
            axi_rd <= S_AXI_RDATA;
            S_AXI_RREADY <= 1;
            @(posedge clk);
            S_AXI_RREADY <= 0;
        end
    endtask

    task cpu_setup;
        input [127:0] key, nonce, pt;
        input [6:0] plen;
        input [1:0] mode;
        begin
            axi_write(32'h000, {30'h0, mode}); // ADDR_MODE
            axi_write(32'h010, key[127:96]);   axi_write(32'h014, key[95:64]);
            axi_write(32'h018, key[63:32]);    axi_write(32'h01C, key[31:0]);
            axi_write(32'h024, nonce[127:96]); axi_write(32'h028, nonce[95:64]);
            axi_write(32'h02C, nonce[63:32]);  axi_write(32'h030, nonce[31:0]);
            axi_write(32'h034, pt[127:96]);    axi_write(32'h038, pt[95:64]);
            axi_write(32'h03C, {25'h0, plen}); // ADDR_DATA_LEN
        end
    endtask

    task wait_done;
        integer t;
        begin
            cyc_start=$time/10; t=0; @(posedge clk);
            while (!hw_done && t<10000) begin @(posedge clk); t=t+1; end
            cyc_total=($time/10)-cyc_start;
            if (t>=10000) $display("  [TIMEOUT] wait_done");
        end
    endtask

    task wait_dma_done;
        integer t;
        begin
            cyc_start=$time/10; t=0; @(posedge clk);
            while (!dma_done_w && t<10000) begin @(posedge clk); t=t+1; end
            cyc_total=($time/10)-cyc_start;
            if (t>=10000) $display("  [TIMEOUT] wait_dma_done");
        end
    endtask

    task check40;
        input [255:0] lbl; input [39:0] got, exp;
        begin
            if (got===exp) begin $display("  [PASS] %s = %h",lbl,got); pass_count=pass_count+1; end
            else begin $display("  [FAIL] %s  got=%h  exp=%h",lbl,got,exp); fail_count=fail_count+1; end
        end
    endtask

    task check128;
        input [255:0] lbl; input [127:0] got, exp;
        begin
            if (got===exp) begin $display("  [PASS] %s = %h",lbl,got); pass_count=pass_count+1; end
            else begin $display("  [FAIL] %s  got=%h  exp=%h",lbl,got,exp); fail_count=fail_count+1; end
        end
    endtask

    task check1;
        input [255:0] lbl; input got, exp;
        begin
            if (got===exp) begin $display("  [PASS] %s = %b",lbl,got); pass_count=pass_count+1; end
            else begin $display("  [FAIL] %s  got=%b  exp=%b",lbl,got,exp); fail_count=fail_count+1; end
        end
    endtask

    initial begin
        $dumpfile("tb_ascon_ip_top_rewrite.vcd");
        $dumpvars(0, tb_ascon_ip_top_rewrite);
        
        $display("======= CPU-DIRECT TEST =======");
        do_reset;
        cpu_setup(TEST_KEY, TEST_NONCE, TEST_PT, PT_LEN, 2'b00); // ADDR_MODE=0
        axi_write(32'h020, 32'h1);  // CTRL: start=1, dma_en=0
        wait_done;
        $display("  Cycles: %0d", cyc_total);
        check40("CT  (5B, CPU-Direct)",  cap_ct[127:88],  SW_CT_NOAD);
        check128("TAG (CPU-Direct)",     cap_tag,         SW_TAG_NOAD);
        
        $display("======= DMA TEST =======");
        do_reset;
        // set key, nonce, data_len. mode=0.
        cpu_setup(TEST_KEY, TEST_NONCE, 128'h0, PT_LEN, 2'b00); // mode=0
        
        // write dma registers
        axi_write(32'h100, 32'h1000); // Src
        axi_write(32'h104, 32'h2000); // Dst
        axi_write(32'h108, 32'd8);    // Len (8 bytes for test)
        axi_write(32'h114, 32'd0);    // Burst (0)
        
        // Populate DDR slave array so DMA can read it
        ddr_mem[12'h1000 >> 3] = TEST_PT[127:64]; 
        
        // start
        axi_write(32'h020, 32'h5); // ctrl=5 -> dma_en=1, start=1

        wait_dma_done;
        $display("  Cycles: %0d", cyc_total);
        
        // Read out DDR
        check40("CT  (5B, DMA)", ddr_mem[12'h2000 >> 3][63:24], SW_CT_NOAD); 
        // Note: CT is placed in memory exactly as it came from CT output
        // The core outputs 64-bit blocks. CT (5B) is at the MSB of the 64-bit word
        $display("  DDR[0x2000] (CT beat 0) = %h", ddr_mem[12'h2000 >> 3]);
        $display("  DDR[0x2008] (TAG beat 0)= %h", ddr_mem[12'h2008 >> 3]);
        $display("  DDR[0x2010] (TAG beat 1)= %h", ddr_mem[12'h2010 >> 3]);
        
        check128("TAG (DMA)", {ddr_mem[12'h2008 >> 3], ddr_mem[12'h2010 >> 3]}, SW_TAG_NOAD);

        $finish;
    end
endmodule
