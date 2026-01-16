// ============================================================================
// Testbench: IFU_tb - Kiểm tra module IFU (Instruction Fetch Unit)
// Mô tả: Kiểm tra chức năng fetch lệnh, PC update, branch/jump và stall
// ============================================================================

`timescale 1ns/1ps
`include "IFU.v"
module tb_IFU;

    // ========================================================================
    // Tín hiệu testbench
    // ========================================================================
    reg clock;
    reg reset;
    reg pc_src;
    reg stall;
    reg [31:0] target_pc;
    
    wire [31:0] PC_out;
    wire [31:0] Instruction_Code;
    
    // ========================================================================
    // Khởi tạo module IFU
    // ========================================================================
    IFU uut (
        .clock(clock),
        .reset(reset),
        .pc_src(pc_src),
        .stall(stall),
        .target_pc(target_pc),
        .PC_out(PC_out),
        .Instruction_Code(Instruction_Code)
    );
    
    // ========================================================================
    // Tạo xung clock: chu kỳ 10ns (100MHz)
    // ========================================================================
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end
    
    // ========================================================================
    // Kịch bản test
    // ========================================================================
    initial begin
        // Tạo file dump để xem sóng
        $dumpfile("tb_IFU.vcd");
        $dumpvars(0, tb_IFU);
        
        // In header
        $display("========================================");
        $display("  IFU Testbench - RISC-V 32IM");
        $display("========================================");
        $display("Time\tPC\t\tInstruction\tMode");
        $display("----------------------------------------");
        
        // Khởi tạo tín hiệu
        reset = 1;
        pc_src = 0;
        stall = 0;
        target_pc = 32'h00000000;
        
        // Test 1: Reset
        #10;
        reset = 0;
        $display("%0t\t0x%h\t0x%h\tReset released", $time, PC_out, Instruction_Code);
        
        // Test 2: Sequential fetch (PC+4)
        $display("\n--- Test Sequential Fetch (PC+4) ---");
        repeat(8) begin
            #10;
            $display("%0t\t0x%h\t0x%h\tSequential", $time, PC_out, Instruction_Code);
        end
        
        // Test 3: Branch/Jump (pc_src = 1)
        $display("\n--- Test Branch to 0x0C ---");
        #10;
        pc_src = 1;
        target_pc = 32'h0000000C;
        #10;
        pc_src = 0;
        $display("%0t\t0x%h\t0x%h\tBranch to 0x0C", $time, PC_out, Instruction_Code);
        
        repeat(3) begin
            #10;
            $display("%0t\t0x%h\t0x%h\tSequential", $time, PC_out, Instruction_Code);
        end
        
        // Test 4: Pipeline Stall
        $display("\n--- Test Pipeline Stall ---");
        #10;
        stall = 1;
        $display("%0t\t0x%h\t0x%h\tStall ON", $time, PC_out, Instruction_Code);
        repeat(3) begin
            #10;
            $display("%0t\t0x%h\t0x%h\tStalled", $time, PC_out, Instruction_Code);
        end
        
        stall = 0;
        #10;
        $display("%0t\t0x%h\t0x%h\tStall OFF", $time, PC_out, Instruction_Code);
        
        // Test 5: Jump to beginning
        $display("\n--- Test Jump to 0x00 ---");
        #10;
        pc_src = 1;
        target_pc = 32'h00000000;
        #10;
        pc_src = 0;
        $display("%0t\t0x%h\t0x%h\tJump to 0x00", $time, PC_out, Instruction_Code);
        
        repeat(4) begin
            #10;
            $display("%0t\t0x%h\t0x%h\tSequential", $time, PC_out, Instruction_Code);
        end
        
        // Test 6: Verify instruction decoding
        $display("\n--- Instruction Verification ---");
        $display("Expected instructions from program.hex:");
        $display("0x00: 0x00000093 - addi x1, x0, 0");
        $display("0x04: 0x00100113 - addi x2, x0, 1");
        $display("0x08: 0x00a00193 - addi x3, x0, 10");
        $display("0x0C: 0x002080b3 - add x1, x1, x2");
        $display("0x10: 0x00110113 - addi x2, x2, 1");
        $display("0x14: 0xfe314ae3 - blt x2, x3, -12");
        $display("0x18: 0x00008513 - addi x10, x1, 0");
        $display("0x1C: 0x00000013 - addi x0, x0, 0 (NOP)");
        
        // Kết thúc simulation
        #50;
        $display("\n========================================");
        $display("  Simulation Complete!");
        $display("========================================");
        $finish;
    end
    
    // ========================================================================
    // Monitor PC changes
    // ========================================================================
    always @(posedge clock) begin
        if (!reset && !stall) begin
            // Có thể thêm check tự động ở đây
        end
    end
    
    // ========================================================================
    // Timeout protection
    // ========================================================================
    initial begin
        #2000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule