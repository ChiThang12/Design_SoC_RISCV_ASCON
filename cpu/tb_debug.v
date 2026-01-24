// ============================================================================
// riscv_soc_tb_debug.v - Enhanced Debug Testbench for RISC-V SoC
// ============================================================================
// Tối ưu để debug pipeline, branch, hazard, AXI, memory access
// ============================================================================

`timescale 1ns / 1ps
`include "riscv_soc_top.v"

module riscv_soc_tb_debug;

    // ========================================================================
    // Signals
    // ========================================================================
    reg         clk;
    reg         rst_n;
    integer     cycle_count = 0;
    integer     max_cycles  = 1000;     // Giới hạn để tránh chạy mãi

    // ========================================================================
    // Clock & Reset
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;          // 100 MHz
    end

    // ========================================================================
    // DUT
    // ========================================================================
    riscv_soc_top soc (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // ========================================================================
    // Waveform dump
    // ========================================================================
    initial begin
        $dumpfile("riscv_soc_debug.vcd");
        $dumpvars(0, riscv_soc_tb_debug);
    end

    // ========================================================================
    // Cycle Counter & Basic Monitor
    // ========================================================================
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;

        // In PC mỗi cycle (có thể comment nếu quá nhiều)
        // $display("[C%4d] PC_IF = 0x%08h  Instr_IF = 0x%08h", cycle_count, soc.cpu.pc_if, soc.cpu.instr_if);

        // Dừng nếu chạy quá lâu
        if (cycle_count > max_cycles) begin
            $display("\n[TIMEOUT] Simulation exceeded %0d cycles!", max_cycles);
            display_final_registers();
            $finish;
        end
    end

    // ========================================================================
    // Enhanced Monitors (chỉ in khi có sự kiện quan trọng)
    // ========================================================================
    // 1. Write-back monitor
    always @(posedge clk) begin
        if (rst_n && soc.cpu.regwrite_wb && soc.cpu.rd_wb != 0) begin
            $display("[C%4d] WB: x%02d <= 0x%08h   (from %s)",
                cycle_count, soc.cpu.rd_wb, soc.cpu.write_back_data_wb,
                (soc.cpu.mem_to_reg_wb) ? "MEMORY" : "ALU");
        end
    end

    // 2. Branch / Jump monitor
    always @(posedge clk) begin
        if (rst_n) begin
            if (soc.cpu.pc_src == 1'b1) begin   // Giả sử pc_src = 1 khi branch taken hoặc jump
                $display("[C%4d] CONTROL FLOW: PC <= 0x%08h  (branch/jal taken from 0x%08h)",
                    cycle_count, soc.cpu.pc_if, soc.cpu.pc_id); // pc_id là PC của lệnh branch
            end
        end
    end

    // 3. AXI IMEM (Fetch) monitor
    always @(posedge clk) begin
        if (rst_n) begin
            if (soc.imem_m_axi_arvalid && soc.imem_m_axi_arready)
                $display("[C%4d] IMEM FETCH REQ  Addr=0x%08h", cycle_count, soc.imem_m_axi_araddr);

            if (soc.imem_m_axi_rvalid && soc.imem_m_axi_rready) begin
                if (soc.imem_m_axi_rdata === 32'hx)
                    $display("[C%4d] IMEM FETCH ERR  X-state @ Addr=0x%08h", cycle_count, soc.imem_m_axi_araddr);
                else
                    $display("[C%4d] IMEM FETCH OK   Addr=0x%08h  Instr=0x%08h",
                        cycle_count, soc.imem_m_axi_araddr, soc.imem_m_axi_rdata);
            end
        end
    end

    // 4. DMEM transactions
    always @(posedge clk) begin
        if (rst_n) begin
            if (soc.dmem_m_axi_awvalid && soc.dmem_m_axi_awready)
                $display("[C%4d] DMEM WRITE REQ  Addr=0x%08h  Data=0x%08h  Strb=%b",
                    cycle_count, soc.dmem_m_axi_awaddr, soc.dmem_m_axi_wdata, soc.dmem_m_axi_wstrb);

            if (soc.dmem_m_axi_arvalid && soc.dmem_m_axi_arready)
                $display("[C%4d] DMEM READ  REQ   Addr=0x%08h", cycle_count, soc.dmem_m_axi_araddr);

            if (soc.dmem_m_axi_rvalid && soc.dmem_m_axi_rready)
                $display("[C%4d] DMEM READ  RSP   Addr=0x%08h  Data=0x%08h",
                    cycle_count, soc.dmem_m_axi_araddr, soc.dmem_m_axi_rdata);
        end
    end

    // ========================================================================
    // Test Sequence
    // ========================================================================
    initial begin
        // Khởi tạo
        rst_n = 0;
        #20;
        rst_n = 1;
        $display("\n======================================");
        $display(" RISC-V SoC Debug Simulation Started ");
        $display("======================================\n");
        $display("[INFO] Reset released at cycle %0d", cycle_count);

        // Chạy đủ lâu để xem chương trình
        wait (cycle_count > 200);   // Hoặc thay bằng điều kiện hoàn thành (ví dụ: PC == địa chỉ end)

        // Kết thúc
        $display("\n======================================");
        $display(" Simulation Completed ");
        $display("======================================\n");

        display_final_registers();
        check_expected_results();

        $finish;
    end

    // ========================================================================
    // Tasks hỗ trợ debug
    // ========================================================================
    task display_final_registers;
        begin
            $display("Final Register File:");
            $display("--------------------------------------");
            $display(" x1  = 0x%08h", soc.cpu.register_file.registers[1]);
            $display(" x2  = 0x%08h", soc.cpu.register_file.registers[2]);
            $display(" x3  = 0x%08h", soc.cpu.register_file.registers[3]);
            $display(" x4  = 0x%08h", soc.cpu.register_file.registers[4]);
            $display(" x5  = 0x%08h", soc.cpu.register_file.registers[5]);
            $display(" x6  = 0x%08h", soc.cpu.register_file.registers[6]);
            $display(" x7  = 0x%08h", soc.cpu.register_file.registers[7]);
            $display(" x8  = 0x%08h", soc.cpu.register_file.registers[8]);
            $display(" x9  = 0x%08h", soc.cpu.register_file.registers[9]);
            $display("x10  = 0x%08h", soc.cpu.register_file.registers[10]);
            $display("x12  = 0x%08h", soc.cpu.register_file.registers[12]);
            $display("x13  = 0x%08h", soc.cpu.register_file.registers[13]);
            $display("x14  = 0x%08h", soc.cpu.register_file.registers[14]);
            $display("x15  = 0x%08h", soc.cpu.register_file.registers[15]);
            $display("x20  = 0x%08h", soc.cpu.register_file.registers[20]);
            $display("--------------------------------------");
        end
    endtask

    task check_expected_results;
        begin
            $display("\nExpected vs Actual Check:");
            $display("--------------------------------------");
            compare_reg( 1, 32'h0000000a, "x1  (addi 10)");
            compare_reg( 2, 32'h00000014, "x2  (addi 20)");
            compare_reg( 3, 32'h0000001e, "x3  (add)");
            compare_reg( 4, 32'h0000001e, "x4  (lw from mem[0])");
            compare_reg( 5, 32'h00000023, "x5  (addi after lw)");
            $display("--------------------------------------");
        end
    endtask

    task compare_reg;
        input [4:0]  reg_idx;
        input [31:0] expected;
        input string desc;
        begin
            if (soc.cpu.register_file.registers[reg_idx] === expected) begin
                $display("[PASS] %s : 0x%08h", desc, expected);
            end else begin
                $display("[FAIL] %s : expected=0x%08h  actual=0x%08h",
                    desc, expected, soc.cpu.register_file.registers[reg_idx]);
            end
        end
    endtask

endmodule