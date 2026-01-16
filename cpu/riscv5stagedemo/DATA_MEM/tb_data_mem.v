`timescale 1ps/1ps
`include "data_mem.v"
module tb_data_mem;
    reg clock, memwrite, memread, sign_ext;
    reg [31:0] address, write_data;
    reg [1:0] byte_size;
    wire [31:0] read_data;
    
    data_mem uut (.*);
    
    initial clock = 0;
    always #5 clock = ~clock;
    
    initial begin
        // Test SW/LW
        memwrite = 1; memread = 0;
        byte_size = 2'b10;
        address = 0;
        write_data = 32'hDEADBEEF;
        #10;
        
        memwrite = 0; memread = 1;
        #10;
        $display("LW: addr=0x%08h, data=0x%08h", address, read_data);
        
        $finish;
    end
endmodule