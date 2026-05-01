`timescale 1ns/1ps

`timescale 1ns/1ps
`include "ascon/ascon_top.v"
module tb_multi_block_dma;

    reg clk;
    reg rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // AXI4 SLAVE INF (connect CPU to slave)
    wire [3:0] s_axi_awid = 4'd0;
    reg [23:0] s_axi_awaddr;
    reg        s_axi_awvalid;
    wire       s_axi_awready;

    reg [31:0] s_axi_wdata;
    reg [3:0]  s_axi_wstrb;
    reg        s_axi_wvalid;
    wire       s_axi_wready;

    reg        s_axi_bready;
    wire       s_axi_bvalid;

    // We can drive the slave AXI to configure
    task write_reg(input [11:0] offset, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr = offset;
            s_axi_awvalid = 1;
            s_axi_wdata = data;
            s_axi_wstrb = 4'hf;
            s_axi_wvalid = 1;
            s_axi_bready = 1;
            
            while (!s_axi_awready) @(posedge clk);
            s_axi_awvalid = 0;
            while (!s_axi_wready) @(posedge clk);
            s_axi_wvalid = 0;
            while (!s_axi_bvalid) @(posedge clk);
            s_axi_bready = 0;
            @(posedge clk);
        end
    endtask

    // DUT
    ascon_ip_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .S_AXI_AWID(s_axi_awid),
        .S_AXI_AWADDR(s_axi_awaddr),
        .S_AXI_AWVALID(s_axi_awvalid),
        .S_AXI_AWREADY(s_axi_awready),
        .S_AXI_WDATA(s_axi_wdata),
        .S_AXI_WSTRB(s_axi_wstrb),
        .S_AXI_WLAST(s_axi_wvalid), // simple
        .S_AXI_WVALID(s_axi_wvalid),
        .S_AXI_WREADY(s_axi_wready),
        .S_AXI_BREADY(s_axi_bready),
        .S_AXI_BVALID(s_axi_bvalid),
        
        .S_AXI_ARVALID(1'b0),
        .S_AXI_RREADY(1'b1),

        // M_AXI loopback simply to test
        .M_AXI_AWREADY(1'b1),
        .M_AXI_WREADY(1'b1),
        .M_AXI_BVALID(1'b1),
        .M_AXI_BRESP(2'b00),
        
        .M_AXI_ARREADY(1'b1),
        .M_AXI_RVALID(M_AXI_ARVALID_del),
        .M_AXI_RDATA(64'h0123456789ABCDEF),
        .M_AXI_RLAST(1'b1)
    );

    reg M_AXI_ARVALID_del;
    always @(posedge clk) M_AXI_ARVALID_del <= u_dut.M_AXI_ARVALID;

    initial begin
        rst_n = 0;
        s_axi_awaddr = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;

        #20 rst_n = 1;

        // Init DMA length to 16 bytes (2 blocks)
        write_reg(12'h108, 32'd16);
        // Init DMA burst to 1
        write_reg(12'h114, 32'd1);
        // Start DMA with DMA_EN = 1
        write_reg(12'h020, 32'h4); // ctrl = dma_en

        #1000;
        $display("Test finished.");
        $finish;
    end

endmodule
