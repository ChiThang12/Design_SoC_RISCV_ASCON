`timescale 1ns/1ps

// ============================================================================
// Testbench: tb_riscv_soc_cached
// ============================================================================
// Mô tả:
//   Testbench cho RISC-V SoC với instruction và data cache
//   - Tự động load program.hex vào instruction memory
//   - Monitor các tín hiệu CPU và cache
//   - Hiển thị thống kê cache performance
//
// Author: ChiThang
// ============================================================================

`timescale 1ns/1ps
`include "cpu_core.v"
// // Define testbench mode để inst_mem load program.hex
`define TESTBENCH_MODE

module tb_riscv_soc_cached;

    // ========================================================================
    // Clock và Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // ========================================================================
    // Tín hiệu Debug từ SoC
    // ========================================================================
    wire [31:0] icache_hits;
    wire [31:0] icache_misses;
    wire [31:0] dcache_hits;
    wire [31:0] dcache_misses;
    wire [31:0] dcache_writes;
    
    // ========================================================================
    // Khởi tạo Clock: 50MHz (20ns period)
    // ========================================================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk;  // Toggle mỗi 10ns -> chu kỳ 20ns
    end
    
    // ========================================================================
    // Reset Sequence
    // ========================================================================
    initial begin
        rst_n = 0;
        #100;                     // Giữ reset trong 100ns
        rst_n = 1;
        $display("[TB] Reset released at time %0t", $time);
    end
    
    // ========================================================================
    // DUT: RISC-V SoC Instance
    // ========================================================================
    riscv_soc_top_cached dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // Debug outputs
        .icache_hits(icache_hits),
        .icache_misses(icache_misses),
        .dcache_hits(dcache_hits),
        .dcache_misses(dcache_misses),
        .dcache_writes(dcache_writes)
    );
    
    // ========================================================================
    // Load Program vào Instruction Memory
    // ========================================================================
    initial begin
        // Đợi một chút để memory được khởi tạo
        #1;
        
        // Load program từ file hex
        $readmemh("memory_axi4full/program.hex", dut.imem.imem.memory);
        $display("[TB] Loaded program.hex into instruction memory");
        
        // Hiển thị một vài lệnh đầu tiên
        $display("[TB] First 8 instructions:");
        $display("  [0x00000000] = 0x%08h", dut.imem.imem.memory[0]);
        $display("  [0x00000004] = 0x%08h", dut.imem.imem.memory[1]);
        $display("  [0x00000008] = 0x%08h", dut.imem.imem.memory[2]);
        $display("  [0x0000000C] = 0x%08h", dut.imem.imem.memory[3]);
        $display("  [0x00000010] = 0x%08h", dut.imem.imem.memory[4]);
        $display("  [0x00000014] = 0x%08h", dut.imem.imem.memory[5]);
        $display("  [0x00000018] = 0x%08h", dut.imem.imem.memory[6]);
        $display("  [0x0000001C] = 0x%08h", dut.imem.imem.memory[7]);
    end
    
    // ========================================================================
    // Monitor CPU Signals
    // ========================================================================
    integer cycle_count;
    
    initial begin
        cycle_count = 0;
    end
    
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            
            // Hiển thị PC và instruction mỗi chu kỳ
            if (dut.cpu.imem_valid && dut.cpu.imem_ready) begin
                $display("[Cycle %0d] PC=0x%08h, Inst=0x%08h", 
                         cycle_count, 
                         dut.cpu.imem_addr, 
                         dut.cpu.imem_rdata);
            end
            
            // Hiển thị data memory access
            if (dut.cpu.dmem_valid && dut.cpu.dmem_ready) begin
                if (dut.cpu.dmem_we) begin
                    $display("[Cycle %0d] WRITE: Addr=0x%08h, Data=0x%08h, Strb=0x%01h",
                             cycle_count,
                             dut.cpu.dmem_addr,
                             dut.cpu.dmem_wdata,
                             dut.cpu.dmem_wstrb);
                end else begin
                    $display("[Cycle %0d] READ:  Addr=0x%08h, Data=0x%08h",
                             cycle_count,
                             dut.cpu.dmem_addr,
                             dut.cpu.dmem_rdata);
                end
            end
        end
    end
    
    // ========================================================================
    // Monitor Cache Performance
    // ========================================================================
    real icache_hit_rate;
    real dcache_hit_rate;
    integer icache_total;
    integer dcache_total;
    
    initial begin
        // Đợi simulation kết thúc
        #100000;  // 100us
        
        // Tính toán hit rate
        icache_total = icache_hits + icache_misses;
        dcache_total = dcache_hits + dcache_misses;
        
        if (icache_total > 0)
            icache_hit_rate = (icache_hits * 100.0) / icache_total;
        else
            icache_hit_rate = 0.0;
            
        if (dcache_total > 0)
            dcache_hit_rate = (dcache_hits * 100.0) / dcache_total;
        else
            dcache_hit_rate = 0.0;
        
        // Hiển thị thống kê
        $display("\n");
        $display("========================================================================");
        $display("                    CACHE PERFORMANCE STATISTICS");
        $display("========================================================================");
        $display("Instruction Cache:");
        $display("  Hits:       %0d", icache_hits);
        $display("  Misses:     %0d", icache_misses);
        $display("  Total:      %0d", icache_total);
        $display("  Hit Rate:   %0.2f%%", icache_hit_rate);
        $display("");
        $display("Data Cache:");
        $display("  Hits:       %0d", dcache_hits);
        $display("  Misses:     %0d", dcache_misses);
        $display("  Writes:     %0d", dcache_writes);
        $display("  Total:      %0d", dcache_total);
        $display("  Hit Rate:   %0.2f%%", dcache_hit_rate);
        $display("========================================================================");
        $display("Total Cycles: %0d", cycle_count);
        $display("========================================================================");
        
        $finish;
    end
    
    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_riscv_soc.vcd");
        $dumpvars(0, tb_riscv_soc_cached);
    end
    
    // ========================================================================
    // Monitor cho Register File (nếu muốn debug chi tiết)
    // ========================================================================
    `ifdef DEBUG_REGISTERS
    always @(posedge clk) begin
        if (rst_n && dut.cpu.reg_file.we) begin
            $display("[RegWrite] x%0d = 0x%08h", 
                     dut.cpu.reg_file.rd_addr,
                     dut.cpu.reg_file.rd_data);
        end
    end
    `endif
    
    // ========================================================================
    // Timeout Protection
    // ========================================================================
    initial begin
        #1000000;  // 1ms timeout
        $display("\n[TB ERROR] Simulation timeout!");
        $finish;
    end

endmodule