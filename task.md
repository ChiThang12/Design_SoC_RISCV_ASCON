---

## Task List (task.md)

### [TB] Testbench run_soc_ascon.v
- [ ] **TB-1**: Thêm biến `pass_cnt`, `fail_cnt`, `all_pass_detected` vào declaration section
- [ ] **TB-2**: Thêm UART pass/fail pattern matcher (sau newline detection, quét `uart_line`)
- [ ] **TB-3**: Thêm wire taps S11 (`s11_aw_valid`, `s11_aw_addr`, `s11_w_data`, `s11_ar_addr`)
- [ ] **TB-4**: Thêm always block monitor S11 với register decode
- [ ] **TB-5**: Thêm always block GPIO change monitor
- [ ] **TB-6**: Cập nhật `print_report()` task với TEST RESULTS section

### [FW] Firmware DMA
- [ ] **FW-1**: Tạo file `gnu_toolchain/tests/test_dma.c` với skeleton + UART init
- [ ] **FW-2**: Implement Test 1 (CH0 polling 256B)
- [ ] **FW-3**: Implement Test 2 (CH1 IRQ-driven 64B + ISR)
- [ ] **FW-4**: Implement Test 3 (CH2+CH3 simultaneous)
- [ ] **FW-5**: Implement Test 4 (alignment error)
- [ ] **FW-6**: Thêm `test_dma.c` vào `build_all.sh`
- [ ] **FW-7**: Thêm `test_dma.c` vào `test_integration.c` (→ 7/7)

### [VERIFY] Xác nhận
- [ ] **V-1**: Build: `./build_all.sh` → check `test_dma.hex` tồn tại
- [ ] **V-2**: Run `test_dma.hex` qua `run_soc_ascon.v` → tìm `[TEST-RESULT] *** PASS ***`
- [ ] **V-3**: Run `test_integration.hex` → tìm `ALL_PASS 7/7`

---

## Verification

```bash
# Build
cd gnu_toolchain && ./build_all.sh

# Chạy test DMA riêng
cp tests/test_dma.hex ../memory/program.hex
~/workflow/run_verilog.sh ../run_soc_ascon.v
rtk read ../run_soc_ascon.log   # tìm [TEST-RESULT] PASS, [S11-DMA] WRITE

# Chạy integration (7 tests)
cp tests/test_integration.hex ../memory/program.hex
~/workflow/run_verilog.sh ../run_soc_ascon.v
rtk read ../run_soc_ascon.log   # tìm ALL_PASS 7/7, TESTS: PASS=7 FAIL=0
```
