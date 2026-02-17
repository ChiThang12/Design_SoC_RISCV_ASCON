// ============================================================================
// tb_riscv_cpu_debug.v - Debug Testbench for Stall Behavior
// ============================================================================
`include "cpu/riscv_cpu_core_v1.v"
`timescale 1ns/1ps

module tb_riscv_cpu_debug;

    reg clk;
    reg rst;
    
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
    riscv_cpu_core dut (
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

    // Instruction Memory
    reg [31:0] imem [0:31];
     integer i;
    initial begin
       
        for (i = 0; i < 32; i = i + 1) begin
            imem[i] = 32'h00000013; // NOP
        end
        
        // Simple test: consecutive ADDs that should show stall issue
        imem[0]  = 32'h00500093; // ADDI x1, x0, 5      x1 = 5
        imem[1]  = 32'h00A00113; // ADDI x2, x0, 10     x2 = 10
        imem[2]  = 32'h002081B3; // ADD  x3, x1, x2     x3 = 15
        imem[3]  = 32'h00300213; // ADDI x4, x0, 3      x4 = 3
        imem[4]  = 32'h004182B3; // ADD  x5, x3, x4     x5 = 18 (depends on x3)
        imem[5]  = 32'h00500313; // ADDI x6, x0, 5      x6 = 5
        imem[6]  = 32'h00628393; // ADD  x7, x5, x6     x7 = 23 (depends on x5)
        imem[7]  = 32'h0000006F; // JAL  x0, 0          Loop
    end
    
    // Instruction memory logic
    always @(*) begin
        if (imem_valid) begin
            imem_rdata = imem[imem_addr[31:2]];
            imem_ready = 1'b1;
        end else begin
            imem_rdata = 32'h00000013;
            imem_ready = 1'b0;
        end
    end

    // Data Memory (simple)
    reg [31:0] dmem [0:255];
    integer j;
    initial begin
        
        for (j = 0; j < 256; j = j + 1) begin
            dmem[j] = 32'h0;
        end
    end
    
    always @(posedge clk) begin
        if (rst) begin
            dmem_ready <= 1'b0;
        end else if (dmem_valid) begin
            dmem_ready <= 1'b1;
            if (dmem_we) begin
                if (dmem_wstrb[0]) dmem[dmem_addr[31:2]][7:0]   <= dmem_wdata[7:0];
                if (dmem_wstrb[1]) dmem[dmem_addr[31:2]][15:8]  <= dmem_wdata[15:8];
                if (dmem_wstrb[2]) dmem[dmem_addr[31:2]][23:16] <= dmem_wdata[23:16];
                if (dmem_wstrb[3]) dmem[dmem_addr[31:2]][31:24] <= dmem_wdata[31:24];
            end else begin
                dmem_rdata <= dmem[dmem_addr[31:2]];
            end
        end else begin
            dmem_ready <= 1'b0;
        end
    end

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test
    initial begin
        rst = 1;
        
        $dumpfile("riscv_cpu_debug.vcd");
        $dumpvars(0, tb_riscv_cpu_debug);
        
        #20;
        rst = 0;
        
        #500;
        
        $display("\n========================================");
        $display("Register File Contents:");
        $display("========================================");
        $display("x1  = 0x%08h (expected: 0x00000005)", dut.register_file.registers[1]);
        $display("x2  = 0x%08h (expected: 0x0000000A)", dut.register_file.registers[2]);
        $display("x3  = 0x%08h (expected: 0x0000000F)", dut.register_file.registers[3]);
        $display("x4  = 0x%08h (expected: 0x00000003)", dut.register_file.registers[4]);
        $display("x5  = 0x%08h (expected: 0x00000012)", dut.register_file.registers[5]);
        $display("x6  = 0x%08h (expected: 0x00000005)", dut.register_file.registers[6]);
        $display("x7  = 0x%08h (expected: 0x00000017)", dut.register_file.registers[7]);
        
        $finish;
    end

    // Monitor critical signals
    always @(posedge clk) begin
        if (!rst) begin
            $display("T=%0t PC=%08h Instr=%08h | stall=%b | EX: alu=%08h rs1=%d rs2=%d fwdA=%d fwdB=%d | MEM: alu=%08h rd=%d wr=%b | WB: alu=%08h rd=%d wr=%b wdata=%08h", 
                     $time, dut.pc_if, dut.instr_if,
                     dut.stall,
                     dut.alu_result_ex, dut.rs1_ex, dut.rs2_ex, dut.forward_a, dut.forward_b,
                     dut.alu_result_mem, dut.rd_mem, dut.regwrite_mem,
                     dut.alu_result_wb, dut.rd_wb, dut.regwrite_wb, dut.write_back_data_wb);
            
            // Debug register writes
            if (dut.regwrite_wb && dut.rd_wb != 0) begin
                $display("         >>> WRITE: x%0d = 0x%08h", dut.rd_wb, dut.write_back_data_wb);
            end
        end
    end

endmodule