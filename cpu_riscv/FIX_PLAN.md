# Sửa lỗi RISC-V SoC - Halfword/Byte Access

## Summary of Fixes

### File 1: datapath.v - Fix WSTRB generation

**Problem:** 
- Line 454: Default case in halfword handling chỉ return 0011, không handle addr[1]=1
- Line 461: Khi NOT writing (memwrite_mem=0), vẫn gửi WSTRB=1111

**Current (WRONG):**
```verilog
2'b01: begin  // Halfword
    case (alu_result_mem[1:0])
        2'b00: byte_strobe = 4'b0011;
        2'b10: byte_strobe = 4'b1100;
        default: byte_strobe = 4'b0011;  // ❌ Sai: cho addr[1:0]=01,11,12,13
    endcase
end
```

**Fixed:**
```verilog
2'b01: begin  // Halfword
    case (alu_result_mem[1:0])
        2'b00: byte_strobe = 4'b0011;   // Bytes [1:0]
        2'b01: byte_strobe = 4'b0011;   // Bytes [1:0] (misaligned)
        2'b10: byte_strobe = 4'b1100;   // Bytes [3:2]
        2'b11: byte_strobe = 4'b1100;   // Bytes [3:2] (misaligned)
    endcase
end
```

**Also fix line 461:**
```verilog
// Change from:
else begin
    byte_strobe = 4'b1111;
end

// To:
else begin
    byte_strobe = 4'b0000;  // No byte writes for read operations
end
```

---

## Detailed Test Analysis

### Test 4 Failure Breakdown

**Program:**
```
ADDI x1, x0, 255     // x1 = 0xFF
LUI  x2, 0x10000     // x2 = 0x10000000
SB   x1, 0(x2)       // Store byte at 0x10000000 ✓ PASS
SH   x1, 2(x2)       // Store half at 0x10000002 ✗ FAIL
LB   x3, 0(x2)       // Load byte from 0x10000000 (tries to exec 17x)
LBU  x4, 0(x2)
LH   x5, 2(x2)
LHU  x6, 2(x2)
NOP
```

**Debug Output Shows:**
```
[DMEM WRITE] addr=0x10000000, data=0x000000ff, strb=0001, size=0, time=2415000 ✓ OK
[DMEM WRITE] addr=0x10000002, data=0x000000ff, strb=0011, size=1, time=2525000 
[DMEM WRITE] addr=0x10000002, data=0x000000ff, strb=0011, size=1, time=2595000
[DMEM WRITE] addr=0x10000002, data=0x000000ff, strb=0011, size=1, time=2665000
...
```

**Issues Identified:**
1. ✓ SB (byte store) works correctly (strb=0001 for addr[1:0]=00)
2. ❌ SH (halfword store) gets strb=0011 consistently
   - Expected: strb=1100 (bytes [3:2] because addr[1:0]=10)
   - Actual: strb=0011 (bytes [1:0])
3. ❌ Instruction repeats 17 times instead of 1 time
   - Root cause: Incorrect WSTRB causes write to fail
   - Pipeline stalls waiting for successful write
   - State machine may detect error and retry

**Memory State After Test 4:**
```
Expected: 
  DMEM[0x10000000] = 0x________FF (byte written)
  DMEM[0x10000001] = 0x__________  
  DMEM[0x10000002] = 0x00FF______ (halfword written)
  
Actual:
  DMEM[0x10000000] = 0xFF
  DMEM[0x10000001] = 0x00
  DMEM[0x10000002] = 0x00  ❌ Should have halfword written
  DMEM[0x10000003] = 0x00
```

---

## Recommended Fix Steps

### Step 1: Fix datapath.v byte_strobe logic

Replace lines 440-461 with:
```verilog
always @(*) begin
    if (memwrite_mem) begin
        case (byte_size_mem)
            2'b00: begin  // Byte Write
                case (alu_result_mem[1:0])
                    2'b00: byte_strobe = 4'b0001;
                    2'b01: byte_strobe = 4'b0010;
                    2'b10: byte_strobe = 4'b0100;
                    2'b11: byte_strobe = 4'b1000;
                endcase
            end
            2'b01: begin  // Halfword Write
                case (alu_result_mem[1:0])
                    2'b00: byte_strobe = 4'b0011;  // addr[1:0]=00,01 → bytes [1:0]
                    2'b01: byte_strobe = 4'b0011;  // Misaligned but handle
                    2'b10: byte_strobe = 4'b1100;  // addr[1:0]=10,11 → bytes [3:2]
                    2'b11: byte_strobe = 4'b1100;  // Misaligned but handle
                endcase
            end
            2'b10: byte_strobe = 4'b1111;  // Word Write
            default: byte_strobe = 4'b1111;
        endcase
    end else begin
        byte_strobe = 4'b0000;  // No strobes for read operations
    end
end
```

### Step 2: Verify aligned_write_data logic

Make sure `aligned_write_data` correctly positions data based on address offset:
- For byte store at addr[1:0]=N, position data in byte N
- For halfword store at addr[1]=L, position data in halfword L

### Step 3: Run Test 4 again

After fix, SH instruction should:
- Execute only ONCE per 2(x2) offset
- Write correct WSTRB=1100 to address 0x10000002
- Proceed to next instruction (LB)

### Step 4: Verify Memory Content

After complete test run, check:
```
DMEM[0x10000000] = 0xFF (SB at 0)
DMEM[0x10000001] = 0x00
DMEM[0x10000002] = 0xFF (SH at 2)
DMEM[0x10000003] = 0x00
```

---

## Expected Test Results After Fix

| Test | Status | Notes |
|------|--------|-------|
| Test 1: ALU | ✓ PASS | No changes |
| Test 2: Branch | ✓ PASS | No changes |
| Test 3: Memory W/L (Word) | ✓ PASS | No changes |
| Test 4: Byte/Halfword | ✓ PASS | Fixed by correcting WSTRB |
| Test 5: Comprehensive | ✓ PASS | Depends on Test 4 fix |

**Expected Final Result:**
```
Total Tests:   5
Passed:        5 ✓✓✓
Failed:        0
Status:        ALL TESTS PASSED ✓✓✓
```

