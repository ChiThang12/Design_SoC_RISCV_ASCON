// ============================================================================
// tb_lsu_demo.v - Simple Testbench for LSU Architecture
// ============================================================================
// Test cases:
//   1. Simple load (no dependency)
//   2. Load-use hazard
//   3. Multiple independent instructions during load
//   4. Back-to-back loads
// ============================================================================

`timescale 1ns/1ps
`include "cpu/riscv_cpu_core_v1.v"
module tb_lsu_demo;

    // Clock and reset
    reg clk;
    reg rst;
    
    // Memory interfaces
    wire [31:0] imem_addr;
    wire        imem_valid;
    reg  [31:0] imem_rdata;
    reg         imem_ready;
    
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_valid;
    wire        dmem_we;
    reg  [31:0] dmem_rdata;
    reg         dmem_ready;
    
    // DUT
    riscv_cpu_core cpu (
        .clk(clk),
        .rst(rst),
        .imem_addr(imem_addr),
        .imem_valid(imem_valid),
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_valid(dmem_valid),
        .dmem_we(dmem_we),
        .dmem_rdata(dmem_rdata),
        .dmem_ready(dmem_ready)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // Instruction Memory Simulation
    // ========================================================================
    reg [31:0] imem [0:255];
    integer i;
    initial begin
        // Test program: Load + independent instructions
        
        // 0x00: lw x1, 0(x2)       # Load from address in x2 (MISS - 10 cycles)
        imem[0] = 32'h00012083;
        
        // 0x04: addi x3, x4, 5     # Independent - should NOT stall
        imem[1] = 32'h00520193;
        
        // 0x08: addi x5, x6, 10    # Independent - should NOT stall
        imem[2] = 32'h00a30293;
        
        // 0x0C: addi x7, x8, 15    # Independent - should NOT stall
        imem[3] = 32'h00f40393;
        
        // 0x10: add x9, x1, x10    # DEPENDENT on x1 - MUST stall until load complete
        imem[4] = 32'h00a084b3;
        
        // 0x14: lw x11, 4(x2)      # Another load
        imem[5] = 32'h00412583;
        
        // 0x18: nop
        imem[6] = 32'h00000013;
        
        // Rest: NOPs
        for (i = 7; i < 256; i = i + 1) begin
            imem[i] = 32'h00000013;
        end
    end
    
    // Instruction memory behavior
    always @(*) begin
        imem_ready = 1'b1;  // Always ready (no I-cache miss)
        imem_rdata = imem[imem_addr[9:2]];
    end
    
    // ========================================================================
    // Data Memory Simulation (với latency)
    // ========================================================================
    reg [31:0] dmem_array [0:255];
    reg [7:0] dmem_latency_counter;
    parameter DMEM_LATENCY = 10;  // 10 cycles latency
    integer j;
    initial begin
        // Initialize data memory
        for (j = 0; j < 256; j = j + 1) begin
            dmem_array[j] = 32'h0000_0000;
        end
        
        // Load test data
        dmem_array[0] = 32'hDEAD_BEEF;  // Address 0x00
        dmem_array[1] = 32'hCAFE_BABE;  // Address 0x04
        
        dmem_latency_counter = 0;
        dmem_ready = 1'b0;
    end
    
    // Data memory behavior with latency
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dmem_ready <= 1'b0;
            dmem_latency_counter <= 0;
        end else begin
            if (dmem_valid && !dmem_ready) begin
                // Start counting latency
                if (dmem_latency_counter < DMEM_LATENCY - 1) begin
                    dmem_latency_counter <= dmem_latency_counter + 1;
                    dmem_ready <= 1'b0;
                end else begin
                    // Latency complete
                    dmem_ready <= 1'b1;
                    dmem_latency_counter <= 0;
                    
                    // Return data for load
                    if (!dmem_we) begin
                        dmem_rdata <= dmem_array[dmem_addr[9:2]];
                    end else begin
                        // Store
                        dmem_array[dmem_addr[9:2]] <= dmem_wdata;
                    end
                end
            end else begin
                dmem_ready <= 1'b0;
                dmem_latency_counter <= 0;
            end
        end
    end
    
    // ========================================================================
    // Monitors
    // ========================================================================
    integer cycle_count;
    
    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;
            
            // Monitor LSU activity
            if (cpu.load_store_unit.req_valid && cpu.load_store_unit.req_ready) begin
                $display("[Cycle %0d] LSU Request: addr=0x%h, is_load=%b, rd=x%0d",
                    cycle_count, cpu.load_store_unit.req_addr, 
                    cpu.load_store_unit.req_is_load, cpu.load_store_unit.req_rd);
            end
            
            if (cpu.load_store_unit.result_valid) begin
                $display("[Cycle %0d] LSU Result: rd=x%0d, data=0x%h",
                    cycle_count, cpu.load_store_unit.result_rd, 
                    cpu.load_store_unit.result_data);
            end
            
            // Monitor scoreboard
            if (cpu.lsu_scoreboard != 0) begin
                $display("[Cycle %0d] Scoreboard: %b (pending loads)", 
                    cycle_count, cpu.lsu_scoreboard);
            end
            
            // Monitor stall
            if (cpu.stall) begin
                $display("[Cycle %0d] STALL: PC=0x%h", 
                    cycle_count, cpu.pc_if);
            end
            
            // Monitor register writes
            if (cpu.regwrite_wb && cpu.rd_wb != 0) begin
                $display("[Cycle %0d] WB: x%0d <= 0x%h", 
                    cycle_count, cpu.rd_wb, cpu.write_back_data_wb);
            end
        end
    end
    
    // ========================================================================
    // Test Sequence
    // ========================================================================
    initial begin
        $dumpfile("tb_lsu_demo.vcd");
        $dumpvars(0, tb_lsu_demo);
        
        // Initialize
        rst = 1;
        cycle_count = 0;
        
        // Initialize register file (x2 = base address)
        #20;
        rst = 0;
        
        // Manually set x2 = 0x00 (base address)
        #10;
        force cpu.register_file.registers[2] = 32'h0000_0000;
        force cpu.register_file.registers[4] = 32'h0000_0001;  // x4 = 1
        force cpu.register_file.registers[6] = 32'h0000_0002;  // x6 = 2
        force cpu.register_file.registers[8] = 32'h0000_0003;  // x8 = 3
        force cpu.register_file.registers[10] = 32'h0000_0100; // x10 = 256
        #10;
        release cpu.register_file.registers[2];
        release cpu.register_file.registers[4];
        release cpu.register_file.registers[6];
        release cpu.register_file.registers[8];
        release cpu.register_file.registers[10];
        
        // Run simulation
        $display("\n========================================");
        $display("LSU Architecture Test");
        $display("========================================\n");
        $display("Expected behavior:");
        $display("1. lw x1 → LSU (10 cycles latency)");
        $display("2. addi x3, addi x5, addi x7 execute DURING load");
        $display("3. add x9 stalls until x1 ready");
        $display("4. lw x11 → LSU\n");
        
        // Wait for completion
        #500;
        
        $display("\n========================================");
        $display("Final Register State:");
        $display("========================================");
        $display("x1  = 0x%h (should be 0xDEADBEEF)", cpu.register_file.registers[1]);
        $display("x3  = 0x%h (should be 0x00000006)", cpu.register_file.registers[3]);
        $display("x5  = 0x%h (should be 0x0000000C)", cpu.register_file.registers[5]);
        $display("x7  = 0x%h (should be 0x00000012)", cpu.register_file.registers[7]);
        $display("x9  = 0x%h (should be 0xDEADBFEF)", cpu.register_file.registers[9]);
        $display("x11 = 0x%h (should be 0xCAFEBABE)", cpu.register_file.registers[11]);
        
        $display("\nTotal cycles: %0d", cycle_count);
        $display("========================================\n");
        
        $finish;
    end
    
    // Timeout
    initial begin
        #10000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule