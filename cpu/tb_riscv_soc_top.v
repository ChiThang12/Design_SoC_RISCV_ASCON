// ============================================================================
// riscv_soc_tb.v - Testbench for Complete RISC-V SoC
// ============================================================================
// Description:
//   Comprehensive testbench for the complete SoC with AXI4-Lite interconnect
//
// Author: ChiThang
// ============================================================================

`timescale 1ns / 1ps
//`define TESTBENCH_MODE  // Thêm dòng này
`include "riscv_soc_top.v"
module riscv_soc_tb;

    // ========================================================================
    // Testbench Signals
    // ========================================================================
    reg clk;
    reg rst_n;
    
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
    // Monitor Signals
    // ========================================================================
    integer cycle_count;
    
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            
            // Monitor CPU state
            if (soc.cpu.regwrite_wb && soc.cpu.rd_wb != 5'b0) begin
                $display("[CYCLE %0d] WB: x%0d <= 0x%h", 
                    cycle_count, soc.cpu.rd_wb, soc.cpu.write_back_data_wb);
            end
            
            // Monitor PC
            $display("[CYCLE %0d] PC = 0x%h, Instr = 0x%h", 
                cycle_count, soc.cpu.pc_if, soc.cpu.instr_if);
            
            // Monitor AXI transactions
            if (soc.imem_m_axi_arvalid && soc.imem_m_axi_arready) begin
                $display("[AXI IMEM READ] Addr = 0x%h", soc.imem_m_axi_araddr);
            end
            
            if (soc.dmem_m_axi_arvalid && soc.dmem_m_axi_arready) begin
                $display("[AXI DMEM READ] Addr = 0x%h", soc.dmem_m_axi_araddr);
            end
            
            if (soc.dmem_m_axi_awvalid && soc.dmem_m_axi_awready) begin
                $display("[AXI DMEM WRITE] Addr = 0x%h, Data = 0x%h, Strb = %b", 
                    soc.dmem_m_axi_awaddr, soc.dmem_m_axi_wdata, soc.dmem_m_axi_wstrb);
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
        
        // Reset sequence
        repeat(10) @(posedge clk);
        rst_n = 1;
        
        $display("[INFO] Reset released, SoC running...");
        
        // Run for enough cycles to complete test program
        repeat(150) @(posedge clk);
        
        $display("========================================");
        $display("Register File Final State:");
        $display("========================================");
        $display("x1  = 0x%h", soc.cpu.register_file.registers[1]);
        $display("x2  = 0x%h", soc.cpu.register_file.registers[2]);
        $display("x3  = 0x%h", soc.cpu.register_file.registers[3]);
        $display("x4  = 0x%h", soc.cpu.register_file.registers[4]);
        $display("x5  = 0x%h", soc.cpu.register_file.registers[5]);
        $display("x6  = 0x%h", soc.cpu.register_file.registers[6]);
        $display("x7  = 0x%h", soc.cpu.register_file.registers[7]);
        $display("x8  = 0x%h", soc.cpu.register_file.registers[8]);
        $display("x9  = 0x%h", soc.cpu.register_file.registers[9]);
        $display("x10 = 0x%h", soc.cpu.register_file.registers[10]);
        $display("x12 = 0x%h", soc.cpu.register_file.registers[12]);
        $display("x13 = 0x%h", soc.cpu.register_file.registers[13]);
        $display("x14 = 0x%h", soc.cpu.register_file.registers[14]);
        $display("x15 = 0x%h", soc.cpu.register_file.registers[15]);
        $display("x16 = 0x%h", soc.cpu.register_file.registers[16]);
        $display("x17 = 0x%h", soc.cpu.register_file.registers[17]);
        $display("x20 = 0x%h", soc.cpu.register_file.registers[20]);
        $display("x21 = 0x%h", soc.cpu.register_file.registers[21]);
        
        $display("========================================");
        $display("Expected Results:");
        $display("========================================");
        $display("x1  = JAL return address");
        $display("x2  = 0x00000003 (ADDI)");
        $display("x3  = 0x00000008 (ADD: 5+3)");
        $display("x4  = 0x00000002 (SUB: 5-3)");
        $display("x5  = 0x00000001 (AND: 5&3)");
        $display("x6  = 0x00000007 (OR:  5|3)");
        $display("x7  = 0x00000006 (XOR: 5^3)");
        $display("x8  = 0x00000014 (SLLI: 5<<2)");
        $display("x9  = 0x00000001 (SRLI: 5>>2)");
        $display("x10 = 0x00000000 (SLT: 5<3 false)");
        $display("x12 = 0x00000005 (LW from memory)");
        $display("x13 = 0x00000003 (LH from memory)");
        $display("x14 = 0x00000008 (LB from memory)");
        $display("x15 = 0x0000000A (ADDI 10)");
        $display("x16 = 0x00000005 (ADDI 5)");
        $display("x17 = 0x00000001 (Branch not taken)");
        $display("x20 = 0x12345000 (LUI)");
        
        $display("========================================");
        $display("SoC Simulation Completed");
        $display("========================================");
        
        $finish;
    end
    
    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #20000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule