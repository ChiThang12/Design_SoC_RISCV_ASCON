# DMA Controller with Full AXI4 Protocol Support

## 📋 Overview

This is an enhanced DMA (Direct Memory Access) controller implementing the **complete AXI4-Full protocol**. The design has been upgraded from the original version to include all AXI4 signals and features for professional SoC integration.

## 🎯 Key Features

### AXI4-Full Protocol Compliance
- ✅ **Transaction IDs** (AWID, ARID, BID, RID) for outstanding transactions
- ✅ **Lock Signals** (AWLOCK, ARLOCK) for atomic operations
- ✅ **Cache Attributes** (AWCACHE, ARCACHE) for memory type control
- ✅ **Protection Attributes** (AWPROT, ARPROT) for security/privilege
- ✅ **QoS Support** (AWQOS, ARQOS) for quality of service
- ✅ **Burst Types**: FIXED, INCR, WRAP
- ✅ **Burst Lengths**: 1 to 256 beats
- ✅ **Data Widths**: 8-bit, 16-bit, 32-bit

### DMA Controller Features
- 🔄 **4 Independent Channels** with priority-based arbitration
- 📊 **Configurable Burst Size**: 1, 4, 8, 16, 32, 64, 128, 256 beats
- 🎚️ **Channel Priority**: 4 levels (0=lowest, 3=highest)
- 💾 **Internal FIFO**: 32-deep data buffer for read data
- ⚡ **High Throughput**: Optimized state machine with pipelined operations
- 🛡️ **Error Handling**: Separate read/write error reporting
- 🔒 **Address Alignment Check**: Automatic validation
- 📡 **Interrupt Support**: Per-channel done and error interrupts

## 📁 File Structure

```
dma_axi4/
├── dma_defines_axi4.vh      # Enhanced constants and parameters
├── dma_engine_axi4.v        # AXI4-Full master transfer engine
├── dma_channel_axi4.v       # Enhanced channel controller
├── dma_top_axi4.v          # Top-level integration module
├── dma_arbiter.v           # Priority-based arbiter (reused)
├── dma_config_slave.v      # AXI4-Lite config interface (reused)
└── README.md               # This file
```

## 🔌 Interface Signals

### AXI4-Lite Slave (Configuration)
Used for programming DMA channel registers via CPU.

**Write Address Channel:**
- `S_AXI_AWADDR[31:0]` - Write address
- `S_AXI_AWPROT[2:0]` - Protection type
- `S_AXI_AWVALID` - Write address valid
- `S_AXI_AWREADY` - Write address ready

**Write Data Channel:**
- `S_AXI_WDATA[31:0]` - Write data
- `S_AXI_WSTRB[3:0]` - Write strobe
- `S_AXI_WVALID` - Write valid
- `S_AXI_WREADY` - Write ready

**Write Response Channel:**
- `S_AXI_BRESP[1:0]` - Write response
- `S_AXI_BVALID` - Write response valid
- `S_AXI_BREADY` - Write response ready

**Read Address Channel:**
- `S_AXI_ARADDR[31:0]` - Read address
- `S_AXI_ARPROT[2:0]` - Protection type
- `S_AXI_ARVALID` - Read address valid
- `S_AXI_ARREADY` - Read address ready

**Read Data Channel:**
- `S_AXI_RDATA[31:0]` - Read data
- `S_AXI_RRESP[1:0]` - Read response
- `S_AXI_RVALID` - Read valid
- `S_AXI_RREADY` - Read ready

### AXI4-Full Master (Data Transfer)

**Write Address Channel:**
- `M_AXI_AWID[3:0]` - Write transaction ID
- `M_AXI_AWADDR[31:0]` - Write address
- `M_AXI_AWLEN[7:0]` - Burst length (beats - 1)
- `M_AXI_AWSIZE[2:0]` - Burst size (bytes per beat)
- `M_AXI_AWBURST[1:0]` - Burst type (FIXED/INCR/WRAP)
- `M_AXI_AWLOCK` - Lock type
- `M_AXI_AWCACHE[3:0]` - Cache type
- `M_AXI_AWPROT[2:0]` - Protection type
- `M_AXI_AWQOS[3:0]` - Quality of Service
- `M_AXI_AWVALID` - Write address valid
- `M_AXI_AWREADY` - Write address ready

**Write Data Channel:**
- `M_AXI_WDATA[31:0]` - Write data
- `M_AXI_WSTRB[3:0]` - Write strobe
- `M_AXI_WLAST` - Write last
- `M_AXI_WVALID` - Write valid
- `M_AXI_WREADY` - Write ready

**Write Response Channel:**
- `M_AXI_BID[3:0]` - Response transaction ID
- `M_AXI_BRESP[1:0]` - Write response
- `M_AXI_BVALID` - Write response valid
- `M_AXI_BREADY` - Write response ready

**Read Address Channel:**
- `M_AXI_ARID[3:0]` - Read transaction ID
- `M_AXI_ARADDR[31:0]` - Read address
- `M_AXI_ARLEN[7:0]` - Burst length (beats - 1)
- `M_AXI_ARSIZE[2:0]` - Burst size
- `M_AXI_ARBURST[1:0]` - Burst type
- `M_AXI_ARLOCK` - Lock type
- `M_AXI_ARCACHE[3:0]` - Cache type
- `M_AXI_ARPROT[2:0]` - Protection type
- `M_AXI_ARQOS[3:0]` - Quality of Service
- `M_AXI_ARVALID` - Read address valid
- `M_AXI_ARREADY` - Read address ready

**Read Data Channel:**
- `M_AXI_RID[3:0]` - Read transaction ID
- `M_AXI_RDATA[31:0]` - Read data
- `M_AXI_RRESP[1:0]` - Read response
- `M_AXI_RLAST` - Read last
- `M_AXI_RVALID` - Read valid
- `M_AXI_RREADY` - Read ready

### Interrupts
- `irq_done[3:0]` - Transfer complete interrupt per channel
- `irq_error[3:0]` - Transfer error interrupt per channel

## 📝 Register Map

Each channel has 8 registers (32 bytes). Base address per channel:
- Channel 0: Base + 0x00
- Channel 1: Base + 0x20
- Channel 2: Base + 0x40
- Channel 3: Base + 0x60

### Per-Channel Registers

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | SRC_ADDR | RW | Source address |
| 0x04 | DST_ADDR | RW | Destination address |
| 0x08 | LENGTH | RW | Transfer length in bytes |
| 0x0C | CTRL | RW | Control register |
| 0x10 | STATUS | RW | Status register (W1C for errors) |
| 0x14 | CURR_SRC | RO | Current source address |
| 0x18 | CURR_DST | RO | Current destination address |
| 0x1C | REMAINING | RO | Remaining bytes |

### Control Register (CTRL) - Offset 0x0C

| Bits | Name | Description |
|------|------|-------------|
| 0 | START | Start transfer (W1S) |
| 1 | ENABLE | Channel enable |
| 4:2 | BURST_SIZE | Burst size (000=1, 001=4, 010=8, 011=16, 100=32, 101=64, 110=128, 111=256) |
| 6:5 | DATA_WIDTH | Data width (00=8bit, 01=16bit, 10=32bit) |
| 7 | SRC_INCR | Source address increment enable |
| 8 | DST_INCR | Destination address increment enable |
| 10:9 | PRIORITY | Channel priority (0=low, 3=high) |
| 14:11 | CACHE_TYPE | AXI cache attribute |
| 17:15 | PROT_TYPE | AXI protection type |
| 31:18 | Reserved | - |

### Status Register (STATUS) - Offset 0x10

| Bit | Name | R/W | Description |
|-----|------|-----|-------------|
| 0 | BUSY | RO | Transfer in progress |
| 1 | DONE | RW1C | Transfer complete |
| 2 | ERROR | RW1C | Transfer error |
| 3 | FIFO_FULL | RO | Internal FIFO full |
| 4 | FIFO_EMPTY | RO | Internal FIFO empty |
| 5 | READ_ERROR | RW1C | Read response error |
| 6 | WRITE_ERROR | RW1C | Write response error |
| 31:7 | Reserved | - | - |

## 🎛️ Cache Type Encoding (AWCACHE/ARCACHE)

| Value | Description |
|-------|-------------|
| 0000 | Device Non-bufferable |
| 0001 | Device Bufferable |
| 0010 | Normal Non-cacheable Non-bufferable |
| 0011 | Normal Non-cacheable Bufferable |
| 1010 | Write-through No-allocate |
| 1110 | Write-through Read-allocate |
| 1011 | Write-back No-allocate |
| 1111 | Write-back Read/Write-allocate |

## 🔒 Protection Type Encoding (AWPROT/ARPROT)

| Bit | Description |
|-----|-------------|
| [0] | 0=Unprivileged, 1=Privileged |
| [1] | 0=Secure, 1=Non-secure |
| [2] | 0=Data, 1=Instruction |

## 🚀 Usage Example

### 1. Configure Channel 0 for Memory-to-Memory Transfer

```c
// Configure source and destination
write_reg(DMA_BASE + CH0_SRC_ADDR, 0x80000000);  // Source
write_reg(DMA_BASE + CH0_DST_ADDR, 0x90000000);  // Destination
write_reg(DMA_BASE + CH0_LENGTH, 1024);          // 1KB transfer

// Configure control register
uint32_t ctrl = 0;
ctrl |= (1 << 1);              // ENABLE
ctrl |= (3 << 2);              // BURST_SIZE = 16 beats
ctrl |= (2 << 5);              // DATA_WIDTH = 32-bit
ctrl |= (1 << 7);              // SRC_INCR = enabled
ctrl |= (1 << 8);              // DST_INCR = enabled
ctrl |= (2 << 9);              // PRIORITY = 2
ctrl |= (0x3 << 11);           // CACHE = Normal bufferable
ctrl |= (0x3 << 15);           // PROT = Privileged non-secure data
write_reg(DMA_BASE + CH0_CTRL, ctrl);

// Start transfer
ctrl |= (1 << 0);              // START
write_reg(DMA_BASE + CH0_CTRL, ctrl);

// Wait for completion
while (read_reg(DMA_BASE + CH0_STATUS) & 0x1);  // Wait while BUSY

// Check for errors
if (read_reg(DMA_BASE + CH0_STATUS) & 0x4) {
    printf("DMA transfer error!\n");
} else {
    printf("DMA transfer complete!\n");
}

// Clear done flag
write_reg(DMA_BASE + CH0_STATUS, 0x2);  // W1C DONE bit
```

## 🔧 Design Improvements Over Original

### 1. **Full AXI4 Protocol Support**
   - Added ID signals for transaction tracking
   - Added LOCK signals for atomic operations
   - Added CACHE signals for memory type control
   - Added PROT signals for security attributes
   - Added QOS signals for priority control

### 2. **Enhanced State Machine**
   - Optimized FSM with separate ERROR state
   - Better outstanding transaction tracking
   - Improved FIFO management with almost-full/empty flags

### 3. **Better Error Handling**
   - Separate read and write error reporting
   - Error type indication in status register
   - Address alignment validation

### 4. **Extended Burst Support**
   - Support for 1-256 beat bursts (vs original 1-16)
   - Better burst length calculation
   - Proper handling of unaligned transfers

### 5. **Configuration Validation**
   - Address alignment checking
   - Transfer length validation
   - Cache/Protection type configuration

## ⚙️ Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| NUM_CHANNELS | 4 | Number of DMA channels |
| ADDR_WIDTH | 32 | Address bus width |
| DATA_WIDTH | 32 | Data bus width |
| ID_WIDTH | 4 | AXI ID width |
| FIFO_DEPTH | 32 | Internal FIFO depth |

## 📊 Performance Characteristics

- **Maximum Throughput**: Up to 1 transfer/clock (when burst enabled)
- **Latency**: ~5-10 clocks from START to first data transfer
- **FIFO Depth**: 32 entries for data buffering
- **Outstanding Transactions**: Up to 4 reads and 4 writes
- **Maximum Burst**: 256 beats × 4 bytes = 1KB per burst

## 🔍 Simulation & Verification

To verify the design:
1. Use the provided testbench (coming soon)
2. Check AXI protocol compliance with Verification IP
3. Verify all burst sizes and data widths
4. Test error injection and recovery
5. Verify multi-channel arbitration

## 📚 References

- [AMBA AXI and ACE Protocol Specification](https://developer.arm.com/documentation/ihi0022/latest/)
- [AXI4 Protocol Overview](https://developer.arm.com/architectures/system-architectures/amba/amba-specifications)

## 👤 Author

**ChiThang** - Enhanced AXI4-Full Version

## 📄 License

This design is provided as-is for educational and commercial purposes.

## 🐛 Known Issues & TODO

- [ ] Add testbench with AXI VIP
- [ ] Add scatter-gather support
- [ ] Add 2D transfer support
- [ ] Optimize for lower latency
- [ ] Add performance counters
