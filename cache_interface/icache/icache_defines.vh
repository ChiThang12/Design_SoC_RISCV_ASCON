`ifndef ICACHE_DEFINES_VH
`define ICACHE_DEFINES_VH

// ============================================================================
// Cache Configuration — LINE_SIZE tăng 16→32 bytes (8 words/line)
// ============================================================================
`define ICACHE_SIZE         1024    // 1KB total (giữ nguyên)
`define ICACHE_LINE_SIZE    32      // 32 bytes per line (8 words)
`define ICACHE_ADDR_WIDTH   32
`define ICACHE_DATA_WIDTH   32

// Derived
`define ICACHE_NUM_LINES    (`ICACHE_SIZE / `ICACHE_LINE_SIZE)  // 32 lines
`define ICACHE_WORDS_PER_LINE (`ICACHE_LINE_SIZE / 4)           // 8 words

// Bit widths
// Địa chỉ 32 bit phân rã:
//   [31:10] tag   = 22 bits  (giữ nguyên)
//   [9:5]   index =  5 bits  (log2(32) = 5)
//   [4:2]   offset=  3 bits  (log2(8)  = 3)
//   [1:0]   byte  =  2 bits  (luôn 00)
`define ICACHE_INDEX_BITS   5       // log2(32) = 5
`define ICACHE_OFFSET_BITS  3       // log2(8)  = 3
`define ICACHE_TAG_BITS     22      // 32 - 5 - 3 - 2 = 22

// AXI Response Codes
`define AXI_RESP_OKAY       2'b00
`define AXI_RESP_EXOKAY     2'b01
`define AXI_RESP_SLVERR     2'b10
`define AXI_RESP_DECERR     2'b11

`endif
