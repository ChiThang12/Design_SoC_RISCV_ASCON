`timescale 1ns/1ps

// Only include top-level modules to avoid circular dependencies
// All sub-modules will be included by these top-level files
`include "riscv_soc_top.v"

module testbench;
    // ========================================================================
    // Signals
    // ========================================================================
    reg clk, rst_n;
    
    wire [31:0] debug_pc, debug_instr, debug_alu_result, debug_mem_data;
    wire [31:0] debug_branch_target;
    wire debug_branch_taken, debug_stall;
    wire [1:0] debug_forward_a, debug_forward_b;
    
    integer cycle_count, instr_count;
    reg program_finished;
    
    // ========================================================================
    // DUT
    // ========================================================================
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
    
    // ========================================================================
    // Clock: 100MHz
    // ========================================================================
    initial clk = 0;
    always #5 clk = ~clk;
    
    // ========================================================================
    // Cycle counter & Watchdog timer
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (debug_instr != 32'h00000013 && debug_instr != 32'h00000000 && !debug_stall) begin
                instr_count = instr_count + 1;
            end
            // Watchdog: stop if cycles exceed reasonable limit
            if (cycle_count > 100000 && !program_finished) begin
                $display("⚠ Watchdog triggered after %0d cycles", cycle_count);
                program_finished = 1;
                print_results();
                $finish;
            end
        end
    end
    
    // ========================================================================
    // Loop detection
    // ========================================================================
    reg [31:0] prev_pc, prev_instr;
    integer stable_cycles;
    
    always @(posedge clk) begin
        if (rst_n && debug_instr != 32'h00000000) begin
            if (debug_pc == prev_pc && debug_instr == prev_instr) begin
                stable_cycles = stable_cycles + 1;
                if (stable_cycles >= 5 && !program_finished) begin
                    program_finished = 1;
                    $display("\n✓ Loop detected at PC=0x%08h", debug_pc);
                    print_results();
                    $finish;
                end
            end else begin
                stable_cycles = 0;
            end
            prev_pc = debug_pc;
            prev_instr = debug_instr;
        end
    end
    
    // ========================================================================
    // Main test
    // ========================================================================
    initial begin
        $dumpfile("soc.vcd");
        $dumpvars(0, testbench);
        
        cycle_count = 0;
        instr_count = 0;
        stable_cycles = 0;
        program_finished = 0;
        prev_pc = 0;
        prev_instr = 0;
        
        rst_n = 0;
        #20;
        rst_n = 1;
        
        $display("\n╔═══════════════════════════════════════╗");
        $display("║   RISC-V SoC Simulation               ║");
        $display("╚═══════════════════════════════════════╝\n");
        
        #10000;  // Reduced timeout for faster feedback
        
        if (!program_finished) begin
            $display("\n⚠ Timeout after %0d cycles", cycle_count);
            print_results();
        end
        
        $finish;
    end
    
    // ========================================================================
    // Print results
    // ========================================================================
    task print_results;
        integer i, non_zero;
        reg [31:0] ret_val;
        real cpi;
    begin
        ret_val = dut.cpu.cpu_core.register_file.registers[10];
        cpi = (instr_count > 0) ? (cycle_count * 1.0 / instr_count) : 0.0;
        
        $display("\n╔═══════════════════════════════════════╗");
        $display("║      Results                           ║");
        $display("╚═══════════════════════════════════════╝\n");
        
        $display("┌─── OUTPUT ─────────────────────────────┐");
        $display("│ Return (x10): %0d (0x%h)", ret_val, ret_val);
        $display("└────────────────────────────────────────┘\n");
        
        $display("┌─── PERFORMANCE ────────────────────────┐");
        $display("│ Cycles:       %0d", cycle_count);
        $display("│ Instructions: %0d", instr_count);
        $display("│ CPI:          %.2f", cpi);
        $display("│ Final PC:     0x%h", debug_pc);
        $display("└────────────────────────────────────────┘\n");
        
        non_zero = 0;
        for (i = 0; i < 32; i = i + 1) begin
            if (dut.cpu.cpu_core.register_file.registers[i] != 0) begin
                non_zero = non_zero + 1;
            end
        end
        
        $display("┌─── REGISTERS (%0d non-zero) ───────────┐", non_zero);
        for (i = 0; i < 32; i = i + 1) begin
            if (dut.cpu.cpu_core.register_file.registers[i] != 0 || i == 10) begin
                $display("│ x%-2d = %0d (0x%h)", i,
                         dut.cpu.cpu_core.register_file.registers[i],
                         dut.cpu.cpu_core.register_file.registers[i]);
            end
        end
        $display("└────────────────────────────────────────┘\n");
        
        if (cpi >= 1.0 && cpi <= 2.0) begin
            $display("✓ Good performance (CPI=%.2f)", cpi);
        end else if (cpi > 2.0) begin
            $display("⚠ High CPI (%.2f) - check for stalls", cpi);
        end
    end
    endtask

endmodule