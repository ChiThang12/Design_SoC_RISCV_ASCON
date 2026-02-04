# DMA AXI4-Full Integration Guide

## 🎯 Mục đích

Tài liệu này hướng dẫn tích hợp DMA Controller AXI4-Full vào hệ thống SoC của bạn.

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          CPU Core                                │
│                      (ARM Cortex-A/R/M)                         │
└───────────────┬─────────────────────────────────────────────────┘
                │ AXI4-Lite (Config)
                │
┌───────────────▼─────────────────────────────────────────────────┐
│                     AXI Interconnect                             │
│                    (Crossbar/Matrix)                             │
└──┬──────────────────────────────────────────────────┬───────────┘
   │ AXI4-Full (Data)                                  │
   │                                                   │
┌──▼───────────────────────┐              ┌──────────▼───────────┐
│   DMA Controller         │              │   Memory Controller  │
│   (dma_top_axi4)        │              │   (DDR/SRAM)         │
│                          │              │                      │
│ - 4 Channels            │              │ - Main Memory        │
│ - Priority Arbiter      │              │ - Cache              │
│ - AXI4-Full Master      │              │                      │
└──┬───────────────────────┘              └──────────────────────┘
   │ Interrupts
   │
┌──▼───────────────────────┐
│   Interrupt Controller   │
│   (GIC/NVIC)            │
└──────────────────────────┘
```

## 📦 Files Required

### Core RTL Files:
```
dma_axi4/
├── dma_defines_axi4.vh      # Constants and parameters
├── dma_engine_axi4.v        # AXI4 master engine
├── dma_channel_axi4.v       # Channel controller
├── dma_arbiter.v            # Channel arbiter
├── dma_config_slave.v       # AXI4-Lite config interface
└── dma_top_axi4.v          # Top-level module
```

### Documentation:
```
docs/
├── README.md               # Overview and features
├── COMPARISON.md           # Comparison with original
└── INTEGRATION.md          # This file
```

## 🔌 Integration Steps

### Step 1: Add Files to Project

**Vivado:**
```tcl
# Add RTL files
add_files -norecurse {
    dma_defines_axi4.vh
    dma_arbiter.v
    dma_config_slave.v
    dma_channel_axi4.v
    dma_engine_axi4.v
    dma_top_axi4.v
}

# Set as top module
set_property top dma_top_axi4 [current_fileset]
```

**Quartus:**
```tcl
set_global_assignment -name VERILOG_FILE dma_defines_axi4.vh
set_global_assignment -name VERILOG_FILE dma_arbiter.v
set_global_assignment -name VERILOG_FILE dma_config_slave.v
set_global_assignment -name VERILOG_FILE dma_channel_axi4.v
set_global_assignment -name VERILOG_FILE dma_engine_axi4.v
set_global_assignment -name VERILOG_FILE dma_top_axi4.v
set_global_assignment -name TOP_LEVEL_ENTITY dma_top_axi4
```

### Step 2: Instantiate in Your Design

```verilog
module my_soc (
    input wire clk,
    input wire rst_n,
    // ... other signals
);

    // DMA interrupt wires
    wire [3:0] dma_irq_done;
    wire [3:0] dma_irq_error;
    
    // DMA instance
    dma_top_axi4 #(
        .NUM_CHANNELS(4),
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .ID_WIDTH(4)
    ) dma_controller (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI4-Lite Slave (Config) - Connect to CPU bus
        .S_AXI_AWADDR(cpu_axi_awaddr),
        .S_AXI_AWPROT(cpu_axi_awprot),
        .S_AXI_AWVALID(cpu_axi_awvalid),
        .S_AXI_AWREADY(cpu_axi_awready),
        // ... other AXI4-Lite signals
        
        // AXI4 Master (Data) - Connect to memory bus
        .M_AXI_AWID(dma_axi_awid),
        .M_AXI_AWADDR(dma_axi_awaddr),
        .M_AXI_AWLEN(dma_axi_awlen),
        .M_AXI_AWSIZE(dma_axi_awsize),
        .M_AXI_AWBURST(dma_axi_awburst),
        .M_AXI_AWLOCK(dma_axi_awlock),
        .M_AXI_AWCACHE(dma_axi_awcache),
        .M_AXI_AWPROT(dma_axi_awprot),
        .M_AXI_AWQOS(dma_axi_awqos),
        .M_AXI_AWVALID(dma_axi_awvalid),
        .M_AXI_AWREADY(dma_axi_awready),
        // ... other AXI4 signals
        
        // Interrupts
        .irq_done(dma_irq_done),
        .irq_error(dma_irq_error)
    );
    
    // Connect interrupts to interrupt controller
    // ...

endmodule
```

### Step 3: Configure Address Map

```verilog
// Define base address for DMA configuration
// Must be aligned to 128 bytes (0x80) for 4 channels
localparam DMA_BASE_ADDR = 32'h4300_0000;

// Address decode logic in your interconnect
wire dma_cfg_sel = (axi_addr >= DMA_BASE_ADDR) && 
                   (axi_addr < (DMA_BASE_ADDR + 32'h80));
```

### Step 4: Connect to Interrupt Controller

```verilog
// Example for ARM GIC
assign gic_irq[IRQ_DMA_CH0_DONE]  = dma_irq_done[0];
assign gic_irq[IRQ_DMA_CH0_ERROR] = dma_irq_error[0];
assign gic_irq[IRQ_DMA_CH1_DONE]  = dma_irq_done[1];
assign gic_irq[IRQ_DMA_CH1_ERROR] = dma_irq_error[1];
assign gic_irq[IRQ_DMA_CH2_DONE]  = dma_irq_done[2];
assign gic_irq[IRQ_DMA_CH2_ERROR] = dma_irq_error[2];
assign gic_irq[IRQ_DMA_CH3_DONE]  = dma_irq_done[3];
assign gic_irq[IRQ_DMA_CH3_ERROR] = dma_irq_error[3];
```

## 🔧 Clock and Reset Requirements

### Clock Domain:
```verilog
// Single clock domain for simplicity
// For multi-clock: add async FIFOs at boundaries
input wire axi_aclk;     // AXI clock (50-400 MHz typical)
input wire axi_aresetn;  // Active-low async reset
```

### Reset Sequence:
```verilog
// Reset assertion: At least 10 clock cycles
// Reset deassertion: Synchronize to axi_aclk

reg [3:0] rst_sync;
always @(posedge axi_aclk or negedge sys_reset_n) begin
    if (!sys_reset_n)
        rst_sync <= 4'b0000;
    else
        rst_sync <= {rst_sync[2:0], 1'b1};
end

assign axi_aresetn = rst_sync[3];
```

## 🌐 AXI Interconnect Configuration

### Xilinx AXI SmartConnect:
```tcl
# Create AXI SmartConnect
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc

# Configure SmartConnect
set_property -dict [list \
    CONFIG.NUM_SI {2} \
    CONFIG.NUM_MI {2} \
] [get_bd_cells axi_smc]

# Connect DMA as master
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI] \
                    [get_bd_intf_pins axi_smc/S00_AXI]

# Connect CPU as master
connect_bd_intf_net [get_bd_intf_pins cpu/M_AXI] \
                    [get_bd_intf_pins axi_smc/S01_AXI]

# Connect to memory
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] \
                    [get_bd_intf_pins ddr/S_AXI]
```

### ARM NIC-400:
```verilog
// Configure NIC-400 with DMA as master
nic400_top nic (
    // Master interfaces
    .m0_axi_awid(cpu_awid),      // CPU
    .m1_axi_awid(dma_awid),      // DMA
    // ...
    
    // Slave interfaces
    .s0_axi_awready(mem_awready), // Memory
    // ...
);
```

## 💾 Memory Access Patterns

### DDR Controller Configuration:
```verilog
// Recommended DDR controller settings for DMA
// - Enable write combining
// - Set appropriate burst length (16-256)
// - Configure QoS for DMA traffic

ddr_controller #(
    .BURST_LENGTH(256),      // Match max DMA burst
    .WRITE_COMBINING(1),     // Enable for better efficiency
    .QOS_ENABLE(1)           // Enable QoS
) ddr (
    // ...
    .qos_in(dma_awqos),      // Use DMA QoS signals
    // ...
);
```

### SRAM Configuration:
```verilog
// SRAM typically supports shorter bursts
// Configure DMA for smaller bursts when accessing SRAM
// In software: set BURST_SIZE = 3'b010 (8 beats) for SRAM
```

## 🔐 Security Configuration

### TrustZone Integration:
```verilog
// Connect PROT signals to security checker
tzc400_security_checker tzc (
    .axprot(dma_axi_awprot),
    .secure_access_ok(dma_secure_ok),
    // ...
);

// Only allow DMA if security check passes
assign dma_axi_awvalid = dma_awvalid_int & dma_secure_ok;
```

### Firewall Integration:
```verilog
// Add address range checker
address_firewall firewall (
    .addr(dma_axi_awaddr),
    .prot(dma_axi_awprot),
    .allowed_regions(allowed_dma_regions),
    .access_ok(dma_access_ok)
);
```

## 📊 Performance Optimization

### 1. Burst Size Configuration:
```c
// For DDR: Use large bursts (64-256 beats)
dma_config_burst(ch, DMA_BURST_256);

// For SRAM: Use medium bursts (8-16 beats)
dma_config_burst(ch, DMA_BURST_16);

// For peripherals: Use single or small bursts
dma_config_burst(ch, DMA_BURST_4);
```

### 2. Cache Configuration:
```c
// Memory-to-Memory: Write-back cacheable
dma_config_cache(ch, CACHE_WBACK_RW_ALLOCATE);

// Memory-to-Peripheral: Device bufferable
dma_config_cache(ch, CACHE_DEV_BUF);

// Peripheral-to-Memory: Normal non-cacheable
dma_config_cache(ch, CACHE_NORMAL_NOCACHE);
```

### 3. Priority Configuration:
```c
// High-priority channels for real-time data
dma_config_priority(0, PRIORITY_HIGH);  // Video channel
dma_config_priority(1, PRIORITY_HIGH);  // Audio channel

// Lower priority for bulk transfers
dma_config_priority(2, PRIORITY_LOW);   // File I/O
dma_config_priority(3, PRIORITY_LOW);   // Background tasks
```

## 🧪 Verification

### Simulation Testbench:
```verilog
module tb_dma_integration;
    // Clock and reset
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk; // 100MHz
    
    // Memory model
    axi_slave_mem #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) memory (
        .clk(clk),
        .rst_n(rst_n),
        // Connect to DMA master
        .s_axi_awid(dma_awid),
        .s_axi_awaddr(dma_awaddr),
        // ... other signals
    );
    
    // DMA instance
    dma_top_axi4 dut (
        .clk(clk),
        .rst_n(rst_n),
        // ... connections
    );
    
    // Test sequence
    initial begin
        // Reset
        rst_n = 0;
        #100;
        rst_n = 1;
        
        // Configure DMA
        write_reg(DMA_CH0_SRC, 32'h1000);
        write_reg(DMA_CH0_DST, 32'h2000);
        write_reg(DMA_CH0_LEN, 1024);
        write_reg(DMA_CH0_CTRL, CTRL_START | CTRL_ENABLE);
        
        // Wait for completion
        wait(dma_irq_done[0]);
        
        // Verify data
        check_memory(32'h2000, 1024);
        
        $display("Test PASSED");
        $finish;
    end
endmodule
```

### ChipScope/ILA Debug:
```tcl
# Add ILA for debugging
create_debug_core u_ila ila
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila]

# Monitor DMA state machine
connect_debug_port u_ila/probe0 [get_nets dma/engine/state]
connect_debug_port u_ila/probe1 [get_nets dma/engine/M_AXI_AWVALID]
connect_debug_port u_ila/probe2 [get_nets dma/engine/M_AXI_AWREADY]
connect_debug_port u_ila/probe3 [get_nets dma/engine/M_AXI_WVALID]
connect_debug_port u_ila/probe4 [get_nets dma/engine/M_AXI_WREADY]
```

## 📱 Software Driver

### Basic Driver Structure:
```c
#include <stdint.h>

// DMA register offsets
#define DMA_REG_SRC_ADDR(ch)    (DMA_BASE + (ch)*0x20 + 0x00)
#define DMA_REG_DST_ADDR(ch)    (DMA_BASE + (ch)*0x20 + 0x04)
#define DMA_REG_LENGTH(ch)      (DMA_BASE + (ch)*0x20 + 0x08)
#define DMA_REG_CTRL(ch)        (DMA_BASE + (ch)*0x20 + 0x0C)
#define DMA_REG_STATUS(ch)      (DMA_BASE + (ch)*0x20 + 0x10)

// Control bits
#define DMA_CTRL_START          (1 << 0)
#define DMA_CTRL_ENABLE         (1 << 1)
#define DMA_CTRL_SRC_INCR       (1 << 7)
#define DMA_CTRL_DST_INCR       (1 << 8)

// Status bits
#define DMA_STATUS_BUSY         (1 << 0)
#define DMA_STATUS_DONE         (1 << 1)
#define DMA_STATUS_ERROR        (1 << 2)

// Initialize DMA channel
void dma_init(uint32_t channel) {
    // Reset channel
    writel(0, DMA_REG_CTRL(channel));
    
    // Clear status
    writel(DMA_STATUS_DONE | DMA_STATUS_ERROR, 
           DMA_REG_STATUS(channel));
}

// Configure and start transfer
int dma_transfer(uint32_t channel, 
                 uint32_t src, 
                 uint32_t dst, 
                 uint32_t len) {
    // Check if channel is busy
    if (readl(DMA_REG_STATUS(channel)) & DMA_STATUS_BUSY)
        return -EBUSY;
    
    // Configure transfer
    writel(src, DMA_REG_SRC_ADDR(channel));
    writel(dst, DMA_REG_DST_ADDR(channel));
    writel(len, DMA_REG_LENGTH(channel));
    
    // Start transfer
    uint32_t ctrl = DMA_CTRL_ENABLE | 
                    DMA_CTRL_START |
                    DMA_CTRL_SRC_INCR | 
                    DMA_CTRL_DST_INCR |
                    (3 << 2) |  // 16-beat burst
                    (2 << 5);   // 32-bit width
    writel(ctrl, DMA_REG_CTRL(channel));
    
    return 0;
}

// Wait for completion
int dma_wait(uint32_t channel, uint32_t timeout_ms) {
    uint32_t status;
    uint32_t count = 0;
    
    do {
        status = readl(DMA_REG_STATUS(channel));
        
        if (status & DMA_STATUS_ERROR)
            return -EIO;
        
        if (status & DMA_STATUS_DONE)
            return 0;
        
        udelay(1);
        count++;
    } while (count < timeout_ms * 1000);
    
    return -ETIMEDOUT;
}

// Interrupt handler
void dma_irq_handler(uint32_t channel) {
    uint32_t status = readl(DMA_REG_STATUS(channel));
    
    if (status & DMA_STATUS_DONE) {
        // Transfer complete
        printk("DMA channel %d: Transfer complete\n", channel);
        
        // Clear done flag
        writel(DMA_STATUS_DONE, DMA_REG_STATUS(channel));
        
        // Wake up waiting process
        wake_up(&dma_wait_queue);
    }
    
    if (status & DMA_STATUS_ERROR) {
        // Transfer error
        printk("DMA channel %d: Transfer error\n", channel);
        
        // Clear error flag
        writel(DMA_STATUS_ERROR, DMA_REG_STATUS(channel));
        
        // Wake up with error
        wake_up(&dma_wait_queue);
    }
}
```

## 🎓 Best Practices

### DO:
✅ Always check BUSY status before starting new transfer
✅ Clear DONE/ERROR flags before starting transfer
✅ Use appropriate burst sizes for memory type
✅ Configure cache attributes correctly
✅ Enable interrupts for async operation
✅ Validate addresses are aligned
✅ Check transfer length is non-zero

### DON'T:
❌ Don't modify config while channel is BUSY
❌ Don't use large bursts for peripherals
❌ Don't ignore error interrupts
❌ Don't use cacheable attribute for device memory
❌ Don't start overlapping transfers on same channel
❌ Don't use unaligned addresses

## 🐛 Troubleshooting

### Issue: Transfer hangs
**Check:**
- AXI interconnect routing
- Memory controller ready
- Clock/reset stability
- FIFO overflow/underflow

### Issue: Data corruption
**Check:**
- Address alignment
- Cache coherency settings
- Burst boundaries
- Memory protection settings

### Issue: Performance lower than expected
**Check:**
- Burst size configuration
- QoS settings
- Interconnect arbitration
- Memory controller bandwidth

## 📞 Support

For technical support or questions:
- GitHub Issues: [project-url]/issues
- Email: support@example.com
- Documentation: [project-url]/docs

---
**Version:** 1.0  
**Last Updated:** 2025-02-04  
**Author:** ChiThang
