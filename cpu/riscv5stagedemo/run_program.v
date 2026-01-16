`timescale 1ns/1ps
`include "datapath.v"

module testbench;
    reg clock;
    reg reset;
    wire [31:0] pc_current;
    wire [31:0] instruction_current;
    wire [31:0] alu_result;
    wire [31:0] mem_out;
    wire branch_taken;
    wire [31:0] branch_target;
    wire stall;
    wire [1:0] forward_a;
    wire [1:0] forward_b;
    
    integer cycle_count;
    integer instr_count;
    reg program_finished;
    
    datapath dut (
        .clock(clock),
        .reset(reset),
        .pc_current(pc_current),
        .instruction_current(instruction_current),
        .alu_result_debug(alu_result),
        .mem_out_debug(mem_out),
        .branch_taken_debug(branch_taken),
        .branch_target_debug(branch_target),
        .stall_debug(stall),
        .forward_a_debug(forward_a),
        .forward_b_debug(forward_b)
    );
    
    // Clock generation: 10ns period (100MHz)
    initial clock = 0;
    always #5 clock = ~clock;
    
    // Cycle and instruction counting
    always @(posedge clock) begin
        if (!reset) begin
            cycle_count = cycle_count + 1;
            // Count only valid instructions (not NOPs and not stalled)
            if (instruction_current != 32'h00000013 && !stall) begin
                instr_count = instr_count + 1;
            end
        end
    end
    
    // Detect program end with improved logic
    reg [31:0] prev_pc;
    reg [31:0] prev_instr;
    integer stable_cycles;
    integer loop_detect_threshold;
    
    // Track PC history for cycle detection (circular buffer)
    reg [31:0] pc_history [0:15];  // Tăng buffer size
    integer pc_idx;
    integer cycle_counter;
    integer match_count_2;
    integer match_count_3;
    integer match_count_4;  // Thêm detection cho 4-instruction loop
    
    // Debug: Enable to see PC pattern
    integer debug_mode;
    
    always @(posedge clock) begin
        if (!reset) begin
            // Debug output (only first 50 cycles)
            if (debug_mode && cycle_count < 50) begin
                $display("[%0d] PC=0x%h, Instr=0x%h", cycle_count, pc_current, instruction_current);
            end
            
            // Method 1: Detect single-instruction infinite loop (j 0x28)
            if ((pc_current == prev_pc) && (instruction_current == prev_instr)) begin
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
                if (pc_current == pc_history[(pc_idx + 14) % 16]) begin  // 2 cycles ago
                    match_count_2 = match_count_2 + 1;
                    
                    if (match_count_2 >= 4 && !program_finished) begin  // Giảm từ 6 → 4
                        program_finished = 1;
                        $display("\n✓ 2-instruction loop detected: 0x%h <-> 0x%h", 
                                 pc_history[(pc_idx + 15) % 16], pc_current);
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_2 = 0;
                end
            end
            
            // Method 3: Detect 3-instruction cycle
            if (cycle_counter >= 3) begin
                if (pc_current == pc_history[(pc_idx + 13) % 16]) begin  // 3 cycles ago
                    match_count_3 = match_count_3 + 1;
                    
                    if (match_count_3 >= 6 && !program_finished) begin  // Giảm từ 9 → 6
                        program_finished = 1;
                        $display("\n✓ 3-instruction loop detected at PC=0x%08h", pc_current);
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_3 = 0;
                end
            end
            
            // Method 4: Detect 4-instruction cycle (most common for halt loops)
            if (cycle_counter >= 4) begin
                if (pc_current == pc_history[(pc_idx + 12) % 16]) begin  // 4 cycles ago
                    match_count_4 = match_count_4 + 1;
                    
                    if (match_count_4 >= 8 && !program_finished) begin
                        program_finished = 1;
                        $display("\n✓ 4-instruction loop detected at PC=0x%08h", pc_current);
                        print_results();
                        $finish;
                    end
                end else begin
                    match_count_4 = 0;
                end
            end
            
            // Update PC history circular buffer
            pc_history[pc_idx] = pc_current;
            pc_idx = (pc_idx + 1) % 16;
            cycle_counter = cycle_counter + 1;
            
            prev_pc = pc_current;
            prev_instr = instruction_current;
        end
    end
    
    // Main test sequence
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, testbench);
        
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
        debug_mode = 0;  // Tắt debug (đổi thành 1 nếu muốn xem PC)
        loop_detect_threshold = 3;
        
        // Reset sequence
        reset = 1;
        #15;
        reset = 0;
        
        $display("\n╔════════════════════════════════════════╗");
        $display("║   RISC-V Pipeline Processor Test       ║");
        $display("╚════════════════════════════════════════╝\n");
        
        // Wait for program to finish (max 2000 cycles - reduced timeout)
        #20000;
        
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
            return_value = dut.register_file.registers[10];  // a0 register
            
            $display("\n╔════════════════════════════════════════╗");
            $display("║      Execution Results                 ║");
            $display("╚════════════════════════════════════════╝\n");
            
            // Main result
            $display("┌─── PROGRAM OUTPUT ──────────────────────────────────────┐");
            $display("│ Return Value (x10/a0):                                  │");
            $display("│   Decimal: %-26d ", return_value);
            $display("│   Hex:     0x%-24h ", return_value);
            $display("│   Binary:  %032b ", return_value);
            $display("└─────────────────────────────────────────────────────────┘\n");
            
            // Performance metrics
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
            
            // Register dump - only non-zero registers
            non_zero_regs = 0;
            for (i = 0; i < 32; i = i + 1) begin
                if (dut.register_file.registers[i] != 0) begin
                    non_zero_regs = non_zero_regs + 1;
                end
            end
            
            $display("┌─── REGISTER FILE (%0d non-zero) ─────┐", non_zero_regs);
            $display("│ Reg  │   Decimal    │     Hex      │");
            $display("├──────┼──────────────┼──────────────┤");
            
            for (i = 0; i < 32; i = i + 1) begin
                if (dut.register_file.registers[i] != 0 || i == 0 || i == 10) begin
                    $display("│ x%-3d │ %12d │ 0x%010h │", 
                             i, 
                             dut.register_file.registers[i],
                             dut.register_file.registers[i]);
                end
            end
            $display("└──────┴──────────────┴──────────────┘\n");
            
            // Pipeline efficiency analysis
            print_pipeline_stats();
            
            $display("════════════════════════════════════════\n");
        end
    endtask
    
    // New task: Analyze pipeline efficiency
    task print_pipeline_stats;
        real efficiency;
        begin
            $display("┌─── PIPELINE ANALYSIS ────────────────┐");
            
            if (cycle_count > 0) begin
                efficiency = (instr_count * 100.0) / cycle_count;
                $display("│ Pipeline Efficiency: %-15.1f%% │", efficiency);
            end
            
            // Ideal CPI for 5-stage pipeline is 1.0
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