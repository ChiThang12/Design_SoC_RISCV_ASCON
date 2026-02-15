`timescale 1ns/1ps
`include "cpu/cpu_core.v"

// ============================================================================
// Testbench: run_soc
// ============================================================================
// Description:
//   Testbench cho RISC-V SoC với ICache, DCache và AXI4 bus
//   Tự động chạy program và hiển thị kết quả
// ============================================================================

module run_soc;

// ============================================================================
// Parameters
// ============================================================================
parameter CLK_PERIOD = 10;      // 100 MHz
parameter TIMEOUT_MAX = 5000;   // Max cycles before timeout

// ============================================================================
// Signals
// ============================================================================
reg clk;
reg rst_n;

wire [31:0] icache_hits;
wire [31:0] icache_misses;
wire [31:0] dcache_hits;
wire [31:0] dcache_misses;
wire [31:0] dcache_writes;

// Performance counters
integer cycle_count;
integer instr_count;
reg program_finished;

// Program detection
reg [31:0] prev_pc;
reg [31:0] prev_instr;
integer stable_cycles;
integer loop_detect_threshold;

// PC history for loop detection
reg [31:0] pc_history [0:15];
integer pc_idx;
integer cycle_counter;
integer match_count_2;
integer match_count_3;
integer match_count_4;

// Debug mode
integer debug_mode;

// ============================================================================
// DUT - Device Under Test
// ============================================================================
riscv_soc_top_cached soc (
    .clk(clk),
    .rst_n(rst_n),
    .icache_hits(icache_hits),
    .icache_misses(icache_misses),
    .dcache_hits(dcache_hits),
    .dcache_misses(dcache_misses),
    .dcache_writes(dcache_writes)
);

// ============================================================================
// Clock Generation
// ============================================================================
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// Waveform Dump
// ============================================================================
initial begin
    $dumpfile("waveform_soc.vcd");
    $dumpvars(0, run_soc);
end

// ============================================================================
// Watchdog Timer
// ============================================================================
initial begin
    #(CLK_PERIOD * TIMEOUT_MAX);
    if (!program_finished) begin
        $display("\n⚠ WARNING: Program timeout after %0d cycles", cycle_count);
        print_results();
    end
    $finish;
end

// ============================================================================
// Access CPU internal signals for monitoring
// ============================================================================
wire [31:0] pc_current = soc.cpu.pc_if;
wire [31:0] instruction_current = soc.cpu.instr_if;
wire stall = soc.cpu.stall_if;

// ============================================================================
// Cycle and Instruction Counting
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        cycle_count = cycle_count + 1;
        
        // Count valid instructions (not NOPs and not stalled)
        if (instruction_current != 32'h00000013 && !stall) begin
            instr_count = instr_count + 1;
        end
    end
end

// ============================================================================
// Program End Detection
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        // Debug output (first 100 cycles)
        if (debug_mode && cycle_count < 100) begin
            $display("[%0d] PC=0x%h, Instr=0x%h, valid=%b, ready=%b", 
                     cycle_count, pc_current, instruction_current,
                     soc.cpu_imem_valid, soc.cpu_imem_ready);
        end
        
        // SKIP detection trong 20 cycles đầu (boot phase)
        if (cycle_count < 20) begin
            stable_cycles = 0;
            match_count_2 = 0;
            match_count_3 = 0;
            match_count_4 = 0;
        end else begin
            // Method 1: Detect single-instruction infinite loop
            if ((pc_current == prev_pc) && (instruction_current == prev_instr) &&
                (instruction_current != 32'h00000013)) begin  // Ignore NOP
                stable_cycles = stable_cycles + 1;
                
                if (stable_cycles >= loop_detect_threshold && !program_finished) begin
                    program_finished = 1;
                    $display("\n✓ Single-instruction loop detected at PC=0x%08h", pc_current);
                    print_results();
                    $finish;
                end
            end else begin
                stable_cycles = 0;
            end
            
            // Method 2: Detect 2-instruction cycle
            if (cycle_counter >= 2) begin
                if (pc_current == pc_history[(pc_idx + 14) % 16]) begin
                    match_count_2 = match_count_2 + 1;
                    
                    if (match_count_2 >= 10 && !program_finished) begin  // Tăng từ 4 lên 10
                        program_finished = 1;
                        $display("\n✓ 2-instruction loop detected");
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_2 = 0;
                end
            end
            
            // Method 3: Detect 3-instruction cycle
            if (cycle_counter >= 3) begin
                if (pc_current == pc_history[(pc_idx + 13) % 16]) begin
                    match_count_3 = match_count_3 + 1;
                    
                    if (match_count_3 >= 15 && !program_finished) begin  // Tăng từ 6 lên 15
                        program_finished = 1;
                        $display("\n✓ 3-instruction loop detected");
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_3 = 0;
                end
            end
            
            // Method 4: Detect 4-instruction cycle
            if (cycle_counter >= 4) begin
                if (pc_current == pc_history[(pc_idx + 12) % 16]) begin
                    match_count_4 = match_count_4 + 1;
                    
                    if (match_count_4 >= 20 && !program_finished) begin  // Tăng từ 8 lên 20
                        program_finished = 1;
                        $display("\n✓ 4-instruction loop detected");
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_4 = 0;
                end
            end
        end
        
        // Update PC history
        pc_history[pc_idx] = pc_current;
        pc_idx = (pc_idx + 1) % 16;
        cycle_counter = cycle_counter + 1;
        
        prev_pc = pc_current;
        prev_instr = instruction_current;
    end
end

// ============================================================================
// Main Test Sequence
// ============================================================================
initial begin
    // Initialize counters
    cycle_count = 0;
    instr_count = 0;
    stable_cycles = 0;
    program_finished = 0;
    prev_pc = 0;
    prev_instr = 0;
    pc_idx = 0;
    cycle_counter = 0;
    match_count_2 = 0;
    match_count_3 = 0;
    match_count_4 = 0;
    debug_mode = 0;  // Set to 1 to enable debug output
    loop_detect_threshold = 10;  // Tăng từ 3 lên 10
    
    // Print header
    $display("\n╔═══════════════════════════════════════════╗");
    $display("║   RISC-V SoC with Cache Test             ║");
    $display("║   ICache: 4KB | DCache: 8KB              ║");
    $display("╚═══════════════════════════════════════════╝\n");
    
    // Reset sequence - LONGER reset for cache initialization
    rst_n = 0;
    #(CLK_PERIOD * 10);  // Tăng từ 2 lên 10 cycles
    rst_n = 1;
    #(CLK_PERIOD * 5);   // Thêm delay sau reset
    
    $display("▶ Starting execution...\n");
    #(CLK_PERIOD * 10000); // Let the program run for a while (adjust as needed)
    // Wait for program to finish (watchdog will timeout if needed)
    wait(program_finished);
end

// ============================================================================
// Task: Print Comprehensive Results
// ============================================================================
task print_results;
    integer i;
    integer non_zero_regs;
    reg [31:0] return_value;
    real cpi;
    real icache_hit_rate;
    real dcache_hit_rate;
    integer total_icache_access;
    integer total_dcache_access;
    begin
        // Get return value from register x10 (a0)
        return_value = soc.cpu.register_file.registers[10];
        
        $display("\n╔═══════════════════════════════════════════╗");
        $display("║      Execution Results                    ║");
        $display("╚═══════════════════════════════════════════╝\n");
        
        // ================================================================
        // PROGRAM OUTPUT
        // ================================================================
        $display("┌─── PROGRAM OUTPUT ──────────────────────────────────────┐");
        $display("│ Return Value (x10/a0):                                  │");
        $display("│   Decimal: %-26d                        │", return_value);
        $display("│   Hex:     0x%-24h                      │", return_value);
        $display("│   Binary:  %032b │", return_value);
        $display("└─────────────────────────────────────────────────────────┘\n");
        
        // ================================================================
        // PERFORMANCE METRICS
        // ================================================================
        if (instr_count > 0) begin
            cpi = cycle_count * 1.0 / instr_count;
        end else begin
            cpi = 0.0;
        end
        
        $display("┌─── PERFORMANCE METRICS ──────────────┐");
        $display("│ Total Clock Cycles:  %-15d │", cycle_count);
        $display("│ Instructions Executed: %-13d │", instr_count);
        $display("│ CPI (Cycles/Instr):  %-15.2f │", cpi);
        $display("│ Final PC:            0x%-13h │", pc_current);
        $display("│ Final Instruction:   0x%-13h │", instruction_current);
        $display("└──────────────────────────────────────┘\n");
        
        // ================================================================
        // CACHE STATISTICS
        // ================================================================
        total_icache_access = icache_hits + icache_misses;
        total_dcache_access = dcache_hits + dcache_misses;
        
        if (total_icache_access > 0) begin
            icache_hit_rate = (icache_hits * 100.0) / total_icache_access;
        end else begin
            icache_hit_rate = 0.0;
        end
        
        if (total_dcache_access > 0) begin
            dcache_hit_rate = (dcache_hits * 100.0) / total_dcache_access;
        end else begin
            dcache_hit_rate = 0.0;
        end
        
        $display("┌─── CACHE STATISTICS ─────────────────────────────────────┐");
        $display("│ Instruction Cache (4KB):                                 │");
        $display("│   Hits:       %-10d  Hit Rate: %6.2f%%               │", 
                 icache_hits, icache_hit_rate);
        $display("│   Misses:     %-10d  Miss Rate: %6.2f%%              │", 
                 icache_misses, 100.0 - icache_hit_rate);
        $display("│   Total Accesses: %-10d                              │", 
                 total_icache_access);
        $display("│                                                          │");
        $display("│ Data Cache (8KB):                                        │");
        $display("│   Hits:       %-10d  Hit Rate: %6.2f%%               │", 
                 dcache_hits, dcache_hit_rate);
        $display("│   Misses:     %-10d  Miss Rate: %6.2f%%              │", 
                 dcache_misses, 100.0 - dcache_hit_rate);
        $display("│   Writes:     %-10d                                  │", 
                 dcache_writes);
        $display("│   Total Accesses: %-10d                              │", 
                 total_dcache_access);
        $display("└──────────────────────────────────────────────────────────┘\n");
        
        // Cache performance interpretation
        if (total_icache_access > 0) begin
            if (icache_hit_rate >= 95.0) begin
                $display("✓ ICache: Excellent performance");
            end else if (icache_hit_rate >= 80.0) begin
                $display("⚠ ICache: Good performance");
            end else begin
                $display("✗ ICache: Poor performance - consider optimization");
            end
        end
        
        if (total_dcache_access > 0) begin
            if (dcache_hit_rate >= 95.0) begin
                $display("✓ DCache: Excellent performance");
            end else if (dcache_hit_rate >= 80.0) begin
                $display("⚠ DCache: Good performance");
            end else begin
                $display("✗ DCache: Poor performance - consider optimization");
            end
        end
        $display("");
        
        // ================================================================
        // REGISTER FILE
        // ================================================================
        non_zero_regs = 0;
        for (i = 0; i < 32; i = i + 1) begin
            if (soc.cpu.register_file.registers[i] != 0) begin
                non_zero_regs = non_zero_regs + 1;
            end
        end
        
        $display("┌─── REGISTER FILE (%0d non-zero) ─────┐", non_zero_regs);
        $display("│ Reg  │   Decimal    │     Hex      │");
        $display("├──────┼──────────────┼──────────────┤");
        
        for (i = 0; i < 32; i = i + 1) begin
            if (soc.cpu.register_file.registers[i] != 0 || i == 0 || i == 10) begin
                $display("│ x%-3d │ %12d │ 0x%010h │", 
                         i, 
                         soc.cpu.register_file.registers[i],
                         soc.cpu.register_file.registers[i]);
            end
        end
        $display("└──────┴──────────────┴──────────────┘\n");
        
        // ================================================================
        // PIPELINE EFFICIENCY
        // ================================================================
        print_pipeline_stats();
        
        $display("═══════════════════════════════════════════\n");
    end
endtask

// ============================================================================
// Task: Pipeline Statistics
// ============================================================================
task print_pipeline_stats;
    real efficiency;
    begin
        $display("┌─── PIPELINE ANALYSIS ────────────────┐");
        
        if (cycle_count > 0) begin
            efficiency = (instr_count * 100.0) / cycle_count;
            $display("│ Pipeline Efficiency: %-15.1f%% │", efficiency);
        end
        
        if (instr_count > 0) begin
            $display("│ Target CPI:          1.00            │");
            $display("│ Overhead:            %-15.2f │", (cycle_count * 1.0 / instr_count) - 1.0);
        end
        
        $display("└──────────────────────────────────────┘\n");
        
        // Interpretation
        if (instr_count > 0) begin
            if (efficiency >= 95.0) begin
                $display("✓ Excellent: Pipeline running near-optimal");
            end else if (efficiency >= 80.0) begin
                $display("✓ Good: Some stalls/hazards present");
            end else if (efficiency >= 60.0) begin
                $display("⚠ Fair: Significant pipeline stalls");
            end else begin
                $display("✗ Poor: Major performance issues");
            end
        end
    end
endtask

endmodule