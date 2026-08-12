# ASCON PERMUTATION Module

Module Verilog thực hiện thuật toán permutation của ASCON - một lightweight cryptographic algorithm được NIST chọn làm tiêu chuẩn cho Lightweight Cryptography (2023).

## 📋 Tổng quan

Module `ASCON_PERMUTATION` thực hiện phép biến đổi permutation p^a hoặc p^b trên state 320-bit (5 words × 64-bit). Mỗi round permutation bao gồm 3 bước:

1. **Constant Addition (pC)** - Thêm round constant
2. **Substitution Layer (pS)** - Áp dụng 5-bit S-box 
3. **Linear Diffusion (pL)** - Khuếch tán tuyến tính

```
Round: pC → pS → pL
```

## 🏗️ Cấu trúc Module

### Module chính: `ASCON_PERMUTATION`

#### Inputs
| Signal | Width | Mô tả |
|--------|-------|-------|
| `clk` | 1 | Clock signal |
| `rst_n` | 1 | Active-low reset |
| `state_in` | 320 | Input state (x0,x1,x2,x3,x4) |
| `rounds` | 4 | Số rounds (12 cho p^a, 6 cho p^b) |
| `start_perm` | 1 | Trigger bắt đầu permutation |
| `mode` | 1 | 0: iterative, 1: pipelined (chưa implement) |

#### Outputs
| Signal | Width | Mô tả |
|--------|-------|-------|
| `state_out` | 320 | Output state sau permutation |
| `valid` | 1 | Signal báo kết quả hợp lệ |
| `done` | 1 | Signal báo hoàn thành |

### Sub-modules

#### 1. `CONSTANT_ADDITION`
Thêm round constant vào word x2.

```verilog
round_constant = 0xF0 - (round_number × 0x0F)
x2_modified = x2 ⊕ round_constant
```

**Ví dụ:**
- Round 0: constant = 0xF0
- Round 1: constant = 0xE1
- Round 11: constant = 0x4B

#### 2. `SUBSTITUTION_LAYER`
Áp dụng 5-bit S-box song song tại 64 vị trí bit.

```verilog
// 64 S-box instances song song
for i=0 to 63:
    [x4[i], x3[i], x2[i], x1[i], x0[i]] = SBOX([x4[i], x3[i], x2[i], x1[i], x0[i]])
```

**Chi tiết S-box (`ASCON_SBOX`):**

```
Input: 5-bit [x4, x3, x2, x1, x0]

Step 1 - Initial XORs:
    x[0] ^= x[4]
    x[4] ^= x[3]  
    x[2] ^= x[1]

Step 2 - Chi layer (non-linear):
    T[i] = (~x[i]) & x[(i+1) mod 5]
    x[i] ^= T[(i+1) mod 5]

Step 3 - Final XORs:
    x[1] ^= x[0]
    x[0] ^= x[4]
    x[3] ^= x[2]
    x[2] = ~x[2]

Output: 5-bit transformed
```

#### 3. `LINEAR_DIFFUSION`
Khuếch tán tuyến tính với các phép rotation khác nhau cho mỗi word.

```verilog
x0 ^= ROR(x0, 19) ^ ROR(x0, 28)
x1 ^= ROR(x1, 61) ^ ROR(x1, 39)
x2 ^= ROR(x2, 1)  ^ ROR(x2, 6)
x3 ^= ROR(x3, 10) ^ ROR(x3, 17)
x4 ^= ROR(x4, 7)  ^ ROR(x4, 41)
```

**ROR** = Right Rotation (circular shift)

## 🔄 Hoạt động

### Iterative Mode (Chế độ hiện tại)

```
Cycle 0: start_perm=1 → Load state_in
Cycle 1: Round 0 execution
Cycle 2: Round 1 execution
...
Cycle N: Round (N-1) execution
Cycle N: done=1, valid=1, state_out ready
```

**Latency:** N+1 cycles (N = số rounds)
- p^a (12 rounds): 13 cycles
- p^b (6 rounds): 7 cycles

### State Format (320-bit)

```
[319:256] = x0 (64-bit)
[255:192] = x1 (64-bit)
[191:128] = x2 (64-bit)
[127:64]  = x3 (64-bit)
[63:0]    = x4 (64-bit)
```

## 📊 Thông số kỹ thuật

### Timing
- **Clock**: Synchronous design
- **Reset**: Asynchronous active-low
- **Latency**: rounds + 1 cycles
- **Throughput**: 1 permutation per (rounds + 1) cycles

### Area Complexity
- **S-boxes**: 64 × 5-bit S-boxes = 320 logic gates
- **Rotations**: Wiring only (no gates)
- **Registers**: 320-bit state + control logic

### Performance (ước lượng)
| Mode | Rounds | Cycles | Throughput |
|------|--------|--------|------------|
| p^a | 12 | 13 | ~1/13 per cycle |
| p^b | 6 | 7 | ~1/7 per cycle |

## 🚀 Sử dụng

### Ví dụ Instantiation

```verilog
ASCON_PERMUTATION perm (
    .clk(clk),
    .rst_n(rst_n),
    .state_in(initial_state),
    .rounds(4'd12),          // p^a: 12 rounds
    .start_perm(start),
    .mode(1'b0),             // Iterative mode
    .state_out(final_state),
    .valid(output_valid),
    .done(complete)
);
```

### Timing Diagram

```
        ___     ___     ___     ___     ___
clk    |   |___|   |___|   |___|   |___|   |___
              _____
start  ______|     |_________________________
                        _____________________
running ______________|                     |_
                                            ___
done   ____________________________________|   |_
                                            ___
valid  ____________________________________|   |_

round   --  | 0 | 1 | 2 |...| N-1 |  --
```

## 📁 File Structure

```
ascon/rtl/PERMUTATION/
├── ascon_PERMUTATION.v          # Top module
├── ascon_CONSTANT_ADDITION.v    # Round constant addition
├── ascon_SUBSTITUTION_LAYER.v   # 64× S-box layer
├── ascon_SBOX.v                 # 5-bit S-box
└── ascon_LINEAR_DIFFUSION.v     # Diffusion với rotation
```

## 🔍 Verification

File VCD đã cung cấp: `ascon_permutation.vcd`

### Testbench suggestions:
```verilog
// Test vector từ ASCON specification
initial_state = 320'h00400c0000000100_8004000000000000_0000000000000000_0000000000000000_0000000000000000;
rounds = 12; // p^a
```

## 🎯 Use Cases trong ASCON

1. **Initialization**: p^a (12 rounds) cho khởi tạo state
2. **Processing**: p^b (6 rounds) giữa các block data
3. **Finalization**: p^a (12 rounds) cho output cuối

## ⚠️ Lưu ý

- **Mode pipelined**: Chưa được implement (line 123-125)
- **Reset**: Active-low asynchronous reset
- **Control signals**: `valid` và `done` chỉ active 1 cycle
- **State width**: Cố định 320-bit (5 × 64-bit words)

## 📖 Tài liệu tham khảo

- [ASCON Specification v1.2](https://ascon.iaik.tugraz.at/specification.html)
- NIST Lightweight Cryptography Standard (2023)
- CAESAR Competition Portfolio

## 🏆 Performance Notes

- **Area-optimized**: Iterative architecture tiết kiệm diện tích
- **Combinational depth**: 3 tầng logic mỗi round (pC + pS + pL)
- **Critical path**: Through S-box layer (longest delay)

---

**Version:** 1.0  
**Author:** ChiThang  
**Date:** February 2026  
**License:** 
