`timescale 1ns/1ps
`include "riscv_soc_top.v"
module testbench;
    // Clock and Reset signals
    reg clk;
    reg rst_n;
    
    // Debug output wires from SoC
    wire [31:0] debug_pc;
    wire [31:0] debug_instr;
    wire [31:0] debug_alu_result;
    wire [31:0] debug_mem_data;
    wire        debug_branch_taken;
    wire [31:0] debug_branch_target;
    wire        debug_stall;
    wire [1:0]  debug_forward_a;
    wire [1:0]  debug_forward_b;
    
    // Test tracking variables
    integer cycle_count;
    integer instr_count;
    reg program_finished;
    
    // DUT instantiation
    riscv_soc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .debug_pc(debug_pc),
        .debug_instr(debug_instr),
        .debug_alu_result(debug_alu_result),
        .debug_mem_data(debug_mem_data),
        .debug_branch_taken(debug_branch_taken),
        .debug_branch_target(debug_branch_target),
        .debug_stall(debug_stall),
        .debug_forward_a(debug_forward_a),
        .debug_forward_b(debug_forward_b)
    );
    
    // Clock generation: 10ns period (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;
    
    // Cycle and instruction counting
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            // Count only valid instructions (not NOPs and not stalled)
            if (debug_instr != 32'h00000013 && !debug_stall) begin
                instr_count = instr_count + 1;
            end
        end
    end
    
    // Program end detection
    reg [31:0] prev_pc;
    reg [31:0] prev_instr;
    integer stable_cycles;
    integer loop_detect_threshold;
    
    // Track PC history for cycle detection
    reg [31:0] pc_history [0:15];
    integer pc_idx;
    integer cycle_counter;
    integer match_count_2;
    integer match_count_3;
    integer match_count_4;
    
    integer debug_mode;
    
    always @(posedge clk) begin
        if (rst_n) begin
            // Debug output (first 50 cycles)
            if (debug_mode && cycle_count < 50) begin
                $display("[%0d] PC=0x%h, Instr=0x%h", cycle_count, debug_pc, debug_instr);
            end
            
            // Method 1: Detect single-instruction infinite loop
            if ((debug_pc == prev_pc) && (debug_instr == prev_instr)) begin
                stable_cycles = stable_cycles + 1;
                
                if (stable_cycles >= loop_detect_threshold && !program_finished) begin
                    program_finished = 1;
                    $display("\n✓ Single-instruction loop detected at PC=0x%08h", debug_pc);
                    print_results();
                    $finish;
                end
            end else begin
                stable_cycles = 0;
            end
            
            // Method 2: Detect 2-instruction cycle
            if (cycle_counter >= 2) begin
                if (debug_pc == pc_history[(pc_idx + 14) % 16]) begin
                    match_count_2 = match_count_2 + 1;
                    
                    if (match_count_2 >= 4 && !program_finished) begin
                        program_finished = 1;
                        $display("\n✓ 2-instruction loop detected: 0x%h <-> 0x%h", 
                                 pc_history[(pc_idx + 15) % 16], debug_pc);
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_2 = 0;
                end
            end
            
            // Method 3: Detect 3-instruction cycle
            if (cycle_counter >= 3) begin
                if (debug_pc == pc_history[(pc_idx + 13) % 16]) begin
                    match_count_3 = match_count_3 + 1;
                    
                    if (match_count_3 >= 6 && !program_finished) begin
                        program_finished = 1;
                        $display("\n✓ 3-instruction loop detected at PC=0x%08h", debug_pc);
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_3 = 0;
                end
            end
            
            // Method 4: Detect 4-instruction cycle
            if (cycle_counter >= 4) begin
                if (debug_pc == pc_history[(pc_idx + 12) % 16]) begin
                    match_count_4 = match_count_4 + 1;
                    
                    if (match_count_4 >= 8 && !program_finished) begin
                        program_finished = 1;
                        $display("\n✓ 4-instruction loop detected at PC=0x%08h", debug_pc);
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_4 = 0;
                end
            end
            
            // Update PC history circular buffer
            pc_history[pc_idx] = debug_pc;
            pc_idx = (pc_idx + 1) % 16;
            cycle_counter = cycle_counter + 1;
            
            prev_pc = debug_pc;
            prev_instr = debug_instr;
        end
    end
    
    // Main test sequence
    initial begin
        $dumpfile("riscv_soc_top_waveform.vcd");
        $dumpvars(0, testbench);
        
        // Initialize variables
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
        loop_detect_threshold = 3;
        
        // Reset sequence
        rst_n = 0;
        #15;
        rst_n = 1;
        
        $display("\n╔════════════════════════════════════════╗");
        $display("║   RISC-V SoC with AXI Interconnect    ║");
        $display("║         Simulation Test                ║");
        $display("╚════════════════════════════════════════╝\n");
        
        // Wait for program to finish (max 20000 clock cycles)
        #200000;
        
        // If still running after timeout
        if (!program_finished) begin
            $display("\n⚠ WARNING: Program timeout after %0d cycles", cycle_count);
            print_results();
        end
        
        $finish;
    end
    
    // Task to print comprehensive results
    task print_results;
        integer i;
        integer non_zero_regs;
        reg [31:0] return_value;
        real cpi;
        begin
            // Access register file from the CPU through SoC
            // Note: Adjust the path based on your actual module hierarchy
            return_value = dut.cpu.datapath.register_file.registers[10];  // a0 register
            
            $display("\n╔════════════════════════════════════════╗");
            $display("║      Execution Results                 ║");
            $display("╚════════════════════════════════════════╝\n");
            
            // Main result
            $display("┌─── PROGRAM OUTPUT ─────────────────────────────┐");
            $display("│ Return Value (x10/a0):                          │");
            $display("│   Decimal: %-26d ", return_value);
            $display("│   Hex:     0x%-24h ", return_value);
            $display("│   Binary:  %032b ", return_value);
            $display("└─────────────────────────────────────────────────┘\n");
            
            // Performance metrics
            if (instr_count > 0) begin
                cpi = cycle_count * 1.0 / instr_count;
            end else begin
                cpi = 0.0;
            end
            
            $display("┌─── PERFORMANCE METRICS ────────────────┐");
            $display("│ Total Clock Cycles:  %-15d │", cycle_count);
            $display("│ Instructions Executed: %-13d │", instr_count);
            $display("│ CPI (Cycles/Instr):  %-15.2f │", cpi);
            $display("│ Final PC:            0x%-13h │", debug_pc);
            $display("│ Final Instruction:   0x%-13h │", debug_instr);
            $display("└──────────────────────────────────────┘\n");
            
            // Register dump - only non-zero registers
            non_zero_regs = 0;
            for (i = 0; i < 32; i = i + 1) begin
                if (dut.cpu.datapath.register_file.registers[i] != 0) begin
                    non_zero_regs = non_zero_regs + 1;
                end
            end
            
            $display("┌─── REGISTER FILE (%0d non-zero) ────────┐", non_zero_regs);
            $display("│ Reg  │   Decimal    │     Hex      │");
            $display("├──────┼──────────────┼──────────────┤");
            
            for (i = 0; i < 32; i = i + 1) begin
                if (dut.cpu.datapath.register_file.registers[i] != 0 || i == 0 || i == 10) begin
                    $display("│ x%-3d │ %12d │ 0x%010h │", 
                             i, 
                             dut.cpu.datapath.register_file.registers[i],
                             dut.cpu.datapath.register_file.registers[i]);
                end
            end
            $display("└──────┴──────────────┴──────────────┘\n");
            
            // Pipeline efficiency analysis
            print_pipeline_stats();
            
            $display("════════════════════════════════════════════════════\n");
        end
    endtask
    
    // Task: Analyze pipeline efficiency
    task print_pipeline_stats;
        real efficiency;
        begin
            $display("┌─── PIPELINE ANALYSIS ──────────────────┐");
            
            if (cycle_count > 0) begin
                efficiency = (instr_count * 100.0) / cycle_count;
                $display("│ Pipeline Efficiency: %-15.1f%% │", efficiency);
            end
            
            // Ideal CPI for 5-stage pipeline is 1.0
            if (instr_count > 0) begin
                $display("│ Target CPI:          1.00              │");
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
