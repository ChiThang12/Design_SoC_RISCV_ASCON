// ============================================================================
// Comprehensive Debug Testbench for RISC-V SoC
// ============================================================================
`timescale 1ns / 1ps
`define TESTBENCH_MODE
`include "riscv_soc_top.v"

module tb_riscv_soc_comprehensive_debug;

    // ========================================================================
    // Clock and Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // ========================================================================
    // DUT Signals
    // ========================================================================
    wire [31:0] pc_current;
    wire [31:0] instruction_current;
    
    // IMEM AXI signals
    wire        S_AXI_IMEM_ARVALID;
    wire        S_AXI_IMEM_ARREADY;
    wire [31:0] S_AXI_IMEM_ARADDR;
    wire        S_AXI_IMEM_RVALID;
    wire        S_AXI_IMEM_RREADY;
    wire [31:0] S_AXI_IMEM_RDATA;
    
    // DMEM AXI signals
    wire        S_AXI_DMEM_AWVALID;
    wire        S_AXI_DMEM_AWREADY;
    wire [31:0] S_AXI_DMEM_AWADDR;
    wire        S_AXI_DMEM_WVALID;
    wire        S_AXI_DMEM_WREADY;
    wire [31:0] S_AXI_DMEM_WDATA;
    wire        S_AXI_DMEM_ARVALID;
    wire        S_AXI_DMEM_ARREADY;
    wire [31:0] S_AXI_DMEM_ARADDR;
    wire        S_AXI_DMEM_RVALID;
    wire        S_AXI_DMEM_RREADY;
    wire [31:0] S_AXI_DMEM_RDATA;
    
    // ========================================================================
    // Testbench Variables
    // ========================================================================
    integer cycle_count;
    integer i;
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    riscv_soc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .pc_current(pc_current),
        .instruction_current(instruction_current),
        
        .S_AXI_IMEM_ARVALID(S_AXI_IMEM_ARVALID),
        .S_AXI_IMEM_ARREADY(S_AXI_IMEM_ARREADY),
        .S_AXI_IMEM_ARADDR(S_AXI_IMEM_ARADDR),
        .S_AXI_IMEM_RVALID(S_AXI_IMEM_RVALID),
        .S_AXI_IMEM_RREADY(S_AXI_IMEM_RREADY),
        .S_AXI_IMEM_RDATA(S_AXI_IMEM_RDATA),
        
        .S_AXI_DMEM_AWVALID(S_AXI_DMEM_AWVALID),
        .S_AXI_DMEM_AWREADY(S_AXI_DMEM_AWREADY),
        .S_AXI_DMEM_AWADDR(S_AXI_DMEM_AWADDR),
        .S_AXI_DMEM_WVALID(S_AXI_DMEM_WVALID),
        .S_AXI_DMEM_WREADY(S_AXI_DMEM_WREADY),
        .S_AXI_DMEM_WDATA(S_AXI_DMEM_WDATA),
        .S_AXI_DMEM_ARVALID(S_AXI_DMEM_ARVALID),
        .S_AXI_DMEM_ARREADY(S_AXI_DMEM_ARREADY),
        .S_AXI_DMEM_ARADDR(S_AXI_DMEM_ARADDR),
        .S_AXI_DMEM_RVALID(S_AXI_DMEM_RVALID),
        .S_AXI_DMEM_RREADY(S_AXI_DMEM_RREADY),
        .S_AXI_DMEM_RDATA(S_AXI_DMEM_RDATA)
    );
    
    // ========================================================================
    // Additional internal signals for deep debug
    // ========================================================================
    wire        imem_ready = dut.imem_ready;
    wire        dmem_ready = dut.dmem_ready;
    wire        dmem_valid = dut.dmem_valid;
    wire        dmem_we = dut.dmem_we;
    wire        stall = dut.u_datapath.stall;
    
    // DMEM AXI Response channels
    wire        S_AXI_DMEM_BVALID;
    wire        S_AXI_DMEM_BREADY;
    wire [1:0]  S_AXI_DMEM_BRESP;
    
    // Connect to internal signals
    assign S_AXI_DMEM_BVALID = dut.S1_AXI_BVALID;
    assign S_AXI_DMEM_BREADY = dut.S1_AXI_BREADY;
    assign S_AXI_DMEM_BRESP = dut.S1_AXI_BRESP;
    
    // ========================================================================
    // Clock Generation: 100MHz (10ns period)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // Cycle Counter
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    // ========================================================================
    // Load Test Program
    // ========================================================================
    initial begin
        #1;
        $display("\n========================================");
        $display("Loading Test Program into IMEM");
        $display("========================================");
        
        dut.u_imem.imem.memory[0] = 32'h00A00093;  // addi x1, x0, 10
        dut.u_imem.imem.memory[1] = 32'h01400113;  // addi x2, x0, 20
        dut.u_imem.imem.memory[2] = 32'h002081B3;  // add x3, x1, x2
        dut.u_imem.imem.memory[3] = 32'h00302023;  // sw x3, 0(x0)
        dut.u_imem.imem.memory[4] = 32'h00002203;  // lw x4, 0(x0)
        dut.u_imem.imem.memory[5] = 32'h00520293;  // addi x5, x4, 5
        dut.u_imem.imem.memory[6] = 32'h00502223;  // sw x5, 4(x0)
        dut.u_imem.imem.memory[7] = 32'h00000063;  // beq x0, x0, 0
        
        $display("Program loaded successfully");
        $display("========================================\n");
    end
    
    // ========================================================================
    // Comprehensive Monitoring
    // ========================================================================
    
    // Monitor 1: Basic CPU state every cycle
    always @(posedge clk) begin
        if (rst_n && cycle_count < 120) begin
            $display("[%3d] PC=%08h INSTR=%08h | x1=%2d x2=%2d x3=%2d x4=%2d x5=%2d | stall=%b imem_rdy=%b dmem_rdy=%b dmem_val=%b dmem_we=%b",
                     cycle_count, pc_current, instruction_current,
                     dut.u_datapath.register_file.registers[1],
                     dut.u_datapath.register_file.registers[2],
                     dut.u_datapath.register_file.registers[3],
                     dut.u_datapath.register_file.registers[4],
                     dut.u_datapath.register_file.registers[5],
                     stall, imem_ready, dmem_ready, dmem_valid, dmem_we);
        end
    end
    
    // Monitor 2: IMEM AXI transactions
    always @(posedge clk) begin
        if (rst_n && cycle_count < 120) begin
            if (S_AXI_IMEM_ARVALID || S_AXI_IMEM_RVALID) begin
                $display("      [IMEM] AR[v=%b r=%b a=%08h] R[v=%b r=%b d=%08h]",
                         S_AXI_IMEM_ARVALID, S_AXI_IMEM_ARREADY, S_AXI_IMEM_ARADDR,
                         S_AXI_IMEM_RVALID, S_AXI_IMEM_RREADY, S_AXI_IMEM_RDATA);
            end
        end
    end
    
    // Monitor 3: DMEM AXI transactions (DETAILED)
    always @(posedge clk) begin
        if (rst_n && cycle_count < 120) begin
            if (S_AXI_DMEM_AWVALID || S_AXI_DMEM_WVALID || S_AXI_DMEM_BVALID ||
                S_AXI_DMEM_ARVALID || S_AXI_DMEM_RVALID) begin
                $display("      [DMEM] AW[v=%b r=%b a=%08h] W[v=%b r=%b d=%08h] B[v=%b r=%b resp=%b] AR[v=%b r=%b a=%08h] R[v=%b r=%b d=%08h]",
                         S_AXI_DMEM_AWVALID, S_AXI_DMEM_AWREADY, S_AXI_DMEM_AWADDR,
                         S_AXI_DMEM_WVALID, S_AXI_DMEM_WREADY, S_AXI_DMEM_WDATA,
                         S_AXI_DMEM_BVALID, S_AXI_DMEM_BREADY, S_AXI_DMEM_BRESP,
                         S_AXI_DMEM_ARVALID, S_AXI_DMEM_ARREADY, S_AXI_DMEM_ARADDR,
                         S_AXI_DMEM_RVALID, S_AXI_DMEM_RREADY, S_AXI_DMEM_RDATA);
            end
        end
    end
    
    // Monitor 4: DMEM internal state
    always @(posedge clk) begin
        if (rst_n && dut.u_dmem.dmem.memwrite) begin
            $display("      >>> [DMEM MEMORY WRITE] addr=0x%08h data=0x%08h (dec=%0d)",
                     dut.u_dmem.dmem.address,
                     dut.u_dmem.dmem.write_data,
                     dut.u_dmem.dmem.write_data);
        end
        if (rst_n && dut.u_dmem.dmem.memread) begin
            $display("      >>> [DMEM MEMORY READ] addr=0x%08h data=0x%08h (dec=%0d)",
                     dut.u_dmem.dmem.address,
                     dut.u_dmem.dmem.read_data,
                     dut.u_dmem.dmem.read_data);
        end
    end
    
    // Monitor 5: Hazard detection state
    reg prev_stall;
    always @(posedge clk) begin
        if (rst_n) begin
            if (stall && !prev_stall) begin
                $display("      !!! STALL ASSERTED !!!");
            end
            if (!stall && prev_stall) begin
                $display("      !!! STALL RELEASED !!!");
            end
            prev_stall <= stall;
        end else begin
            prev_stall <= 0;
        end
    end
    
    // ========================================================================
    // Test Stimulus
    // ========================================================================
    initial begin
        rst_n = 0;
        cycle_count = 0;
        prev_stall = 0;
        
        $display("\n========================================");
        $display("RISC-V SoC Comprehensive Debug");
        $display("========================================\n");
        
        // Reset
        #20;
        rst_n = 1;
        $display("[Time %0t] Reset released\n", $time);
        
        // Run for 120 cycles
        repeat(120) @(posedge clk);
        
        // Print final state
        $display("\n========================================");
        $display("Final State After 120 Cycles");
        $display("========================================");
        
        $display("\nRegister File:");
        for (i = 0; i < 8; i = i + 1) begin
            $display("  x%0d = %0d (0x%08h)", i,
                     dut.u_datapath.register_file.registers[i],
                     dut.u_datapath.register_file.registers[i]);
        end
        
        $display("\nData Memory (first 16 bytes):");
        for (i = 0; i < 16; i = i + 1) begin
            $display("  DMEM[%2d] = 0x%02h", i, dut.u_dmem.dmem.memory[i]);
        end
        
        $display("\nExpected Results:");
        $display("  x1 = 10, x2 = 20, x3 = 30, x4 = 30, x5 = 35");
        $display("  DMEM[0-3] = 0x1E 0x00 0x00 0x00 (30 in little-endian)");
        $display("  DMEM[4-7] = 0x23 0x00 0x00 0x00 (35 in little-endian)");
        
        $display("\n========================================\n");
        $finish;
    end
    
    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_riscv_soc_comprehensive.vcd");
        $dumpvars(0, tb_riscv_soc_comprehensive_debug);
    end
    
    // ========================================================================
    // Timeout
    // ========================================================================
    initial begin
        #15000;
        $display("\n*** TIMEOUT ***");
        $finish;
    end

endmodule