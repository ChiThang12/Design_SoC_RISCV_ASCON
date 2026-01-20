# RISC-V SoC Testbench Results & Bug Report

## Executive Summary

**Testbench Execution Results:**
- ✓ Compiled successfully with iverilog
- ✓ Ran 5 comprehensive tests
- ✗ **2 tests FAILED** (Test 4 & Test 5)
- ✓ 3 tests PASSED

**Critical Issue Found:** Byte/Halfword WSTRB generation logic is broken

---

## Test Results Summary

### ✅ Test 1: ALU Operations & Forwarding - **PASSED**
- Forwarding logic working correctly
- All arithmetic operations (ADD, SUB, AND, OR) executed properly
- Target PC reached in 42 cycles

### ✅ Test 2: Branch & Control Flow - **PASSED**
- Branch conditions (BEQ, BNE) evaluated correctly
- JAL (jump) instruction working
- Target PC reached in 49 cycles

### ✅ Test 3: Memory Store/Load (32-bit) - **PASSED**
- Word (32-bit) store/load operations working
- Data written and read back correctly
- Verification: `DMEM[0x10000000] = 0x0000001E` ✓

### ❌ Test 4: Byte & Halfword Access - **FAILED**
- ✓ Byte store (SB) works correctly
- ✗ Halfword store (SH) broken
- ✗ Halfword load (LH) fails due to stuck instruction
- ✗ PC stuck at 0x14, no progress to 0x24
- **Result:** TIMEOUT after 150 cycles

### ❌ Test 5: Comprehensive (ALU + Branch + Memory) - **FAILED**
- Fails due to halfword operation issue from Test 4
- PC stuck fetching from address 0x00000000 repeatedly
- **Result:** TIMEOUT after 200 cycles

---

## Root Cause Analysis

### Primary Bug: WSTRB Generation in datapath.v

**Location:** [datapath.v lines 440-461](datapath.v#L440-L461)

**Issue:** The byte strobe (write enable) generation for halfword operations is incorrect.

```verilog
// CURRENT (WRONG):
2'b01: begin  // Halfword
    case (alu_result_mem[1:0])
        2'b00: byte_strobe = 4'b0011;
        2'b10: byte_strobe = 4'b1100;
        default: byte_strobe = 4'b0011;  // ❌ WRONG! Doesn't handle 01, 11
    endcase
end
```

**Problem 1: Incomplete Case Statement**
- When `alu_result_mem[1:0] = 2'b01` (odd address): Should send strobe 0011, but default handles it
- When `alu_result_mem[1:0] = 2'b11` (odd address): Should send strobe 1100, but default sends 0011 ✗

**Problem 2: Read Operations**
```verilog
else begin
    byte_strobe = 4'b1111;  // ❌ WRONG! Should be 0000 for reads
end
```

**Symptom in Test 4:**
```
SH x1, 2(x2) → Store Halfword at address 0x10000002 (addr[1:0] = 10)
Expected: WSTRB = 1100 (write bytes [3:2])
Actual:   WSTRB = 0011 (write bytes [1:0]) ❌

Result: Data written to wrong byte locations
        Pipeline stalls and retries 17 times
        Instruction never completes
        PC never advances
```

---

## Detailed Debug Output from Test 4

```
Program: Byte & Halfword Access

[INTERCONNECT] Read addr=0x00000000 -> Slave 0  (ADDI x1)
[INTERCONNECT] Read addr=0x00000000 -> Slave 0  (ADDI x1)
[INTERCONNECT] Read addr=0x00000004 -> Slave 0  (LUI x2)
[INTERCONNECT] Read addr=0x00000008 -> Slave 0  (SB x1)
[INTERCONNECT] Read addr=0x0000000c -> Slave 0  (SH x1) ← Instruction fetch
[INTERCONNECT] Write addr=0x10000000 -> Slave 1 (SB: Store byte 0xFF at 0x10000000) ✓
[DMEM WRITE] addr=0x10000000, data=0x000000ff, strb=0001, size=0 ✓ Correct!

[INTERCONNECT] Write addr=0x10000002 -> Slave 1 (SH: Store half 0xFF at 0x10000002) ❌
[DMEM WRITE] addr=0x10000002, data=0x000000ff, strb=0011, size=1 ❌ WRONG STRB!

[INTERCONNECT] Write addr=0x10000002 -> Slave 1 (RETRY 1)
[DMEM WRITE] addr=0x10000002, data=0x000000ff, strb=0011, size=1
... (repeats 17+ times)

[INTERCONNECT] Read addr=0x00000000 -> Slave 0 (keeps refetching)
...

Status: FAIL - Timeout at PC=00000014 after 150 cycles ❌
```

---

## Impact Analysis

### Affected Operations
- **SH (Store Halfword)** - BROKEN
- **LH/LHU (Load Halfword)** - Cannot work if store is broken
- **SB (Store Byte)** - Works correctly
- **LB/LBU (Load Byte)** - Works correctly

### Affected Test Cases
1. Test 4: Byte & Halfword Access - FAILS
2. Test 5: Comprehensive test - FAILS (depends on halfword)
3. Any real program using halfword ops - WILL FAIL

### Severity: **CRITICAL**

This bug breaks half of the memory access operations and must be fixed before the SoC can be deployed.

---

## Required Files to Fix

1. **datapath.v** - Fix byte_strobe generation logic
   - Lines 440-461: Update byte strobe combinational logic
   - Add explicit cases for all address offsets
   - Handle both read and write correctly

2. **Optional: Add Error Detection** (Recommended)
   - Add timeout counter for stuck instructions
   - Monitor AXI handshake signals
   - Add watchdog to prevent infinite loops

---

## Verification Checklist

After applying fix:
- [ ] Recompile testbench
- [ ] Run all 5 tests
- [ ] Verify Test 4 passes (byte and halfword ops correct)
- [ ] Verify Test 5 passes (comprehensive test)
- [ ] Check waveforms for SH/LH instruction execution
- [ ] Confirm DMEM contents match expected values
- [ ] All 5 tests should show "✓ PASSED"

---

## Files Generated

1. **ERROR_REPORT.md** - Detailed error analysis
2. **FIX_PLAN.md** - Step-by-step fix instructions
3. **This file** - Summary report

