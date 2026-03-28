module reg_file (
    input wire clock,
    input wire reset,
    
    // Read ports (asynchronous with forwarding)
    input wire [4:0] read_reg_num1,      // rs1
    input wire [4:0] read_reg_num2,      // rs2
    output wire [31:0] read_data1,       // dữ liệu từ rs1
    output wire [31:0] read_data2,       // dữ liệu từ rs2
    
    // Write port (synchronous)
    input wire regwrite,                 // enable ghi
    input wire [4:0] write_reg,          // rd
    input wire [31:0] write_data         // dữ liệu ghi vào rd
);

    // Khai báo 32 thanh ghi, mỗi thanh ghi 32-bit
    reg [31:0] registers [31:0];
    
    // Biến để debug
    integer i;
    
    // ========================================================================
    // WRITE & RESET: On POSEDGE clock (STANDARD DESIGN)
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'h00000000;
            end
        end else begin
            if (regwrite && (write_reg != 5'b00000)) begin
                registers[write_reg] <= write_data;
            end
            // x0 luôn = 0
            registers[0] <= 32'h00000000;
        end
    end
    
    // ========================================================================
    // READ: Combinational read WITH internal forwarding
    // ========================================================================
    // CRITICAL: Internal forwarding ensures same-cycle read-after-write works
    // When: Write to register X at WB stage, Read register X at ID stage (next instruction)
    // Without forwarding: Would read OLD value from registers array
    // With forwarding: Reads NEW value from write_data directly
    // ========================================================================
    
    assign read_data1 = (read_reg_num1 == 5'b00000) ? 32'h00000000 :
                        (regwrite && (write_reg == read_reg_num1) && (write_reg != 5'b00000)) ? write_data :
                        registers[read_reg_num1];
    
    assign read_data2 = (read_reg_num2 == 5'b00000) ? 32'h00000000 :
                        (regwrite && (write_reg == read_reg_num2) && (write_reg != 5'b00000)) ? write_data :
                        registers[read_reg_num2];

endmodule