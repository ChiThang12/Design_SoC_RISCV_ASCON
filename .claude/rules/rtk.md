# RTK Rules — Token Optimization cho AI Agent

## 1. Nguyên tắc chính
RTK (Rust Token Killer) là CLI proxy giảm 60-90% token output.
**Mọi lệnh shell PHẢI dùng `rtk` prefix** trừ khi lệnh không có rtk equivalent.

## 2. Bảng thay thế lệnh

### Files & Navigation
| Thay vì | Dùng | Tiết kiệm |
|---------|------|-----------|
| `ls -la` | `rtk ls .` | −80% |
| `cat file` | `rtk read file` | −70% |
| `head -n 50 file` | `rtk read file` | −70% |
| `tail -n 50 file` | `rtk read file` | −70% |
| `find . -name "*.v"` | `rtk find "*.v" .` | −80% |
| `grep -rn "pattern" .` | `rtk grep "pattern" .` | −80% |
| `wc -l file` | `rtk wc file` | −80% |
| `diff file1 file2` | `rtk diff file1 file2` | −75% |

### Git
| Thay vì | Dùng | Tiết kiệm |
|---------|------|-----------|
| `git status` | `rtk git status` | −80% |
| `git diff` | `rtk git diff` | −75% |
| `git log` | `rtk git log -n 10` | −80% |
| `git add .` | `rtk git add .` | −92% |
| `git commit -m "msg"` | `rtk git commit -m "msg"` | −92% |
| `git push` | `rtk git push` | −92% |

### Build & Test (dự án này)
| Thay vì | Dùng | Tiết kiệm |
|---------|------|-----------|
| `iverilog ... && vvp ...` | `~/workflow/urun_verilog.sh <file.v>` | Script chuẩn |
| Đọc log simulation | `rtk read <file>.log` | −70% |
| `iverilog -Wall -tnull` | `~/workflow/ulint_verilog.sh <file.v>` | Script chuẩn |

## 3. Đặc biệt cho dự án Verilog/SoC

### Simulation
```bash
# ĐÚNG: dùng workflow script (đã tối ưu)
~/workflow/urun_verilog.sh run_soc_ascon.v
rtk read run_soc_ascon.log

# ĐÚNG: lint
~/workflow/ulint_verilog.sh ascon/ascon_top.v
rtk read ascon_top.log

# SAI: chạy trực tiếp (output dài, tốn token)
iverilog -g2005 -o sim.vvp run_soc_ascon.v
vvp sim.vvp
```

### Firmware Build
```bash
# Build firmware → đọc kết quả bằng rtk
cd gnu_toolchain
./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c
rtk read main.dump           # disassembly (compact)
rtk read main.map            # linker map (compact)
```

### Tìm kiếm code
```bash
# Tìm signal trong RTL
rtk grep "core_aead_start" ascon/
rtk grep "pump_state" ascon/dma/

# Tìm register offset
rtk grep "ASCON_OFS_" gnu_toolchain/include/ascon.h

# Tìm tất cả module instantiation
rtk grep "\\." soc_top.v
```

## 4. Advanced RTK commands

```bash
# Đọc file chỉ lấy signatures (bỏ function body)
rtk read file.v -l aggressive

# Tóm tắt file nhanh 2 dòng
rtk smart file.v

# Xem token savings
rtk gain
rtk gain --graph

# Tìm cơ hội tiết kiệm chưa dùng
rtk discover

# Pass-through khi cần output gốc (debug)
rtk proxy <command>
```

## 5. Khi KHÔNG dùng rtk
- Lệnh interactive cần user input (ví dụ: `gtkwave`)
- Lệnh cần output binary (`objcopy`, `hexdump`)
- Khi cần output chính xác 100% byte-for-byte để debug
  → Dùng `rtk proxy <cmd>` để vẫn tracking nhưng không filter