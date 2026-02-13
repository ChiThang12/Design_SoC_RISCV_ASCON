// ============================================================================
// Testbench: tb_dcache_top
// ============================================================================
// Description:
//   Complete integration test for data cache with AXI4 Full
//   Tests read hits/misses, write-through, and mixed operations
// ============================================================================
`timescale 1ns/1ps
`include "cpu/interface/dcache/tb/dcache_defines.vh"
`include "cpu/interface/dcache/tb/dcache_top.v"

module tb_dcache_top;

    // Clock and Reset
    reg clk;
    reg rst_n;
    
    // CPU Interface
    reg [31:0] cpu_addr;
    reg [31:0] cpu_wdata;
    reg [3:0]  cpu_wstrb;
    reg        cpu_req;
    reg        cpu_we;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;
    reg        fence;
    
    // AXI4 Read Channel
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
    
    // AXI4 Write Channel
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
    
    // Statistics
    wire [31:0] stat_hits;
    wire [31:0] stat_misses;
    wire [31:0] stat_writes;
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    dcache_top dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_wstrb(cpu_wstrb),
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .fence(fence),
        
        .mem_araddr(mem_araddr),
        .mem_arlen(mem_arlen),
        .mem_arsize(mem_arsize),
        .mem_arburst(mem_arburst),
        .mem_arprot(mem_arprot),
        .mem_arvalid(mem_arvalid),
        .mem_arready(mem_arready),
        
        .mem_rdata(mem_rdata),
        .mem_rresp(mem_rresp),
        .mem_rlast(mem_rlast),
        .mem_rvalid(mem_rvalid),
        .mem_rready(mem_rready),
        
        .mem_awaddr(mem_awaddr),
        .mem_awlen(mem_awlen),
        .mem_awsize(mem_awsize),
        .mem_awburst(mem_awburst),
        .mem_awprot(mem_awprot),
        .mem_awvalid(mem_awvalid),
        .mem_awready(mem_awready),
        
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_wlast(mem_wlast),
        .mem_wvalid(mem_wvalid),
        .mem_wready(mem_wready),
        
        .mem_bresp(mem_bresp),
        .mem_bvalid(mem_bvalid),
        .mem_bready(mem_bready),
        
        .stat_hits(stat_hits),
        .stat_misses(stat_misses),
        .stat_writes(stat_writes)
    );
    
    // ========================================================================
    // Clock Generation (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // Memory Model (1KB)
    // ========================================================================
    reg [31:0] main_memory [0:255];
    integer i;
    
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            main_memory[i] = 32'h1000_0000 + (i << 4);
        end
    end
    
    // ========================================================================
    // AXI4 Read Slave Model
    // ========================================================================
    reg [31:0] ar_addr_latched;
    reg [7:0]  ar_len_latched;
    reg [7:0]  rd_beat_counter;
    reg [1:0]  rd_state;
    
    localparam RD_IDLE = 2'b00;
    localparam RD_AR   = 2'b01;
    localparam RD_R    = 2'b10;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE;
            mem_arready <= 1'b0;
            mem_rdata <= 32'h0;
            mem_rresp <= 2'b00;
            mem_rlast <= 1'b0;
            mem_rvalid <= 1'b0;
            ar_addr_latched <= 32'h0;
            ar_len_latched <= 8'h0;
            rd_beat_counter <= 8'h0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    mem_arready <= 1'b1;
                    mem_rvalid <= 1'b0;
                    if (mem_arvalid && mem_arready) begin
                        ar_addr_latched <= mem_araddr;
                        ar_len_latched <= mem_arlen;
                        rd_beat_counter <= 8'h0;
                        mem_arready <= 1'b0;
                        rd_state <= RD_R;
                    end
                end
                
                RD_R: begin
                    if (!mem_rvalid || mem_rready) begin
                        mem_rdata <= main_memory[(ar_addr_latched >> 2) + rd_beat_counter];
                        mem_rresp <= 2'b00;
                        mem_rlast <= (rd_beat_counter == ar_len_latched);
                        mem_rvalid <= 1'b1;
                        
                        if (mem_rready && mem_rvalid) begin
                            if (mem_rlast) begin
                                rd_state <= RD_IDLE;
                            end else begin
                                rd_beat_counter <= rd_beat_counter + 1;
                            end
                        end
                    end
                end
            endcase
        end
    end
    
    initial begin
        $dumpfile("tb_dcache_top.vcd");
        $dumpvars(0, tb_dcache_top);
    end

    // ========================================================================
    // AXI4 Write Slave Model
    // ========================================================================
    reg [31:0] aw_addr_latched;
    reg [1:0]  wr_state;
    
    localparam WR_IDLE = 2'b00;
    localparam WR_AW   = 2'b01;
    localparam WR_W    = 2'b10;
    localparam WR_B    = 2'b11;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WR_IDLE;
            mem_awready <= 1'b0;
            mem_wready <= 1'b0;
            mem_bresp <= 2'b00;
            mem_bvalid <= 1'b0;
            aw_addr_latched <= 32'h0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    mem_awready <= 1'b1;
                    mem_wready <= 1'b1;
                    mem_bvalid <= 1'b0;
                    
                    if (mem_awvalid && mem_awready) begin
                        aw_addr_latched <= mem_awaddr;
                    end
                    
                    if (mem_wvalid && mem_wready) begin
                        // Write to memory with byte enable
                        if (mem_wstrb[0]) main_memory[aw_addr_latched >> 2][7:0]   = mem_wdata[7:0];
                        if (mem_wstrb[1]) main_memory[aw_addr_latched >> 2][15:8]  = mem_wdata[15:8];
                        if (mem_wstrb[2]) main_memory[aw_addr_latched >> 2][23:16] = mem_wdata[23:16];
                        if (mem_wstrb[3]) main_memory[aw_addr_latched >> 2][31:24] = mem_wdata[31:24];
                        
                        $display("[MEM WRITE] addr=0x%h data=0x%h strb=%b @ %0t", 
                                 aw_addr_latched, mem_wdata, mem_wstrb, $time);
                        
                        mem_awready <= 1'b0;
                        mem_wready <= 1'b0;
                        wr_state <= WR_B;
                    end
                end
                
                WR_B: begin
                    mem_bresp <= 2'b00;
                    mem_bvalid <= 1'b1;
                    if (mem_bready) begin
                        wr_state <= WR_IDLE;
                    end
                end
            endcase
        end
    end
    
    // ========================================================================
    // Test Tasks
    // ========================================================================
    task cpu_read;
        input [31:0] addr;
        begin
            cpu_addr = addr;
            cpu_req = 1'b1;
            cpu_we = 1'b0;
            wait(cpu_ready);
            $display("[CPU READ] addr=0x%h data=0x%h @ %0t", addr, cpu_rdata, $time);
            @(posedge clk);
            cpu_req = 1'b0;
            @(posedge clk);
        end
    endtask
    
    task cpu_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            cpu_addr = addr;
            cpu_wdata = data;
            cpu_wstrb = strb;
            cpu_req = 1'b1;
            cpu_we = 1'b1;
            wait(cpu_ready);
            $display("[CPU WRITE] addr=0x%h data=0x%h strb=%b @ %0t", addr, data, strb, $time);
            @(posedge clk);
            cpu_req = 1'b0;
            @(posedge clk);
        end
    endtask
    
    // ========================================================================
    // Test Sequence
    // ========================================================================
    initial begin
        $display("========================================");
        $display("DCache Top-Level Testbench");
        $display("========================================");
        
        // Initialize
        rst_n = 0;
        cpu_addr = 0;
        cpu_wdata = 0;
        cpu_wstrb = 0;
        cpu_req = 0;
        cpu_we = 0;
        fence = 0;
        
        // Reset
        #20;
        rst_n = 1;
        #20;
        
        // Test 1: Read Miss (cache line fill)
        $display("\n=== Test 1: Read Miss ===");
        cpu_read(32'h0000);  // Should trigger refill
        
        // Test 2: Read Hit (same cache line)
        $display("\n=== Test 2: Read Hit ===");
        cpu_read(32'h0004);  // Hit in same line
        cpu_read(32'h0008);  // Hit
        cpu_read(32'h000C);  // Hit
        
        // Test 3: Write Hit
        $display("\n=== Test 3: Write Hit ===");
        cpu_write(32'h0000, 32'hDEADBEEF, 4'b1111);
        
        // Read back to verify
        cpu_read(32'h0000);
        
        // Test 4: Write Miss (no refill)
        $display("\n=== Test 4: Write Miss ===");
        cpu_write(32'h0100, 32'h12345678, 4'b1111);
        
        // Test 5: Read after write miss
        $display("\n=== Test 5: Read after Write Miss ===");
        cpu_read(32'h0100);  // Should refill and see written value
        
        // Test 6: Byte write
        $display("\n=== Test 6: Byte Write ===");
        cpu_write(32'h0000, 32'h000000AA, 4'b0001);
        cpu_read(32'h0000);
        
        // Test 7: Halfword write
        $display("\n=== Test 7: Halfword Write ===");
        cpu_write(32'h0004, 32'h0000BBCC, 4'b0011);
        cpu_read(32'h0004);
        
        // Test 8: Multiple cache lines
        $display("\n=== Test 8: Multiple Cache Lines ===");
        cpu_read(32'h0040);  // Line 1
        cpu_read(32'h0080);  // Line 2
        cpu_read(32'h00C0);  // Line 3
        
        // Test 9: Fence (flush cache)
        $display("\n=== Test 9: Fence ===");
        fence = 1;
        @(posedge clk);
        fence = 0;
        @(posedge clk);
        
        // After fence, should miss
        cpu_read(32'h0000);
        
        // Test 10: Statistics
        $display("\n=== Test 10: Statistics ===");
        $display("Hits: %0d", stat_hits);
        $display("Misses: %0d", stat_misses);
        $display("Writes: %0d", stat_writes);
        
        #100;
        $display("\n========================================");
        $display("Test Complete");
        $display("========================================");
        $finish;
    end
    
    // Timeout
    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule