// ============================================================================
// tb_riscv_soc_top.v - Testbench cho RISC-V SoC với AXI Interconnect
// ============================================================================
// Mô tả:
//   - Test instruction fetch từ IMEM qua AXI
//   - Test data read/write tới DMEM qua AXI
//   - Monitor debug signals
//   - Dump waveform cho GTKWave
// ============================================================================

`timescale 1ns/1ps
`include "riscv_soc_top.v"
module tb_riscv_soc_top;

    // ========================================================================
    // Clock và Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // Clock period = 10ns (100MHz)
    localparam CLK_PERIOD = 10;
    
    // ========================================================================
    // Debug Signals từ SoC
    // ========================================================================
    wire [31:0] debug_pc;
    wire [31:0] debug_instr;
    wire [31:0] debug_alu_result;
    wire [31:0] debug_mem_data;
    wire        debug_branch_taken;
    wire [31:0] debug_branch_target;
    wire        debug_stall;
    wire [1:0]  debug_forward_a;
    wire [1:0]  debug_forward_b;
    
    // ========================================================================
    // DUT - RISC-V SoC
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
    // Clock Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ========================================================================
    // Test Sequence
    // ========================================================================
    initial begin
        // Khởi tạo
        rst_n = 0;
        
        // Wait 3 clock cycles
        repeat(3) @(posedge clk);
        
        // Release reset
        rst_n = 1;
        $display("\n[%0t] Reset released, SoC starting...", $time);
        
        // Chạy 200 clock cycles để observe
        repeat(200) @(posedge clk);
        
        $display("\n[%0t] Simulation completed", $time);
        $finish;
    end
    
    // ========================================================================
    // Monitor PC và Instructions
    // ========================================================================
    integer instr_count;
    
    initial begin
        instr_count = 0;
        
        // Wait for reset release
        @(posedge rst_n);
        
        $display("\n========================================");
        $display("PC Trace:");
        $display("========================================");
        $display("Time\t\tPC\t\tInstruction\tALU Result");
        
        forever begin
            @(posedge clk);
            if (!debug_stall) begin
                $display("%0t\t0x%08h\t0x%08h\t0x%08h", 
                         $time, debug_pc, debug_instr, debug_alu_result);
                instr_count = instr_count + 1;
            end
        end
    end
    
    // ========================================================================
    // Monitor Branch Events with Instruction Decode
    // ========================================================================
    reg [31:0] prev_pc;
    reg branch_detected;
    
    initial begin
        @(posedge rst_n);
        prev_pc = 32'h0;
        branch_detected = 0;
        
        forever begin
            @(posedge clk);
            
            // Detect branch/jump
            if (debug_branch_taken && !debug_stall) begin
                branch_detected = 1;
                $display("\n[%0t] *** BRANCH/JUMP TAKEN ***", $time);
                $display("    From PC:   0x%08h", debug_pc);
                $display("    To Target: 0x%08h", debug_branch_target);
                $display("    Instruction: 0x%08h", debug_instr);
            end
            
            // Monitor PC continuity
            if (!debug_stall && prev_pc != 32'h0) begin
                if (debug_pc != prev_pc + 4 && !branch_detected) begin
                    $display("\n[%0t] WARNING: PC discontinuity without branch!", $time);
                    $display("    Expected: 0x%08h, Got: 0x%08h", prev_pc + 4, debug_pc);
                end
            end
            
            if (!debug_stall) begin
                prev_pc = debug_pc;
                branch_detected = 0;
            end
        end
    end
    
    // ========================================================================
    // Monitor Memory Access (via interconnect) - DETAILED
    // ========================================================================
    reg [31:0] last_if_addr;
    reg [31:0] last_mem_addr;
    integer if_latency_count;
    integer mem_latency_count;
    
    initial begin
        @(posedge rst_n);
        if_latency_count = 0;
        mem_latency_count = 0;
        
        forever begin
            @(posedge clk);
            
            // Monitor instruction fetch with latency tracking
            if (dut.interconnect.M_AXI_ARVALID && 
                dut.interconnect.M_AXI_ARREADY &&
                !dut.interconnect.addr_decode_rd(dut.interconnect.M_AXI_ARADDR)) begin
                last_if_addr = dut.interconnect.M_AXI_ARADDR;
                if_latency_count = 1;
                $display("[%0t] IMEM READ START: addr=0x%08h", 
                         $time, dut.interconnect.M_AXI_ARADDR);
            end
            
            if (dut.interconnect.S0_AXI_RVALID && dut.interconnect.S0_AXI_RREADY) begin
                $display("[%0t] IMEM READ DONE: addr=0x%08h, data=0x%08h, latency=%0d cycles", 
                         $time, last_if_addr, dut.interconnect.S0_AXI_RDATA, if_latency_count);
                if_latency_count = 0;
            end else if (if_latency_count > 0) begin
                if_latency_count = if_latency_count + 1;
            end
            
            // Monitor data read
            if (dut.interconnect.M_AXI_ARVALID && 
                dut.interconnect.M_AXI_ARREADY &&
                dut.interconnect.addr_decode_rd(dut.interconnect.M_AXI_ARADDR)) begin
                last_mem_addr = dut.interconnect.M_AXI_ARADDR;
                mem_latency_count = 1;
                $display("[%0t] DMEM READ START: addr=0x%08h", 
                         $time, dut.interconnect.M_AXI_ARADDR);
            end
            
            if (dut.interconnect.S1_AXI_RVALID && dut.interconnect.S1_AXI_RREADY) begin
                $display("[%0t] DMEM READ DONE: addr=0x%08h, data=0x%08h, latency=%0d cycles", 
                         $time, last_mem_addr, dut.interconnect.S1_AXI_RDATA, mem_latency_count);
                mem_latency_count = 0;
            end else if (mem_latency_count > 0) begin
                mem_latency_count = mem_latency_count + 1;
            end
            
            // Monitor data write
            if (dut.interconnect.M_AXI_AWVALID && 
                dut.interconnect.M_AXI_AWREADY) begin
                $display("[%0t] DMEM WRITE: addr=0x%08h, data=0x%08h, strb=%b", 
                         $time, dut.interconnect.M_AXI_AWADDR,
                         dut.interconnect.M_AXI_WDATA,
                         dut.interconnect.M_AXI_WSTRB);
            end
        end
    end
    
    // ========================================================================
    // Monitor Stalls và Hazards
    // ========================================================================
    initial begin
        @(posedge rst_n);
        
        forever begin
            @(posedge clk);
            if (debug_stall) begin
                $display("[%0t] PIPELINE STALL detected", $time);
            end
            
            if (debug_forward_a != 2'b00) begin
                $display("[%0t] FORWARD_A = %b", $time, debug_forward_a);
            end
            
            if (debug_forward_b != 2'b00) begin
                $display("[%0t] FORWARD_B = %b", $time, debug_forward_b);
            end
        end
    end
    
    // ========================================================================
    // Monitor AXI Protocol Violations
    // ========================================================================
    initial begin
        @(posedge rst_n);
        
        forever begin
            @(posedge clk);
            
            // Check AWVALID và WVALID relationship
            if (dut.interconnect.M_AXI_AWVALID && 
                !dut.interconnect.M_AXI_AWREADY &&
                dut.interconnect.M_AXI_WVALID &&
                !dut.interconnect.M_AXI_WREADY) begin
                // Both waiting - this is OK
            end
            
            // Check for hanging transactions
            if (dut.interconnect.M_AXI_ARVALID && 
                !dut.interconnect.M_AXI_ARREADY) begin
                $display("[%0t] WARNING: Read address channel waiting", $time);
            end
        end
    end
    
    // ========================================================================
    // Performance Counter
    // ========================================================================
    integer cycle_count;
    integer mem_read_count;
    integer mem_write_count;
    integer stall_count;
    
    initial begin
        cycle_count = 0;
        mem_read_count = 0;
        mem_write_count = 0;
        stall_count = 0;
        
        @(posedge rst_n);
        
        forever begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            
            if (debug_stall)
                stall_count = stall_count + 1;
                
            if (dut.interconnect.M_AXI_ARVALID && 
                dut.interconnect.M_AXI_ARREADY &&
                dut.interconnect.addr_decode_rd(dut.interconnect.M_AXI_ARADDR))
                mem_read_count = mem_read_count + 1;
                
            if (dut.interconnect.M_AXI_AWVALID && 
                dut.interconnect.M_AXI_AWREADY)
                mem_write_count = mem_write_count + 1;
        end
    end
    
    // ========================================================================
    // Final Statistics
    // ========================================================================
    initial begin
        @(posedge rst_n);
        
        #(CLK_PERIOD * 200);
        
        $display("\n========================================");
        $display("Simulation Statistics:");
        $display("========================================");
        $display("Total Cycles:        %0d", cycle_count);
        $display("Instructions:        %0d", instr_count);
        $display("Memory Reads:        %0d", mem_read_count);
        $display("Memory Writes:       %0d", mem_write_count);
        $display("Pipeline Stalls:     %0d", stall_count);
        $display("CPI: %.2f", $itor(cycle_count) / $itor(instr_count));

        $display("========================================\n");
    end
    
    // ========================================================================
    // Waveform Dump cho GTKWave
    // ========================================================================
    initial begin
        $dumpfile("riscv_soc.vcd");
        $dumpvars(0, tb_riscv_soc_top);
        
        // Dump deeper hierarchy
        $dumpvars(0, dut.cpu);
        $dumpvars(0, dut.interconnect);
        $dumpvars(0, dut.imem_slave);
        $dumpvars(0, dut.dmem_slave);
    end
    
    // ========================================================================
    // Timeout Protection
    // ========================================================================
    initial begin
        #(CLK_PERIOD * 1000);
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end
    
    // ========================================================================
    // Test Specific Memory Content (Optional)
    // ========================================================================
    initial begin
        // Wait một chút để memory được initialize
        #(CLK_PERIOD * 5);
        
        $display("\n========================================");
        $display("Initial Memory Content:");
        $display("========================================");
        
        // Sample instruction memory
        $display("IMEM[0x00] = 0x%08h", dut.imem_slave.imem.memory[0]);
        $display("IMEM[0x04] = 0x%08h", dut.imem_slave.imem.memory[1]);
        $display("IMEM[0x08] = 0x%08h", dut.imem_slave.imem.memory[2]);
        $display("IMEM[0x0C] = 0x%08h", dut.imem_slave.imem.memory[3]);
        
        $display("\n");
    end

endmodule