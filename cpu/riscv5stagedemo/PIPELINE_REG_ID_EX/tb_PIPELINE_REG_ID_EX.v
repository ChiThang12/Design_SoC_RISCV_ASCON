`timescale 1ps/1ps
`include "PIPELINE_REG_ID_EX.v"
module tb_PIPELINE_REG_ID_EX;

    reg clock;
    reg reset;
    reg flush;
    reg stall;
    
    // Control signals input
    reg regwrite_in;
    reg alusrc_in;
    reg memread_in;
    reg memwrite_in;
    reg memtoreg_in;
    reg branch_in;
    reg jump_in;
    
    // Data inputs
    reg [31:0] read_data1_in;
    reg [31:0] read_data2_in;
    reg [31:0] imm_in;
    reg [31:0] pc_in;
    
    // Register addresses
    reg [4:0] rs1_in;
    reg [4:0] rs2_in;
    reg [4:0] rd_in;
    
    // Function codes
    reg [2:0] funct3_in;
    reg [6:0] funct7_in;
    
    // Control signals output
    wire regwrite_out;
    wire alusrc_out;
    wire memread_out;
    wire memwrite_out;
    wire memtoreg_out;
    wire branch_out;
    wire jump_out;
    
    // Data outputs
    wire [31:0] read_data1_out;
    wire [31:0] read_data2_out;
    wire [31:0] imm_out;
    wire [31:0] pc_out;
    
    // Register addresses
    wire [4:0] rs1_out;
    wire [4:0] rs2_out;
    wire [4:0] rd_out;
    
    // Function codes
    wire [2:0] funct3_out;
    wire [6:0] funct7_out;

    // Instantiate UUT
    PIPELINE_REG_ID_EX uut (
        .clock(clock),
        .reset(reset),
        .flush(flush),
        .stall(stall),
        .regwrite_in(regwrite_in),
        .alusrc_in(alusrc_in),
        .memread_in(memread_in),
        .memwrite_in(memwrite_in),
        .memtoreg_in(memtoreg_in),
        .branch_in(branch_in),
        .jump_in(jump_in),
        .read_data1_in(read_data1_in),
        .read_data2_in(read_data2_in),
        .imm_in(imm_in),
        .pc_in(pc_in),
        .rs1_in(rs1_in),
        .rs2_in(rs2_in),
        .rd_in(rd_in),
        .funct3_in(funct3_in),
        .funct7_in(funct7_in),
        .regwrite_out(regwrite_out),
        .alusrc_out(alusrc_out),
        .memread_out(memread_out),
        .memwrite_out(memwrite_out),
        .memtoreg_out(memtoreg_out),
        .branch_out(branch_out),
        .jump_out(jump_out),
        .read_data1_out(read_data1_out),
        .read_data2_out(read_data2_out),
        .imm_out(imm_out),
        .pc_out(pc_out),
        .rs1_out(rs1_out),
        .rs2_out(rs2_out),
        .rd_out(rd_out),
        .funct3_out(funct3_out),
        .funct7_out(funct7_out)
    );

    // Clock generation
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end

    // Helper task to set control signals
    task set_control_signals;
        input rw, alu, mr, mw, m2r, br, jp;
        begin
            regwrite_in = rw;
            alusrc_in = alu;
            memread_in = mr;
            memwrite_in = mw;
            memtoreg_in = m2r;
            branch_in = br;
            jump_in = jp;
        end
    endtask

    // Helper task to set data
    task set_data;
        input [31:0] rd1, rd2, imm, pc;
        input [4:0] rs1, rs2, rd;
        input [2:0] f3;
        input [6:0] f7;
        begin
            read_data1_in = rd1;
            read_data2_in = rd2;
            imm_in = imm;
            pc_in = pc;
            rs1_in = rs1;
            rs2_in = rs2;
            rd_in = rd;
            funct3_in = f3;
            funct7_in = f7;
        end
    endtask

    // Test scenarios
    initial begin
        $display("=== Testbench for PIPELINE_REG_ID_EX ===\n");
        
        // Initialize
        reset = 0;
        flush = 0;
        stall = 0;
        set_control_signals(0, 0, 0, 0, 0, 0, 0);
        set_data(0, 0, 0, 0, 0, 0, 0, 0, 0);

        // Test 1: Reset
        $display("Test 1: Reset");
        reset = 1;
        set_control_signals(1, 1, 1, 1, 1, 1, 1);
        set_data(32'hAAAAAAAA, 32'hBBBBBBBB, 32'hCCCCCCCC, 32'h00000100, 5'd10, 5'd11, 5'd12, 3'd5, 7'd60);
        #10;
        if (regwrite_out == 0 && memread_out == 0 && memwrite_out == 0 && 
            read_data1_out == 0 && pc_out == 0 && rd_out == 0)
            $display("✓ PASS - All outputs cleared\n");
        else
            $display("✗ FAIL - Outputs not cleared properly\n");
        reset = 0;

        // Test 2: Normal operation - ADD instruction
        $display("Test 2: Normal operation - ADD instruction");
        set_control_signals(1, 0, 0, 0, 0, 0, 0); // regwrite=1, rest=0
        set_data(32'h00000010, 32'h00000020, 32'h00000000, 32'h00000004, 5'd1, 5'd2, 5'd3, 3'd0, 7'd0);
        #10;
        if (regwrite_out == 1 && alusrc_out == 0 && read_data1_out == 32'h00000010 && 
            read_data2_out == 32'h00000020 && rd_out == 5'd3)
            $display("✓ PASS - ADD instruction propagated correctly\n");
        else
            $display("✗ FAIL\n");

        // Test 3: Load instruction
        $display("Test 3: Load instruction");
        set_control_signals(1, 1, 1, 0, 1, 0, 0); // regwrite, alusrc, memread, memtoreg
        set_data(32'h00001000, 32'h00000000, 32'h00000100, 32'h00000008, 5'd5, 5'd0, 5'd6, 3'd2, 7'd0);
        #10;
        if (regwrite_out == 1 && alusrc_out == 1 && memread_out == 1 && 
            memtoreg_out == 1 && imm_out == 32'h00000100)
            $display("✓ PASS - Load instruction signals correct\n");
        else
            $display("✗ FAIL\n");

        // Test 4: Store instruction
        $display("Test 4: Store instruction");
        set_control_signals(0, 1, 0, 1, 0, 0, 0); // alusrc, memwrite
        set_data(32'h00002000, 32'h12345678, 32'h00000200, 32'h0000000C, 5'd7, 5'd8, 5'd0, 3'd2, 7'd0);
        #10;
        if (regwrite_out == 0 && alusrc_out == 1 && memwrite_out == 1 && 
            read_data2_out == 32'h12345678 && imm_out == 32'h00000200)
            $display("✓ PASS - Store instruction signals correct\n");
        else
            $display("✗ FAIL\n");

        // Test 5: Branch instruction
        $display("Test 5: Branch instruction");
        set_control_signals(0, 0, 0, 0, 0, 1, 0); // branch
        set_data(32'h00000030, 32'h00000030, 32'h00000010, 32'h00000010, 5'd9, 5'd10, 5'd0, 3'd0, 7'd0);
        #10;
        if (branch_out == 1 && jump_out == 0 && read_data1_out == 32'h00000030)
            $display("✓ PASS - Branch instruction correct\n");
        else
            $display("✗ FAIL\n");

        // Test 6: Jump instruction
        $display("Test 6: Jump instruction");
        set_control_signals(1, 0, 0, 0, 0, 0, 1); // regwrite, jump
        set_data(32'h00000000, 32'h00000000, 32'h00001000, 32'h00000014, 5'd0, 5'd0, 5'd1, 3'd0, 7'd0);
        #10;
        if (jump_out == 1 && regwrite_out == 1 && imm_out == 32'h00001000)
            $display("✓ PASS - Jump instruction correct\n");
        else
            $display("✗ FAIL\n");

        // Test 7: Stall
        $display("Test 7: Stall");
        stall = 1;
        set_control_signals(0, 1, 1, 1, 1, 1, 1);
        set_data(32'hFFFFFFFF, 32'hEEEEEEEE, 32'hDDDDDDDD, 32'h00000018, 5'd20, 5'd21, 5'd22, 3'd7, 7'd127);
        #10;
        if (jump_out == 1 && regwrite_out == 1 && imm_out == 32'h00001000 && 
            read_data1_out != 32'hFFFFFFFF)
            $display("✓ PASS - Stall holds previous values\n");
        else
            $display("✗ FAIL\n");
        stall = 0;

        // Test 8: Flush
        $display("Test 8: Flush");
        #10; // Let previous data propagate
        flush = 1;
        set_control_signals(1, 1, 1, 1, 1, 1, 1);
        set_data(32'h99999999, 32'h88888888, 32'h77777777, 32'h0000001C, 5'd25, 5'd26, 5'd27, 3'd6, 7'd100);
        #10;
        if (regwrite_out == 0 && memread_out == 0 && memwrite_out == 0 && 
            branch_out == 0 && jump_out == 0)
            $display("✓ PASS - Flush clears control signals (NOP)\n");
        else
            $display("✗ FAIL\n");
        flush = 0;

        // Test 9: Sequential instructions
        $display("Test 9: Sequential instructions");
        // Instruction 1
        set_control_signals(1, 0, 0, 0, 0, 0, 0);
        set_data(32'h00000001, 32'h00000002, 32'h00000000, 32'h00000000, 5'd1, 5'd2, 5'd3, 3'd0, 7'd0);
        #10;
        $display("  Instr 1: rd=%d, data1=0x%h, data2=0x%h", rd_out, read_data1_out, read_data2_out);
        
        // Instruction 2
        set_control_signals(1, 1, 1, 0, 1, 0, 0);
        set_data(32'h00001000, 32'h00000000, 32'h00000004, 32'h00000004, 5'd4, 5'd0, 5'd5, 3'd2, 7'd0);
        #10;
        $display("  Instr 2: rd=%d, data1=0x%h, imm=0x%h, memread=%b", rd_out, read_data1_out, imm_out, memread_out);
        
        // Instruction 3
        set_control_signals(0, 1, 0, 1, 0, 0, 0);
        set_data(32'h00002000, 32'hDEADBEEF, 32'h00000008, 32'h00000008, 5'd6, 5'd7, 5'd0, 3'd2, 7'd0);
        #10;
        $display("  Instr 3: data2=0x%h, imm=0x%h, memwrite=%b", read_data2_out, imm_out, memwrite_out);
        
        if (memwrite_out == 1 && read_data2_out == 32'hDEADBEEF)
            $display("✓ PASS - Sequential instructions work correctly\n");
        else
            $display("✗ FAIL\n");

        // Test 10: Stall then Resume
        $display("Test 10: Stall then Resume");
        set_control_signals(1, 0, 0, 0, 0, 0, 0);
        set_data(32'h00000050, 32'h00000060, 32'h00000000, 32'h0000000C, 5'd10, 5'd11, 5'd12, 3'd0, 7'd0);
        #10;
        $display("  Before stall: rd=%d, data1=0x%h", rd_out, read_data1_out);
        
        stall = 1;
        set_control_signals(0, 1, 1, 1, 1, 1, 1);
        set_data(32'hAAAAAAAA, 32'hBBBBBBBB, 32'hCCCCCCCC, 32'h00000010, 5'd20, 5'd21, 5'd22, 3'd5, 7'd60);
        #10;
        $display("  During stall: rd=%d, data1=0x%h (should be same)", rd_out, read_data1_out);
        
        stall = 0;
        #10;
        $display("  After stall: rd=%d, data1=0x%h (should be new)", rd_out, read_data1_out);
        
        if (rd_out == 5'd22 && read_data1_out == 32'hAAAAAAAA)
            $display("✓ PASS - Stall/resume works correctly\n");
        else
            $display("✗ FAIL\n");

        $display("=== All tests completed ===");
        #20;
        $finish;
    end

    // Dump waveform
    initial begin
        $dumpfile("tb_PIPELINE_REG_ID_EX.vcd");
        $dumpvars(0, tb_PIPELINE_REG_ID_EX);
    end

endmodule