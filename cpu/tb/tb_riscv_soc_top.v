// // ============================================================================
// // riscv_soc_tb.v - Testbench for Complete RISC-V SoC
// // ============================================================================
// // Description:
// //   Comprehensive testbench for the complete SoC with AXI4-Lite interconnect
// //
// // Author: ChiThang
// // ============================================================================

// `timescale 1ns / 1ps
// `include "riscv_soc_top.v"

// module riscv_soc_tb;

//     // ========================================================================
//     // Testbench Signals
//     // ========================================================================
//     reg clk;
//     reg rst_n;
    
//     // ========================================================================
//     // Clock Generation - 10ns period (100MHz)
//     // ========================================================================
//     initial begin
//         clk = 0;
//         forever #5 clk = ~clk;
//     end
    
//     // ========================================================================
//     // DUT Instantiation
//     // ========================================================================
//     riscv_soc_top soc (
//         .clk(clk),
//         .rst_n(rst_n)
//     );
    
//     // ========================================================================
//     // Monitor Signals
//     // ========================================================================
//     integer cycle_count;
    
//     always @(posedge clk) begin
//         if (rst_n) begin
//             cycle_count = cycle_count + 1;
            
//             // Monitor CPU state
//             if (soc.cpu.regwrite_wb && soc.cpu.rd_wb != 5'b0) begin
//                 $display("[CYCLE %0d] WB: x%0d <= 0x%h", 
//                     cycle_count, soc.cpu.rd_wb, soc.cpu.write_back_data_wb);
//             end
            
//             // Monitor PC
//             $display("[CYCLE %0d] PC = 0x%h, Instr = 0x%h", 
//                 cycle_count, soc.cpu.pc_if, soc.cpu.instr_if);
            
//             // Monitor AXI transactions
//             if (soc.imem_m_axi_arvalid && soc.imem_m_axi_arready) begin
//                 $display("[AXI IMEM READ] Addr = 0x%h", soc.imem_m_axi_araddr);
//             end
            
//             if (soc.dmem_m_axi_arvalid && soc.dmem_m_axi_arready) begin
//                 $display("[AXI DMEM READ] Addr = 0x%h", soc.dmem_m_axi_araddr);
//             end
            
//             if (soc.dmem_m_axi_awvalid && soc.dmem_m_axi_awready) begin
//                 $display("[AXI DMEM WRITE] Addr = 0x%h, Data = 0x%h, Strb = %b", 
//                     soc.dmem_m_axi_awaddr, soc.dmem_m_axi_wdata, soc.dmem_m_axi_wstrb);
//             end
//         end
//     end
    
//     // ========================================================================
//     // Test Procedure
//     // ========================================================================
//     initial begin
//         // Waveform dump
//         $dumpfile("riscv_soc_tb.vcd");
//         $dumpvars(0, riscv_soc_tb);
        
//         // Initialize
//         rst_n = 0;
//         cycle_count = 0;
        
//         $display("========================================");
//         $display("RISC-V SoC Testbench Started");
//         $display("========================================");
//         $display("[INFO] Instruction memory loaded from memory/program.hex");
        
//         // Reset sequence
//         repeat(10) @(posedge clk);
//         rst_n = 1;
        
//         $display("[INFO] Reset released, SoC running...");
        
//         // Run for enough cycles to complete test program
//         repeat(150) @(posedge clk);
        
//         $display("========================================");
//         $display("Register File Final State:");
//         $display("========================================");
//         $display("x1  = 0x%h", soc.cpu.register_file.registers[1]);
//         $display("x2  = 0x%h", soc.cpu.register_file.registers[2]);
//         $display("x3  = 0x%h", soc.cpu.register_file.registers[3]);
//         $display("x4  = 0x%h", soc.cpu.register_file.registers[4]);
//         $display("x5  = 0x%h", soc.cpu.register_file.registers[5]);
//         $display("x6  = 0x%h", soc.cpu.register_file.registers[6]);
//         $display("x7  = 0x%h", soc.cpu.register_file.registers[7]);
//         $display("x8  = 0x%h", soc.cpu.register_file.registers[8]);
//         $display("x9  = 0x%h", soc.cpu.register_file.registers[9]);
//         $display("x10 = 0x%h", soc.cpu.register_file.registers[10]);
//         $display("x11 = 0x%h", soc.cpu.register_file.registers[11]);
//         $display("x12 = 0x%h", soc.cpu.register_file.registers[12]);
//         $display("x13 = 0x%h", soc.cpu.register_file.registers[13]);
//         $display("x14 = 0x%h", soc.cpu.register_file.registers[14]);
//         $display("x15 = 0x%h", soc.cpu.register_file.registers[15]);
//         $display("x16 = 0x%h", soc.cpu.register_file.registers[16]);
//         $display("x17 = 0x%h", soc.cpu.register_file.registers[17]);
//         $display("x18 = 0x%h", soc.cpu.register_file.registers[18]);
//         $display("x19 = 0x%h", soc.cpu.register_file.registers[19]);
//         $display("x20 = 0x%h", soc.cpu.register_file.registers[20]);
        
//         $display("========================================");
//         $display("Expected Results (ALU Test):");
//         $display("========================================");
//         $display("x1  = 0x00000005 (ADDI 5)");
//         $display("x2  = 0x00000003 (ADDI 3)");
//         $display("x3  = 0x00000008 (ADD: 5+3)");
//         $display("x4  = 0x00000002 (SUB: 5-3)");
//         $display("x5  = 0x00000001 (AND: 5&3)");
//         $display("x6  = 0x00000007 (OR:  5|3)");
//         $display("x7  = 0x00000006 (XOR: 5^3)");
//         $display("x8  = 0x00000014 (SLLI: 5<<2 = 20)");
//         $display("x9  = 0x00000001 (SRLI: 5>>2 = 1)");
//         $display("x10 = 0x00000000 (SLT: 7<3 false)");
//         $display("x11 = 0x0000000A (ADDI 10)");
//         $display("x12 = 0x00000005 (ADDI 5)");
//         $display("x13 = 0x00000000 (ADDI 0)");
//         $display("x14 = 0x00000000 (ADDI 0)");
//         $display("x15 = 0x00000000 (ADDI 0)");
//         $display("x16 = 0x00000000 (ADDI 0)");
//         $display("x17 = 0x00000000 (ADDI 0)");
//         $display("x20 = 0x12345000 (LUI)");
        
//         $display("========================================");
//         $display("SoC Simulation Completed");
//         $display("========================================");
        
//         $finish;
//     end
    
//     // ========================================================================
//     // Timeout Watchdog
//     // ========================================================================
//     initial begin
//         #20000;
//         $display("ERROR: Simulation timeout!");
//         $finish;
//     end

// endmodule

// ============================================================================
// riscv_soc_tb.v - Enhanced Testbench for Complete RISC-V SoC
// ============================================================================
// Description:
//   Comprehensive testbench with detailed debugging for memory operations
//
// Author: ChiThang (Enhanced)
// ============================================================================

`timescale 1ns / 1ps
`include "riscv_soc_top.v"

module riscv_soc_tb;

    // ========================================================================
    // Testbench Signals
    // ========================================================================
    reg clk;
    reg rst_n;
    integer cycle_count;
    
    // ========================================================================
    // Clock Generation - 10ns period (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    riscv_soc_top soc (
        .clk(clk),
        .rst_n(rst_n)
    );
    
    // ========================================================================
    // MONITOR 1: Basic Instruction Flow (posedge - before update)
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            
            // Monitor PC and Instruction
            $display("[CYCLE %0d] PC = 0x%h, Instr = 0x%h", 
                cycle_count, soc.cpu.pc_if, soc.cpu.instr_if);
            
            // Monitor AXI IMEM transactions
            if (soc.imem_m_axi_arvalid && soc.imem_m_axi_arready) begin
                $display("[AXI IMEM READ] Addr = 0x%h", soc.imem_m_axi_araddr);
            end
            
            // Monitor AXI DMEM transactions
            if (soc.dmem_m_axi_arvalid && soc.dmem_m_axi_arready) begin
                $display("[AXI DMEM READ] Addr = 0x%h", soc.dmem_m_axi_araddr);
            end
            
            if (soc.dmem_m_axi_awvalid && soc.dmem_m_axi_awready) begin
                $display("[AXI DMEM WRITE] Addr = 0x%h, Data = 0x%h, Strb = %b", 
                    soc.dmem_m_axi_awaddr, soc.dmem_m_axi_wdata, soc.dmem_m_axi_wstrb);
            end
            
            // Monitor stalls
            if (soc.cpu.stall) begin
                $display("[STALL] imem_ready=%b, dmem_valid=%b, dmem_ready=%b, mem_req_pending=%b",
                         soc.imem_m_axi_arready,
                         soc.cpu.dmem_valid,
                         soc.cpu.dmem_ready,
                         soc.cpu.mem_req_pending);
            end
        end
    end
    
    // ========================================================================
    // MONITOR 2: Write-Back Stage (posedge - immediate display)
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // Monitor register writes
            if (soc.cpu.regwrite_wb && soc.cpu.rd_wb != 5'b0) begin
                $display("[CYCLE %0d] WB: x%0d <= 0x%h (src: %s)", 
                    cycle_count, 
                    soc.cpu.rd_wb, 
                    soc.cpu.write_back_data_wb,
                    soc.cpu.memtoreg_wb ? "MEMORY" : (soc.cpu.jump_wb ? "PC+4" : "ALU"));
            end
        end
    end
    
    // ========================================================================
    // MONITOR 3: Memory Operations (negedge - after state update)
    // ========================================================================
    always @(negedge clk) begin
        if (rst_n) begin
            // Monitor memory FSM state
            if (soc.cpu.dmem_valid || soc.cpu.mem_req_pending) begin
                $display("[MEM_FSM] Cycle=%0d, valid=%b, ready=%b, pending=%b, wb_done=%b, we=%b, addr=0x%h",
                         cycle_count,
                         soc.cpu.dmem_valid,
                         soc.cpu.dmem_ready,
                         soc.cpu.mem_req_pending,
                         soc.cpu.wb_done,
                         soc.cpu.dmem_we,
                         soc.cpu.dmem_addr);
            end
            
            // Monitor memory operations in MEM stage
            if (soc.cpu.memread_mem || soc.cpu.memwrite_mem) begin
                $display("[MEM_STAGE] Cycle=%0d, Op=%s, Addr=0x%h, rd=%0d, regwrite=%b, memtoreg=%b",
                         cycle_count,
                         soc.cpu.memread_mem ? "LOAD" : "STORE",
                         soc.cpu.alu_result_mem,
                         soc.cpu.rd_mem,
                         soc.cpu.regwrite_mem,
                         soc.cpu.memtoreg_mem);
            end
            
            // Monitor snapshot capture
            if (soc.cpu.dmem_valid && soc.cpu.dmem_ready && !soc.cpu.mem_req_pending) begin
                $display("[SNAPSHOT] Cycle=%0d, Captured: rd=%0d, regwrite=%b, memtoreg=%b, jump=%b",
                         cycle_count,
                         soc.cpu.rd_mem,
                         soc.cpu.regwrite_mem,
                         soc.cpu.memtoreg_mem,
                         soc.cpu.jump_mem);
            end
            
            // Monitor writeback from snapshot
            if (soc.cpu.mem_req_pending && soc.cpu.wb_done) begin
                $display("[SNAPSHOT_WB] Cycle=%0d, Using snapshot: rd=%0d, regwrite=%b, memtoreg=%b",
                         cycle_count,
                         soc.cpu.rd_mem_snapshot,
                         soc.cpu.regwrite_mem_snapshot,
                         soc.cpu.memtoreg_mem_snapshot);
            end
        end
    end
    
    // ========================================================================
    // MONITOR 4: FSM Transitions
    // ========================================================================
    reg prev_mem_req_pending;
    reg prev_wb_done;
    
    always @(posedge clk) begin
        if (rst_n) begin
            prev_mem_req_pending <= soc.cpu.mem_req_pending;
            prev_wb_done <= soc.cpu.wb_done;
        end else begin
            prev_mem_req_pending <= 1'b0;
            prev_wb_done <= 1'b0;
        end
    end
    
    always @(negedge clk) begin
        if (rst_n) begin
            // Detect mem_req_pending transitions
            if (prev_mem_req_pending !== soc.cpu.mem_req_pending) begin
                $display("[FSM_TRANSITION] Cycle=%0d: mem_req_pending %b → %b",
                         cycle_count,
                         prev_mem_req_pending,
                         soc.cpu.mem_req_pending);
            end
            
            // Detect wb_done transitions
            if (prev_wb_done !== soc.cpu.wb_done) begin
                $display("[FSM_TRANSITION] Cycle=%0d: wb_done %b → %b",
                         cycle_count,
                         prev_wb_done,
                         soc.cpu.wb_done);
            end
        end
    end
    
    // ========================================================================
    // Test Procedure
    // ========================================================================
    initial begin
        // Waveform dump
        $dumpfile("riscv_soc_tb.vcd");
        $dumpvars(0, riscv_soc_tb);
        
        // Initialize
        rst_n = 0;
        cycle_count = 0;
        
        $display("========================================");
        $display("RISC-V SoC Testbench Started");
        $display("========================================");
        $display("[INFO] Test Program:");
        $display("  addi x1, x0, 5      # x1 = 5");
        $display("  addi x2, x0, 3      # x2 = 3");
        $display("  sw   x1, 0(x0)      # mem[0] = 5");
        $display("  lw   x3, 0(x0)      # x3 = mem[0] = 5");
        $display("  lh   x4, 0(x0)      # x4 = 5 (halfword)");
        $display("  lb   x5, 0(x0)      # x5 = 5 (byte)");
        $display("  addi x6, x0, 5      # x6 = 5");
        $display("  addi x7, x0, 6      # x7 = 6");
        $display("  sw   x12, 0(x6)     # mem[5] = 0");
        $display("  lw   x8, 0(x6)      # x8 = mem[5] = 0");
        $display("  addi x9, x0, 10     # x9 = 10");
        $display("  addi x10, x0, 5     # x10 = 5");
        $display("  addi x11, x0, 0     # x11 = 0");
        $display("  lui  x20, 0x12345   # x20 = 0x12345000");
        $display("  jal  x0, 0          # Infinite loop");
        $display("========================================");
        
        // Reset sequence
        repeat(10) @(posedge clk);
        rst_n = 1;
        
        $display("[INFO] Reset released, SoC running...");
        $display("========================================");
        
        // Run for enough cycles to complete test program
        // 14 instructions + AXI latencies + infinite loop detection
        repeat(250) @(posedge clk);
        
        // Display results
        $display("");
        $display("========================================");
        $display("SIMULATION COMPLETED");
        $display("========================================");
        $display("");
        $display("Register File Final State:");
        $display("========================================");
        $display("x0  = 0x%h (expected: 0x00000000)", soc.cpu.register_file.registers[0]);
        $display("x1  = 0x%h (expected: 0x00000005)", soc.cpu.register_file.registers[1]);
        $display("x2  = 0x%h (expected: 0x00000003)", soc.cpu.register_file.registers[2]);
        $display("x3  = 0x%h (expected: 0x00000005) ← LOAD TEST", soc.cpu.register_file.registers[3]);
        $display("x4  = 0x%h (expected: 0x00000005) ← LH TEST", soc.cpu.register_file.registers[4]);
        $display("x5  = 0x%h (expected: 0x00000005) ← LB TEST", soc.cpu.register_file.registers[5]);
        $display("x6  = 0x%h (expected: 0x00000005)", soc.cpu.register_file.registers[6]);
        $display("x7  = 0x%h (expected: 0x00000006)", soc.cpu.register_file.registers[7]);
        $display("x8  = 0x%h (expected: 0x00000000) ← LOAD TEST 2", soc.cpu.register_file.registers[8]);
        $display("x9  = 0x%h (expected: 0x0000000a)", soc.cpu.register_file.registers[9]);
        $display("x10 = 0x%h (expected: 0x00000005)", soc.cpu.register_file.registers[10]);
        $display("x11 = 0x%h (expected: 0x00000000)", soc.cpu.register_file.registers[11]);
        $display("x12 = 0x%h (expected: 0x00000000)", soc.cpu.register_file.registers[12]);
        $display("x20 = 0x%h (expected: 0x12345000) ← LUI TEST", soc.cpu.register_file.registers[20]);
        
        $display("");
        $display("Memory Contents:");
        $display("========================================");
        $display("mem[0] = 0x%h (expected: 0x00000005)", soc.dmem_slave.dmem.memory[0]);
        $display("mem[5] = 0x%h (expected: 0x00000000)", soc.dmem_slave.dmem.memory[5]);
        
        $display("");
        $display("Test Results:");
        $display("========================================");
        
        // Check critical values
        if (soc.cpu.register_file.registers[1] == 32'h00000005 &&
            soc.cpu.register_file.registers[2] == 32'h00000003 &&
            soc.cpu.register_file.registers[3] == 32'h00000005 &&
            soc.cpu.register_file.registers[4] == 32'h00000005 &&
            soc.cpu.register_file.registers[5] == 32'h00000005 &&
            soc.cpu.register_file.registers[6] == 32'h00000005 &&
            soc.cpu.register_file.registers[7] == 32'h00000006 &&
            soc.cpu.register_file.registers[8] == 32'h00000000 &&
            soc.cpu.register_file.registers[9] == 32'h0000000a &&
            soc.cpu.register_file.registers[10] == 32'h00000005 &&
            soc.cpu.register_file.registers[20] == 32'h12345000) begin
            $display("✓ ALL TESTS PASSED!");
        end else begin
            $display("✗ TESTS FAILED - Check register values above");
        end
        
        $display("========================================");
        
        $finish;
    end
    
    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #30000;
        $display("");
        $display("========================================");
        $display("ERROR: Simulation timeout!");
        $display("========================================");
        $finish;
    end

endmodule