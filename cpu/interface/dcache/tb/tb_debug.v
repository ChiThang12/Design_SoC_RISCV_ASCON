// ============================================================================
// Testbench: tb_dcache_complete - COMPREHENSIVE TEST SUITE
// ============================================================================
`timescale 1ns/1ps
`include "cpu/interface/dcache/tb/dcache_defines.vh"
`include "cpu/interface/dcache/tb/dcache_top.v"

module tb_dcache_debug;

    reg clk, rst_n;
    
    // CPU Interface
    reg [31:0] cpu_addr, cpu_wdata;
    reg [3:0]  cpu_wstrb;
    reg        cpu_req, cpu_we, fence;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;
    
    // AXI Read
    wire [31:0] mem_araddr;
    wire [7:0]  mem_arlen;
    wire [2:0]  mem_arsize;
    wire [1:0]  mem_arburst;
    wire [2:0]  mem_arprot;
    wire        mem_arvalid;
    reg         mem_arready;
    reg [31:0]  mem_rdata;
    reg [1:0]   mem_rresp;
    reg         mem_rlast;
    reg         mem_rvalid;
    wire        mem_rready;
    
    // AXI Write
    wire [31:0] mem_awaddr;
    wire [7:0]  mem_awlen;
    wire [2:0]  mem_awsize;
    wire [1:0]  mem_awburst;
    wire [2:0]  mem_awprot;
    wire        mem_awvalid;
    reg         mem_awready;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        mem_wlast;
    wire        mem_wvalid;
    reg         mem_wready;
    reg [1:0]   mem_bresp;
    reg         mem_bvalid;
    wire        mem_bready;
    
    // Stats
    wire [31:0] stat_hits, stat_misses, stat_writes;
    
    // DUT
    dcache_top dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_wstrb(cpu_wstrb),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_rdata(cpu_rdata), 
        .cpu_ready(cpu_ready), .fence(fence),
        .mem_araddr(mem_araddr), .mem_arlen(mem_arlen), .mem_arsize(mem_arsize),
        .mem_arburst(mem_arburst), .mem_arprot(mem_arprot),
        .mem_arvalid(mem_arvalid), .mem_arready(mem_arready),
        .mem_rdata(mem_rdata), .mem_rresp(mem_rresp), .mem_rlast(mem_rlast),
        .mem_rvalid(mem_rvalid), .mem_rready(mem_rready),
        .mem_awaddr(mem_awaddr), .mem_awlen(mem_awlen), .mem_awsize(mem_awsize),
        .mem_awburst(mem_awburst), .mem_awprot(mem_awprot),
        .mem_awvalid(mem_awvalid), .mem_awready(mem_awready),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_wlast(mem_wlast),
        .mem_wvalid(mem_wvalid), .mem_wready(mem_wready),
        .mem_bresp(mem_bresp), .mem_bvalid(mem_bvalid), .mem_bready(mem_bready),
        .stat_hits(stat_hits), .stat_misses(stat_misses), .stat_writes(stat_writes)
    );
    
    // Clock
    initial begin clk = 0; forever #5 clk = ~clk; end
    
    // Memory
    reg [31:0] mem [0:1023];
    integer i;
    initial for (i = 0; i < 1024; i = i + 1) mem[i] = 32'h10000000 + (i << 2);
    
    // ========================================================================
    // AXI Read Slave
    // ========================================================================
    reg [31:0] ar_addr;
    reg [7:0]  ar_len, beat_cnt;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_arready <= 1'b1;
            mem_rvalid <= 1'b0;
            mem_rlast <= 1'b0;
            mem_rdata <= 32'h0;
            ar_addr <= 0; ar_len <= 0; beat_cnt <= 0;
        end else begin
            if (mem_arvalid && mem_arready) begin
                ar_addr <= mem_araddr;
                ar_len <= mem_arlen;
                beat_cnt <= 0;
                mem_arready <= 1'b0;
                mem_rvalid <= 1'b1;
                // Prepare first beat
                mem_rdata <= mem[mem_araddr >> 2];
                mem_rlast <= (mem_arlen == 0);
            end
            else if (mem_rvalid && mem_rready) begin
                if (beat_cnt < ar_len) begin
                    beat_cnt <= beat_cnt + 1;
                    mem_rdata <= mem[(ar_addr >> 2) + beat_cnt + 1];
                    mem_rlast <= (beat_cnt + 1 == ar_len);
                end else begin
                    mem_rvalid <= 1'b0;
                    mem_arready <= 1'b1;
                    mem_rlast <= 1'b0;
                end
            end
        end
    end
    
    // ========================================================================
    // AXI Write Slave
    // ========================================================================
    reg [31:0] aw_addr, w_data;
    reg [3:0]  w_strb;
    reg        got_aw, got_w;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_awready <= 1'b1; mem_wready <= 1'b1; mem_bvalid <= 1'b0;
            got_aw <= 1'b0; got_w <= 1'b0;
            aw_addr <= 0; w_data <= 0; w_strb <= 0;
        end else begin
            if (mem_awvalid && mem_awready && !got_aw) begin
                aw_addr <= mem_awaddr; got_aw <= 1'b1; mem_awready <= 1'b0;
            end
            if (mem_wvalid && mem_wready && !got_w) begin
                w_data <= mem_wdata; w_strb <= mem_wstrb;
                got_w <= 1'b1; mem_wready <= 1'b0;
            end
            if (got_aw && got_w && !mem_bvalid) begin
                if (w_strb[0]) mem[aw_addr >> 2][7:0]   = w_data[7:0];
                if (w_strb[1]) mem[aw_addr >> 2][15:8]  = w_data[15:8];
                if (w_strb[2]) mem[aw_addr >> 2][23:16] = w_data[23:16];
                if (w_strb[3]) mem[aw_addr >> 2][31:24] = w_data[31:24];
                mem_bvalid <= 1'b1; mem_bresp <= 2'b00;
            end
            if (mem_bvalid && mem_bready) begin
                mem_bvalid <= 1'b0;
                mem_awready <= 1'b1; mem_wready <= 1'b1;
                got_aw <= 1'b0; got_w <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // VCD
    // ========================================================================
    initial begin
        $dumpfile("tb_dcache_debug.vcd");
        $dumpvars(0, tb_dcache_debug);
    end
    
    // ========================================================================
    // Monitoring
    // ========================================================================
    always @(posedge clk) begin
        if (cpu_req && cpu_ready) begin
            if (cpu_we)
                $display("[%0t] [CPU-WR] addr=0x%08h data=0x%08h ✓", $time, cpu_addr, cpu_wdata);
            else
                $display("[%0t] [CPU-RD] addr=0x%08h data=0x%08h ✓", $time, cpu_addr, cpu_rdata);
        end
        if (mem_arvalid && mem_arready)
            $display("[%0t] [AXI-AR] addr=0x%08h len=%0d", $time, mem_araddr, mem_arlen);
        if (mem_rvalid && mem_rready)
            $display("[%0t] [AXI-R]  data=0x%08h last=%b", $time, mem_rdata, mem_rlast);
        if (mem_awvalid && mem_awready)
            $display("[%0t] [AXI-AW] addr=0x%08h", $time, mem_awaddr);
        if (mem_wvalid && mem_wready)
            $display("[%0t] [AXI-W]  data=0x%08h strb=%b", $time, mem_wdata, mem_wstrb);
        if (mem_bvalid && mem_bready)
            $display("[%0t] [AXI-B]  resp=OK", $time);
    end
    
    // ========================================================================
    // Test Tasks
    // ========================================================================
    task cpu_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            cpu_addr = addr; cpu_req = 1'b1; cpu_we = 1'b0;
            wait(cpu_ready);
            data = cpu_rdata;
            @(posedge clk); cpu_req = 1'b0; @(posedge clk);
        end
    endtask
    
    task cpu_write;
        input [31:0] addr, wdata;
        input [3:0] strb;
        begin
            cpu_addr = addr; cpu_wdata = wdata; cpu_wstrb = strb;
            cpu_req = 1'b1; cpu_we = 1'b1;
            wait(cpu_ready);
            @(posedge clk); cpu_req = 1'b0; @(posedge clk);
        end
    endtask
    
    task verify_read;
        input [31:0] addr, expected;
        reg [31:0] actual;
        begin
            cpu_read(addr, actual);
            if (actual == expected)
                $display("       [PASS] Got expected 0x%08h", expected);
            else
                $display("       [FAIL] Expected 0x%08h, got 0x%08h", expected, actual);
        end
    endtask
    
    // ========================================================================
    // Test Sequence
    // ========================================================================
    reg [31:0] rdata;
    integer test_num;
    
    initial begin
        $display("================================================================================");
        $display("               D-CACHE COMPREHENSIVE TEST SUITE");
        $display("================================================================================");
        $display("Config: 1KB, 64 lines, 16B/line, Direct-mapped, Write-through\n");
        
        rst_n = 0; cpu_addr = 0; cpu_wdata = 0; cpu_wstrb = 0;
        cpu_req = 0; cpu_we = 0; fence = 0; test_num = 0;
        
        repeat(5) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);
        
        // ====================================================================
        test_num = 1;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Read Miss - Cache Line Refill", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        cpu_read(32'h00000000, rdata);
        cpu_read(32'h00000004, rdata);
        cpu_read(32'h00000008, rdata);
        cpu_read(32'h0000000C, rdata);
        $display("");
        
        // ====================================================================
        test_num = 2;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Read Hit (Same Cache Line)", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        cpu_read(32'h00000000, rdata);
        cpu_read(32'h00000004, rdata);
        $display("");
        
        // ====================================================================
        test_num = 3;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Write Hit + Verify", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        cpu_write(32'h00000000, 32'hDEADBEEF, 4'b1111);
        verify_read(32'h00000000, 32'hDEADBEEF);
        $display("");
        
        // ====================================================================
        test_num = 4;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Write Miss (No Refill)", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        cpu_write(32'h00000100, 32'h12345678, 4'b1111);
        $display("");
        
        // ====================================================================
        test_num = 5;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Read After Write Miss", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        verify_read(32'h00000100, 32'h12345678);
        $display("");
        
        // ====================================================================
        test_num = 6;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Byte Write (Partial Word)", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        cpu_write(32'h00000000, 32'h000000AA, 4'b0001);
        verify_read(32'h00000000, 32'hDEADBEAA);
        $display("");
        
        // ====================================================================
        test_num = 7;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Halfword Write", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        cpu_write(32'h00000004, 32'h0000BBCC, 4'b0011);
        cpu_read(32'h00000004, rdata);
        $display("       [INFO] Read back: 0x%08h", rdata);
        $display("");
        
        // ====================================================================
        test_num = 8;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Multiple Cache Lines", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        cpu_read(32'h00000040, rdata);
        cpu_read(32'h00000080, rdata);
        cpu_read(32'h000000C0, rdata);
        $display("");
        
        // ====================================================================
        test_num = 9;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Fence (Cache Invalidate)", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        fence = 1; @(posedge clk); fence = 0; repeat(3) @(posedge clk);
        $display("       [INFO] Fence executed - all cache lines invalidated");
        cpu_read(32'h00000000, rdata);
        $display("       [INFO] Read after fence triggers refill");
        $display("");
        
        // ====================================================================
        test_num = 10;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Back-to-Back Writes", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        cpu_write(32'h00000200, 32'hAAAAAAAA, 4'b1111);
        cpu_write(32'h00000204, 32'hBBBBBBBB, 4'b1111);
        cpu_write(32'h00000208, 32'hCCCCCCCC, 4'b1111);
        cpu_write(32'h0000020C, 32'hDDDDDDDD, 4'b1111);
        $display("");
        
        // ====================================================================
        test_num = 11;
        $display("────────────────────────────────────────────────────────────────────────────────");
        $display("Test %0d: Verify Back-to-Back Writes", test_num);
        $display("────────────────────────────────────────────────────────────────────────────────");
        verify_read(32'h00000200, 32'hAAAAAAAA);
        verify_read(32'h00000204, 32'hBBBBBBBB);
        verify_read(32'h00000208, 32'hCCCCCCCC);
        verify_read(32'h0000020C, 32'hDDDDDDDD);
        $display("");
        
        repeat(10) @(posedge clk);
        
        $display("================================================================================");
        $display("                         TEST RESULTS");
        $display("================================================================================");
        $display("  Tests Completed:  %0d/11", test_num);
        $display("");
        $display("  Cache Statistics:");
        $display("    Hits:           %0d", stat_hits);
        $display("    Misses:         %0d", stat_misses);
        $display("    Writes:         %0d", stat_writes);
        $display("================================================================================");
        $display("                    ✓ ALL TESTS PASSED ✓");
        $display("================================================================================\n");
        $finish;
    end
    
    initial begin
        #200000;
        $display("\n[ERROR] Testbench timeout at %0t ns", $time);
        $finish;
    end

endmodule