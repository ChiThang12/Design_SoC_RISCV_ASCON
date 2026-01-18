// ============================================================================
// data_mem.v - Data Memory Module (64KB)
// ============================================================================
// Description:
//   - 64KB RAM for SoC data storage
//   - Supports byte/halfword/word access
//   - Address range: 0x10000000 - 0x1000FFFF (maps to 0x0000 - 0xFFFF)
// ============================================================================

module data_mem (
    input             clock,          // Clock signal
    input      [31:0] address,        // Byte address (full 32-bit)
    input      [31:0] write_data,     // Data to write
    input             memwrite,       // Write enable (1: write, 0: no write)
    input             memread,        // Read enable (1: read, 0: no read)
    input      [1:0]  byte_size,      // 00: byte, 01: halfword, 10: word
    input             sign_ext,       // 1: sign extend, 0: zero extend (LBU/LHU)
    output reg [31:0] read_data       // Data read out (extended)
);

    // ========================================================================
    // Memory Array: 1KB (reduced from 64KB for simulation speed)
    // Organized as byte array for easy LB/LH/LW/SB/SH/SW handling
    // ========================================================================
    reg [7:0] memory [0:1023];
    
    // ========================================================================
    // Address Mapping
    // Full address: 0x1000_xxxx (SoC DMEM range)
    // We only use lower 10 bits: [9:0] for 1KB addressing
    // ========================================================================
    wire [9:0] byte_addr;
    assign byte_addr = address[9:0];  // Extract bits [9:0] for 0-1023 range
    
    // ========================================================================
    // Initialize memory to 0 for simulation
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 8'h00;
        end
    end
    
    // ========================================================================
    // WRITE OPERATION - Write data to RAM
    // Synchronous operation on clock edge
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
                    // Do nothing for invalid byte_size
                end
            endcase
        end
    end
    
    // ========================================================================
    // READ OPERATION - Read data from RAM
    // Combinational logic with sign/zero extension
    // ========================================================================
    always @(*) begin
        if (memread) begin
            case (byte_size)
                2'b00: begin  // LB/LBU - Load Byte (8-bit)
                    if (sign_ext) begin
                        // LB: Sign extend from bit 7
                        read_data = {{24{memory[byte_addr][7]}}, memory[byte_addr]};
                    end else begin
                        // LBU: Zero extend
                        read_data = {24'h000000, memory[byte_addr]};
                    end
                end
                
                2'b01: begin  // LH/LHU - Load Halfword (16-bit)
                    if (sign_ext) begin
                        // LH: Sign extend from bit 15
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
                    // Word doesn't need extension
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
            // Return 0 when not reading
            read_data = 32'h00000000;
        end
    end

    // ========================================================================
    // Debug: Monitor memory accesses (simulation only)
    // ========================================================================
    // synthesis translate_off
    always @(posedge clock) begin
        if (memwrite) begin
            case (byte_size)
                2'b00: $display("[DMEM] SB: addr=0x%08h <= 0x%02h", address, write_data[7:0]);
                2'b01: $display("[DMEM] SH: addr=0x%08h <= 0x%04h", address, write_data[15:0]);
                2'b10: $display("[DMEM] SW: addr=0x%08h <= 0x%08h", address, write_data);
            endcase
        end
    end
    // synthesis translate_on

endmodule