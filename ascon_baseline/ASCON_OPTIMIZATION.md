# ASCON Accelerator — Optimization Guide (CPU + HW)

## 1. Benchmark kết quả thực đo (Fclk = 100 MHz)

| Mode | Block size | Cycles/block | Throughput |
|------|-----------|--------------|------------|
| DMA (AXI + FIFO) | 8B | ~8–10 | **478 Mbps** |
| CPU-direct, 8B/block | 8B | 3 | **2125 Mbps** |
| CPU-direct, 16B/block | 16B | 3 | **4250 Mbps** ← tối đa |

**Bottleneck DMA**: AXI handshake + width converter 64→32 + FIFO pipeline  
**CORE hardware**: 3 cycles/block cố định (1 DATA_LOAD + 2 DATA_PERM), `G_SBOX_PIPELINE=0`

---

## 2. Khi nào dùng mode nào

| Tình huống | Mode tối ưu | Lý do |
|-----------|-------------|-------|
| Encrypt payload lớn (> 1KB), CPU rảnh | **DMA** | CPU làm việc khác, offload hoàn toàn |
| Encrypt payload nhỏ (< 256B) | **CPU-direct** | DMA setup overhead > thời gian xử lý |
| Latency-critical (single block) | **CPU-direct** | DMA init ~20–30 cycles overhead |
| Throughput tối đa, CPU dedicated | **CPU-direct 16B** | 4250 Mbps, không overhead bus |
| Multi-task: CPU xử lý tiếp trong khi encrypt | **DMA + IRQ** | Interrupt-driven, CPU không bị block |

---

## 3. CPU-Direct Mode — Cách dùng tối ưu

### 3.1. Feed 16-byte blocks (tốc độ tối đa)

Dùng toàn bộ 128-bit data width. Cả x0 và x1 đều được XOR (`is_128a=1` hardwired).

```c
// include/ascon.h — CPU-direct pattern
ascon_soft_reset();
ascon_set_mode(ASCON_MODE_128_ENC);
ascon_set_key(k0, k1, k2, k3);
ascon_set_nonce(n0, n1, n2, n3);
ascon_clear_ad();                    // no AD → skip AD phase

// Feed 16-byte blocks
for (int i = 0; i < n_blocks; i++) {
    uint32_t p0 = PT[i*4+0], p1 = PT[i*4+1];
    uint32_t p2 = PT[i*4+2], p3 = PT[i*4+3];
    int last = (i == n_blocks - 1);

    ascon_set_ptext_128(p0, p1, p2, p3, last ? (len % 16) : 16);
    ascon_core_start();
    ascon_wait_core_done();           // 3 cycles HW, ~poll overhead in SW
    ascon_get_ctext_128(&c0, &c1, &c2, &c3);
}
ascon_get_tag(&t0, &t1, &t2, &t3);
```

> **Note**: `ascon_set_ptext_128` / `ascon_get_ctext_128` cần thêm vào `ascon.h`  
> (hiện tại chỉ có 64-bit `ascon_set_ptext` / `ascon_get_ctext`).

### 3.2. Feed 8-byte blocks (tương thích DMA format)

```c
// Dùng khi data đến từ DMA buffer (8B/block format hiện tại)
ascon_set_ptext(p0, p1, 8);          // upper 64-bit only
ascon_core_start();
ascon_wait_core_done();
ascon_get_ctext(&c0, &c1);           // upper 64-bit ciphertext
```

---

## 4. DMA Mode — Cách dùng tối ưu

### 4.1. Chọn đúng mode theo payload size

```c
// Threshold: payload > ~200 bytes thì DMA có lợi (CPU freed)
#define DMA_THRESHOLD_BYTES  200

if (payload_len > DMA_THRESHOLD_BYTES) {
    // DMA + WFI (CPU sleeps, wakes on IRQ)
    ascon_dma_config(src_addr, dst_addr, payload_len);
    ascon_dma_start();               // CTRL = 0x5
    __asm__ volatile ("wfi");        // CPU chờ interrupt
    // ISR: plic_complete(PLIC_SRC_ASCON)
} else {
    // CPU-direct
    ascon_set_ptext(p0, p1, payload_len);
    ascon_core_start();
    ascon_wait_core_done();
}
```

### 4.2. Fence đúng chỗ (tránh stale data)

```c
// TRƯỚC khi start DMA: đảm bảo CPU writes đã đến DMEM
__asm__ volatile ("fence rw,rw" ::: "memory");
ascon_dma_start();

// SAU khi DMA done: đảm bảo CPU đọc được ciphertext mới
uint32_t st = ascon_wait_dma_done();
__asm__ volatile ("fence r,r" ::: "memory");
// Bây giờ mới đọc CT buffer
```

---

## 5. Pipeline CPU + DMA (Double-buffer)

Khi encrypt nhiều frames/packets liên tiếp, dùng double-buffer để overlap:

```
Frame 0: [DMA encrypt]
Frame 1:             [CPU prepare] → [DMA encrypt]
Frame 2:                                          [CPU prepare] → [DMA encrypt]
```

```c
uint8_t buf_a[FRAME_SIZE], buf_b[FRAME_SIZE];
uint8_t *enc_buf = buf_a, *prep_buf = buf_b;

// Kick off frame 0
memcpy(enc_buf, frame[0], FRAME_SIZE);
fence_rw();
ascon_dma_config((uint32_t)enc_buf, dst, FRAME_SIZE);
ascon_dma_start();

for (int i = 1; i < n_frames; i++) {
    // CPU chuẩn bị frame tiếp theo trong khi DMA encrypt frame hiện tại
    memcpy(prep_buf, frame[i], FRAME_SIZE);

    // Chờ DMA xong frame trước
    ascon_wait_dma_done();
    fence_r();
    save_ciphertext(enc_buf, dst);

    // Swap buffers, start DMA cho frame mới
    swap(&enc_buf, &prep_buf);
    fence_rw();
    ascon_dma_config((uint32_t)enc_buf, dst, FRAME_SIZE);
    ascon_dma_start();
}
// Drain last frame
ascon_wait_dma_done();
```

**Hiệu quả**: CPU overhead (memcpy + prep) chạy song song với DMA encrypt  
→ thực tế gần với throughput lý thuyết của CORE hơn.

---

## 6. Tối ưu phần cứng để tăng thêm

### 6.1. Tăng AXI bus width 32→64 bit

Bỏ `axi_width_converter_64to32.v`:
- Mỗi DMA block (64-bit) chỉ cần 1 beat thay vì 2
- DMA throughput tăng ~2× → ~900 Mbps+

### 6.2. Tăng block size DMA từ 8B→16B

Sửa `dma_ctrl_fsm.v` để feed 2 × 8B per iteration:
- Giảm số DMA transactions xuống một nửa
- Tận dụng đầy đủ 128-bit rate của CORE

### 6.3. Tăng FIFO depth (giảm stall)

Tăng `RD_FIFO_DEPTH` và `WR_FIFO_DEPTH` từ 4→8 entries:
- Giảm backpressure khi AXI read latency cao
- Cho phép CORE chạy liên tục không bị stall

### 6.4. Enable G_SBOX_PIPELINE=1 (tăng Fmax)

| | G_SBOX_PIPELINE=0 | G_SBOX_PIPELINE=1 |
|-|------------------|--------------------|
| Cycles/block | 3 | pb+1 = 9 |
| Fmax (FPGA) | ~80–100 MHz | ~200–300 MHz |
| Throughput | 4250 Mbps @100MHz | **~1800 Mbps @200MHz** |

> Chỉ có lợi nếu critical path hiện tại đang giới hạn Fmax dưới 200 MHz.

---

## 7. Lộ trình tối ưu theo mức độ ưu tiên

```
[Ngắn hạn — không cần sửa HW]
  1. Dùng CPU-direct 16B blocks cho payload < 200B
  2. Dùng DMA + WFI IRQ thay vì poll cho payload lớn
  3. Double-buffer khi xử lý nhiều frame liên tiếp

[Trung hạn — sửa firmware]
  4. Thêm ascon_set_ptext_128() / ascon_get_ctext_128() vào ascon.h
  5. Auto-select CPU/DMA mode theo payload_len

[Dài hạn — sửa RTL]
  6. Tăng AXI bus width 32→64 bit (axi_width_converter bỏ đi)
  7. DMA block size 8B→16B (dma_ctrl_fsm.v)
  8. Tăng FIFO depth
```

---

## 8. Tóm tắt con số

```
CORE hardware limit (CPU-direct, 16B/block):    4250 Mbps  (4.25 Gbps)
CORE hardware limit (CPU-direct,  8B/block):    2125 Mbps  (2.12 Gbps)
DMA hiện tại (8B/block, 32-bit AXI):             478 Mbps
SW reference (Python, single-core):             ~1.9 Mbps

Bottleneck DMA = AXI 32-bit width + 8B block size + FIFO pipeline
CORE không phải bottleneck — CORE chạy 3 cycles/block bất kể mode
```
