// ============================================================================
// REG_FILE.v - RISC-V Register File (32 x 32-bit)
// ============================================================================
// Mô tả: Tập 32 thanh ghi, x0 luôn = 0
//        Đọc bất đồng bộ (asynchronous read)
//        Ghi đồng bộ (synchronous write) tại cạnh lên của clock
// ============================================================================

module reg_file (
    input wire clock,
    input wire reset,
    
    // Read ports (asynchronous)
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
    
    // Biến để debug (có thể bỏ khi synthesize)
    integer i;
    
    // ========================================================================
    // RESET: Khởi tạo tất cả thanh ghi = 0
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'h00000000;
            end
        end
        else begin
            // ================================================================
            // WRITE: Ghi đồng bộ tại cạnh lên của clock
            // ================================================================
            if (regwrite && (write_reg != 5'b00000)) begin
                registers[write_reg] <= write_data;
            end
            // x0 luôn = 0 (đảm bảo x0 không bao giờ bị ghi đè)
            registers[0] <= 32'h00000000;
        end
    end
    
    // ========================================================================
    // READ: Đọc bất đồng bộ (asynchronous read)
    // ========================================================================
    // x0 luôn trả về 0, các thanh ghi khác trả về giá trị thực
    assign read_data1 = (read_reg_num1 == 5'b00000) ? 32'h00000000 : registers[read_reg_num1];
    assign read_data2 = (read_reg_num2 == 5'b00000) ? 32'h00000000 : registers[read_reg_num2];

endmodule