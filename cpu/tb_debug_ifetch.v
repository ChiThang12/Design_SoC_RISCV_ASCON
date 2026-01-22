// Simple debug testbench to trace instruction fetch
`timescale 1ns/1ps

module tb_debug_ifetch();
    reg clk, rst_n;
    
    // Create simple program ROM
    reg [31:0] imem [0:15];
    
    wire [31:0] pc;
    wire [31:0] inst;
    wire imem_valid;
    wire imem_ready;
    
    // Simple ROM
    assign imem_ready = 1'b1;  // Always ready
    assign inst = imem[pc[5:2]];  // Simple sync read
    
    // Simple PC counter
    reg [31:0] pc_reg;
    assign pc = pc_reg;
    
    initial begin
        $dumpfile("debug_ifetch.vcd");
        $dumpvars(0, tb_debug_ifetch);
        
        // Load program
        imem[0] = 32'h00a00093;  // addi x1, x0, 10
        imem[1] = 32'h01400113;  // addi x2, x0, 20
        imem[2] = 32'h002081b3;  // add x3, x1, x2
        imem[3] = 32'h100002b7;  // lui x5, 0x10000
        imem[4] = 32'h0032a023;  // sw x3, 0(x5)
        imem[5] = 32'h0002a203;  // lw x4, 0(x5)
        imem[6] = 32'h00120213;  // addi x4, x4, 1
        imem[7] = 32'h0000006f;  // jal x0, 0 (infinite loop)
        
        clk = 0;
        rst_n = 0;
        pc_reg = 0;
        
        #100 rst_n = 1;
        
        // Simple PC increment every 4 cycles
        repeat(100) begin
            @(posedge clk);
            if (($time - 100) % 40 == 0 && $time > 100) begin
                pc_reg <= pc_reg + 4;
                $display("[%0t] PC advances to 0x%08h, instruction=0x%08h", 
                         $time, pc_reg + 4, imem[(pc_reg + 4) >> 2]);
            end
        end
        
        $finish;
    end
    
    initial begin
        forever #5 clk = ~clk;
    end
    
    initial begin
        #2000;
        $display("Timeout!");
        $finish;
    end

endmodule
