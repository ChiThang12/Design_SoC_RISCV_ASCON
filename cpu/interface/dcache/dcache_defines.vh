// ============================================================================
// File: dcache_defines.vh
// Write-Back + Write-Allocate version
// FIX: NUM_LINES/NUM_SETS corrected từ 512 → 64
// ============================================================================
// Cache Configuration:
//   - Size: 8KB (64 lines)
//   - Line size: 16 bytes (4 words)
//   - Associativity: Direct-mapped
//   - Write policy: Write-Back + Write-Allocate
//   - Address: 32-bit
//
// Address Breakdown (32-bit):
//   [31:10] - Tag        (22 bits)
//   [9:4]   - Index      (6 bits)  → 64 sets
//   [3:2]   - Word offset (2 bits) → 4 words/line
//   [1:0]   - Byte offset (2 bits)
// ============================================================================

`ifndef DCACHE_DEFINES_VH
`define DCACHE_DEFINES_VH

// ============================================================================
// Cache Size Configuration
// FIX-BUG1: 8KB / 16B per line = 64 lines, không phải 512
// ============================================================================
`define DCACHE_SIZE         8192
`define DCACHE_LINE_SIZE    16
`define DCACHE_NUM_LINES    64      // FIX: was 512
`define DCACHE_NUM_SETS     64      // FIX: was 512

// ============================================================================
// Address Width
// ============================================================================
`define DCACHE_ADDR_WIDTH   32
`define DCACHE_DATA_WIDTH   32

// ============================================================================
// Address Bit Fields
// ============================================================================
`define DCACHE_TAG_WIDTH    22
`define DCACHE_INDEX_WIDTH  6
`define DCACHE_OFFSET_WIDTH 2
`define DCACHE_BYTE_WIDTH   2

`define DCACHE_WORDS_PER_LINE 4

// ============================================================================
// AXI4 Configuration
// ============================================================================
`define DCACHE_AXI_BURST_LEN  4
`define DCACHE_AXI_SIZE       3'b010
`define DCACHE_AXI_BURST_INCR 2'b01

// ============================================================================
// State Machine States — Write-Back version
// ============================================================================
`define DCACHE_STATE_IDLE         3'b000  // Chờ request mới
`define DCACHE_STATE_LOOKUP       3'b001  // Tag check sau miss (cur_addr stable)
`define DCACHE_STATE_REFILL       3'b010  // AXI burst read (cache miss)
`define DCACHE_STATE_EVICT        3'b011  // AXI burst write (dirty eviction)
`define DCACHE_STATE_WAIT         3'b100  // 1-cycle buffer sau evict → trước refill
`define DCACHE_STATE_REFILL_DRAIN 3'b101  // CWF: CPU đã served, drain nốt burst

`endif // DCACHE_DEFINES_VH
