# ASCON Firmware Test Task — Status & Bug Tracker

## Cách dùng
- Đọc "Current Sprint" trước khi làm bất kỳ thứ gì.
- Sau mỗi test → cập nhật Status Table.
- Sau mỗi fix → ghi vào Bug Tracker.
- Chỉ ghi kết quả đã chạy simulation thực, không ghi assumption.

---

## Current Sprint

**Focus**: ✅ FIXED root cause thật — CPU pipeline replay bug (KHÔNG phải stack overflow).

**Root cause (2026-06-18)**: `BUG-T3-STACK` trong doc cũ là SAI hướng — sp init đúng
`0x10001ff0`, stack frame run_dma_noad_test = `0x10001fa0` (trong DMEM). sp bị đẩy lên
`0x10002040` là HỆ QUẢ của một CPU pipeline bug:

> Instruction `addi sp,sp,16` (epilogue fill_plaintext, pc=0x578) **retire 11 lần**
> khi icache miss (`stall_if`) xảy ra đúng lúc nó ở EX stage. `stall_if` đóng băng ID/EX
> (giữ addi trong EX) nhưng KHÔNG đóng băng EX/MEM register → addi advance nhiều lần,
> và forwarding từ WB nuôi lại sp tăng dần (feedback loop) → sp += 16 × 11 = +0xB0.

**Fix đã apply & verify**:
- `cpu/riscv_cpu_core_v2.v`: `stall_ex_mem` thêm `| stall_if` → freeze EX/MEM cùng front-end.
- `cpu/core/PIPELINE_REG_EX_MEM.v`: pass-once dedup signature bỏ `alu_result_in`/`write_data_in`
  (chỉ giữ instruction identity = pc_plus_4 + control), và nhớ sig mọi lần pass.

**Regression kết quả (2026-06-18, sau fix)**:
```
T1 test_ascon_cpu8_noad  ✅ PASS    uart=82
T2 test_ascon_cpu8_ad    ✅ PASS    uart=82   (fixed bởi CPU pipeline fix)
T3 test_ascon_dma_noad   ✅ PASS    uart=82   (fixed bởi CPU pipeline fix)
T4 test_ascon_dma_ad     ✅ PASS    uart=82   (fixed: AD_ADDR firmware + AD-burst RTL)
T5 test_ascon_bench      ❌ FAIL    uart=44   [FAIL] cpu_noad (bench-specific, điều tra riêng)
```
> Validation T4: ctext block0 KHÁC T3 (T4=f760a78d... vs T3=68e2fccd...) dù cùng key/nonce/PT
> → AD được absorb đúng (AEAD behavior). AD read addr=0x10000330 len=0 (1 beat=8B đúng).
> KHÔNG regression: uart_simple/crt0/uart vẫn PASS; gpio/clint/plic/ascon(16blk)/dma_uart/
> integration/timer fail trên CẢ HEAD (pre-existing, không liên quan các fix này).

**Bước tiếp theo**:
```
1. [x] FIX CPU pipeline replay → T2, T3 PASS
2. [x] FIX T4 (2 bug): firmware AD_ADDR + RTL AD-burst sizing → PASS
3. [ ] FIX T5: bench cpu_noad fail (standalone T1 pass → bench flow/timing khác)
4. [ ] (tùy chọn) Verify T4 tag vs Python golden (lưu ý ascon.py là bản NIST, HW là ASCON-128 legacy)
5. [ ] Điền throughput/cycles (lưu ý: mcycle CSR hiện trả 0 — pre-existing, cả T1 cũng cyc=0)
```

---

## Status Table

| ID | File | Mode | AD | Payload | Build | Sim | Kết quả | Ghi chú |
|----|------|------|-----|---------|-------|-----|---------|--------|
| T1 | `test_ascon_cpu8_noad.c` | CPU-direct | Không | 1×8B | ✅ | ✅ | ✅ PASS | Latency baseline |
| T2 | `test_ascon_cpu8_ad.c` | CPU-direct | 8B | 1×8B | ✅ | ✅ | ✅ PASS | Fixed bởi CPU pipeline fix |
| T3 | `test_ascon_dma_noad.c` | DMA | Không | 16×8B | ✅ | ✅ | ✅ PASS | Fixed bởi CPU pipeline fix |
| T4 | `test_ascon_dma_ad.c` | DMA | 8B | 16×8B | ✅ | ✅ | ✅ PASS | Fixed: AD_ADDR + AD-burst sizing |
| T5 | `test_ascon_bench.c` | Tất cả | Cả hai | 1B+128B | ✅ | ❌ | ❌ FAIL | bench cpu_noad fail — điều tra riêng |
| SW | `gen_test_vectors_bench.py` | Python ref | Cả hai | Tất cả | N/A | N/A | ⚠️ | Tạo xong, chưa verify vs hardware |

**Legend**: ✅ PASS | ❌ FAIL | ⚠️ PARTIAL | ❓ Not done

---

## Performance Baseline (điền sau khi chạy sim)

| Mode | Cycles đo được | Throughput Mbps | Latency 10KB (μs) |
|------|---------------|-----------------|-------------------|
| CPU-direct 8B no AD | — | — | N/A (single block) |
| CPU-direct 8B + AD | — | — | N/A |
| DMA 128B no AD | — | — | — |
| DMA 128B + AD | — | — | — |

> Công thức: `throughput_mbps = payload_bytes * 800 / cycles`
> Latency 10KB extrapolated: `(10240 / 128) * cycles_128B * 10 / 1000` μs

---

## Bug Tracker

### OPEN

#### Bug #001 — DMA tests bị stall sau khi in header (T3, T4)
- **Triệu chứng**: T3/T4 chỉ in header (18/15 chars), sau đó CPU không tiếp tục → watchdog 800K fire
- **Fix đã apply** (2026-06-17):
  - Thêm `ASCON_WRITE(ASCON_OFS_IRQ_EN, 0x02u)` sau DATA_LEN write
  - Tăng `TIMEOUT_LIMIT` lên `0x003FFFFFu`
- **Kết quả**: Vẫn TIMEOUT sau fix → IRQ_EN không phải root cause chính
- **Debug tiếp (dma_noad_debug2.log)**: Xem BUG-T3-STACK — stack pointer ra ngoài DMEM là root cause thực
- **Files**: `gnu_toolchain/tests/test_ascon_dma_noad.c`, `test_ascon_dma_ad.c`
- **Status**: ⚠️ FIX APPLIED nhưng KHÔNG PASS → escalate sang BUG-T3-STACK

#### Bug #002 — CPU-direct + AD: CORE_DONE không bao giờ fire (T2)
- **Triệu chứng**: T2 timeout sau TIMEOUT_LIMIT=20000 iterations, CORE_DONE bit không set
- **Root cause khả năng cao**: RTL CONTROLLER FSM không xử lý AD path khi dùng CPU-direct mode
  - `ascon_set_ad()` ghi AD_DATA_0..3 (0x058–0x064) và AD_LEN (0x124)
  - Trong test_ascon.c, AD chỉ được dùng với DMA mode (không test CPU-direct+AD)
  - CONTROLLER có thể cần một sequence đặc biệt để xử lý AD trước khi CORE_START
- **Fix đề xuất**: Cần trace RTL — xem `ascon_CONTROLLER.v` để hiểu AD FSM states, verify `ascon_set_ad()` header macro viết đúng registers
- **Files**: `gnu_toolchain/tests/test_ascon_cpu8_ad.c`, `ascon/rtl/ascon_CONTROLLER.v`, `gnu_toolchain/include/ascon.h`

#### Bug #003 — bench in header 2 lần, rồi [FAIL] ascon_bench cpu_noad (T5)
- **Triệu chứng**: UART output = `[ASCON-BENCH]\r\n[ASCON-BENCH]\r\n[FAIL] ascon_bench cpu_noad\r` (58 bytes)
- **Phân tích**: Theo disassembly, lần 2 header + [FAIL] cpu_noad → run_cpu_enc bị timeout ở lần gọi thứ 2
  - Lần 1: run_bench_test → header → run_cpu_enc (pass silently) → run_dma_enc bắt đầu → SOMETHING xảy ra → main() khởi động lại?
  - Lần 2: run_cpu_enc timeout → `[FAIL] ascon_bench cpu_noad`
  - Khả năng: sau khi DMA start, ASCON bị stuck state; lần gọi run_cpu_enc thứ 2 (sau ASCON stuck) → ascon_soft_reset không reset đúng → CORE_DONE không fire
- **Dependency**: Phụ thuộc vào Bug #001 fix trước — nếu DMA hoạt động đúng thì bench flow sẽ đúng
- **Files**: `gnu_toolchain/tests/test_ascon_bench.c`

---

#### BUG-T3-STACK — Stack pointer ra ngoài DMEM valid range (T3, T4)
- **Severity**: HIGH — root cause của TIMEOUT
- **Triệu chứng phát hiện qua $display trace**:
  ```
  [ST] addr=0x1000203c  data=0x00010203  strb=1111   ← sw k0, 12(sp)
  [ST] addr=0x10002038  data=0x04050607  strb=1111   ← sw k1, 8(sp)
  [ST] addr=0x10002034  data=0x08090A0B  strb=1111   ← sw k2, 4(sp)
  [ST] addr=0x10002030  data=0x0C0D0E0F  strb=1111   ← sw k3, 0(sp)
  ```
  → `sp = 0x10002030` tại entry của `ascon_set_key()`. DMEM chỉ valid đến `0x10001FFF`.
  → sp vượt quá 0x31 bytes = 49 bytes vào vùng unmapped.
- **Side effect**: Mỗi `fence w,w` trong ASCON_WRITE → DCache flush → dirty line ở index=3 (addr 0x10002030) bị evict → AXI write → DECERR slave → evict_done pulse → overhead ~150 cycles/write × 17 writes = ~2500 cycles.
- **Tất cả 17 ASCON writes ĐÃ COMPLETE** (confirmed bởi trace), kể cả CTRL=0x5 (DMA start). Vấn đề là DMA_DONE không fire hoặc UART [PASS] không in được trong 800K cycles còn lại do overhead.
- **Root cause hypothesis**: `__stack_top` trong linker script sai (không phải 0x10001FF0) HOẶC run_dma_noad_test() có stack frame quá lớn → sp giảm vượt DMEM xuống (nhưng DMEM là từ 0x10000000 lên → lạ), HOẶC sp được init ở địa chỉ cao bất thường.
- **Debug path**:
  1. Đọc `gnu_toolchain/test_ascon_dma_noad.map` → verify `__stack_top` thực tế
  2. Xem disassembly `_start` tại offset 0x00 → xem `la sp, __stack_top` được load bao nhiêu
  3. Xem main → run_dma_noad_test frame allocation (hiện tại là -64 tại 0x580)
- **Files**: `gnu_toolchain/compile_c_to_hex.sh` (linker script), `test_ascon_dma_noad.map`
- **Status**: ❌ NOT FIXED — cần verify `.map` trước

---

#### BUG-T3-DCACHE-DECERR — DCache evict dirty stack line vào unmapped address
- **Severity**: MEDIUM — hệ quả của BUG-T3-STACK, không phải root cause độc lập
- **Cơ chế**: Mỗi `fence w,w` (16 lần trong ascon_set_key/nonce) → FLUSH_SCAN → dirty bit index=3 (tag=0x040008 → evict_addr=0x10002030) → AXI write → DECERR → overhead.
- **Confirmation**: DECERR slave trả BVALID với BRESP=0b11 → evict_done fire → flush tiếp tục bình thường. Không gây deadlock, nhưng gây overhead ~150 cycles/write.
- **Fix**: Sẽ tự resolve khi BUG-T3-STACK được fix (sp về đúng range → không còn dirty line ở 0x10002030).
- **Status**: ❌ NOT FIXED (dependent on BUG-T3-STACK)

---

### CLOSED

| Bug ID | Mô tả | Fix | Ngày |
|--------|-------|-----|------|
| CPU-REPLAY-SP | `addi sp,sp,16` retire 11× khi icache miss → sp hỏng +0xB0 → DECERR/hang (T2,T3). Doc cũ chẩn sai là "stack overflow". | `stall_ex_mem \|= stall_if` (freeze EX/MEM cùng front-end) + dedup signature bỏ data fields trong `PIPELINE_REG_EX_MEM.v` | 2026-06-18 |
| BUG-T4-DMA-AD-1 | DMA đọc AD từ `AD_ADDR=0x0` (firmware không set) → AXI read 0x0 → hang. Firmware cấp AD qua AD_DATA register (đường CPU-direct), DMA mode lại fetch AD từ memory. | Firmware `test_ascon_dma_ad.c`: ghi AD vào DMEM buffer (0x10000330) + set `AD_ADDR`/`AD_LEN` thay vì `ascon_set_ad()` | 2026-06-18 |
| BUG-T4-DMA-AD-2 | AD read dùng payload burst_len=7 (8 beats=64B) cho AD 1 block → RD FIFO (depth 4) đầy, AD pump pop 1 block → read engine stall → DMA deadlock. | RTL `dma_ctrl_fsm.v`: burst length theo phase (`ad_burst_len = ad_total_blocks-1` cap RD_FIFO_DEPTH), wire `rd_burst_len` tới read engine qua `ascon_dma.v` | 2026-06-18 |
| Bug #001 | T3 stall sau header | = CPU-REPLAY-SP (không phải IRQ_EN/stack) | 2026-06-18 |
| Bug #002 | T2 CORE_DONE không fire | = CPU-REPLAY-SP (sp hỏng làm setup sai) | 2026-06-18 |
| BUG-T3-STACK | sp=0x10002040 ngoài DMEM | TRIỆU CHỨNG của CPU-REPLAY-SP, không phải root cause | 2026-06-18 |

---

## Thứ tự chạy tối thiểu để declare "ASCON firmware verified"

```
T1 ✅ → T2 ✅ → T3 ✅ → T4 ✅
               ↓
           T5 ✅ (cross-mode CT+TAG match)
               ↓
    SW golden ✅ (byte-for-byte match với Python)
               ↓
         ASCON FIRMWARE VERIFIED → sẵn sàng FPGA integration
```

---

## Uncommitted Changes

```bash
# Files đã tạo/sửa (chưa commit):
gnu_toolchain/tests/test_ascon_cpu8_noad.c   (T1 — PASS)
gnu_toolchain/tests/test_ascon_cpu8_ad.c     (T2 — Bug #002)
gnu_toolchain/tests/test_ascon_dma_noad.c    (T3 — Bug #001)
gnu_toolchain/tests/test_ascon_dma_ad.c      (T4 — Bug #001+#002)
gnu_toolchain/tests/test_ascon_bench.c       (T5 — Bug #003)
gnu_toolchain/tests/test_ascon_*.hex         (built artifacts)
ascon/SW_check/gen_test_vectors_bench.py     (SW — tạo xong)
regression_full.sh                           (updated: thêm 5 tests)
```

---

## Tham chiếu nhanh

```bash
# Build tất cả
cd gnu_toolchain
for f in cpu8_noad cpu8_ad dma_noad dma_ad bench; do
    ./compile_c_to_hex.sh -i tests/test_ascon_${f}.c -o tests/test_ascon_${f}.hex -O 0
done

# Chạy song song
bash regression_full.sh -j test_ascon_cpu8_noad test_ascon_cpu8_ad \
                             test_ascon_dma_noad test_ascon_dma_ad test_ascon_bench

# Xem kết quả nhanh
grep -E "throughput|cycles|PASS|FAIL|tag=" log/test_ascon_bench.log
```
