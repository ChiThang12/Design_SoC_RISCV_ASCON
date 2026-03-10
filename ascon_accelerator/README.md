# ASCON Crypto Accelerator IP

## Tổng quan

IP ASCON là một accelerator mã hóa/giải mã tích hợp cho SoC RISC-V, triển khai thuật toán **ASCON-128/128a** — chuẩn mã hóa nhẹ (lightweight cryptography) được NIST lựa chọn năm 2023. IP vừa hoạt động như một **AXI4-Lite Slave** (CPU lập trình trực tiếp) vừa như một **DMA Master** (tự đọc/ghi memory mà không cần CPU can thiệp từng byte).

---

## Kiến trúc tổng thể

```
RISC-V CPU
    │
    │  AXI4-Lite (S_AXI_*)              AXI4-Full (M_AXI_*)
    │                                         │
    ▼                                         ▼
┌─────────────────────┐              ┌──────────────────────┐
│   ascon_axi_slave   │◄─ control ──►│      ascon_dma       │
│  (register bank,    │              │  (read engine,       │
│   interrupt logic)  │              │   write engine,      │
└─────────┬───────────┘              │   FIFOs, ctrl FSM)   │
          │                          └──────────┬───────────┘
          │ core_*                              │ core_*
          └──────────────┬──────────────────────┘
                         ▼
               ┌─────────────────┐
               │   ascon_CORE    │
               │ (permutation,   │
               │  tag gen/cmp)   │
               └─────────────────┘
```

### Các module

| File | Module | Vai trò |
|---|---|---|
| `ascon_top.v` | `ascon_top` | **Top module** — kết nối 3 khối bên dưới |
| `ascon_axi_slave.v` | `ascon_axi_slave` | AXI4-Lite slave register interface |
| `ascon_CORE.v` | `ascon_CORE` | Lõi tính toán ASCON permutation |
| `ascon_dma.v` | `ascon_dma` | DMA engine với AXI4-Full master |
| `tb_ascon_top.v` | `tb_ascon_top` | Testbench đầy đủ cho `ascon_top` |

---

## Bản đồ thanh ghi (Register Map)

> Base address: `0x2000_0000`

| Offset | Tên | Loại | Bit | Mô tả |
|---|---|---|---|---|
| `0x000` | CTRL | R/W | [0] START | Kích hoạt encryption/decryption (1 cycle pulse) |
| | | | [1] SOFT_RST | Xóa cờ DONE/DMA_DONE, giữ KEY/NONCE |
| | | | [2] DMA_EN | Bật DMA mode — data input từ memory |
| `0x004` | STATUS | RO | [0] BUSY | Core đang bận |
| | | | [1] DONE | Encryption/decryption xong (sticky) |
| | | | [2] DMA_BUSY | DMA engine đang hoạt động |
| | | | [3] DMA_DONE | DMA hoàn thành (sticky) |
| | | | [4] ERROR | Lỗi core |
| | | | [5] DMA_ERROR | Lỗi AXI master (SLVERR/DECERR) |
| `0x008` | MODE | R/W | [0] ENC_DEC | 0=Encrypt, 1=Decrypt |
| | | | [1] PERM_MODE | 0=ASCON-128, 1=ASCON-128a |
| `0x00C` | IRQ_EN | R/W | [0] DONE_IRQ_EN | Bật ngắt khi DONE |
| | | | [1] DMA_DONE_IRQ_EN | Bật ngắt khi DMA_DONE |
| | | | [2] ERROR_IRQ_EN | Bật ngắt khi có lỗi |
| `0x010–0x01C` | KEY_0..3 | WO | [31:0] | Khóa 128-bit (MSB first) |
| `0x020–0x02C` | NONCE_0..3 | WO | [31:0] | Nonce 128-bit (MSB first) |
| `0x030–0x034` | PTEXT_0..1 | WO | [31:0] | Plaintext 64-bit (slave mode) |
| `0x040–0x044` | CTEXT_0..1 | RO | [31:0] | Ciphertext 64-bit (đọc sau DONE) |
| `0x048–0x054` | TAG_0..3 | RO | [31:0] | Authentication tag 128-bit |
| `0x100` | DMA_SRC | R/W | [31:0] | Địa chỉ nguồn DMA (plaintext trong DDR) |
| `0x104` | DMA_DST | R/W | [31:0] | Địa chỉ đích DMA (ctext+tag ghi ra) |
| `0x108` | DMA_LEN | R/W | [31:0] | Số byte cần truyền (Phase 1: = 8) |

---

## Hai chế độ hoạt động

### Chế độ 1 — CPU Slave Mode

CPU lập trình toàn bộ qua AXI4-Lite. Không cần DMA.

```
1. Ghi KEY[0..3]    → 0x010..0x01C
2. Ghi NONCE[0..3]  → 0x020..0x02C
3. Ghi PTEXT[0..1]  → 0x030..0x034
4. Ghi MODE         → 0x008 (0=ENC, 1=DEC)
5. Ghi CTRL[0]=1    → 0x000 (START)
6. Ghi CTRL[0]=0    → 0x000 (deassert)
7. Poll STATUS[1]   → 0x004 (chờ DONE=1)
8. Đọc CTEXT[0..1]  → 0x040..0x044
9. Đọc TAG[0..3]    → 0x048..0x054
10. Ghi CTRL[1]=1   → 0x000 (SOFT_RST để xóa DONE)
```

### Chế độ 2 — DMA Mode

CPU chỉ cần cấu hình một lần, IP tự đọc plaintext từ DDR và ghi ciphertext+tag về DDR.

```
1. Ghi KEY[0..3], NONCE[0..3] như trên
2. Ghi DMA_SRC  → 0x100 (địa chỉ plaintext trong DDR)
3. Ghi DMA_DST  → 0x104 (địa chỉ đích ciphertext+tag)
4. Ghi DMA_LEN  → 0x108 (số byte, Phase 1 = 8)
5. Ghi CTRL = 0x05  (DMA_EN=1 + START=1)
6. Ghi CTRL = 0x04  (DMA_EN=1, deassert START)
7. Chờ IRQ hoặc poll STATUS[3]=DMA_DONE
8. Đọc kết quả từ DDR tại DMA_DST
```

---

## Sơ đồ luồng dữ liệu

### CPU Mode

```
CPU ──AXI4-Lite──► ascon_axi_slave ──core_data_in──► ascon_CORE ──data_out──► CTEXT reg
                                   ──core_start──►             ──tag_out──►  TAG reg
                   ◄────────────────────────────── core_done ◄──────────────
```

### DMA Mode

```
DDR ──AXI4-Read──► ascon_dma ──ptext──► ascon_CORE ──ctext/tag──► ascon_dma ──AXI4-Write──► DDR
                   (rd_fifo)  ──start──►            ──done────────►(wr_fifo)
```

---

## Tín hiệu ưu tiên

| Tình huống | Ưu tiên |
|---|---|
| `DMA_EN=1` | `core_start` đến từ DMA engine |
| `DMA_EN=0` | `core_start` đến từ AXI slave (CPU) |
| `DMA_EN=1` | `core_data_in` đến từ DMA FIFO |
| `DMA_EN=0` | `core_data_in` đến từ PTEXT registers |

---

## Ngắt (Interrupt)

```
irq = (STATUS[1]=DONE     & IRQ_EN[0]) |
      (STATUS[3]=DMA_DONE & IRQ_EN[1]) |
      (STATUS[4..5]=ERROR & IRQ_EN[2])
```

- IRQ là **level-triggered**, giữ cao đến khi SOFT_RST xóa cờ sticky.
- Kết nối vào RISC-V PLIC tại external interrupt line.

---

## Thông số tổng hợp (Phase 1)

| Thông số | Giá trị |
|---|---|
| Giao thức slave | AXI4-Lite (32-bit data) |
| Giao thức master | AXI4-Full (64-bit data) |
| Tần số mục tiêu | ≥ 40 MHz (tùy process node) |
| Latency mã hóa | ~12 round × N cycles (phụ thuộc CONTROLLER) |
| Plaintext/block | 8 bytes (64-bit rate, Phase 1) |
| Key length | 128-bit |
| Tag length | 128-bit |

---

## Testbench (`tb_ascon_top.v`)

### Các test case

| Test | Mô tả |
|---|---|
| TEST 1 | CPU slave mode — mã hóa 8 byte plaintext, kiểm tra CTEXT & TAG khác 0, IRQ |
| TEST 2 | CPU slave mode — giải mã ciphertext từ TEST 1, kiểm tra khôi phục plaintext |
| TEST 3 | DMA mode — plaintext nạp sẵn trong memory model, DMA đọc → mã hóa → ghi |
| TEST 4 | Back-to-back register writes — stress test ghi nhiều thanh ghi liên tiếp |
| TEST 5 | IRQ enable/disable — kiểm tra IRQ bị chặn khi IRQ_EN=0, phát lại khi re-enable |

### Chạy simulation

```bash
# Iverilog
iverilog -g2012 -DSIMULATION \
    -I ascon_accelerator/rtl \
    -I ascon_accelerator/axi/rtl \
    -I ascon_accelerator/dma/rtl \
    ascon_top.v \
    tb_ascon_top.v \
    -o tb_ascon_top.out

vvp tb_ascon_top.out

# Xem waveform
gtkwave tb_ascon_top.vcd
```

```bash
# Questa / ModelSim
vlog -sv +define+SIMULATION ascon_top.v tb_ascon_top.v
vsim -c tb_ascon_top -do "run -all; quit"
```

### Kết quả kỳ vọng

```
========================================================
  ASCON IP Top-level Testbench
========================================================
[...] Reset released
--- TEST 1: CPU Slave Mode Encryption ---
[...] Encryption started (CPU mode)
[...] DONE asserted, reading results...
[...] Ciphertext : XXXXXXXX_XXXXXXXX
[...] Tag        : XXXXXXXX_XXXXXXXX_XXXXXXXX_XXXXXXXX
[PASS] AXI write response OKAY
[PASS] Ciphertext non-zero
[PASS] Tag non-zero
[PASS] IRQ asserted after encryption done
[PASS] IRQ deasserted after SOFT_RST
--- TEST 2: CPU Slave Mode Decryption ---
[PASS] Decryption recovered original plaintext
--- TEST 3: DMA Mode Encryption ---
[PASS] DMA_DONE bit set in STATUS register
[PASS] No DMA errors detected
--- TEST 4: Back-to-back register writes stress test ---
[PASS] Stress test encryption produced output
--- TEST 5: IRQ enable/disable ---
[PASS] IRQ correctly suppressed when IRQ_EN=0
[PASS] IRQ asserted after IRQ_EN re-enabled
========================================================
  Test Summary: 10 PASS / 0 FAIL
  ALL TESTS PASSED
========================================================
```

---

## Cấu trúc file dự án

```
ascon_accelerator/
├── rtl/
│   ├── ascon_top.v              ← TOP MODULE (file này)
│   ├── ascon_CORE.v
│   ├── ascon_INITIALIZATION.v
│   ├── ascon_STATE_REGISTER.v
│   ├── ascon_DATAPATH.v
│   ├── ascon_TAG_GENERATOR.v
│   ├── ascon_TAG_COMPARATOR.v
│   ├── ascon_CONTROLLER.v
│   └── PERMUTATION/
│       └── ascon_PERMUTATION.v
├── axi/
│   └── rtl/
│       └── ascon_axi_slave.v
├── dma/
│   └── rtl/
│       ├── ascon_dma.v
│       ├── dma_ctrl_fsm.v
│       ├── dma_read_engine.v
│       ├── dma_write_engine.v
│       └── sync_fifo.v
└── tb/
    └── tb_ascon_top.v           ← TESTBENCH (file này)
```

---

## Roadmap (Phase 2+)

| Feature | Mô tả |
|---|---|
| Multi-block | Hỗ trợ plaintext > 8 bytes, streaming qua DMA |
| Associated Data | Kết nối AD path vào ascon_CORE |
| Tag verification | Tích hợp TAG_COMPARATOR qua DMA cho decryption |
| Scatter-Gather | DMA descriptor list cho nhiều buffer |
| Clock domain crossing | CDC FIFOs cho M_AXI và core dùng clock riêng |

---

## Tác giả

ASCON IP cho SoC RISC-V — Phase 1  
Tham khảo: ASCON v1.2 specification (Dobraunig et al.), NIST LWC finalist 2023.