module inst_mem (
    input  [31:0] PC,                  // Program Counter - địa chỉ byte hiện tại
    input         reset,               // Tín hiệu reset (không sử dụng cho ROM)
    output [31:0] Instruction_Code     // Lệnh 32-bit đọc ra
);

    // ========================================================================
    // Khai báo bộ nhớ: 1024 từ x 32 bit = 4096 byte = 4KB
    // ========================================================================
    reg [31:0] memory [0:1023];
    
    // ========================================================================
    // Tính địa chỉ từ (word address) từ địa chỉ byte
    // PC là địa chỉ byte, cần chia 4 để lấy địa chỉ từ (word-aligned)
    // PC[11:2] tương đương PC >> 2 (dịch phải 2 bit)
    // ========================================================================
    wire [9:0] word_addr;              // Địa chỉ từ 10-bit (0 đến 1023)
    assign word_addr = PC[11:2];       // Lấy bit [11:2] làm địa chỉ từ
    
    integer i;  // For initialization loop
    
    // ========================================================================
    // Đọc lệnh từ bộ nhớ
    // Truy cập đồng bộ theo địa chỉ word_addr
    // ========================================================================
    assign Instruction_Code = memory[word_addr];
    
    // ========================================================================
    // Khởi tạo bộ nhớ từ file hex khi simulation
    // File program.hex chứa các lệnh dạng hex, mỗi dòng 1 lệnh 32-bit
    // ========================================================================
    initial begin
        // Initialize to NOPs
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 32'h00000013;  // NOP
        end
        
        // Load program from hex file
        $readmemh("memory/program.hex", memory);
        $display("[IMEM] Loaded program.hex");
        $display("[IMEM] First instruction: 0x%08h", memory[0]);
        $display("[IMEM] Instruction @ 0x30 (main): 0x%08h", memory[12]);
    end

endmodule