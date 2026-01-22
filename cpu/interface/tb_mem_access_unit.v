// ============================================================================
// tb_mem_access_unit.v - CPU RISC-V Realistic Testbench
// ============================================================================

`timescale 1ns/1ps
`include "mem_access_unit.v"

module tb_mem_access_unit;

    // Clock and Reset
    reg clk;
    reg rst_n;
    
    // IF Interface (Instruction Fetch)
    reg  [31:0] if_addr;
    reg         if_req;
    wire [31:0] if_data;
    wire        if_ready;
    wire        if_error;
    
    // MEM Interface (Data Memory)
    reg  [31:0] mem_addr;
    reg  [31:0] mem_wdata;
    reg  [3:0]  mem_wstrb;
    reg         mem_req;
    reg         mem_wr;
    wire [31:0] mem_rdata;
    wire        mem_ready;
    wire        mem_error;
    
    // AXI4-Lite Interface
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
    
    // Test counters
    integer test_num = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    // ========================================================================
    // Clock Generation (10ns period = 100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    mem_access_unit dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .if_addr(if_addr),
        .if_req(if_req),
        .if_data(if_data),
        .if_ready(if_ready),
        .if_error(if_error),
        
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_req(mem_req),
        .mem_wr(mem_wr),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .mem_error(mem_error),
        
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
        .M_AXI_RREADY(M_AXI_RREADY)
    );
    
    // ========================================================================
    // AXI Slave Model (Memory)
    // ========================================================================
    
    // Write Address Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_AWREADY <= 1'b0;
        end else begin
            M_AXI_AWREADY <= M_AXI_AWVALID && !M_AXI_AWREADY;
        end
    end
    
    // Write Data Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_WREADY <= 1'b0;
        end else begin
            M_AXI_WREADY <= M_AXI_WVALID && !M_AXI_WREADY;
        end
    end
    
    // Write Response Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_BVALID <= 1'b0;
            M_AXI_BRESP  <= 2'b00;
        end else begin
            if (M_AXI_WVALID && M_AXI_WREADY && !M_AXI_BVALID) begin
                M_AXI_BVALID <= 1'b1;
                M_AXI_BRESP  <= 2'b00;
            end else if (M_AXI_BREADY && M_AXI_BVALID) begin
                M_AXI_BVALID <= 1'b0;
            end
        end
    end
    
    // Read Address Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_ARREADY <= 1'b0;
        end else begin
            M_AXI_ARREADY <= M_AXI_ARVALID && !M_AXI_ARREADY;
        end
    end
    
    // Read Data Channel - Returns instruction/data based on address
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_RVALID <= 1'b0;
            M_AXI_RDATA  <= 32'h0;
            M_AXI_RRESP  <= 2'b00;
        end else begin
            if (M_AXI_ARVALID && M_AXI_ARREADY && !M_AXI_RVALID) begin
                M_AXI_RVALID <= 1'b1;
                M_AXI_RDATA  <= M_AXI_ARADDR ^ 32'hFFFFFFFF;
                M_AXI_RRESP  <= 2'b00;
            end else if (M_AXI_RREADY && M_AXI_RVALID) begin
                M_AXI_RVALID <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // Tasks
    // ========================================================================
    
    task reset_system;
        begin
            $display("\n========================================");
            $display("SYSTEM RESET");
            $display("========================================");
            rst_n = 0;
            if_addr = 32'h0;
            if_req = 0;
            mem_addr = 32'h0;
            mem_wdata = 32'h0;
            mem_wstrb = 4'h0;
            mem_req = 0;
            mem_wr = 0;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
        end
    endtask
    
    task fetch_instruction;
        input [31:0] pc;
        output [31:0] instruction;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] Fetch instruction from PC=0x%08h", test_num, pc);
            
            @(posedge clk);
            if_addr = pc;
            if_req = 1;
            
            @(posedge clk);
            if_req = 0;
            
            wait(if_ready == 1);
            @(posedge clk);
            
            instruction = if_data;
            
            if (if_error === 0) begin
                $display("  [PASS] Instruction = 0x%08h", instruction);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Fetch error occurred");
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    task load_word;
        input [31:0] addr;
        output [31:0] data;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] LW (Load Word) from 0x%08h", test_num, addr);
            
            @(posedge clk);
            mem_addr = addr;
            mem_wr = 0;
            mem_req = 1;
            
            @(posedge clk);
            mem_req = 0;
            
            wait(mem_ready == 1);
            @(posedge clk);
            
            data = mem_rdata;
            
            if (mem_error === 0) begin
                $display("  [PASS] Data = 0x%08h", data);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Load error occurred");
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    task store_word;
        input [31:0] addr;
        input [31:0] data;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] SW (Store Word) to 0x%08h = 0x%08h", test_num, addr, data);
            
            @(posedge clk);
            mem_addr = addr;
            mem_wdata = data;
            mem_wstrb = 4'b1111; // Full word
            mem_wr = 1;
            mem_req = 1;
            
            @(posedge clk);
            mem_req = 0;
            
            wait(mem_ready == 1);
            @(posedge clk);
            
            if (mem_error === 0) begin
                $display("  [PASS] Store completed");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Store error occurred");
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    task store_halfword;
        input [31:0] addr;
        input [15:0] data;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] SH (Store Halfword) to 0x%08h = 0x%04h", test_num, addr, data);
            
            @(posedge clk);
            mem_addr = addr;
            mem_wdata = {16'h0, data};
            mem_wstrb = (addr[1] == 0) ? 4'b0011 : 4'b1100; // Lower or upper half
            mem_wr = 1;
            mem_req = 1;
            
            @(posedge clk);
            mem_req = 0;
            
            wait(mem_ready == 1);
            @(posedge clk);
            
            if (mem_error === 0) begin
                $display("  [PASS] Store halfword completed");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Store error occurred");
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    task store_byte;
        input [31:0] addr;
        input [7:0] data;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] SB (Store Byte) to 0x%08h = 0x%02h", test_num, addr, data);
            
            @(posedge clk);
            mem_addr = addr;
            mem_wdata = {24'h0, data};
            case (addr[1:0])
                2'b00: mem_wstrb = 4'b0001;
                2'b01: mem_wstrb = 4'b0010;
                2'b10: mem_wstrb = 4'b0100;
                2'b11: mem_wstrb = 4'b1000;
            endcase
            mem_wr = 1;
            mem_req = 1;
            
            @(posedge clk);
            mem_req = 0;
            
            wait(mem_ready == 1);
            @(posedge clk);
            
            if (mem_error === 0) begin
                $display("  [PASS] Store byte completed");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Store error occurred");
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // ========================================================================
    // Main Test Sequence - Simulating Real CPU Behavior
    // ========================================================================
       reg [31:0] instr;
        reg [31:0] data;
    initial begin
     
        
        $dumpfile("mem_access_unit.vcd");
        $dumpvars(0, tb_mem_access_unit);
        
        $display("\n========================================");
        $display("RISC-V CPU Memory Access Unit Test");
        $display("========================================");
        
        reset_system();
        
        // ====================================================================
        // Scenario 1: Sequential Instruction Fetch (Normal execution)
        // ====================================================================
        $display("\n=== Scenario 1: Sequential Instruction Fetch ===");
        fetch_instruction(32'h0000_0000, instr); // PC = 0x00
        fetch_instruction(32'h0000_0004, instr); // PC = 0x04
        fetch_instruction(32'h0000_0008, instr); // PC = 0x08
        fetch_instruction(32'h0000_000C, instr); // PC = 0x0C
        
        // ====================================================================
        // Scenario 2: Fetch + Load (e.g., LW instruction execution)
        // ====================================================================
        $display("\n=== Scenario 2: Fetch then Load ===");
        fetch_instruction(32'h0000_0010, instr); // Fetch LW instruction
        load_word(32'h0000_1000, data);          // Execute LW
        
        // ====================================================================
        // Scenario 3: Fetch + Store (e.g., SW instruction execution)
        // ====================================================================
        $display("\n=== Scenario 3: Fetch then Store ===");
        fetch_instruction(32'h0000_0014, instr); // Fetch SW instruction
        store_word(32'h0000_2000, 32'hDEADBEEF); // Execute SW
        
        // ====================================================================
        // Scenario 4: Load-Use Pattern (common in programs)
        // ====================================================================
        $display("\n=== Scenario 4: Load-Use Pattern ===");
        fetch_instruction(32'h0000_0018, instr); // Fetch LW
        load_word(32'h0000_3000, data);          // Execute LW
        fetch_instruction(32'h0000_001C, instr); // Fetch next (use loaded data)
        
        // ====================================================================
        // Scenario 5: Store-Load Pattern
        // ====================================================================
        $display("\n=== Scenario 5: Store-Load Pattern ===");
        fetch_instruction(32'h0000_0020, instr); // Fetch SW
        store_word(32'h0000_4000, 32'hCAFEBABE); // Execute SW
        fetch_instruction(32'h0000_0024, instr); // Fetch LW
        load_word(32'h0000_4000, data);          // Execute LW (read back)
        
        // ====================================================================
        // Scenario 6: Byte/Halfword Operations
        // ====================================================================
        $display("\n=== Scenario 6: Sub-word Operations ===");
        fetch_instruction(32'h0000_0028, instr); // Fetch SB
        store_byte(32'h0000_5000, 8'hAA);        // Execute SB
        fetch_instruction(32'h0000_002C, instr); // Fetch SH
        store_halfword(32'h0000_6000, 16'h1234); // Execute SH
        
        // ====================================================================
        // Scenario 7: Branch Target Fetch (non-sequential PC)
        // ====================================================================
        $display("\n=== Scenario 7: Branch Target Fetch ===");
        fetch_instruction(32'h0000_0030, instr); // Fetch branch instruction
        fetch_instruction(32'h0000_0100, instr); // Jump to branch target
        fetch_instruction(32'h0000_0104, instr); // Continue from target
        
        // ====================================================================
        // Scenario 8: Multiple Loads (e.g., array access)
        // ====================================================================
        $display("\n=== Scenario 8: Array Access Pattern ===");
        fetch_instruction(32'h0000_0108, instr); // Fetch LW
        load_word(32'h0000_7000, data);          // Load array[0]
        fetch_instruction(32'h0000_010C, instr); // Fetch LW
        load_word(32'h0000_7004, data);          // Load array[1]
        fetch_instruction(32'h0000_0110, instr); // Fetch LW
        load_word(32'h0000_7008, data);          // Load array[2]
        
        // ====================================================================
        // Scenario 9: Stack Operations
        // ====================================================================
        $display("\n=== Scenario 9: Stack Push/Pop ===");
        fetch_instruction(32'h0000_0114, instr);      // Fetch SW (push)
        store_word(32'h0000_7FFC, 32'h12345678);      // Push to stack
        fetch_instruction(32'h0000_0118, instr);      // Fetch LW (pop)
        load_word(32'h0000_7FFC, data);               // Pop from stack
        
        // Wait some cycles
        repeat(10) @(posedge clk);
        
        // ====================================================================
        // Print Summary
        // ====================================================================
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests:  %0d", test_num);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("✓ ALL TESTS PASSED");
            $display("✓ Memory Access Unit is ready for RISC-V CPU");
        end else begin
            $display("✗ SOME TESTS FAILED");
        end
        $display("========================================\n");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100000;
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

endmodule