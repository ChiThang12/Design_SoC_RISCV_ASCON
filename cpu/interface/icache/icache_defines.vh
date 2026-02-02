// ============================================================================
// File: icache_defines.vh
// ============================================================================
// Description:
//   Shared constants and parameters for instruction cache
//
// Author: ChiThang
// ============================================================================

`ifndef ICACHE_DEFINES_VH
`define ICACHE_DEFINES_VH

// ============================================================================
// Cache Configuration
// ============================================================================
`define ICACHE_SIZE         1024    // 1KB total cache size
`define ICACHE_LINE_SIZE    16      // 16 bytes per line (4 words)
`define ICACHE_ADDR_WIDTH   32      // Address width
`define ICACHE_DATA_WIDTH   32      // Data width

// Derived parameters
`define ICACHE_NUM_LINES    (`ICACHE_SIZE / `ICACHE_LINE_SIZE)  // 64 lines
`define ICACHE_WORDS_PER_LINE (`ICACHE_LINE_SIZE / 4)           // 4 words

// Bit widths
`define ICACHE_INDEX_BITS   6       // log2(64) = 6 bits
`define ICACHE_OFFSET_BITS  2       // log2(4) = 2 bits
`define ICACHE_TAG_BITS     22      // 32 - 6 - 2 - 2 = 22 bits

// ============================================================================
// Cache States
// ============================================================================
`define ICACHE_STATE_IDLE       3'd0
`define ICACHE_STATE_COMPARE    3'd1
`define ICACHE_STATE_MISS_REQ   3'd2
`define ICACHE_STATE_MISS_WAIT  3'd3
`define ICACHE_STATE_REFILL     3'd4

// ============================================================================
// AXI Response Codes
// ============================================================================
`define AXI_RESP_OKAY       2'b00
`define AXI_RESP_EXOKAY     2'b01
`define AXI_RESP_SLVERR     2'b10
`define AXI_RESP_DECERR     2'b11

`endif // ICACHE_DEFINES_VH