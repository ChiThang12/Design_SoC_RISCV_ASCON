// ============================================================================
// File: dcache_defines.vh
// ============================================================================
// Description:
//   Configuration parameters for data cache
//   Optimized for RISC-V load/store operations
//
// Cache Configuration:
//   - Size: 8KB (512 lines)
//   - Line size: 16 bytes (4 words)
//   - Associativity: Direct-mapped
//   - Write policy: Write-through
//   - Address: 32-bit
//
// Author: ChiThang
// ============================================================================

`ifndef DCACHE_DEFINES_VH
`define DCACHE_DEFINES_VH

// ============================================================================
// Cache Size Configuration
// ============================================================================
`define DCACHE_SIZE         1024        // 1KB total cache size (64 lines x 16bytes)
`define DCACHE_LINE_SIZE    16          // 16 bytes per cache line (4 words)
`define DCACHE_NUM_LINES    64          // 1KB / 16B = 64 lines (2^6)
`define DCACHE_NUM_SETS     64          // Direct-mapped: 1 way

// ============================================================================
// Address Width
// ============================================================================
`define DCACHE_ADDR_WIDTH   32
`define DCACHE_DATA_WIDTH   32

// ============================================================================
// Address Breakdown (for 32-bit address)
// ============================================================================
// [31:10] - Tag (22 bits)
// [9:4]   - Index (6 bits)   -> 2^6 = 64 lines
// [3:2]   - Word offset (2 bits) -> 4 words per line (each 4 bytes)
// [1:0]   - Byte offset (2 bits) -> within 4-byte word
// Total: 22 + 6 + 2 + 2 = 32 bits

`define DCACHE_TAG_WIDTH    22          // Bits for tag [31:10]
`define DCACHE_INDEX_WIDTH  6           // Bits for index [9:4] (2^6 = 64 lines)
`define DCACHE_OFFSET_WIDTH 2           // Bits for word offset [3:2]
`define DCACHE_BYTE_WIDTH   2           // Bits for byte offset [1:0]

`define DCACHE_WORDS_PER_LINE 4         // 16 bytes / 4 bytes = 4 words

// ============================================================================
// AXI4 Configuration
// ============================================================================
`define DCACHE_AXI_BURST_LEN  4         // Burst length = 4 (for 4 words)
`define DCACHE_AXI_SIZE       3'b010    // 4 bytes (32-bit)
`define DCACHE_AXI_BURST_INCR 2'b01     // INCR burst type

// ============================================================================
// State Machine States
// ============================================================================
`define DCACHE_STATE_IDLE       3'b000
`define DCACHE_STATE_LOOKUP     3'b001
`define DCACHE_STATE_REFILL     3'b010
`define DCACHE_STATE_WRITE_THRU 3'b011
`define DCACHE_STATE_WAIT       3'b100

`endif // DCACHE_DEFINES_VH
