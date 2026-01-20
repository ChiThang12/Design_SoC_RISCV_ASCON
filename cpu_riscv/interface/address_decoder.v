// ============================================================================
// address_decoder.v - Address Space Decoder for SoC
// ============================================================================
// Mô tả:
//   - Decode địa chỉ CPU request thành chip select cho các peripheral
//   - Memory map:
//     * 0x0000_0000 - 0x0000_0FFF: Instruction Memory (4KB)
//     * 0x0000_1000 - 0x0000_1FFF: Data Memory (4KB)
//     * 0x1000_0000 - 0x1000_00FF: ASCON Accelerator (256B)
//     * Others: Invalid address
// ============================================================================

module address_decoder (
    input wire [31:0] addr,           // Địa chỉ từ CPU
    
    // Chip select outputs (one-hot encoded)
    output reg sel_imem,              // Select Instruction Memory
    output reg sel_dmem,              // Select Data Memory
    output reg sel_ascon,             // Select ASCON Accelerator
    output reg sel_invalid            // Invalid address (bus error)
);

    // ========================================================================
    // Memory Map Configuration
    // ========================================================================
    // IMEM: 0x0000_0000 - 0x0000_0FFF (4KB)
    localparam [31:0] IMEM_BASE  = 32'h0000_0000;
    localparam [31:0] IMEM_SIZE  = 32'h0000_1000;  // 4KB
    localparam [31:0] IMEM_MASK  = 32'hFFFF_F000;  // Mask để check range
    
    // DMEM: 0x0000_1000 - 0x0000_1FFF (4KB)
    localparam [31:0] DMEM_BASE  = 32'h0000_1000;
    localparam [31:0] DMEM_SIZE  = 32'h0000_1000;  // 4KB
    localparam [31:0] DMEM_MASK  = 32'hFFFF_F000;
    
    // ASCON: 0x1000_0000 - 0x1000_00FF (256B)
    localparam [31:0] ASCON_BASE = 32'h1000_0000;
    localparam [31:0] ASCON_SIZE = 32'h0000_0100;  // 256B
    localparam [31:0] ASCON_MASK = 32'hFFFF_FF00;
    
    // ========================================================================
    // Address Decoding Logic
    // ========================================================================
    always @(*) begin
        // Default: Tất cả đều = 0 (one-hot)
        sel_imem    = 1'b0;
        sel_dmem    = 1'b0;
        sel_ascon   = 1'b0;
        sel_invalid = 1'b0;
        
        // Priority-based decoding
        if ((addr & IMEM_MASK) == IMEM_BASE) begin
            // Address trong range IMEM: 0x0000_0xxx
            sel_imem = 1'b1;
        end
        else if ((addr & DMEM_MASK) == DMEM_BASE) begin
            // Address trong range DMEM: 0x0000_1xxx
            sel_dmem = 1'b1;
        end
        else if ((addr & ASCON_MASK) == ASCON_BASE) begin
            // Address trong range ASCON: 0x1000_00xx
            sel_ascon = 1'b1;
        end
        else begin
            // Address không thuộc vùng nào -> invalid
            sel_invalid = 1'b1;
        end
    end
    
    // ========================================================================
    // Assertion: Đảm bảo chỉ có 1 select active (one-hot)
    // ========================================================================
    // synthesis translate_off
    always @(*) begin
        if ((sel_imem + sel_dmem + sel_ascon + sel_invalid) != 1) begin
            $error("Address decoder error: Multiple or no selects active at addr=0x%08h", addr);
        end
    end
    // synthesis translate_on

endmodule