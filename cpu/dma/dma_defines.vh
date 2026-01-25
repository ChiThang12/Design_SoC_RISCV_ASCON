// ============================================================================
// File: dma_defines.vh
// ============================================================================
// Description:
//   Shared constants and parameters for DMA controller
//
// Author: ChiThang
// ============================================================================

`ifndef DMA_DEFINES_VH
`define DMA_DEFINES_VH

// ============================================================================
// DMA Configuration
// ============================================================================
`define NUM_DMA_CHANNELS    4
`define DMA_DATA_WIDTH      32
`define DMA_ADDR_WIDTH      32

// ============================================================================
// Register Map (per channel offset = 0x20)
// ============================================================================
// Base address per channel: BASE + (channel_id * 0x20)
`define DMA_REG_SRC_ADDR    4'h0    // 0x00: Source Address
`define DMA_REG_DST_ADDR    4'h1    // 0x04: Destination Address
`define DMA_REG_LENGTH      4'h2    // 0x08: Transfer Length (bytes)
`define DMA_REG_CTRL        4'h3    // 0x0C: Control Register
`define DMA_REG_STATUS      4'h4    // 0x10: Status Register
`define DMA_REG_CURR_SRC    4'h5    // 0x14: Current Source (RO)
`define DMA_REG_CURR_DST    4'h6    // 0x18: Current Destination (RO)
`define DMA_REG_REMAINING   4'h7    // 0x1C: Remaining Bytes (RO)

// ============================================================================
// Control Register Bit Fields
// ============================================================================
`define DMA_CTRL_START_BIT      0   // [0]: Start transfer (W1S)
`define DMA_CTRL_ENABLE_BIT     1   // [1]: Channel enable
`define DMA_CTRL_BURST_LSB      2   // [4:2]: Burst size
`define DMA_CTRL_BURST_MSB      4
`define DMA_CTRL_WIDTH_LSB      5   // [6:5]: Data width
`define DMA_CTRL_WIDTH_MSB      6
`define DMA_CTRL_SRC_INCR_BIT   7   // [7]: Source address increment
`define DMA_CTRL_DST_INCR_BIT   8   // [8]: Destination address increment
`define DMA_CTRL_PRIORITY_LSB   9   // [10:9]: Channel priority (0=low, 3=high)
`define DMA_CTRL_PRIORITY_MSB   10

// Burst size encoding
`define DMA_BURST_1         3'b000  // Single transfer
`define DMA_BURST_4         3'b001  // 4-beat burst
`define DMA_BURST_8         3'b010  // 8-beat burst
`define DMA_BURST_16        3'b011  // 16-beat burst

// Data width encoding
`define DMA_WIDTH_8BIT      2'b00   // Byte transfer
`define DMA_WIDTH_16BIT     2'b01   // Halfword transfer
`define DMA_WIDTH_32BIT     2'b10   // Word transfer

// ============================================================================
// Status Register Bit Fields
// ============================================================================
`define DMA_STATUS_BUSY_BIT     0   // [0]: Transfer in progress
`define DMA_STATUS_DONE_BIT     1   // [1]: Transfer complete (W1C)
`define DMA_STATUS_ERROR_BIT    2   // [2]: Transfer error (W1C)
`define DMA_STATUS_FIFO_FULL    3   // [3]: Internal FIFO full
`define DMA_STATUS_FIFO_EMPTY   4   // [4]: Internal FIFO empty

// ============================================================================
// DMA Engine States
// ============================================================================
`define DMA_STATE_IDLE          3'd0
`define DMA_STATE_READ_ADDR     3'd1
`define DMA_STATE_READ_DATA     3'd2
`define DMA_STATE_WRITE_ADDR    3'd3
`define DMA_STATE_WRITE_DATA    3'd4
`define DMA_STATE_WRITE_RESP    3'd5
`define DMA_STATE_DONE          3'd6

// ============================================================================
// AXI Constants
// ============================================================================
`define AXI_RESP_OKAY       2'b00
`define AXI_RESP_EXOKAY     2'b01
`define AXI_RESP_SLVERR     2'b10
`define AXI_RESP_DECERR     2'b11

`define AXI_BURST_FIXED     2'b00
`define AXI_BURST_INCR      2'b01
`define AXI_BURST_WRAP      2'b10

`define AXI_SIZE_1BYTE      3'b000
`define AXI_SIZE_2BYTE      3'b001
`define AXI_SIZE_4BYTE      3'b010
`define AXI_SIZE_8BYTE      3'b011

// ============================================================================
// FIFO Configuration
// ============================================================================
`define DMA_FIFO_DEPTH      16      // Internal read buffer depth

`endif // DMA_DEFINES_VH