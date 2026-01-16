// ============================================================================
// Module: DATA_MEM - Bộ nhớ dữ liệu (RAM)
// Mô tả: RAM byte-addressable cho load/store RISC-V 32IM
// Hỗ trợ: LB/LH/LW/LBU/LHU/SB/SH/SW với sign-extension
// Tương thích: Icarus Verilog simulation & OpenLane synthesis
// ============================================================================

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

// ============================================================================
// Ghi chú sử dụng:
// ============================================================================
// 1. Tín hiệu byte_size:
//    - 2'b00: Byte (8-bit)    -> LB/LBU/SB
//    - 2'b01: Halfword (16-bit) -> LH/LHU/SH
//    - 2'b10: Word (32-bit)   -> LW/SW
//    - 2'b11: Không sử dụng
//
// 2. Tín hiệu sign_ext (chỉ dùng cho load):
//    - 1: Sign extension (LB, LH)
//    - 0: Zero extension (LBU, LHU)
//    - Không ảnh hưởng tới LW (word không cần extend)
//
// 3. Ví dụ các lệnh RISC-V:
//    - LB  x1, 0(x2)  -> memread=1, byte_size=00, sign_ext=1
//    - LBU x1, 0(x2)  -> memread=1, byte_size=00, sign_ext=0
//    - LH  x1, 0(x2)  -> memread=1, byte_size=01, sign_ext=1
//    - LHU x1, 0(x2)  -> memread=1, byte_size=01, sign_ext=0
//    - LW  x1, 0(x2)  -> memread=1, byte_size=10, sign_ext=x
//    - SB  x1, 0(x2)  -> memwrite=1, byte_size=00
//    - SH  x1, 0(x2)  -> memwrite=1, byte_size=01
//    - SW  x1, 0(x2)  -> memwrite=1, byte_size=10
//
// 4. Địa chỉ hợp lệ:
//    - 0x00000000 đến 0x000003FF (1024 bytes)
//    - Little-endian: byte thấp ở địa chỉ thấp
//
// 5. Timing:
//    - Ghi: đồng bộ theo posedge clock
//    - Đọc: tổ hợp (combinational), kết quả ngay lập tức
// ============================================================================