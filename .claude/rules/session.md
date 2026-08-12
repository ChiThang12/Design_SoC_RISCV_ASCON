# Session Protocol

## /start — Kickoff Sprint
Chạy khi bắt đầu mỗi sprint để tìm lại chỗ dừng:

```bash
rtk git log -n 5        # xem 5 commit gần nhất
rtk git status          # uncommitted changes
```
Sau đó đọc `MEMORY.md` (nếu có) để recall decisions.

Báo tóm tắt:
```
Đang làm dở : <task từ commit/handoff gần nhất>
Chưa commit  : <files từ git status>
Đề xuất tiếp: <bước logic tiếp theo>
```

## /verify — Verification Chain
Chạy theo thứ tự — **dừng tại bước đầu tiên fail**, báo lỗi cụ thể (file:line):

```bash
# Bước 1: Lint
./workflow/ulint_verilog.sh <file.v>

# Bước 2: SoC simulation
./workflow/urun_verilog.sh run_soc_ascon.v
# Tìm ERROR/FAIL trong log

# Bước 3: ASCON unit test
iverilog -g2005 -o build_test ascon/tb/ascon_top_tb.v && vvp build_test

# Bước 4: Firmware build
cd gnu_toolchain && ./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c
```

## /handoff — Kết thúc Sprint
Ghi vào `.claude/handoff.md` (append, không overwrite):

```markdown
## YYYY-MM-DD HH:MM Session Summary

### Đã làm
- <list>

### Files thay đổi
- `<file>`: <1-line reason>

### Còn làm
- <list>

### Design decisions
- <non-obvious choices — tại sao chọn approach X>

### Known bugs chưa fix
- <nếu có>
```

## RTL vs Firmware — Agent Context
Khi nhận task, xác định domain:

| Domain | Hot files tự động xem xét |
|--------|--------------------------|
| RTL task (`.v`) | `ascon/interface/ascon_axi_slave.v` localparams khi liên quan ASCON register |
| FW task (`.c/.h`) | `gnu_toolchain/include/ascon.h`, `include/memory_map.h` |
| SoC integration | `soc_top.v` port list |

Không load file lớn tự động — chỉ khi task liên quan trực tiếp.
