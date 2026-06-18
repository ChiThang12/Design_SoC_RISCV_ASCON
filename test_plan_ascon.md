# ASCON Firmware Test Plan — Camera JPEG Pipeline

## 1. Use Case Overview

```
[Laptop Camera] → JPEG compress → (UART/interface) → [SoC DMEM]
                                                           ↓
                                               [ASCON Accelerator]
                                                  DMA reads PT
                                                  Encrypts → CT
                                                           ↓
                                              [DMEM CT buffer] → [FPGA] → [Display]
```

**Frame parameters:**
- Format: JPEG compressed, ~5–20 KB/frame
- AD: frame header `{frame_id[31:0], timestamp[31:0]}` = 8 bytes
- Target: 30 fps → 33ms/frame budget
- At 478 Mbps DMA: 10KB frame = 167μs → **<0.5% of frame budget** ✓

---

## 2. Test Modes — 4 Files + 1 Bench

| File | Mode | AD | Payload | Mục tiêu |
|------|------|-----|---------|---------|
| `test_ascon_cpu8_noad.c` | CPU-direct 8B | Không | 1 block (8B) | Latency baseline 1 session |
| `test_ascon_cpu8_ad.c` | CPU-direct 8B | 8B | 1 block (8B) | AD overhead per session |
| `test_ascon_dma_noad.c` | DMA 16-block | Không | 128B (16×8B) | Throughput tối đa DMA |
| `test_ascon_dma_ad.c` | DMA 16-block | 8B | 128B (16×8B) | Full AEAD pipeline (gần JPEG nhất) |
| `test_ascon_bench.c` | Tất cả | Cả hai | 1B + 128B | Cross-mode comparison table |

> **Ghi chú kiến trúc:**
> - CPU-direct = **single AEAD session** per call (`slave_data_last=1'b1` hardwired trong AXI slave line 295)
> - DMA = **multi-block AEAD** (CONTROLLER loop DATA_LOAD→DATA_PERM cho N blocks)
> - CPU-direct multi-block (4250 Mbps) cần thêm PTEXT_2/3 vào RTL → **chưa implement**

---

## 3. Performance Targets

| Mode | Lý thuyết | Thực đo (mục tiêu) | Bottleneck |
|------|-----------|---------------------|------------|
| CPU-direct 8B, no AD | latency ~30–50 cycles/session | < 60 cycles | AXI write overhead |
| CPU-direct 8B, with 8B AD | +6 cycles (pb) vs no AD | < 70 cycles | AD phase (S_AD_LOAD + S_AD_PERM) |
| DMA, no AD | 478 Mbps | > 400 Mbps | 32-bit AXI + RD_FIFO_DEPTH=4 |
| DMA, with 8B AD | 478 Mbps − AD overhead | > 380 Mbps | +1 AD block overhead |

**Throughput tính theo công thức:**
```
throughput_mbps = (payload_bytes * 800) / cycles_total
                   ^--- = bytes * 8bits * 100MHz / cycles / 1e6
```

**Latency JPEG frame (extrapolated từ 128B test → 10KB):**
```
latency_us = (10240 / 128) * cycles_128B * 10ns / 1000
```

---

## 4. Hardware Configuration (tối đa throughput)

```c
/* DMA tối đa trong giới hạn RD_FIFO_DEPTH=4 (64-bit entries) */
ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);   // ARLEN=7 → 8 beats × 4B = 32B = 4 FIFO entries

/* Fence pattern chuẩn — không bỏ, không di chuyển */
__asm__ volatile ("fence rw,rw" ::: "memory");   // trước DMA_START
ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);
// ... wait DMA_DONE ...
__asm__ volatile ("fence r,r" ::: "memory");     // sau DMA_DONE trước đọc CT

/* Poll loop tối ưu — 8 NOP để không saturate AXI bus */
do {
    __asm__ volatile ("nop;nop;nop;nop;nop;nop;nop;nop" ::: "memory");
    ASCON_READ(ASCON_OFS_STATUS, status);
} while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR)));
```

---

## 5. Test Keys & Vectors (shared across all tests)

```c
/* Standard test vector — dùng cho tất cả tests để so sánh cross-mode */
#define TV_KEY_0    0x00010203u
#define TV_KEY_1    0x04050607u
#define TV_KEY_2    0x08090A0Bu
#define TV_KEY_3    0x0C0D0E0Fu

#define TV_NONCE_0  0x10111213u
#define TV_NONCE_1  0x14151617u
#define TV_NONCE_2  0x18191A1Bu
#define TV_NONCE_3  0x1C1D1E1Fu

/* AD = frame header: "FRMH" (4B) + frame_id=1 (4B) = 8 bytes, 1 AD block */
#define TV_AD_W0    0x46524D48u   /* "FRMH" */
#define TV_AD_W1    0x00000001u   /* frame_id = 1 */
#define TV_AD_LEN   8u

/* Plaintext block 0 (dùng cho CPU-direct single-block test) */
#define TV_PT_W0    0xA0000000u
#define TV_PT_W1    0xB0000000u

/* DMA plaintext: 16 blocks — block[i] = {0xA0000000|i, 0xB0000000|i} */
#define TV_DMA_N_BLOCKS    16u
#define TV_DMA_PAYLOAD_B   128u    /* = 16 × 8 */
```

---

## 6. Output Format (UART)

Mỗi test in ra UART theo format chuẩn (dễ parse):

```
[ASCON-CPU8-NOAD]
  mode=CPU-direct blocks=1 bytes=8
  cycles_total=XXXXXXXX
  throughput_mbps=XXXX
  ct=XXXXXXXX XXXXXXXX
  tag=XXXXXXXX XXXXXXXX XXXXXXXX XXXXXXXX
  [PASS] ascon_cpu8_noad

[ASCON-DMA-AD]
  mode=DMA blocks=16 bytes=128
  cycles_total=XXXXXXXX
  throughput_mbps=XXXX
  latency_10k_us=XXX
  tag=XXXXXXXX XXXXXXXX XXXXXXXX XXXXXXXX
  [PASS] ascon_dma_ad
```

**Giải thích latency_10k_us**: extrapolated latency cho 10KB JPEG frame.

---

## 7. Correctness Check — Cross-Mode Comparison

**Test bench cross-check:**
1. CPU-direct 1 block (no AD) → lưu CT0, TAG0
2. DMA 1 block (no AD, DMA_LEN=8) → lưu CT1, TAG1
3. **Verify CT0 == CT1 AND TAG0 == TAG1** → nếu match → cả hai mode đúng

**SW golden reference:**
```bash
python3 ascon/SW_check/gen_test_vectors_bench.py
# Output: golden_cpu8_noad.txt, golden_dma_ad.txt, ...
# Dùng để verify SoC output khi chạy simulation
```

---

## 8. Cách chạy từng Test

### Build firmware
```bash
cd gnu_toolchain
# Build từng test
./compile_c_to_hex.sh -i tests/test_ascon_cpu8_noad.c  -o tests/test_ascon_cpu8_noad.hex  -O 0
./compile_c_to_hex.sh -i tests/test_ascon_cpu8_ad.c    -o tests/test_ascon_cpu8_ad.hex    -O 0
./compile_c_to_hex.sh -i tests/test_ascon_dma_noad.c   -o tests/test_ascon_dma_noad.hex   -O 0
./compile_c_to_hex.sh -i tests/test_ascon_dma_ad.c     -o tests/test_ascon_dma_ad.hex     -O 0
./compile_c_to_hex.sh -i tests/test_ascon_bench.c      -o tests/test_ascon_bench.hex      -O 0
```

### Chạy SoC simulation
```bash
# Từng test
bash regression_full.sh test_ascon_cpu8_noad
bash regression_full.sh test_ascon_cpu8_ad
bash regression_full.sh test_ascon_dma_noad
bash regression_full.sh test_ascon_dma_ad
bash regression_full.sh test_ascon_bench

# Tất cả song song (~90s)
bash regression_full.sh -j test_ascon_cpu8_noad test_ascon_cpu8_ad test_ascon_dma_noad test_ascon_dma_ad test_ascon_bench
```

### Đọc kết quả
```bash
rtk read log/test_ascon_cpu8_noad.log
rtk read log/test_ascon_bench.log
grep -E "throughput|cycles|latency|PASS|FAIL" log/test_ascon_bench.log
```

---

## 9. Điều kiện Pass

| Test | Pass | Fail |
|------|------|------|
| cpu8_noad | `[PASS] ascon_cpu8_noad` in log, cycles < 200 | timeout hoặc tag = 0 |
| cpu8_ad | `[PASS] ascon_cpu8_ad`, cycles < 250 | timeout hoặc tag = 0 |
| dma_noad | `[PASS] ascon_dma_noad`, throughput > 400 Mbps | DMA_ERR hoặc timeout |
| dma_ad | `[PASS] ascon_dma_ad`, throughput > 380 Mbps | DMA_ERR hoặc TAG_MISMATCH |
| bench | Cross-mode CT+TAG match, comparison table printed | CT mismatch giữa CPU và DMA |

---

## 10. Debug Flow khi Fail

```
DMA timeout → kiểm tra:
  1. CTRL=0x5 (DMA_EN | CORE_START) → KHÔNG dùng 0x4
  2. fence rw,rw TRƯỚC DMA_START
  3. DMA_LEN aligned? (bội số 8B cho ASCON-128)
  4. DMA_BURST ≤ 7 (RD_FIFO_DEPTH=4 → max 8 beats × 4B = 32B per burst)
  5. ★ IRQ_EN=0x02 phải được ghi TRƯỚC DMA_START (thiếu → poll không complete đúng cách)

TAG mismatch → kiểm tra:
  1. AD_LEN đúng (8 với AD, 0 không AD) → ASCON_OFS_AD_LEN = 0x124
  2. AD_DATA_0/1 viết đúng (0x46524D48, 0x00000001)
  3. ascon_soft_reset() trước mỗi session
  4. Key/Nonce giống nhau giữa encrypt và verify

CPU-direct timeout → kiểm tra:
  1. CTRL=0x1 (CORE_START, không phải DMA_START)
  2. DATA_LEN=8 viết trước CORE_START
  3. Poll ASCON_ST_CORE_DONE (bit1), không phải ASCON_ST_DMA_DONE (bit3)
```

### 10.1. DCache & Stack Debug — Phát hiện từ session 2026-06-17

**Vấn đề đặc thù của DMA tests** (T3/T4): Do CPU -O0, mỗi hàm `ascon_set_key/nonce` lưu tham số xuống stack trước khi ghi MMIO. Nếu stack pointer ra ngoài DMEM valid range (0x10000000–0x10001FFF), DCache sẽ:
1. Cache các store đó vào dirty line nằm ngoài DMEM
2. Khi `fence w,w` được gọi (sau mỗi ASCON_WRITE) → flush dirty lines
3. Evict line đó qua AXI write → DECERR slave (unmapped) → overhead ~150 cycles/write

**Verify trình tự** khi DMA timeout dù ASCON writes thấy OK:
```bash
# Thêm DEBUG_DCACHE vào run_soc_ascon.v
`define DEBUG_DCACHE

# Xem trong log:
grep "NC-WRITE-DONE\|FLUSH-EVICT-ADDR\|EV-B-DONE" log/test_ascon_dma_noad.log
# Nếu thấy FLUSH-EVICT-ADDR với addr > 0x10001FFF → stack overflow

# Kiểm tra __stack_top trong linker map
grep "__stack_top\|_stack" gnu_toolchain/test_ascon_dma_noad.map
```

**Kiểm tra trong disassembly `_start`**:
```bash
# __stack_top phải = 0x10001FF0
grep -A 3 "<_start>" gnu_toolchain/test_ascon_dma_noad.dump
# Tìm: lui/addi load sp → so sánh với 0x10001FF0
```

**Xác nhận ASCON writes OK vs DMA_DONE không fire**:
Nếu log thấy tất cả 17 `[ASCON]` NC-WRITE-DONE (addr=0x2000xxxx) kể cả CTRL=0x5 mà vẫn timeout → vấn đề là ở ASCON DMA engine sau khi nhận CTRL, không phải ở AXI path. Trace thêm:
```verilog
// ascon/dma/rtl/dma_ctrl_fsm.v — theo dõi pump_state
$display("[%0t][DMA-FSM] pump_state=%0d", $time, pump_state);
```

---

## 11. Lộ trình FPGA Integration

```
Bước 1: [SIM] Tất cả 5 test PASS → firmware API verified
Bước 2: [SIM] bench cross-mode match → CT identical giữa CPU và DMA
Bước 3: [FPGA] Flash firmware, verify UART output với Python golden reference
Bước 4: [FPGA] Kết nối camera → DMEM pipeline
         - UART RX → buffer → DMEM: receive JPEG frame
         - ASCON DMA encrypt → CT buffer
         - FPGA display controller đọc CT buffer → decode → display
Bước 5: [PERF] Đo FPS thực tế, tune nếu latency quá lớn
         - Nếu bottleneck DMA: xem xét tăng RD_FIFO_DEPTH (RTL)
         - Nếu bottleneck UART RX: tăng baud rate hoặc dùng SPI
```

---

## 12. Tương lai — Tăng Throughput thêm

| Cải tiến | Loại | Throughput dự kiến | Effort |
|---------|------|-----------------|--------|
| Tăng RD_FIFO_DEPTH 4→8 | RTL | ~600 Mbps | Nhỏ |
| Bỏ width converter (AXI 64-bit) | RTL | ~900 Mbps | Trung bình |
| DMA block size 8B→16B (ASCON-128a) | RTL | ~1200 Mbps | Trung bình |
| Thêm PTEXT_2/3 cho CPU-direct 16B | RTL | 4250 Mbps (single-block) | Nhỏ |
| DMA + WFI interrupt (giải phóng CPU) | Firmware | Không tăng Mbps, CPU free | Nhỏ |
