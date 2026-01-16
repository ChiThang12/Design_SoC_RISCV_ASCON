// ============================================================================
// tb_riscv_soc_top.v - Testbench cho RISC-V SoC
// ============================================================================

`timescale 1ns/1ps
`include "riscv_soc_top.v"
module tb_riscv_soc_top;

    // ========================================================================
    // Tín hiệu Clock và Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // ========================================================================
    // Debug Signals
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
    // Khởi tạo DUT (Device Under Test)
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
    // Clock Generation - 50MHz (20ns period)
    // ========================================================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    // ========================================================================
    // Test Scenario
    // ========================================================================
    initial begin
        // Khởi tạo waveform dump
        $dumpfile("riscv_soc_tb.vcd");
        $dumpvars(0, tb_riscv_soc_top);
        
        // Header
        $display("========================================");
        $display("  RISC-V SoC Testbench");
        $display("========================================");
        $display("Time: %0t", $time);
        
        // Reset sequence
        rst_n = 0;
        #100;
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        
        // Load test program vào IMEM
        // (Giả sử bạn đã có initial block trong inst_mem_axi_slave)
        $display("[%0t] Starting program execution...", $time);
        
        // Chạy trong 100 cycles
        repeat(100) @(posedge clk);
        
        $display("========================================");
        $display("  Simulation Complete");
        $display("========================================");
        $finish;
    end
    
    // ========================================================================
    // Monitor - Theo dõi hoạt động của CPU
    // ========================================================================
    integer instr_count;
    initial instr_count = 0;
    
    always @(posedge clk) begin
        if (rst_n) begin
            if (!debug_stall) instr_count = instr_count + 1;
            
            $display("[%0t] #%0d PC=%h | Instr=%h | ALU=%h | MemData=%h | Stall=%b | Branch=%b->%h", 
                     $time, instr_count, debug_pc, debug_instr, debug_alu_result, 
                     debug_mem_data, debug_stall, debug_branch_taken, debug_branch_target);
            
            // Hiển thị forwarding info nếu có
            if (debug_forward_a != 2'b00 || debug_forward_b != 2'b00) begin
                $display("       Forwarding: A=%b, B=%b", debug_forward_a, debug_forward_b);
            end
            
            // Warning nếu stall quá lâu
            if (debug_stall && instr_count > 5) begin
                $display("       WARNING: Pipeline stalled for extended period!");
            end
        end
    end
    
    // ========================================================================
    // AXI Transaction Monitor (hierarchical access)
    // ========================================================================
    reg write_in_progress;
    initial write_in_progress = 0;
    
    always @(posedge clk) begin
        if (rst_n) begin
            // Monitor AXI Read
            if (dut.m_axi_arvalid && dut.m_axi_arready) begin
                $display("       [AXI-AR] Read Request: addr=0x%h", dut.m_axi_araddr);
            end
            if (dut.m_axi_rvalid && dut.m_axi_rready) begin
                $display("       [AXI-R]  Read Response: data=0x%h, resp=%b", dut.m_axi_rdata, dut.m_axi_rresp);
            end
            
            // Monitor AXI Write with detailed state tracking
            if (dut.m_axi_awvalid && dut.m_axi_awready) begin
                $display("       [AXI-AW] ✅ Write Address Accepted: addr=0x%h", dut.m_axi_awaddr);
                write_in_progress = 1;
            end
            
            if (dut.m_axi_wvalid && dut.m_axi_wready) begin
                $display("       [AXI-W]  ✅ Write Data Accepted: data=0x%h, strb=%b", dut.m_axi_wdata, dut.m_axi_wstrb);
            end
            
            if (dut.m_axi_bvalid && dut.m_axi_bready) begin
                $display("       [AXI-B]  ✅ Write Response: resp=%b", dut.m_axi_bresp);
                if (dut.m_axi_bresp != 2'b00) begin
                    $display("       ⚠️  ERROR: Write failed with BRESP=%b (2'b10=SLVERR)", dut.m_axi_bresp);
                end
                write_in_progress = 0;
            end
            
            // Detect stuck write transactions
            if (write_in_progress) begin
                if (!dut.m_axi_wvalid && !dut.m_axi_awvalid) begin
                    $display("       ⚠️  WAITING: WVALID=%b, AWVALID=%b, BVALID=%b", 
                             dut.m_axi_wvalid, dut.m_axi_awvalid, dut.m_axi_bvalid);
                end
            end
        end
    end
    
    // ========================================================================
    // Watchdog Timer - Ngăn simulation chạy mãi
    // ========================================================================
    initial begin
        #100000; // Timeout sau 100us
        $display("ERROR: Simulation timeout!");
        $finish;
    end
    
    // ========================================================================
    // Memory Initialization Info
    // ========================================================================
    initial begin
        // Đợi reset
        @(posedge rst_n);
        #1;
        
        // Program được load từ memory/program.hex
        $display("[%0t] Test program loaded from memory/program.hex", $time);
        $display("       IMEM content:");
        $display("       [0x00] = 0x%08h", dut.imem_slave.imem.memory[0]);
        $display("       [0x04] = 0x%08h", dut.imem_slave.imem.memory[1]);
        $display("       [0x08] = 0x%08h", dut.imem_slave.imem.memory[2]);
        $display("       [0x0C] = 0x%08h", dut.imem_slave.imem.memory[3]);
        $display("       [0x10] = 0x%08h", dut.imem_slave.imem.memory[4]);
    end
    
    // ========================================================================
    // Register File Monitor (Optional - nếu có access)
    // ========================================================================
    // always @(posedge clk) begin
    //     if (dut.cpu.regfile.wen && rst_n) begin
    //         $display("       RegWrite: x%0d <= %h", 
    //                  dut.cpu.regfile.waddr, dut.cpu.regfile.wdata);
    //     end
    // end

endmodule