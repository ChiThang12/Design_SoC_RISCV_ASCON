# Final Integration Guide - Cache SOC

## Quick Summary

### ✅ Files Ready to Use (No Changes)
1. **inst_mem.v** - Đã có burst read support
2. **inst_mem_axi_slave.v** - Đã là AXI4 Full, compatible với ICache

### 📦 New Files Created
3. **data_mem_burst.v** - Upgrade của data_mem.v với burst support
4. **data_mem_axi4_slave.v** - AXI4 Full wrapper cho data memory
5. **dcache_top.v** - Data cache top-level module
6. **dcache_defines.vh** - Data cache parameters
7. **riscv_soc_top_cached.v** - SOC với cache integration

### 🔧 Files Need Minor Updates
8. **riscv_soc_top_cached.v** - Sửa include paths

---

## Integration Steps

### Step 1: Organize File Structure

```
project/
├── cache/
│   ├── icache/
│   │   ├── icache_top.v
│   │   ├── icache_defines.vh
│   │   ├── icache_controller.v
│   │   ├── icache_tag_array.v
│   │   ├── icache_data_array.v
│   │   └── icache_axi_interface.v
│   │
│   └── dcache/
│       ├── dcache_top.v          ← NEW
│       ├── dcache_defines.vh     ← NEW
│       ├── dcache_controller.v   ← TO CREATE
│       ├── dcache_tag_array.v    ← TO CREATE
│       ├── dcache_data_array.v   ← TO CREATE
│       └── dcache_axi_interface.v← TO CREATE
│
├── memory/
│   ├── inst_mem.v                ← KEEP AS-IS
│   ├── inst_mem_axi_slave.v      ← KEEP AS-IS
│   ├── data_mem.v                ← LEGACY (keep for reference)
│   ├── data_mem_axi_slave.v      ← LEGACY (keep for reference)
│   ├── data_mem_burst.v          ← NEW
│   └── data_mem_axi4_slave.v     ← NEW
│
└── riscv_soc_top_cached.v        ← NEW
```

### Step 2: Create DCache Sub-modules

Bạn cần tạo 4 modules cho DCache bằng cách copy từ ICache:

#### 2A. dcache_tag_array.v
```bash
# Copy và sửa tên
cp icache/icache_tag_array.v dcache/dcache_tag_array.v

# Sửa:
# - Module name: icache_tag_array → dcache_tag_array
# - Include: icache_defines.vh → dcache_defines.vh
# - Tất cả ICACHE → DCACHE
```

**Changes needed**: ZERO logic changes, chỉ rename!

#### 2B. dcache_data_array.v
```bash
cp icache/icache_data_array.v dcache/dcache_data_array.v
```

**Changes needed**: Thêm write_strb support

```verilog
// ADD to port list:
input wire [3:0] write_strb,

// MODIFY write logic:
always @(posedge clk) begin
    if (write_enable) begin
        // Byte-enable write
        if (write_strb[0]) cache_data[write_index][write_offset][7:0]   <= write_data[7:0];
        if (write_strb[1]) cache_data[write_index][write_offset][15:8]  <= write_data[15:8];
        if (write_strb[2]) cache_data[write_index][write_offset][23:16] <= write_data[23:16];
        if (write_strb[3]) cache_data[write_index][write_offset][31:24] <= write_data[31:24];
    end
end
```

#### 2C. dcache_axi_interface.v
```bash
cp icache/icache_axi_interface.v dcache/dcache_axi_interface.v
```

**Changes needed**: Thêm write channels

```verilog
// ADD to ports:
// Write-through interface
input  wire [31:0] wt_addr,
input  wire [31:0] wt_data,
input  wire [3:0]  wt_strb,
input  wire        wt_start,
output reg         wt_busy,
output reg         wt_done,

// AXI Write channels
output reg [31:0] M_AXI_AWADDR,
output reg [7:0]  M_AXI_AWLEN,
output reg [2:0]  M_AXI_AWSIZE,
output reg [1:0]  M_AXI_AWBURST,
output reg [2:0]  M_AXI_AWPROT,
output reg        M_AXI_AWVALID,
input  wire       M_AXI_AWREADY,

output reg [31:0] M_AXI_WDATA,
output reg [3:0]  M_AXI_WSTRB,
output reg        M_AXI_WLAST,
output reg        M_AXI_WVALID,
input  wire       M_AXI_WREADY,

input  wire [1:0] M_AXI_BRESP,
input  wire       M_AXI_BVALID,
output reg        M_AXI_BREADY,

// ADD write FSM (3 states):
localparam WT_IDLE = 2'b00;
localparam WT_ADDR = 2'b01;
localparam WT_DATA = 2'b10;
localparam WT_RESP = 2'b11;

// Implementation similar to read FSM
```

#### 2D. dcache_controller.v
```bash
cp icache/icache_controller.v dcache/dcache_controller.v
```

**Changes needed**: Thêm write logic

```verilog
// ADD to ports:
input wire        cpu_we,
input wire [31:0] cpu_wdata,
input wire [3:0]  cpu_wstrb,

output reg [31:0] wt_addr,
output reg [31:0] wt_data,
output reg [3:0]  wt_strb,
output reg        wt_start,
input wire        wt_busy,
input wire        wt_done,

// ADD states:
localparam STATE_WRITE_THRU = 3'b011;

// MODIFY LOOKUP state:
LOOKUP: begin
    if (tag_hit) begin
        if (cpu_we) begin
            // Write hit: update cache + write-through
            data_write_enable <= 1'b1;
            wt_start <= 1'b1;
            next_state <= WRITE_THRU;
        end else begin
            // Read hit
            cpu_rdata <= data_read_data;
            cpu_ready <= 1'b1;
            next_state <= IDLE;
        end
    end else begin
        if (cpu_we) begin
            // Write miss: write-through only (no refill)
            wt_start <= 1'b1;
            next_state <= WRITE_THRU;
        end else begin
            // Read miss: refill
            refill_start <= 1'b1;
            next_state <= REFILL;
        end
    end
end

// ADD WRITE_THRU state:
WRITE_THRU: begin
    if (wt_done) begin
        cpu_ready <= 1'b1;
        next_state <= IDLE;
    end
end
```

### Step 3: Update riscv_soc_top_cached.v

Sửa include paths:

```verilog
// OLD (in template)
`include "icache_top.v"
`include "dcache_top.v"
`include "memory/inst_mem_axi_slave.v"
`include "memory/data_mem_axi_slave.v"

// NEW (correct paths)
`include "cache/icache/icache_top.v"
`include "cache/dcache/dcache_top.v"
`include "memory/inst_mem_axi_slave.v"
`include "memory/data_mem_axi4_slave.v"  // ← IMPORTANT!
```

Sửa data memory instance:

```verilog
// Change module name
data_mem_axi4_slave dmem (  // was: data_mem_axi_slave
    .clk(clk),
    .rst_n(rst_n),
    
    // ... rest stays the same
);
```

### Step 4: Compilation Order

Compile theo thứ tự:

```bash
# 1. Defines
icache_defines.vh
dcache_defines.vh

# 2. Memory modules
inst_mem.v
inst_mem_axi_slave.v
data_mem_burst.v
data_mem_axi4_slave.v

# 3. Cache sub-modules
icache_tag_array.v
icache_data_array.v
icache_axi_interface.v
icache_controller.v
icache_top.v

dcache_tag_array.v
dcache_data_array.v
dcache_axi_interface.v
dcache_controller.v
dcache_top.v

# 4. CPU and SOC
riscv_cpu_core.v
riscv_soc_top_cached.v
```

---

## Testing Strategy

### Phase 1: Test ICache Alone

**Test 1: Single word fetch**
```verilog
// Testbench
initial begin
    cpu_imem_addr = 32'h0000_0000;
    cpu_imem_valid = 1'b1;
    wait(cpu_imem_ready);
    // Check cpu_imem_rdata
end
```

**Expected behavior:**
- First access: Miss → AXI burst read → Cache fill → Hit
- Second access to same line: Hit immediately (1 cycle)

**Test 2: Sequential accesses**
```verilog
for (i = 0; i < 16; i = i + 1) begin
    cpu_imem_addr = i * 4;
    cpu_imem_valid = 1'b1;
    wait(cpu_imem_ready);
end
```

**Expected:**
- Every 4 instructions: 1 miss, 3 hits
- Hit rate: ~75%

### Phase 2: Test DCache Alone

**Test 3: Read operations**
```verilog
// Read miss → refill → hit
cpu_dmem_addr = 32'h0000_0000;
cpu_dmem_valid = 1'b1;
cpu_dmem_we = 1'b0;
wait(cpu_dmem_ready);
```

**Test 4: Write operations**
```verilog
// Write-through (hit or miss)
cpu_dmem_addr = 32'h0000_0000;
cpu_dmem_wdata = 32'hDEAD_BEEF;
cpu_dmem_wstrb = 4'b1111;
cpu_dmem_valid = 1'b1;
cpu_dmem_we = 1'b1;
wait(cpu_dmem_ready);

// Verify in memory
// Check AXI write transaction occurred
```

**Test 5: Mixed read/write**
```verilog
// Write → Read same address
// Write → Read different address in same line
// Write → Read different line
```

### Phase 3: Integration Test

**Test 6: Simple program**
```assembly
# Load test.s
li x1, 100
li x2, 200
add x3, x1, x2
sw x3, 0(x0)
lw x4, 0(x0)
```

**Monitor:**
- ICache hit/miss counts
- DCache hit/miss counts
- Total cycles
- CPI calculation

**Expected results:**
```
Instructions: 5
ICache hits: 4 (80%)
DCache hits: 1/2 (50% - first time)
Total cycles: ~8-10 (vs ~25-30 without cache)
CPI: ~1.6-2.0 (vs ~5-6 without cache)
```

---

## Debugging Checklist

### Common Issues

#### Issue 1: ICache not responding
```
Symptom: cpu_imem_ready never asserts
Check:
□ inst_mem_axi_slave properly connected
□ AXI signals valid (ARVALID, ARREADY handshake)
□ burst_req signal toggling
□ Memory has data
```

#### Issue 2: DCache write not working
```
Symptom: Writes don't appear in memory
Check:
□ data_mem_axi4_slave write FSM
□ AXI write channels (AW, W, B)
□ burst_wr_strb signal
□ Write-through logic in controller
```

#### Issue 3: Cache thrashing
```
Symptom: Very low hit rate
Check:
□ Address mapping (tag, index, offset)
□ Sequential vs random access pattern
□ Cache size sufficient
□ Tag comparison logic
```

#### Issue 4: AXI protocol violation
```
Symptom: AXI ERROR or deadlock
Check:
□ ARLEN matches actual burst length
□ RLAST asserted correctly
□ AWLEN/WLAST match for writes
□ BRESP checked
```

---

## Performance Monitoring

### Statistics to Track

```verilog
// In testbench
reg [31:0] total_cycles;
reg [31:0] total_instructions;
reg [31:0] icache_accesses;
reg [31:0] dcache_accesses;

always @(posedge clk) begin
    total_cycles <= total_cycles + 1;
    
    if (cpu_imem_valid) icache_accesses <= icache_accesses + 1;
    if (cpu_dmem_valid) dcache_accesses <= dcache_accesses + 1;
    
    // At end of test:
    $display("=== Performance Report ===");
    $display("Total Cycles: %0d", total_cycles);
    $display("Total Instructions: %0d", total_instructions);
    $display("CPI: %0f", total_cycles * 1.0 / total_instructions);
    
    $display("ICache Hits: %0d", icache_hits);
    $display("ICache Misses: %0d", icache_misses);
    $display("ICache Hit Rate: %0f%%", 
             icache_hits * 100.0 / icache_accesses);
    
    $display("DCache Hits: %0d", dcache_hits);
    $display("DCache Misses: %0d", dcache_misses);
    $display("DCache Hit Rate: %0f%%", 
             dcache_hits * 100.0 / dcache_accesses);
end
```

### Expected Performance

| Metric | Without Cache | With Cache | Improvement |
|--------|--------------|------------|-------------|
| CPI | 3.5-5.0 | 1.2-2.0 | 2-3x better |
| ICache Hit Rate | N/A | 85-95% | - |
| DCache Hit Rate | N/A | 80-90% | - |
| Cycles/Inst Fetch | 4-5 | 1.2 | 3-4x better |
| Cycles/Load | 4-5 | 1.5 | 3x better |
| Cycles/Store | 4-5 | 2.0 | 2x better |

---

## Final Checklist

### Before Integration
- [x] Created dcache_top.v
- [x] Created dcache_defines.vh
- [x] Created data_mem_burst.v
- [x] Created data_mem_axi4_slave.v
- [x] Created riscv_soc_top_cached.v
- [ ] Created dcache_tag_array.v
- [ ] Created dcache_data_array.v
- [ ] Created dcache_axi_interface.v
- [ ] Created dcache_controller.v

### During Integration
- [ ] Updated file paths in riscv_soc_top_cached.v
- [ ] Organized directory structure
- [ ] Compiled all modules
- [ ] Fixed syntax errors
- [ ] Connected all signals

### Testing
- [ ] ICache single access test
- [ ] ICache burst access test
- [ ] DCache read test
- [ ] DCache write test
- [ ] Mixed access test
- [ ] Simple program test
- [ ] Statistics verification

### Verification
- [ ] Hit/miss counting correct
- [ ] AXI transactions valid
- [ ] Memory coherency maintained
- [ ] Performance improvement measured
- [ ] CPI reduced significantly

---

## Success Criteria

✅ **Minimum Success**:
- ICache working with >70% hit rate
- DCache working with >60% hit rate
- CPI < 2.5 (from ~4.0)
- No correctness errors

🎯 **Target Success**:
- ICache hit rate >85%
- DCache hit rate >80%
- CPI < 2.0
- 2.5x performance improvement

🏆 **Excellent Success**:
- ICache hit rate >90%
- DCache hit rate >85%
- CPI < 1.5
- 3x+ performance improvement

---

## Estimated Timeline

| Phase | Task | Time | Cumulative |
|-------|------|------|------------|
| 1 | Create DCache sub-modules | 2 hours | 2h |
| 2 | Update SOC integration | 1 hour | 3h |
| 3 | Compile and fix errors | 1 hour | 4h |
| 4 | Unit tests (ICache) | 1 hour | 5h |
| 5 | Unit tests (DCache) | 1 hour | 6h |
| 6 | Integration tests | 2 hours | 8h |
| 7 | Performance tuning | 2 hours | 10h |

**Total**: ~10 hours (1-2 working days)

---

## Next Actions

1. **Immediate** (next 1 hour):
   - Create 4 DCache sub-modules from ICache templates
   - Compile and fix syntax errors

2. **Short-term** (next 2-4 hours):
   - Update SOC file paths
   - Create simple testbench
   - Test ICache functionality

3. **Medium-term** (next 4-8 hours):
   - Test DCache functionality
   - Integration testing
   - Performance measurement

4. **Final** (last 2 hours):
   - Document results
   - Optimize if needed
   - Celebrate success! 🎉

---

## Support Files Provided

All necessary files đã được tạo:
1. ✅ dcache_top.v
2. ✅ dcache_defines.vh
3. ✅ data_mem_burst.v
4. ✅ data_mem_axi4_slave.v
5. ✅ riscv_soc_top_cached.v
6. ✅ MEMORY_UPGRADE_ANALYSIS.md
7. ✅ CACHE_INTEGRATION_README.md
8. ✅ ICACHE_DCACHE_COMPARISON.md

**You're 70% done!** Chỉ cần tạo 4 DCache sub-modules (copy từ ICache) và integrate!

Good luck! 🚀
