// ============================================================================
// data_mem.v - Data Memory Module (FIXED)
// ============================================================================
// Sửa lỗi:
//   - Byte order khi ghi halfword/word (phải little-endian)
//   - Logic đọc/ghi phải nhất quán
// ============================================================================
module data_mem (
    input             clock,          // Xung clock
    input      [31:0] address,        // Địa chỉ truy cập (byte address)
    input      [31:0] write_data,     // Dữ liệu ghi vào
    input             memwrite,       // Cho phép ghi (1: ghi, 0: không ghi)
    input             memread,        // Cho phép đọc (1: đọc, 0: không đọc)
    input      [1:0]  byte_size,      // 00: byte, 01: halfword, 10: word
    input             sign_ext,       // 1: sign extend, 0: zero extend
    output reg [31:0] read_data       // Dữ liệu đọc ra (đã extend)
);

    // ========================================================================
    // Khai báo bộ nhớ: 1024 byte
    // ========================================================================
    reg [7:0] memory [0:1023];
    
    // ========================================================================
    // Địa chỉ và offset
    // ========================================================================
    wire [9:0] byte_addr;
    wire [1:0] byte_offset;
    
    assign byte_addr = address[9:0];
    assign byte_offset = address[1:0];
    
    // ========================================================================
    // Địa chỉ aligned
    // ========================================================================
    wire [9:0] aligned_addr;
    assign aligned_addr = {byte_addr[9:2], 2'b00};
    
    // ========================================================================
    // Khởi tạo bộ nhớ
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 8'h00;
        end
    end
    
    // ========================================================================
    // WRITE OPERATION
    // ========================================================================
    always @(posedge clock) begin
        if (memwrite) begin
            case (byte_size)
                2'b00: begin  // SB - Store Byte
                    case (byte_offset)
                        2'b00: memory[aligned_addr + 0] <= write_data[7:0];
                        2'b01: memory[aligned_addr + 1] <= write_data[7:0];
                        2'b10: memory[aligned_addr + 2] <= write_data[7:0];
                        2'b11: memory[aligned_addr + 3] <= write_data[7:0];
                    endcase
                end
                
                2'b01: begin  // SH - Store Halfword (LITTLE ENDIAN!)
                    case (byte_offset[1])
                        1'b0: begin  // Offset 0: ghi vào byte 0-1
                            memory[aligned_addr + 0] <= write_data[7:0];   // LSB
                            memory[aligned_addr + 1] <= write_data[15:8];  // MSB
                        end
                        1'b1: begin  // Offset 2: ghi vào byte 2-3
                            memory[aligned_addr + 2] <= write_data[7:0];   // LSB
                            memory[aligned_addr + 3] <= write_data[15:8];  // MSB
                        end
                    endcase
                end
                
                2'b10: begin  // SW - Store Word (LITTLE ENDIAN!)
                    memory[aligned_addr + 0] <= write_data[7:0];    // Byte 0 (LSB)
                    memory[aligned_addr + 1] <= write_data[15:8];   // Byte 1
                    memory[aligned_addr + 2] <= write_data[23:16];  // Byte 2
                    memory[aligned_addr + 3] <= write_data[31:24];  // Byte 3 (MSB)
                end
                
                default: begin
                    // Không làm gì
                end
            endcase
        end
    end
    
    // ========================================================================
    // READ OPERATION
    // ========================================================================
    always @(*) begin
        if (memread) begin
            case (byte_size)
                2'b00: begin  // LB/LBU - Load Byte
                    case (byte_offset)
                        2'b00: begin
                            if (sign_ext)
                                read_data = {{24{memory[aligned_addr + 0][7]}}, memory[aligned_addr + 0]};
                            else
                                read_data = {24'h000000, memory[aligned_addr + 0]};
                        end
                        2'b01: begin
                            if (sign_ext)
                                read_data = {{24{memory[aligned_addr + 1][7]}}, memory[aligned_addr + 1]};
                            else
                                read_data = {24'h000000, memory[aligned_addr + 1]};
                        end
                        2'b10: begin
                            if (sign_ext)
                                read_data = {{24{memory[aligned_addr + 2][7]}}, memory[aligned_addr + 2]};
                            else
                                read_data = {24'h000000, memory[aligned_addr + 2]};
                        end
                        2'b11: begin
                            if (sign_ext)
                                read_data = {{24{memory[aligned_addr + 3][7]}}, memory[aligned_addr + 3]};
                            else
                                read_data = {24'h000000, memory[aligned_addr + 3]};
                        end
                    endcase
                end
                
                2'b01: begin  // LH/LHU - Load Halfword (LITTLE ENDIAN!)
                    case (byte_offset[1])
                        1'b0: begin  // Offset 0: đọc từ byte 0-1
                            if (sign_ext)
                                read_data = {{16{memory[aligned_addr + 1][7]}}, 
                                           memory[aligned_addr + 1],    // MSB
                                           memory[aligned_addr + 0]};   // LSB
                            else
                                read_data = {16'h0000, 
                                           memory[aligned_addr + 1],    // MSB
                                           memory[aligned_addr + 0]};   // LSB
                        end
                        1'b1: begin  // Offset 2: đọc từ byte 2-3
                            if (sign_ext)
                                read_data = {{16{memory[aligned_addr + 3][7]}}, 
                                           memory[aligned_addr + 3],    // MSB
                                           memory[aligned_addr + 2]};   // LSB
                            else
                                read_data = {16'h0000, 
                                           memory[aligned_addr + 3],    // MSB
                                           memory[aligned_addr + 2]};   // LSB
                        end
                    endcase
                end
                
                2'b10: begin  // LW - Load Word (LITTLE ENDIAN!)
                    read_data = {memory[aligned_addr + 3],    // Byte 3 (MSB)
                               memory[aligned_addr + 2],      // Byte 2
                               memory[aligned_addr + 1],      // Byte 1
                               memory[aligned_addr + 0]};     // Byte 0 (LSB)
                end
                
                default: begin
                    read_data = 32'h00000000;
                end
            endcase
        end else begin
            read_data = 32'h00000000;
        end
    end

endmodule