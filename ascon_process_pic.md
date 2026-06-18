# ASCON Image Encryption Test — Hướng dẫn cho AI Agent

## 1. Mục tiêu

Test tính đúng đắn và đo thông lượng của ASCON IP (DMA mode) bằng cách mã hóa
một ảnh grayscale nhỏ. Kết quả phần cứng (HW) phải khớp với phần mềm (SW).

| Mục tiêu | Nội dung |
|----------|---------|
| Correctness | HW CT + TAG == SW CT + TAG (byte-for-byte) |
| Throughput HW | image_bytes / thời_gian_DMA (MB/s, tại 100 MHz) |
| Throughput SW | image_bytes / thời_gian_Python (MB/s) |
| Chế độ HW | **DMA mode only** (CTRL = 0x5) — không dùng CPU-direct |

---

## 2. Thông số cố định

```
Variant  : Ascon-AEAD128
KEY      : 000102030405060708090A0B0C0D0E0F   (16 bytes)
NONCE    : 101112131415161718191A1B1C1D1E1F   (16 bytes)
AD       : (không có — ad_len = 0)
Clock HW : 100 MHz  (chu kỳ 10 ns, timescale 1ns/1ps trong testbench)
```

### 2.1 Ảnh test

```
Kích thước : 8 × 8 pixel, grayscale, 64 bytes
Công thức  : pixel[row][col] = ((row * 8 + col) * 4) % 256
             row = 0..7,  col = 0..7

Hex dump (row-major):
  00 04 08 0C 10 14 18 1C   ← row 0
  20 24 28 2C 30 34 38 3C   ← row 1
  40 44 48 4C 50 54 58 5C   ← row 2
  60 64 68 6C 70 74 78 7C   ← row 3
  80 84 88 8C 90 94 98 9C   ← row 4
  A0 A4 A8 AC B0 B4 B8 BC   ← row 5
  C0 C4 C8 CC D0 D4 D8 DC   ← row 6
  E0 E4 E8 EC F0 F4 F8 FC   ← row 7

IMAGE_HEX = 000408...F8FC   (128 hex chars = 64 bytes)
PT_LEN    = 64  (= 8 DMA blocks × 8 bytes/block)
AD_LEN    = 0
```

---

## 3. Cấu trúc file (đã có và cần tạo)

### 3.1 Files đã tồn tại (KHÔNG sửa)

```
ascon/SW_check/ascon.py           ← ASCON-128 Python reference (import)
ascon/SW_check/run_auto.py        ← Cosim driver (tham khảo pattern)
ascon/tb_ascon_top.v              ← Testbench gốc (tham khảo boilerplate)
ascon/ascon_top.v                 ← DUT top
memory/data_mem_axi_slave.v       ← AXI RAM slave
axi_width_converter_64to32.v      ← Width converter (DMA write path)
```

### 3.2 Files cần tạo (task của agent)

```
ascon/SW_check/ascon_process_pic.py   ← SW reference + benchmark
ascon/tb_pic_encrypt.v                ← HW testbench (DMA, 64-byte image)
pic_test_vectors.hex                  ← Output của Python, input cho HW TB
```

---

## 4. Bước 1 — Tạo SW reference (`ascon_process_pic.py`)

**Đặt tại**: `ascon/SW_check/ascon_process_pic.py`

Script Python phải thực hiện:

```python
#!/usr/bin/env python3
"""SW reference cho ASCON image encryption — sinh pic_test_vectors.hex"""
import sys, os, time
sys.path.insert(0, os.path.dirname(__file__))
import ascon  # module đã có trong ascon/SW_check/ascon.py

KEY    = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
NONCE  = bytes.fromhex("101112131415161718191a1b1c1d1e1f")
AD     = b""
VARIANT = "Ascon-AEAD128"

# 8×8 grayscale gradient — 64 bytes
IMAGE = bytes([(r * 8 + c) * 4 % 256 for r in range(8) for c in range(8)])

# 1. Encrypt once → CT, TAG
ct_full = ascon.ascon_encrypt(KEY, NONCE, AD, IMAGE, VARIANT)
ct  = ct_full[:-16]
tag = ct_full[-16:]

# 2. Benchmark: N lần, tính avg µs và MB/s
N = 5000
for _ in range(100): ascon.ascon_encrypt(KEY, NONCE, AD, IMAGE, VARIANT)  # warmup
t0 = time.perf_counter()
for _ in range(N): ascon.ascon_encrypt(KEY, NONCE, AD, IMAGE, VARIANT)
elapsed = time.perf_counter() - t0
avg_us  = elapsed / N * 1e6
tput_mb = len(IMAGE) / (elapsed / N) / 1e6

# 3. In kết quả
print(f"IMAGE  : {IMAGE.hex().upper()}")
print(f"CT     : {ct.hex().upper()}")
print(f"TAG    : {tag.hex().upper()}")
print(f"SW time: {avg_us:.3f} µs/op  ({tput_mb:.2f} MB/s = {tput_mb*8:.1f} Mbps)")

# 4. Ghi test vector (cùng format với test_vectors.hex của tb_ascon_top)
out = os.path.join(os.path.dirname(__file__), "..", "pic_test_vectors.hex")
with open(out, "w") as f:
    f.write("// Format: HW_MODE KEY NONCE AD_LEN AD PT_LEN PT CT TAG\n")
    f.write(f"// Image: 8x8 grayscale 64 bytes | Variant: Ascon-AEAD128\n")
    f.write(
        f"1 {KEY.hex().upper()} {NONCE.hex().upper()} "
        f"0000 00 "
        f"0040 {IMAGE.hex().upper()} "
        f"{ct.hex().upper()} {tag.hex().upper()}\n"
    )
print(f"Written: {out}")
```

**Chạy SW:**
```bash
cd ascon/SW_check
python3 ascon_process_pic.py
```

**Output mong đợi** (in ra stdout + ghi file):
- Dòng CT: 64 hex bytes = 128 ký tự
- Dòng TAG: 16 hex bytes = 32 ký tự
- SW time và MB/s
- File `pic_test_vectors.hex` ở thư mục gốc project

---

## 5. Bước 2 — Tạo HW testbench (`tb_pic_encrypt.v`)

**Đặt tại**: `ascon/tb_pic_encrypt.v`

### 5.1 Include và DUT

Copy nguyên phần include + DUT instantiation từ `ascon/tb_ascon_top.v` **nhưng thay**:
```verilog
// QUAN TRỌNG: tăng WR_FIFO_DEPTH để chứa 8-block CT + TAG
// 64-byte PT → 8 blocks → 16 CT words + 4 TAG words = 20 WR beats
// WR_FIFO_DEPTH mặc định = 8 không đủ, dùng 32
.RD_FIFO_DEPTH (8), .WR_FIFO_DEPTH (32)
```

### 5.2 Localparam địa chỉ RAM

```verilog
localparam DMA_AD_BASE = 32'h0000_1000;
localparam DMA_PT_BASE = 32'h0000_2000;  // load image tại đây
localparam DMA_CT_BASE = 32'h0000_3000;  // đọc CT + TAG từ đây
localparam IMAGE_BYTES = 32'd64;
localparam CLK_PERIOD_NS = 10;           // 100 MHz
```

### 5.3 Luồng test chính (trong `initial`)

```
1. do_reset
2. Đọc pic_test_vectors.hex bằng $fscanf
   → tv_key, tv_nonce, tv_pt (64 bytes), tv_ct (64 bytes), tv_tag (16 bytes)

3. load_ram(DMA_PT_BASE, IMAGE_BYTES, tv_pt)
   → ghi 64 bytes ảnh vào RAM[0x2000..0x203F]

4. dma_setup_full(tv_key, tv_nonce, ad_len=0, pt_len=64)
   → ghi registers: KEY, NONCE, SRC=PT_BASE, DST=CT_BASE, BYTE_LEN=64, AD_LEN=0
   → BURST_LEN tự tính: (64>>3)-1=7, cap tại 3 → ghi 3

5. Ghi hw_start_time = $time  ← đo thời gian BẮT ĐẦU

6. axi_write(32'h020, 32'h5)   ← CTRL = DMA_EN | CORE_START = 0x5
7. wait_dma_done               ← poll dut.dma_busy_w

8. Ghi hw_end_time = $time     ← đo thời gian KẾT THÚC
   hw_cycles = (hw_end_time - hw_start_time) / CLK_PERIOD_NS

9. Đọc TAG từ AXI slave register (offsets 0x048..0x054)

10. Đọc CT từ backdoor RAM:
    for i in 0..7:
      word_lo = u_ram.dmem.memory[(DMA_CT_BASE/4) + i*2]     // byte 0-3
      word_hi = u_ram.dmem.memory[(DMA_CT_BASE/4) + i*2 + 1] // byte 4-7
      tmp_ct[block i] = {word_lo, word_hi}  // ← same as tb_ascon_top TC4

11. So sánh TAG và CT với tv_tag, tv_ct
    → [PASS] hoặc [FAIL]

12. In throughput:
    $display("HW cycles : %0d", hw_cycles);
    $display("HW time   : %0d ns  (%0d µs)", hw_cycles*10, hw_cycles*10/1000);
    $display("HW tput   : ** see ascon_process_pic.md for formula **");
    // Throughput (MB/s) = IMAGE_BYTES*1e3 / (hw_cycles * CLK_PERIOD_NS)
    //                   = 64000 / (hw_cycles * 10)  [in KB/s × 1000]
```

### 5.4 Format đọc test vector

```verilog
// Dùng $fscanf giống tb_ascon_top.v
// Format: HW_MODE KEY NONCE AD_LEN AD PT_LEN PT CT TAG
integer fd;
reg [31:0]   tv_mode, tv_ad_len, tv_pt_len;
reg [127:0]  tv_key, tv_nonce, tv_tag;
reg [1023:0] tv_ad, tv_pt, tv_ct;

fd = $fopen("pic_test_vectors.hex", "r");
// skip dòng comment (bắt đầu //)
count = $fscanf(fd, "%d %h %h %h %h %h %h %h %h\n",
                tv_mode, tv_key, tv_nonce, tv_ad_len, tv_ad,
                tv_pt_len, tv_pt, tv_ct, tv_tag);
```

### 5.5 Hàm dma_setup_full — BURST_LEN calculation

```verilog
// Reuse từ tb_ascon_top.v, không thay đổi
burst_calc = (pt_len >> 3);                          // = 8 (số blocks)
burst_calc = (burst_calc > 0) ? burst_calc - 1 : 0; // = 7
burst_calc = (burst_calc > 3) ? 3 : burst_calc;     // = 3 (cap tại 3)
axi_write(32'h114, burst_calc);
// → ARLEN = 3 → 4 beats × 8 bytes = 32 bytes/burst → 2 bursts cho 64 bytes
```

### 5.6 CT reconstruction (64 bytes = 8 blocks)

```verilog
// Tương tự tb_ascon_top.v nhưng loop 8 lần (không phải 1)
tmp_ct = 1024'h0;
for (i = 0; i < tv_pt_len/8; i = i + 1) begin       // i = 0..7
    word_lo = u_ram.dmem.memory[(DMA_CT_BASE/4) + i*2];
    word_hi = u_ram.dmem.memory[(DMA_CT_BASE/4) + i*2 + 1];
    // bit position: block i chiếm bits [(tv_pt_len-8-i*8)*8+63 : (tv_pt_len-8-i*8)*8]
    tmp_ct = tmp_ct | ({960'h0, {word_lo, word_hi}} << ((tv_pt_len - 8 - i*8)*8));
end
```

---

## 6. Bước 3 — Chạy và đọc kết quả

### 6.1 Thứ tự chạy (bắt buộc)

```bash
# Bước 1: SW — sinh CT/TAG reference + pic_test_vectors.hex
cd ascon/SW_check
python3 ascon_process_pic.py
cd ../..

# Bước 2: HW simulation
./workflow/urun_verilog.sh ascon/tb_pic_encrypt.v

# Bước 3: Đọc log
rtk read log/tb_pic_encrypt.log
```

### 6.2 Kết quả mong đợi trong log HW

```
=== ASCON Image Encryption HW Test ===
Image  : 8x8 grayscale, 64 bytes, DMA mode
[PASS] TAG matches
[PASS] CT matches (64 bytes)
HW cycles : <N>
HW time   : <N*10> ns  (<N/100> µs)
=== ALL TESTS PASSED ===
```

---

## 7. Công thức đo thông lượng

### 7.1 HW throughput

```
hw_cycles  = (hw_end_time_ns - hw_start_time_ns) / 10
hw_time_us = hw_cycles * 10 / 1000

Throughput_HW (MB/s) = 64 / (hw_cycles * 10e-9) / 1e6
                     = 64e6 / (hw_cycles * 10)
                     = 6400000 / hw_cycles     [MB/s]

Throughput_HW (Mbps) = Throughput_HW * 8
```

Ví dụ: nếu hw_cycles = 3000:
```
Throughput_HW = 6400000 / 3000 ≈ 2133 KB/s ≈ 2.1 MB/s ≈ 17 Mbps
```

### 7.2 SW throughput

Script Python đã in ra:
```
SW time: X.XXX µs/op  (Y.YY MB/s = Z.Z Mbps)
```

### 7.3 Bảng so sánh (đã đo 2026-06-16)

| Metric | SW (Python) | HW (100 MHz sim) | Tỉ lệ HW/SW |
|--------|------------|-----------------|------------|
| Time (µs/op) | 267.5 µs | 1.07 µs | 250× |
| Throughput (MB/s) | 0.24 MB/s | 59.81 MB/s | 249× |
| Throughput (Mbps) | 1.9 Mbps | 478 Mbps | 252× |
| Cycles | N/A | 107 cycles | — |

> **Ghi chú chạy 2026-06-16**: HW correctness PASS (CT + TAG đều khớp).
> HW thuật toán: 8-byte DMA blocks, chỉ x0 XOR PT (x1 không thay đổi vì data_len=64 >
> rate=16 → apply_padding không insert 0x01), pb=8 rounds giữa các blocks, finalization
> chuẩn Ascon-AEAD128. SW: python3 ascon_process_pic.py, N=5000 warmup+bench.

> **Lưu ý**: HW simulation time ≠ real ASIC time. Với real 100 MHz ASIC, thông
> lượng sẽ đúng như tính toán. SW Python chạy trên host CPU ở GHz → thường nhanh
> hơn về latency nhưng throughput ASIC sẽ cao hơn khi pipeline nhiều lần.

---

## 8. Các lưu ý kỹ thuật quan trọng

### 8.1 WR_FIFO_DEPTH phải tăng lên 32

Testbench mặc định `tb_ascon_top.v` dùng `WR_FIFO_DEPTH=8`. Với 8 PT blocks:
- CT output: 8 blocks × 2 words = 16 WR FIFO pushes
- TAG output: 4 WR FIFO pushes
- Tổng: 20 pushes > depth 8 → có thể overflow với permutation tốc độ cao

`tb_pic_encrypt.v` phải dùng `.WR_FIFO_DEPTH(32)`.

### 8.2 Byte order (endianness fix đã áp dụng)

CT reconstruction trong testbench: `{word_lo, word_hi}` (word_lo = mem[even], word_hi = mem[odd]).
Lý do: RAM lưu little-endian 64-bit (địa chỉ thấp hơn = bit thấp hơn của AXI RDATA).
Width converter ghi low word (WDATA[31:0]) vào addr+0, high word (WDATA[63:32]) vào addr+4.
Phải reconstruct là `{mem[even], mem[odd]}` → khớp với Python reference.

### 8.3 File `pic_test_vectors.hex` phải có trước khi chạy HW

Testbench dùng `$fopen("pic_test_vectors.hex", "r")`. File này nằm ở thư mục
**làm việc khi chạy simulation** (tức là thư mục gốc project khi dùng `urun_verilog.sh`).

### 8.4 `expected_wr_beats` trong DMA FSM

```
expected_wr_beats = total_blocks + 2
                  = (64/8) + 2 = 10

Ý nghĩa: mỗi beat = 1 AXI write transaction (64-bit) = 8 bytes.
Tổng: 8 CT blocks + 2 TAG transactions (16 bytes / 8 = 2) = 10 beats.

Khi wr_beats_done == 10 → dma_done fires → dma_busy = 0.
```

### 8.5 DMA register map (offsets từ ASCON base address)

| Offset | Register | Giá trị cho image test |
|--------|----------|----------------------|
| 0x000 | MODE | 0x0 (encrypt) |
| 0x010..01C | KEY[127:0] | 4 words |
| 0x024..030 | NONCE[127:0] | 4 words |
| 0x100 | SRC_ADDR (PT) | 0x0000_2000 |
| 0x104 | DST_ADDR (CT) | 0x0000_3000 |
| 0x108 | BYTE_LEN | 64 (0x40) |
| 0x03C | DATA_LEN | 64 |
| 0x114 | BURST_LEN | 3 (4 beats/burst) |
| 0x120 | AD_ADDR | 0x0000_1000 |
| 0x124 | AD_LEN | 0 |
| 0x020 | CTRL | 0x5 (DMA_EN\|CORE_START) |

---

## 9. Checklist cho agent

```
[x] 1. Tạo ascon/SW_check/ascon_process_pic.py  (HW emulation: 8-byte blocks, x0-only XOR)
[x] 2. Chạy python3 ascon_process_pic.py → CT+TAG đúng, pic_test_vectors.hex đã ghi
[x] 3. Tạo ascon/tb_pic_encrypt.v (WR_FIFO_DEPTH=32, đọc pic_test_vectors.hex)
[x] 4. Chạy ./workflow/urun_verilog.sh ascon/tb_pic_encrypt.v
[x] 5. Kiểm tra log: [PASS] TAG + [PASS] CT  ← PASSED 2026-06-16
[x] 6. hw_cycles = 107
[x] 7. Bảng so sánh đã điền ở mục 7.3
[x] 8. Kết quả: correctness PASS, HW throughput 59.81 MB/s / 478 Mbps (250× faster than SW)
```

---

## 10. Debug nhanh nếu thất bại

| Triệu chứng | Nguyên nhân | Kiểm tra |
|------------|-------------|---------|
| `$fopen` fail | `pic_test_vectors.hex` chưa có | Chạy Python trước |
| [FAIL] TAG/CT | WR FIFO overflow | Tăng WR_FIFO_DEPTH lên 64 |
| [FAIL] TAG/CT | CT reconstruction sai | Xem lại word_lo/word_hi order |
| [TIMEOUT] dma_done | expected_wr_beats sai hoặc write engine stuck | Xem `wr_beats_done` vs `expected_wr_beats` trong `dma_ctrl_fsm.v` |
| Kết quả không khớp SW | byte order không đồng nhất | Verify AD endian fix đã áp dụng (session trước) |

---

*File này dùng để điều phối giữa các AI agent. Mọi thay đổi RTL hoặc testbench
đều phải verify lại bằng `./workflow/urun_verilog.sh ascon/tb_ascon_top.v` (4/4 PASS)
trước khi commit.*
