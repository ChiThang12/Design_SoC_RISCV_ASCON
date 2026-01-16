module data_mem (
    input             clock,          // Xung clock
    input      [31:0] address,        // Địa chỉ truy cập (byte address)
    input      [31:0] write_data,     // Dữ liệu ghi vào
    input             memwrite,       // Cho phép ghi (1: ghi, 0: không ghi)
    input             memread,        // Cho phép đọc (1: đọc, 0: không đọc)
    input      [1:0]  byte_size,      // 00: byte, 01: halfword, 10: word
    input             sign_ext,       // 1: sign extend, 0: zero extend (LBU/LHU)
    output reg [31:0] read_data       // Dữ liệu đọc ra (đã extend)
);

    // ========================================================================
    // Khai báo bộ nhớ: 1024 byte
    // Tổ chức theo byte để dễ dàng xử lý LB/LH/LW/SB/SH/SW
    // ========================================================================
    reg [7:0] memory [0:1023];
    
    // ========================================================================
    // Địa chỉ word-aligned (bỏ 2 bit thấp)
    // ========================================================================
    wire [9:0] byte_addr;
    assign byte_addr = address[9:0];  // Chỉ lấy 10 bit thấp (0-1023)
    
    // ========================================================================
    // Khởi tạo bộ nhớ = 0 khi simulation
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 8'h00;
        end
    end
    
    // ========================================================================
    // WRITE OPERATION - Ghi dữ liệu vào RAM
    // Thực hiện đồng bộ theo clock
    // ========================================================================
    always @(posedge clock) begin
        if (memwrite) begin
            case (byte_size)
                2'b00: begin  // SB - Store Byte (8-bit)
                    memory[byte_addr] <= write_data[7:0];
                end
                
                2'b01: begin  // SH - Store Halfword (16-bit)
                    memory[byte_addr]     <= write_data[7:0];
                    memory[byte_addr + 1] <= write_data[15:8];
                end
                
                2'b10: begin  // SW - Store Word (32-bit)
                    memory[byte_addr]     <= write_data[7:0];
                    memory[byte_addr + 1] <= write_data[15:8];
                    memory[byte_addr + 2] <= write_data[23:16];
                    memory[byte_addr + 3] <= write_data[31:24];
                end
                
                default: begin
                    // Không làm gì
                end
            endcase
        end
    end
    
    // ========================================================================
    // READ OPERATION - Đọc dữ liệu từ RAM
    // Thực hiện tổ hợp (combinational) với sign/zero extension
    // ========================================================================
    always @(*) begin
        if (memread) begin
            case (byte_size)
                2'b00: begin  // LB/LBU - Load Byte (8-bit)
                    if (sign_ext) begin
                        // LB: Sign extend từ bit 7
                        read_data = {{24{memory[byte_addr][7]}}, memory[byte_addr]};
                    end else begin
                        // LBU: Zero extend
                        read_data = {24'h000000, memory[byte_addr]};
                    end
                end
                
                2'b01: begin  // LH/LHU - Load Halfword (16-bit)
                    if (sign_ext) begin
                        // LH: Sign extend từ bit 15
                        read_data = {{16{memory[byte_addr + 1][7]}}, 
                                     memory[byte_addr + 1], 
                                     memory[byte_addr]};
                    end else begin
                        // LHU: Zero extend
                        read_data = {16'h0000, 
                                     memory[byte_addr + 1], 
                                     memory[byte_addr]};
                    end
                end
                
                2'b10: begin  // LW - Load Word (32-bit)
                    // Word luôn không cần extend
                    read_data = {memory[byte_addr + 3],
                                 memory[byte_addr + 2],
                                 memory[byte_addr + 1],
                                 memory[byte_addr]};
                end
                
                default: begin
                    read_data = 32'h00000000;
                end
            endcase
        end else begin
            // Giữ nguyên giá trị cũ khi không đọc
            read_data = read_data;
        end
    end

endmodule
