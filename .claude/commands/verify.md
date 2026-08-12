Chạy verification chain theo protocol `/verify` trong `.claude/rules/session.md`.

Thứ tự bắt buộc — dừng tại bước đầu tiên fail:
1. **Lint**: `./workflow/ulint_verilog.sh <file.v>` — nếu không chỉ định file, lint tất cả file `.v` vừa được sửa trong session
2. **SoC sim**: `./workflow/urun_verilog.sh run_soc_ascon.v` — grep ERROR/FAIL trong output
3. **ASCON unit**: `iverilog -g2005 -o build_test ascon/tb/ascon_top_tb.v && vvp build_test`
4. **Firmware**: `cd gnu_toolchain && ./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c`

Báo kết quả: PASS/FAIL từng bước. Nếu FAIL → báo file:line cụ thể.
