`timescale 1ns/1ps
`include "./memory/data_mem_axi_slave.v"
`include "./memory/inst_mem_axi_slave.v"

module tb_axi_memory;

    // ========================================================================
    // Clock & Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    parameter CLK_PERIOD = 10;
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ========================================================================
    // AXI4-Lite Signals for Data Memory
    // ========================================================================
    reg [31:0]  dmem_awaddr;
    reg [2:0]   dmem_awprot;
    reg         dmem_awvalid;
    wire        dmem_awready;
    
    reg [31:0]  dmem_wdata;
    reg [3:0]   dmem_wstrb;
    reg         dmem_wvalid;
    wire        dmem_wready;
    
    wire [1:0]  dmem_bresp;
    wire        dmem_bvalid;
    reg         dmem_bready;
    
    reg [31:0]  dmem_araddr;
    reg [2:0]   dmem_arprot;
    reg         dmem_arvalid;
    wire        dmem_arready;
    
    wire [31:0] dmem_rdata;
    wire [1:0]  dmem_rresp;
    wire        dmem_rvalid;
    reg         dmem_rready;
    
    // ========================================================================
    // AXI4-Lite Signals for Instruction Memory
    // ========================================================================
    reg [31:0]  imem_awaddr;
    reg [2:0]   imem_awprot;
    reg         imem_awvalid;
    wire        imem_awready;
    
    reg [31:0]  imem_wdata;
    reg [3:0]   imem_wstrb;
    reg         imem_wvalid;
    wire        imem_wready;
    
    wire [1:0]  imem_bresp;
    wire        imem_bvalid;
    reg         imem_bready;
    
    reg [31:0]  imem_araddr;
    reg [2:0]   imem_arprot;
    reg         imem_arvalid;
    wire        imem_arready;
    
    wire [31:0] imem_rdata;
    wire [1:0]  imem_rresp;
    wire        imem_rvalid;
    reg         imem_rready;
    
    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    data_mem_axi_slave dmem_slave (
        .clk(clk),
        .rst_n(rst_n),
        .S_AXI_AWADDR(dmem_awaddr),
        .S_AXI_AWPROT(dmem_awprot),
        .S_AXI_AWVALID(dmem_awvalid),
        .S_AXI_AWREADY(dmem_awready),
        .S_AXI_WDATA(dmem_wdata),
        .S_AXI_WSTRB(dmem_wstrb),
        .S_AXI_WVALID(dmem_wvalid),
        .S_AXI_WREADY(dmem_wready),
        .S_AXI_BRESP(dmem_bresp),
        .S_AXI_BVALID(dmem_bvalid),
        .S_AXI_BREADY(dmem_bready),
        .S_AXI_ARADDR(dmem_araddr),
        .S_AXI_ARPROT(dmem_arprot),
        .S_AXI_ARVALID(dmem_arvalid),
        .S_AXI_ARREADY(dmem_arready),
        .S_AXI_RDATA(dmem_rdata),
        .S_AXI_RRESP(dmem_rresp),
        .S_AXI_RVALID(dmem_rvalid),
        .S_AXI_RREADY(dmem_rready)
    );
    
    inst_mem_axi_slave imem_slave (
        .clk(clk),
        .rst_n(rst_n),
        .S_AXI_AWADDR(imem_awaddr),
        .S_AXI_AWPROT(imem_awprot),
        .S_AXI_AWVALID(imem_awvalid),
        .S_AXI_AWREADY(imem_awready),
        .S_AXI_WDATA(imem_wdata),
        .S_AXI_WSTRB(imem_wstrb),
        .S_AXI_WVALID(imem_wvalid),
        .S_AXI_WREADY(imem_wready),
        .S_AXI_BRESP(imem_bresp),
        .S_AXI_BVALID(imem_bvalid),
        .S_AXI_BREADY(imem_bready),
        .S_AXI_ARADDR(imem_araddr),
        .S_AXI_ARPROT(imem_arprot),
        .S_AXI_ARVALID(imem_arvalid),
        .S_AXI_ARREADY(imem_arready),
        .S_AXI_RDATA(imem_rdata),
        .S_AXI_RRESP(imem_rresp),
        .S_AXI_RVALID(imem_rvalid),
        .S_AXI_RREADY(imem_rready)
    );
    
    // ========================================================================
    // Test Statistics
    // ========================================================================
    integer test_pass = 0;
    integer test_fail = 0;
    
    // ========================================================================
    // ARPROT Encoding
    // ========================================================================
    // ARPROT[2:1] = 00: Byte, 01: Halfword, 10: Word
    // ARPROT[0]   = 0: Unsigned, 1: Signed
    localparam [2:0] PROT_LBU  = 3'b000;  // Load Byte Unsigned
    localparam [2:0] PROT_LB   = 3'b001;  // Load Byte Signed
    localparam [2:0] PROT_LHU  = 3'b010;  // Load Halfword Unsigned
    localparam [2:0] PROT_LH   = 3'b011;  // Load Halfword Signed
    localparam [2:0] PROT_LW   = 3'b100;  // Load Word
    
    // ========================================================================
    // Task: AXI Write
    // ========================================================================
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            // Write Address
            @(posedge clk);
            dmem_awaddr  <= addr;
            dmem_awprot  <= 3'b000;
            dmem_awvalid <= 1'b1;
            
            @(posedge clk);
            while (!dmem_awready) @(posedge clk);
            dmem_awvalid <= 1'b0;
            
            // Write Data
            dmem_wdata  <= data;
            dmem_wstrb  <= strb;
            dmem_wvalid <= 1'b1;
            
            @(posedge clk);
            while (!dmem_wready) @(posedge clk);
            dmem_wvalid <= 1'b0;
            
            // Write Response
            dmem_bready <= 1'b1;
            @(posedge clk);
            while (!dmem_bvalid) @(posedge clk);
            dmem_bready <= 1'b0;
            
            $display("[DMEM WRITE] Addr=0x%08h, Data=0x%08h, Strb=%b, Resp=%02b", 
                     addr, data, strb, dmem_bresp);
        end
    endtask
    
    // ========================================================================
    // Task: AXI Read
    // ========================================================================
    task axi_read;
        input [31:0] addr;
        input [2:0]  prot;
        output [31:0] data;
        output [1:0]  resp;
        begin
            // Read Address
            @(posedge clk);
            dmem_araddr  <= addr;
            dmem_arprot  <= prot;
            dmem_arvalid <= 1'b1;
            
            @(posedge clk);
            while (!dmem_arready) @(posedge clk);
            dmem_arvalid <= 1'b0;
            
            // Read Data
            dmem_rready <= 1'b1;
            @(posedge clk);
            while (!dmem_rvalid) @(posedge clk);
            data = dmem_rdata;
            resp = dmem_rresp;
            dmem_rready <= 1'b0;
            
            $display("[DMEM READ] Addr=0x%08h, Data=0x%08h, Resp=%02b, PROT=%03b", 
                     addr, data, resp, prot);
        end
    endtask
    
    // ========================================================================
    // Task: IMEM Read
    // ========================================================================
    task imem_read;
        input [31:0] addr;
        output [31:0] data;
        output [1:0]  resp;
        begin
            @(posedge clk);
            imem_araddr  <= addr;
            imem_arprot  <= 3'b000;
            imem_arvalid <= 1'b1;
            
            @(posedge clk);
            while (!imem_arready) @(posedge clk);
            imem_arvalid <= 1'b0;
            
            imem_rready <= 1'b1;
            @(posedge clk);
            while (!imem_rvalid) @(posedge clk);
            data = imem_rdata;
            resp = imem_rresp;
            imem_rready <= 1'b0;
            
            $display("[IMEM READ] Addr=0x%08h, Data=0x%08h, Resp=%02b", addr, data, resp);
        end
    endtask
    
    // ========================================================================
    // Task: IMEM Write (should fail)
    // ========================================================================
    task imem_write;
        input [31:0] addr;
        input [31:0] data;
        output [1:0]  resp;
        begin
            @(posedge clk);
            imem_awaddr  <= addr;
            imem_awvalid <= 1'b1;
            @(posedge clk);
            while (!imem_awready) @(posedge clk);
            imem_awvalid <= 1'b0;
            
            imem_wdata  <= data;
            imem_wstrb  <= 4'b1111;
            imem_wvalid <= 1'b1;
            @(posedge clk);
            while (!imem_wready) @(posedge clk);
            imem_wvalid <= 1'b0;
            
            imem_bready <= 1'b1;
            @(posedge clk);
            while (!imem_bvalid) @(posedge clk);
            resp = imem_bresp;
            imem_bready <= 1'b0;
            
            $display("[IMEM WRITE] Addr=0x%08h, Data=0x%08h, Resp=%02b (expect SLVERR=10)", 
                     addr, data, resp);
        end
    endtask
    
    // ========================================================================
    // Main Test
    // ========================================================================
    reg [31:0] read_data;
    reg [1:0]  read_resp;
    
    initial begin
        // Initialize
        rst_n = 0;
        
        dmem_awaddr = 0; dmem_awprot = 0; dmem_awvalid = 0;
        dmem_wdata = 0; dmem_wstrb = 0; dmem_wvalid = 0;
        dmem_bready = 0;
        dmem_araddr = 0; dmem_arprot = 0; dmem_arvalid = 0;
        dmem_rready = 0;
        
        imem_awaddr = 0; imem_awprot = 0; imem_awvalid = 0;
        imem_wdata = 0; imem_wstrb = 0; imem_wvalid = 0;
        imem_bready = 0;
        imem_araddr = 0; imem_arprot = 0; imem_arvalid = 0;
        imem_rready = 0;
        
        #100;
        rst_n = 1;
        #50;
        
        // ====================================================================
        // TEST 1: Instruction Memory Read
        // ====================================================================
        $display("\n========================================");
        $display("TEST 1: Instruction Memory Read");
        $display("========================================");
        imem_read(32'h00000000, read_data, read_resp);
        imem_read(32'h00000004, read_data, read_resp);
        imem_read(32'h00000008, read_data, read_resp);
        
        // ====================================================================
        // TEST 2: Instruction Memory Write (should fail)
        // ====================================================================
        $display("\n========================================");
        $display("TEST 2: Instruction Memory Write (should fail)");
        $display("========================================");
        imem_write(32'h00000000, 32'hDEADBEEF, read_resp);
        if (read_resp == 2'b10) begin
            $display("✓ PASS: Write rejected with SLVERR");
            test_pass = test_pass + 1;
        end else begin
            $display("✗ FAIL: Expected SLVERR (10) but got %02b", read_resp);
            test_fail = test_fail + 1;
        end
        
        // ====================================================================
        // TEST 3: Data Memory Write/Read Word (32-bit)
        // ====================================================================
        $display("\n========================================");
        $display("TEST 3: Data Memory Write/Read Word (32-bit)");
        $display("========================================");
        axi_write(32'h00000000, 32'hDEADBEEF, 4'b1111);
        axi_read(32'h00000000, PROT_LW, read_data, read_resp);
        if (read_data == 32'hDEADBEEF) begin
            $display("✓ PASS: Word write/read");
            test_pass = test_pass + 1;
        end else begin
            $display("✗ FAIL: Expected 0xDEADBEEF but got 0x%08h", read_data);
            test_fail = test_fail + 1;
        end
        
        // ====================================================================
        // TEST 4: Byte Write with Different Offsets
        // ====================================================================
        $display("\n========================================");
        $display("TEST 4: Byte Write with Different Offsets");
        $display("========================================");
        axi_write(32'h00000010, 32'h000000AB, 4'b0001);  // Byte 0
        axi_write(32'h00000011, 32'h000000CD, 4'b0010);  // Byte 1
        axi_write(32'h00000012, 32'h000000EF, 4'b0100);  // Byte 2
        axi_write(32'h00000013, 32'h00000012, 4'b1000);  // Byte 3
        axi_read(32'h00000010, PROT_LW, read_data, read_resp);
        if (read_data == 32'h12EFCDAB) begin
            $display("✓ PASS: Byte writes at different offsets");
            test_pass = test_pass + 1;
        end else begin
            $display("✗ FAIL: Expected 0x12EFCDAB but got 0x%08h", read_data);
            test_fail = test_fail + 1;
        end
        
        // ====================================================================
        // TEST 5: Halfword Write with Different Offsets
        // ====================================================================
        $display("\n========================================");
        $display("TEST 5: Halfword Write with Different Offsets");
        $display("========================================");
        axi_write(32'h00000020, 32'h00001234, 4'b0011);  // Lower halfword
        axi_write(32'h00000022, 32'h00005678, 4'b1100);  // Upper halfword
        axi_read(32'h00000020, PROT_LW, read_data, read_resp);
        if (read_data == 32'h56781234) begin
            $display("✓ PASS: Halfword writes at different offsets");
            test_pass = test_pass + 1;
        end else begin
            $display("✗ FAIL: Expected 0x56781234 but got 0x%08h", read_data);
            test_fail = test_fail + 1;
        end
        
        // ====================================================================
        // TEST 6: Sign Extension - LB (signed)
        // ====================================================================
        $display("\n========================================");
        $display("TEST 6: Sign Extension - LB (signed)");
        $display("========================================");
        axi_write(32'h00000030, 32'h000000FF, 4'b0001);
        axi_read(32'h00000030, PROT_LB, read_data, read_resp);
        if (read_data == 32'hFFFFFFFF) begin
            $display("✓ PASS: LB sign extension (0xFF → 0xFFFFFFFF)");
            test_pass = test_pass + 1;
        end else begin
            $display("✗ FAIL: Expected 0xFFFFFFFF but got 0x%08h", read_data);
            test_fail = test_fail + 1;
        end
        
        // ====================================================================
        // TEST 7: Zero Extension - LBU (unsigned)
        // ====================================================================
        $display("\n========================================");
        $display("TEST 7: Zero Extension - LBU (unsigned)");
        $display("========================================");
        axi_read(32'h00000030, PROT_LBU, read_data, read_resp);
        if (read_data == 32'h000000FF) begin
            $display("✓ PASS: LBU zero extension (0xFF → 0x000000FF)");
            test_pass = test_pass + 1;
        end else begin
            $display("✗ FAIL: Expected 0x000000FF but got 0x%08h", read_data);
            test_fail = test_fail + 1;
        end
        
        // ====================================================================
        // TEST 8: Halfword Sign/Zero Extension
        // ====================================================================
        $display("\n========================================");
        $display("TEST 8: Halfword Sign/Zero Extension");
        $display("========================================");
        axi_write(32'h00000040, 32'h00008000, 4'b0011);
        axi_read(32'h00000040, PROT_LH, read_data, read_resp);
        if (read_data == 32'hFFFF8000) begin
            $display("✓ PASS: LH sign extension (0x8000 → 0xFFFF8000)");
            test_pass = test_pass + 1;
        end else begin
            $display("✗ FAIL: Expected 0xFFFF8000 but got 0x%08h", read_data);
            test_fail = test_fail + 1;
        end
        
        axi_read(32'h00000040, PROT_LHU, read_data, read_resp);
        if (read_data == 32'h00008000) begin
            $display("✓ PASS: LHU zero extension (0x8000 → 0x00008000)");
            test_pass = test_pass + 1;
        end else begin
            $display("✗ FAIL: Expected 0x00008000 but got 0x%08h", read_data);
            test_fail = test_fail + 1;
        end
        
        // ====================================================================
        // TEST 9: Back-to-back Transactions
        // ====================================================================
        $display("\n========================================");
        $display("TEST 9: Back-to-back Transactions");
        $display("========================================");
        axi_write(32'h00000050, 32'h11111111, 4'b1111);
        axi_write(32'h00000054, 32'h22222222, 4'b1111);
        axi_write(32'h00000058, 32'h33333333, 4'b1111);
        
        axi_read(32'h00000050, PROT_LW, read_data, read_resp);
        axi_read(32'h00000054, PROT_LW, read_data, read_resp);
        axi_read(32'h00000058, PROT_LW, read_data, read_resp);
        
        // ====================================================================
        // Summary
        // ====================================================================
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("PASSED: %0d tests", test_pass);
        $display("FAILED: %0d tests", test_fail);
        if (test_fail == 0) begin
            $display("✓✓✓ ALL TESTS PASSED ✓✓✓");
        end else begin
            $display("✗✗✗ SOME TESTS FAILED ✗✗✗");
        end
        $display("========================================");
        
        #100;
        $finish;
    end

endmodule