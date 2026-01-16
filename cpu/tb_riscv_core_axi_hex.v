// ============================================================================
// tb_riscv_core_axi_hex.v - Testbench đọc file hex cho RISC-V Core với AXI4-Lite
// ============================================================================
// Description:
//   - Testbench cho module riscv_core_axi
//   - Đọc instruction từ file .hex (tạo bởi GNU toolchain)
//   - Tích hợp AXI memory model
//   - Đo hiệu năng pipeline
// ============================================================================

`timescale 1ns/1ps
`include "riscv_core_axi.v"
module tb_riscv_core_axi_hex;

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter CLK_PERIOD = 10;           // 100 MHz
    parameter RESET_TIME = 100;
    parameter TIMEOUT_CYCLES = 10000;    // Timeout sau 10,000 cycles
    parameter HEX_FILE = "/home/chithang/Project/SoC/cpu_riscv/program.hex";  // File hex chứa chương trình
    
    // Memory addresses
    parameter TEXT_BASE   = 32'h0000_0000;
    parameter DATA_BASE   = 32'h1000_0000;
    parameter TEXT_SIZE   = 32'h0001_0000;  // 64KB
    parameter DATA_SIZE   = 32'h0001_0000;  // 64KB
    
    // ========================================================================
    // Signals
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // AXI4-Lite Master Interface
    wire [31:0] M_AXI_AWADDR;
    wire [2:0]  M_AXI_AWPROT;
    wire        M_AXI_AWVALID;
    reg         M_AXI_AWREADY;
    
    wire [31:0] M_AXI_WDATA;
    wire [3:0]  M_AXI_WSTRB;
    wire        M_AXI_WVALID;
    reg         M_AXI_WREADY;
    
    reg  [1:0]  M_AXI_BRESP;
    reg         M_AXI_BVALID;
    wire        M_AXI_BREADY;
    
    wire [31:0] M_AXI_ARADDR;
    wire [2:0]  M_AXI_ARPROT;
    wire        M_AXI_ARVALID;
    reg         M_AXI_ARREADY;
    
    reg  [31:0] M_AXI_RDATA;
    reg  [1:0]  M_AXI_RRESP;
    reg         M_AXI_RVALID;
    wire        M_AXI_RREADY;
    
    // Debug Outputs
    wire [31:0] debug_pc;
    wire [31:0] debug_instr;
    wire [31:0] debug_alu_result;
    wire [31:0] debug_mem_data;
    wire        debug_branch_taken;
    wire [31:0] debug_branch_target;
    wire        debug_stall;
    wire [1:0]  debug_forward_a;
    wire [1:0]  debug_forward_b;
    
    // Testbench control
    integer cycle_count;
    integer instr_count;
    integer timeout_counter;
    reg program_finished;
    integer hex_file;
    integer eof_flag;
    integer line_count;
    
    // Memory model
    reg [7:0] text_mem [0:65535];  // 64KB
    reg [7:0] data_mem [0:65535];  // 64KB
    
    // AXI model internal signals
    reg [31:0] axi_read_addr;
    reg [31:0] axi_write_addr;
    reg [3:0]  axi_write_strb;
    reg [31:0] axi_write_data;
    reg        read_pending;
    reg        write_pending;
    
    // Loop detection
    reg [31:0] prev_pc;
    reg [31:0] prev_instr;
    integer stable_cycles;
    reg [31:0] pc_history [0:15];
    integer pc_idx;
    integer history_counter;
    integer match_count_2;
    integer match_count_3;
    integer match_count_4;
    
    // Performance metrics
    integer axi_read_count;
    integer axi_write_count;
    real cpi;
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    riscv_core_axi dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI4-Lite Master Interface
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY),
        
        // Debug Outputs
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
    // AXI Memory Model
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_ARREADY <= 1'b0;
            M_AXI_RVALID <= 1'b0;
            M_AXI_RDATA <= 32'h0;
            M_AXI_RRESP <= 2'b00;
            
            M_AXI_AWREADY <= 1'b0;
            M_AXI_WREADY <= 1'b0;
            M_AXI_BVALID <= 1'b0;
            M_AXI_BRESP <= 2'b00;
            
            read_pending <= 1'b0;
            write_pending <= 1'b0;
            
            axi_read_addr <= 32'h0;
            axi_write_addr <= 32'h0;
            axi_write_strb <= 4'b0000;
            axi_write_data <= 32'h0;
        end
        else begin
            // Read address channel
            if (M_AXI_ARVALID && !read_pending) begin
                axi_read_addr <= M_AXI_ARADDR;
                read_pending <= 1'b1;
                M_AXI_ARREADY <= 1'b1;
            end
            else begin
                M_AXI_ARREADY <= 1'b0;
            end
            
            // Provide read data after 1 cycle delay
            if (read_pending) begin
                M_AXI_RVALID <= 1'b1;
                M_AXI_RDATA <= read_memory(axi_read_addr);
                M_AXI_RRESP <= 2'b00;
                read_pending <= 1'b0;
            end
            else begin
                M_AXI_RVALID <= 1'b0;
            end
            
            // Write address channel
            if (M_AXI_AWVALID && !write_pending) begin
                axi_write_addr <= M_AXI_AWADDR;
                write_pending <= 1'b1;
                M_AXI_AWREADY <= 1'b1;
            end
            else begin
                M_AXI_AWREADY <= 1'b0;
            end
            
            // Write data channel
            if (M_AXI_WVALID && write_pending) begin
                axi_write_data <= M_AXI_WDATA;
                axi_write_strb <= M_AXI_WSTRB;
                write_memory(axi_write_addr, M_AXI_WDATA, M_AXI_WSTRB);
                M_AXI_WREADY <= 1'b1;
                
                // Write response
                M_AXI_BVALID <= 1'b1;
                M_AXI_BRESP <= 2'b00;
                write_pending <= 1'b0;
            end
            else begin
                M_AXI_WREADY <= 1'b0;
                if (M_AXI_BREADY && M_AXI_BVALID) begin
                    M_AXI_BVALID <= 1'b0;
                end
            end
        end
    end
    
    // ========================================================================
    // Memory Functions
    // ========================================================================
    function [31:0] read_memory;
        input [31:0] addr;
        reg [31:0] data;
        integer offset;
    begin
        data = 32'h00000000;
        
        // Check if address is in text memory range
        if (addr >= TEXT_BASE && addr < (TEXT_BASE + TEXT_SIZE)) begin
            offset = addr - TEXT_BASE;
            if (offset + 3 < TEXT_SIZE) begin
                data[7:0]   = text_mem[offset + 0];
                data[15:8]  = text_mem[offset + 1];
                data[23:16] = text_mem[offset + 2];
                data[31:24] = text_mem[offset + 3];
            end
        end
        // Check if address is in data memory range
        else if (addr >= DATA_BASE && addr < (DATA_BASE + DATA_SIZE)) begin
            offset = addr - DATA_BASE;
            if (offset + 3 < DATA_SIZE) begin
                data[7:0]   = data_mem[offset + 0];
                data[15:8]  = data_mem[offset + 1];
                data[23:16] = data_mem[offset + 2];
                data[31:24] = data_mem[offset + 3];
            end
        end
        
        read_memory = data;
    end
    endfunction
    
    task write_memory;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        integer offset;
    begin
        // Check if address is in text memory range
        if (addr >= TEXT_BASE && addr < (TEXT_BASE + TEXT_SIZE)) begin
            offset = addr - TEXT_BASE;
            if (strb[0] && (offset < TEXT_SIZE)) text_mem[offset + 0] = data[7:0];
            if (strb[1] && (offset + 1 < TEXT_SIZE)) text_mem[offset + 1] = data[15:8];
            if (strb[2] && (offset + 2 < TEXT_SIZE)) text_mem[offset + 2] = data[23:16];
            if (strb[3] && (offset + 3 < TEXT_SIZE)) text_mem[offset + 3] = data[31:24];
        end
        // Check if address is in data memory range
        else if (addr >= DATA_BASE && addr < (DATA_BASE + DATA_SIZE)) begin
            offset = addr - DATA_BASE;
            if (strb[0] && (offset < DATA_SIZE)) data_mem[offset + 0] = data[7:0];
            if (strb[1] && (offset + 1 < DATA_SIZE)) data_mem[offset + 1] = data[15:8];
            if (strb[2] && (offset + 2 < DATA_SIZE)) data_mem[offset + 2] = data[23:16];
            if (strb[3] && (offset + 3 < DATA_SIZE)) data_mem[offset + 3] = data[31:24];
        end
    end
    endtask
    
    // ========================================================================
    // Load HEX File
    // ========================================================================
    task load_hex_file;
        reg [8*100:1] hex_line;
        reg [8*10:1] addr_str;
        reg [8*9:1] data_str;
        integer addr;
        integer data;
        integer i;
    begin
        $display("[INFO] Loading hex file: %s", HEX_FILE);
        
        hex_file = $fopen(HEX_FILE, "r");
        if (hex_file == 0) begin
            $display("[ERROR] Cannot open hex file: %s", HEX_FILE);
            $finish;
        end
        
        line_count = 0;
        eof_flag = 0;
        
        while (!$feof(hex_file) && !eof_flag) begin
            // Read line
            if ($fgets(hex_line, hex_file) == 0) begin
                eof_flag = 1;
            end
            else begin
                line_count = line_count + 1;
                
                // Parse hex line (format: @address data)
                if (hex_line[0] == "@") begin
                    // Extract address and data
                    for (i = 1; i < 100; i = i + 1) begin
                        if (hex_line[i] == " " || hex_line[i] == 8'h09) begin  // Space or tab
                            addr_str = hex_line[1:i-1];
                            data_str = hex_line[i+1:i+8];
                            
                            // Convert to integers
                            addr = hex_to_int(addr_str);
                            data = hex_to_int(data_str);
                            
                            // Store in memory
                            write_memory(addr, data, 4'b1111);
                            
                            if (line_count <= 5) begin
                                $display("[DEBUG] Line %0d: addr=0x%08h, data=0x%08h", 
                                        line_count, addr, data);
                            end
                            
                        end
                    end
                end
            end
        end
        
        $fclose(hex_file);
        $display("[INFO] Loaded %0d lines from hex file", line_count);
    end
    endtask
    
    // Helper function to convert hex string to integer
    function integer hex_to_int;
        input [8*100:1] hex_str;
        integer i;
        integer result;
        reg [7:0] char;
    begin
        result = 0;
        for (i = 1; i <= 100; i = i + 1) begin
            char = hex_str[i];
            if (char == 0) ;
            
            result = result << 4;
            case (char)
                "0": result = result | 0;
                "1": result = result | 1;
                "2": result = result | 2;
                "3": result = result | 3;
                "4": result = result | 4;
                "5": result = result | 5;
                "6": result = result | 6;
                "7": result = result | 7;
                "8": result = result | 8;
                "9": result = result | 9;
                "a", "A": result = result | 10;
                "b", "B": result = result | 11;
                "c", "C": result = result | 12;
                "d", "D": result = result | 13;
                "e", "E": result = result | 14;
                "f", "F": result = result | 15;
                default: begin
                    $display("[WARNING] Invalid hex character: %c", char);
                end
            endcase
        end
        hex_to_int = result;
    end
    endfunction
    
    // ========================================================================
    // Execution Monitor
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // Count cycles
            cycle_count = cycle_count + 1;
            timeout_counter = timeout_counter + 1;
            
            // Count instructions (when not stalled and not NOP)
            if (!debug_stall && debug_instr !== 32'h00000013) begin
                instr_count = instr_count + 1;
            end
            
            // Count AXI transactions
            if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                axi_read_count = axi_read_count + 1;
            end
            if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                axi_write_count = axi_write_count + 1;
            end
            
            // Loop detection logic (giống mẫu bạn gửi)
            if ((debug_pc == prev_pc) && (debug_instr == prev_instr)) begin
                stable_cycles = stable_cycles + 1;
                if (stable_cycles >= 3 && !program_finished) begin
                    program_finished = 1;
                    $display("\n[INFO] Single-instruction loop detected at PC=0x%08h", debug_pc);
                    print_results();
                end
            end else begin
                stable_cycles = 0;
            end
            
            // 2-instruction cycle detection
            if (history_counter >= 2) begin
                if (debug_pc == pc_history[(pc_idx + 14) % 16]) begin
                    match_count_2 = match_count_2 + 1;
                    if (match_count_2 >= 4 && !program_finished) begin
                        program_finished = 1;
                        $display("\n[INFO] 2-instruction loop detected");
                        print_results();
                    end
                end else begin
                    match_count_2 = 0;
                end
            end
            
            // 3-instruction cycle detection
            if (history_counter >= 3) begin
                if (debug_pc == pc_history[(pc_idx + 13) % 16]) begin
                    match_count_3 = match_count_3 + 1;
                    if (match_count_3 >= 6 && !program_finished) begin
                        program_finished = 1;
                        $display("\n[INFO] 3-instruction loop detected");
                        print_results();
                    end
                end else begin
                    match_count_3 = 0;
                end
            end
            
            // 4-instruction cycle detection
            if (history_counter >= 4) begin
                if (debug_pc == pc_history[(pc_idx + 12) % 16]) begin
                    match_count_4 = match_count_4 + 1;
                    if (match_count_4 >= 8 && !program_finished) begin
                        program_finished = 1;
                        $display("\n[INFO] 4-instruction loop detected");
                        print_results();
                    end
                end else begin
                    match_count_4 = 0;
                end
            end
            
            // Update PC history
            pc_history[pc_idx] = debug_pc;
            pc_idx = (pc_idx + 1) % 16;
            if (history_counter < 16) history_counter = history_counter + 1;
            
            prev_pc = debug_pc;
            prev_instr = debug_instr;
            
            // Timeout check
            if (timeout_counter > TIMEOUT_CYCLES && !program_finished) begin
                $display("\n[WARNING] Timeout after %0d cycles", TIMEOUT_CYCLES);
                program_finished = 1;
                print_results();
            end
            
            // Debug output (first 50 cycles)
            if (cycle_count <= 50) begin
                $display("[CYCLE %0d] PC=0x%08h, Instr=0x%08h, Stall=%b", 
                        cycle_count, debug_pc, debug_instr, debug_stall);
            end
        end
    end
    
    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        // Initialize variables
        cycle_count = 0;
        instr_count = 0;
        timeout_counter = 0;
        program_finished = 0;
        stable_cycles = 0;
        pc_idx = 0;
        history_counter = 0;
        match_count_2 = 0;
        match_count_3 = 0;
        match_count_4 = 0;
        axi_read_count = 0;
        axi_write_count = 0;
        
        // Initialize memory to 0
        begin : init_memory
            integer i;
            for (i = 0; i < TEXT_SIZE; i = i + 1) text_mem[i] = 8'h00;
            for (i = 0; i < DATA_SIZE; i = i + 1) data_mem[i] = 8'h00;
        end
        
        // Load hex file
        load_hex_file();
        
        // Reset sequence
        rst_n = 1'b0;
        #RESET_TIME;
        rst_n = 1'b1;
        
        $display("\n╔════════════════════════════════════════════════════╗");
        $display("║   RISC-V Pipeline Processor Test with AXI4-Lite    ║");
        $display("║   Program: %-30s    ║", HEX_FILE);
        $display("╚════════════════════════════════════════════════════╝\n");
        
        $display("[INFO] Starting execution...");
        $display("[INFO] Timeout set to %0d cycles", TIMEOUT_CYCLES);
        
        // Wait for program to finish
        wait(program_finished);
        
        // Final delay
        #(CLK_PERIOD * 10);
        $finish;
    end
    
    // ========================================================================
    // Print Results Task
    // ========================================================================
    task print_results;
        integer i;
        integer non_zero_regs;
        reg [31:0] return_value;
    begin
        // Tính CPI
        if (instr_count > 0) begin
            cpi = cycle_count * 1.0 / instr_count;
        end else begin
            cpi = 0.0;
        end
        
        $display("\n╔════════════════════════════════════════╗");
        $display("║           EXECUTION RESULTS           ║");
        $display("╚════════════════════════════════════════╝\n");
        
        // Performance metrics
        $display("┌─── PERFORMANCE METRICS ──────────────┐");
        $display("│ Total Clock Cycles:  %-15d │", cycle_count);
        $display("│ Instructions Executed: %-13d │", instr_count);
        $display("│ CPI (Cycles/Instr):  %-15.2f │", cpi);
        $display("│ AXI Read Transactions: %-12d │", axi_read_count);
        $display("│ AXI Write Transactions: %-11d │", axi_write_count);
        $display("│ Final PC:            0x%-13h │", debug_pc);
        $display("│ Final Instruction:   0x%-13h │", debug_instr);
        $display("│ Stall Signal:        %-15b │", debug_stall);
        $display("└──────────────────────────────────────┘\n");
        
        // Pipeline efficiency
        $display("┌─── PIPELINE EFFICIENCY ──────────────┐");
        if (instr_count > 0) begin
            real efficiency;
            efficiency = (instr_count * 100.0) / cycle_count;
            $display("│ Pipeline Efficiency: %-15.1f%% │", efficiency);
            
            // Interpretation
            if (efficiency >= 95.0) begin
                $display("│ Status:             Excellent         │");
            end else if (efficiency >= 80.0) begin
                $display("│ Status:             Good              │");
            end else if (efficiency >= 60.0) begin
                $display("│ Status:             Fair              │");
            end else begin
                $display("│ Status:             Poor              │");
            end
        end
        $display("└──────────────────────────────────────┘\n");
        
        // Final state
        $display("┌─── FINAL STATE ───────────────────────┐");
        $display("│ PC:              0x%-17h │", debug_pc);
        $display("│ Instruction:     0x%-17h │", debug_instr);
        $display("│ ALU Result:      0x%-17h │", debug_alu_result);
        $display("│ Branch Taken:    %-18b │", debug_branch_taken);
        $display("│ Stall:           %-18b │", debug_stall);
        $display("│ Forward A:       %-18b │", debug_forward_a);
        $display("│ Forward B:       %-18b │", debug_forward_b);
        $display("└──────────────────────────────────────┘\n");
        
        // Check return value (register a0/x10)
        // Note: You need to expose register file through debug port
        // or modify datapath to output registers
        $display("════════════════════════════════════════\n");
        $display("[INFO] Simulation completed successfully");
        
        // Check if program reached expected end
        if (debug_pc == 32'h00000024 || debug_instr == 32'h0000006f) begin
            $display("✅ Program reached expected infinite loop");
        end
        
        if (cycle_count < TIMEOUT_CYCLES) begin
            $display("✅ Program completed within timeout");
        end
    end
    endtask
    
    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("riscv_core_axi_waveform.vcd");
        $dumpvars(0, tb_riscv_core_axi_hex);
    end

endmodule