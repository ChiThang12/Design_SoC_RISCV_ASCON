// ============================================================================
// tb_axi4_lite_master_if.v - Testbench cho AXI4-Lite Master Interface
// ============================================================================

`timescale 1ns/1ps
`include "interface/axi4_lite_master_if.v"
module tb_axi4_lite_master_if;

    // ========================================================================
    // Clock & Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // ========================================================================
    // CPU Request Interface
    // ========================================================================
    reg [31:0] cpu_addr;
    reg [31:0] cpu_wdata;
    reg [3:0]  cpu_wstrb;
    reg        cpu_req;
    reg        cpu_wr;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;
    wire        cpu_error;
    
    // ========================================================================
    // AXI4-Lite Master Interface
    // ========================================================================
    wire [31:0] M_AXI_AWADDR;
    wire [2:0]  M_AXI_AWPROT;
    wire        M_AXI_AWVALID;
    reg         M_AXI_AWREADY;
    
    wire [31:0] M_AXI_WDATA;
    wire [3:0]  M_AXI_WSTRB;
    wire        M_AXI_WVALID;
    reg         M_AXI_WREADY;
    
    reg [1:0]   M_AXI_BRESP;
    reg         M_AXI_BVALID;
    wire        M_AXI_BREADY;
    
    wire [31:0] M_AXI_ARADDR;
    wire [2:0]  M_AXI_ARPROT;
    wire        M_AXI_ARVALID;
    reg         M_AXI_ARREADY;
    
    reg [31:0]  M_AXI_RDATA;
    reg [1:0]   M_AXI_RRESP;
    reg         M_AXI_RVALID;
    wire        M_AXI_RREADY;
    
    // ========================================================================
    // Slave Memory Model (đơn giản)
    // ========================================================================
    reg [31:0] memory [0:255];  // 256 words memory
    integer i;
    
    // ========================================================================
    // Test Statistics
    // ========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    axi4_lite_master_if dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_wstrb(cpu_wstrb),
        .cpu_req(cpu_req),
        .cpu_wr(cpu_wr),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .cpu_error(cpu_error),
        
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );
    
    // ========================================================================
    // Clock Generation - 100MHz (10ns period)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // AXI Slave Response Model
    // ========================================================================
    
    // Write Address Channel Response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_AWREADY <= 1'b0;
        end else begin
            // Random ready hoặc immediate ready
            if (M_AXI_AWVALID && !M_AXI_AWREADY) begin
                M_AXI_AWREADY <= 1'b1;  // Immediate ready cho test đơn giản
            end else begin
                M_AXI_AWREADY <= 1'b0;
            end
        end
    end
    
    // Write Data Channel Response
    reg [31:0] write_addr_latched;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_addr_latched <= 32'h0;
        end else begin
            if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                write_addr_latched <= M_AXI_AWADDR;
            end
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_WREADY <= 1'b0;
        end else begin
            if (M_AXI_WVALID && !M_AXI_WREADY) begin
                M_AXI_WREADY <= 1'b1;
                // Ghi vào memory với byte strobe
                if (M_AXI_AWVALID) begin
                    // Address và data cùng lúc
                    if (M_AXI_WSTRB[0]) memory[M_AXI_AWADDR[9:2]][7:0]   <= M_AXI_WDATA[7:0];
                    if (M_AXI_WSTRB[1]) memory[M_AXI_AWADDR[9:2]][15:8]  <= M_AXI_WDATA[15:8];
                    if (M_AXI_WSTRB[2]) memory[M_AXI_AWADDR[9:2]][23:16] <= M_AXI_WDATA[23:16];
                    if (M_AXI_WSTRB[3]) memory[M_AXI_AWADDR[9:2]][31:24] <= M_AXI_WDATA[31:24];
                end else begin
                    // Dùng địa chỉ đã latch
                    if (M_AXI_WSTRB[0]) memory[write_addr_latched[9:2]][7:0]   <= M_AXI_WDATA[7:0];
                    if (M_AXI_WSTRB[1]) memory[write_addr_latched[9:2]][15:8]  <= M_AXI_WDATA[15:8];
                    if (M_AXI_WSTRB[2]) memory[write_addr_latched[9:2]][23:16] <= M_AXI_WDATA[23:16];
                    if (M_AXI_WSTRB[3]) memory[write_addr_latched[9:2]][31:24] <= M_AXI_WDATA[31:24];
                end
            end else begin
                M_AXI_WREADY <= 1'b0;
            end
        end
    end
    
    // Write Response Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_BVALID <= 1'b0;
            M_AXI_BRESP  <= 2'b00;
        end else begin
            if (M_AXI_WVALID && M_AXI_WREADY && !M_AXI_BVALID) begin
                M_AXI_BVALID <= 1'b1;
                M_AXI_BRESP  <= 2'b00;  // OKAY
            end else if (M_AXI_BREADY && M_AXI_BVALID) begin
                M_AXI_BVALID <= 1'b0;
            end
        end
    end
    
    // Read Address Channel Response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_ARREADY <= 1'b0;
        end else begin
            if (M_AXI_ARVALID && !M_AXI_ARREADY) begin
                M_AXI_ARREADY <= 1'b1;
            end else begin
                M_AXI_ARREADY <= 1'b0;
            end
        end
    end
    
    // Read Data Channel Response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_RVALID <= 1'b0;
            M_AXI_RDATA  <= 32'h0;
            M_AXI_RRESP  <= 2'b00;
        end else begin
            if (M_AXI_ARVALID && M_AXI_ARREADY && !M_AXI_RVALID) begin
                M_AXI_RVALID <= 1'b1;
                M_AXI_RDATA  <= memory[M_AXI_ARADDR[9:2]];
                M_AXI_RRESP  <= 2'b00;  // OKAY
            end else if (M_AXI_RREADY && M_AXI_RVALID) begin
                M_AXI_RVALID <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // Tasks for Testing
    // ========================================================================
    
    // Task: CPU Write
    task cpu_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(posedge clk);
            cpu_addr  = addr;
            cpu_wdata = data;
            cpu_wstrb = strb;
            cpu_wr    = 1'b1;
            cpu_req   = 1'b1;
            
            @(posedge clk);
            cpu_req = 1'b0;
            
            // Đợi transaction hoàn thành
            wait(cpu_ready);
            @(posedge clk);
            
            if (cpu_error) begin
                $display("[%0t] WRITE ERROR at addr=0x%08h", $time, addr);
                fail_count = fail_count + 1;
            end else begin
                $display("[%0t] WRITE SUCCESS: addr=0x%08h, data=0x%08h, strb=0x%h", 
                         $time, addr, data, strb);
                pass_count = pass_count + 1;
            end
            test_count = test_count + 1;
        end
    endtask
    
    // Task: CPU Read
    task cpu_read;
        input [31:0] addr;
        input [31:0] expected_data;
        begin
            @(posedge clk);
            cpu_addr = addr;
            cpu_wr   = 1'b0;
            cpu_req  = 1'b1;
            
            @(posedge clk);
            cpu_req = 1'b0;
            
            // Đợi transaction hoàn thành
            wait(cpu_ready);
            @(posedge clk);
            
            if (cpu_error) begin
                $display("[%0t] READ ERROR at addr=0x%08h", $time, addr);
                fail_count = fail_count + 1;
            end else if (cpu_rdata !== expected_data) begin
                $display("[%0t] READ MISMATCH: addr=0x%08h, expected=0x%08h, got=0x%08h", 
                         $time, addr, expected_data, cpu_rdata);
                fail_count = fail_count + 1;
            end else begin
                $display("[%0t] READ SUCCESS: addr=0x%08h, data=0x%08h", 
                         $time, addr, cpu_rdata);
                pass_count = pass_count + 1;
            end
            test_count = test_count + 1;
        end
    endtask
    
    // Task: Reset
    task reset_system;
        begin
            rst_n = 1'b0;
            cpu_addr  = 32'h0;
            cpu_wdata = 32'h0;
            cpu_wstrb = 4'h0;
            cpu_req   = 1'b0;
            cpu_wr    = 1'b0;
            
            repeat(5) @(posedge clk);
            rst_n = 1'b1;
            repeat(2) @(posedge clk);
            $display("[%0t] System Reset Complete", $time);
        end
    endtask
    
    // ========================================================================
    // Test Scenarios
    // ========================================================================
    initial begin
        // Khởi tạo
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Khởi tạo memory
        for (i = 0; i < 256; i = i + 1) begin
            memory[i] = 32'h0;
        end
        
        $display("============================================================");
        $display("  AXI4-Lite Master Interface Testbench");
        $display("============================================================");
        
        // Reset
        reset_system();
        
        // ================================================================
        // TEST 1: Basic Write
        // ================================================================
        $display("\n[TEST 1] Basic Write Operations");
        cpu_write(32'h0000_0000, 32'hDEAD_BEEF, 4'hF);
        cpu_write(32'h0000_0004, 32'h1234_5678, 4'hF);
        cpu_write(32'h0000_0008, 32'hABCD_EF00, 4'hF);
        
        // ================================================================
        // TEST 2: Basic Read
        // ================================================================
        $display("\n[TEST 2] Basic Read Operations");
        cpu_read(32'h0000_0000, 32'hDEAD_BEEF);
        cpu_read(32'h0000_0004, 32'h1234_5678);
        cpu_read(32'h0000_0008, 32'hABCD_EF00);
        
        // ================================================================
        // TEST 3: Write then Read (Verify)
        // ================================================================
        $display("\n[TEST 3] Write-Read Verification");
        cpu_write(32'h0000_0010, 32'hCAFE_BABE, 4'hF);
        cpu_read(32'h0000_0010, 32'hCAFE_BABE);
        
        cpu_write(32'h0000_0014, 32'h5555_AAAA, 4'hF);
        cpu_read(32'h0000_0014, 32'h5555_AAAA);
        
        // ================================================================
        // TEST 4: Byte Write (wstrb testing)
        // ================================================================
        $display("\n[TEST 4] Byte-level Write (wstrb)");
        cpu_write(32'h0000_0020, 32'h0000_0000, 4'hF);  // Clear
        cpu_write(32'h0000_0020, 32'h0000_00FF, 4'h1);  // Byte 0
        cpu_write(32'h0000_0020, 32'h0000_FF00, 4'h2);  // Byte 1
        cpu_read(32'h0000_0020, 32'h0000_FFFF);
        
        // ================================================================
        // TEST 5: Burst Transactions
        // ================================================================
        $display("\n[TEST 5] Multiple Sequential Transactions");
        for (i = 0; i < 8; i = i + 1) begin
            cpu_write(32'h0000_0100 + (i*4), i, 4'hF);
        end
        
        for (i = 0; i < 8; i = i + 1) begin
            cpu_read(32'h0000_0100 + (i*4), i);
        end
        
        // ================================================================
        // TEST 6: Random Access Pattern
        // ================================================================
        $display("\n[TEST 6] Random Access Pattern");
        cpu_write(32'h0000_0080, 32'hAAAA_AAAA, 4'hF);
        cpu_write(32'h0000_0040, 32'h5555_5555, 4'hF);
        cpu_read(32'h0000_0080, 32'hAAAA_AAAA);
        cpu_read(32'h0000_0040, 32'h5555_5555);
        
        // ================================================================
        // Kết thúc test
        // ================================================================
        repeat(10) @(posedge clk);
        
        $display("\n============================================================");
        $display("  Test Summary");
        $display("============================================================");
        $display("  Total Tests: %0d", test_count);
        $display("  Passed:      %0d", pass_count);
        $display("  Failed:      %0d", fail_count);
        $display("============================================================");
        
        if (fail_count == 0) begin
            $display("  ALL TESTS PASSED!");
        end else begin
            $display("  SOME TESTS FAILED!");
        end
        $display("============================================================\n");
        
        $finish;
    end
    
    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #100000;  // 100us timeout
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end
    
    // ========================================================================
    // Waveform Dump (cho GTKWave/ModelSim)
    // ========================================================================
    initial begin
        $dumpfile("axi4_lite_master_tb.vcd");
        $dumpvars(0, tb_axi4_lite_master_if);
    end

endmodule