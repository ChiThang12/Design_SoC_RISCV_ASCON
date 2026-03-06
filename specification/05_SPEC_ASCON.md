# 05 — Đặc Tả Module: ASCON Accelerator

**Tên module:** `ascon_core` + `ascon_axi_slave`  
**File đầu ra:**
- `crypto/ascon/ascon_core.v` — datapath thuật toán ASCON
- `crypto/ascon/ascon_axi_slave.v` — wrapper AXI4 Lite

**Ưu tiên:** Cao — đây là deliverable khoa học chính của đề tài  
**Đọc trước:** `02_QUY_UONG_AXI4.md`, `03_SO_DO_DIA_CHI.md`

---

## Mục lục

1. [Tổng quan thuật toán ASCON-128](#1-tổng-quan-thuật-toán-ascon-128)
2. [Kiến trúc hai module](#2-kiến-trúc-hai-module)
3. [Đặc tả `ascon_core`](#3-đặc-tả-ascon_core)
4. [Register Map của `ascon_axi_slave`](#4-register-map-của-ascon_axi_slave)
5. [Danh sách Port của `ascon_axi_slave`](#5-danh-sách-port-của-ascon_axi_slave)
6. [Luồng sử dụng từ phần mềm](#6-luồng-sử-dụng-từ-phần-mềm)
7. [Yêu cầu hành vi](#7-yêu-cầu-hành-vi)
8. [Ví dụ code C sử dụng ASCON](#8-ví-dụ-code-c-sử-dụng-ascon)

---

## 1. Tổng quan thuật toán ASCON-128

ASCON là thuật toán mã hóa xác thực (Authenticated Encryption with Associated Data — AEAD) hạng nhẹ, được NIST chọn làm chuẩn lightweight cryptography năm 2023.

**Thông số ASCON-128:**

| Thông số | Giá trị |
|---|---|
| Kích thước key | 128 bit |
| Kích thước nonce | 128 bit |
| Kích thước block | 64 bit (rate = 64 bit) |
| Kích thước tag | 128 bit |
| Số vòng permutation khởi tạo | 12 vòng (pa = 12) |
| Số vòng permutation dữ liệu | 6 vòng (pb = 6) |
| Kích thước state nội bộ | 320 bit (5 × 64-bit word) |

**Các bước mã hóa cơ bản:**
```
1. Khởi tạo: state = IV || Key || Nonce, rồi chạy permutation 12 vòng, XOR Key vào cuối
2. Xử lý Associated Data: XOR vào state, permutation 6 vòng (nếu có)
3. Mã hóa từng block: XOR plaintext vào state, lấy ciphertext, permutation 6 vòng
4. Finalization: XOR Key vào state, permutation 12 vòng, XOR Key, lấy 128-bit tag
```

**Trong Phase 1:** Chỉ hỗ trợ mã hóa/giải mã **một block 64-bit** (không có Associated Data). Hỗ trợ multi-block và AD để làm trong Phase 2.

---

## 2. Kiến trúc hai module

```
┌──────────────────────────────────────────────────┐
│                ascon_axi_slave                   │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │             AXI4 Lite FSM                   │ │
│  │  (đọc/ghi thanh ghi, decode địa chỉ)        │ │
│  └─────────────────────┬───────────────────────┘ │
│                        │ control signals          │
│  ┌─────────────────────▼───────────────────────┐ │
│  │              ascon_core                     │ │
│  │  (320-bit state machine, permutation logic) │ │
│  └─────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
         │
         │ AXI4 Lite (S_AXI_*)
         │
    AXI4 Crossbar (S2)
```

**Lý do tách hai module:**
- `ascon_core` có thể được test độc lập (chạy thuật toán không cần AXI4)
- `ascon_axi_slave` chỉ là "vỏ bọc" AXI4 — logic mật mã không bị lẫn với logic bus
- Dễ tái sử dụng `ascon_core` nếu muốn kết nối bằng interface khác

---

## 3. Đặc tả `ascon_core`

### Port list

```verilog
module ascon_core (
    input  wire         clk,
    input  wire         rst_n,

    // --- Control ---
    input  wire         start,        // Pulse 1 cycle để bắt đầu
    input  wire         mode,         // 0 = mã hóa, 1 = giải mã
    output reg          busy,         // 1 khi đang tính toán
    output reg          done,         // Pulse 1 cycle khi hoàn thành

    // --- Key (128-bit) ---
    input  wire [31:0]  key_0,        // bits [127:96]
    input  wire [31:0]  key_1,        // bits [95:64]
    input  wire [31:0]  key_2,        // bits [63:32]
    input  wire [31:0]  key_3,        // bits [31:0]

    // --- Nonce (128-bit) ---
    input  wire [31:0]  nonce_0,      // bits [127:96]
    input  wire [31:0]  nonce_1,      // bits [95:64]
    input  wire [31:0]  nonce_2,      // bits [63:32]
    input  wire [31:0]  nonce_3,      // bits [31:0]

    // --- Plaintext/Ciphertext (64-bit) ---
    input  wire [31:0]  ptext_0,      // bits [63:32]
    input  wire [31:0]  ptext_1,      // bits [31:0]

    // --- Output ---
    output reg  [31:0]  ctext_0,      // bits [63:32]
    output reg  [31:0]  ctext_1,      // bits [31:0]
    output reg  [31:0]  tag_0,        // bits [127:96]
    output reg  [31:0]  tag_1,        // bits [95:64]
    output reg  [31:0]  tag_2,        // bits [63:32]
    output reg  [31:0]  tag_3         // bits [31:0]
);
```

### State machine nội bộ

```
IDLE ──(start)──▶ INIT_PERM ──(12 rounds done)──▶ ABSORB_AD
                                                        │
                                               (no AD, skip)
                                                        │
                                                        ▼
                                               ENCRYPT_BLOCK ──(6 rounds done)──▶ FINALIZE
                                                                                        │
                                                                              (12 rounds done)
                                                                                        │
                                                                                        ▼
                                                                                      DONE ──▶ IDLE
```

### Số chu kỳ clock ước tính

Với kiến trúc iterative (1 round/cycle):
- Khởi tạo: 12 cycles
- Mã hóa 1 block: 6 cycles  
- Finalization: 12 cycles
- **Tổng: ~30 cycles từ `start` đến `done`**

Số chu kỳ chính xác phải được ghi rõ trong comment header của module sau khi implement.

---

## 4. Register Map của `ascon_axi_slave`

**Địa chỉ base:** `0x2000_0000` (xem `03_SO_DO_DIA_CHI.md`)

| Offset | Tên thanh ghi | Quyền | Reset | Mô tả |
|---|---|---|---|---|
| `0x00` | `CTRL` | R/W | `0x0000_0000` | Thanh ghi điều khiển |
| `0x04` | `STATUS` | RO | `0x0000_0000` | Thanh ghi trạng thái |
| `0x08` | `MODE` | R/W | `0x0000_0000` | Chế độ mã hóa/giải mã |
| `0x0C` | *(dự phòng)* | — | — | Không sử dụng |
| `0x10` | `KEY_0` | WO | — | Key word 0 \[127:96\] |
| `0x14` | `KEY_1` | WO | — | Key word 1 \[95:64\] |
| `0x18` | `KEY_2` | WO | — | Key word 2 \[63:32\] |
| `0x1C` | `KEY_3` | WO | — | Key word 3 \[31:0\] |
| `0x20` | `NONCE_0` | WO | — | Nonce word 0 \[127:96\] |
| `0x24` | `NONCE_1` | WO | — | Nonce word 1 \[95:64\] |
| `0x28` | `NONCE_2` | WO | — | Nonce word 2 \[63:32\] |
| `0x2C` | `NONCE_3` | WO | — | Nonce word 3 \[31:0\] |
| `0x30` | `PTEXT_0` | WO | — | Plaintext word 0 \[63:32\] |
| `0x34` | `PTEXT_1` | WO | — | Plaintext word 1 \[31:0\] |
| `0x38` | *(dự phòng)* | — | — | — |
| `0x3C` | *(dự phòng)* | — | — | — |
| `0x40` | `CTEXT_0` | RO | `0x0` | Ciphertext word 0 \[63:32\] |
| `0x44` | `CTEXT_1` | RO | `0x0` | Ciphertext word 1 \[31:0\] |
| `0x48` | `TAG_0` | RO | `0x0` | Auth tag word 0 \[127:96\] |
| `0x4C` | `TAG_1` | RO | `0x0` | Auth tag word 1 \[95:64\] |
| `0x50` | `TAG_2` | RO | `0x0` | Auth tag word 2 \[63:32\] |
| `0x54` | `TAG_3` | RO | `0x0` | Auth tag word 3 \[31:0\] |

### Chi tiết các bit quan trọng

**CTRL Register (0x00):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `START` | Ghi 1 để bắt đầu. Tự clear sau 1 cycle. Bị bỏ qua nếu STATUS.BUSY=1 |
| [1] | `SOFT_RST` | Ghi 1 để reset toàn bộ core về trạng thái ban đầu |
| [31:2] | *(dự phòng)* | Bỏ qua khi ghi, đọc về 0 |

**STATUS Register (0x04):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `BUSY` | 1 khi core đang tính toán |
| [1] | `DONE` | 1 khi phép tính hoàn thành, giữ cho đến khi CTRL.SOFT_RST=1 |
| [2] | `ERROR` | 1 nếu có lỗi (dùng cho Phase 2) |
| [31:3] | *(dự phòng)* | Đọc về 0 |

**MODE Register (0x08):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `ENC_DEC` | 0 = mã hóa (encrypt), 1 = giải mã (decrypt) |
| [31:1] | *(dự phòng)* | Bỏ qua khi ghi, đọc về 0 |

---

## 5. Danh sách Port của `ascon_axi_slave`

```verilog
module ascon_axi_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI4 Lite Slave Interface
    // Read Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [7:0]              S_AXI_ARLEN,    // bỏ qua (AXI4 Lite luôn = 0)
    input  wire [2:0]              S_AXI_ARSIZE,   // bỏ qua
    input  wire [1:0]              S_AXI_ARBURST,  // bỏ qua
    input  wire [2:0]              S_AXI_ARPROT,
    input  wire                    S_AXI_ARVALID,
    output wire                    S_AXI_ARREADY,

    // Read Data Channel
    output wire [ID_WIDTH-1:0]     S_AXI_RID,
    output wire [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,    // luôn = 1 (1 beat)
    output wire                    S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [7:0]              S_AXI_AWLEN,    // bỏ qua
    input  wire [2:0]              S_AXI_AWSIZE,   // bỏ qua
    input  wire [1:0]              S_AXI_AWBURST,  // bỏ qua
    input  wire [2:0]              S_AXI_AWPROT,
    input  wire                    S_AXI_AWVALID,
    output wire                    S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WLAST,    // bỏ qua
    input  wire                    S_AXI_WVALID,
    output wire                    S_AXI_WREADY,

    // Write Response Channel
    output wire [ID_WIDTH-1:0]     S_AXI_BID,
    output wire [1:0]              S_AXI_BRESP,
    output wire                    S_AXI_BVALID,
    input  wire                    S_AXI_BREADY
);
```

---

## 6. Luồng sử dụng từ phần mềm

```
Bước 1: Ghi KEY (8 lần store word)
  *(ASCON_BASE + 0x10) = key[127:96]
  *(ASCON_BASE + 0x14) = key[95:64]
  *(ASCON_BASE + 0x18) = key[63:32]
  *(ASCON_BASE + 0x1C) = key[31:0]

Bước 2: Ghi NONCE (4 lần store word)
  *(ASCON_BASE + 0x20) = nonce[127:96]
  ... (tương tự key)

Bước 3: Ghi PLAINTEXT (2 lần store word)
  *(ASCON_BASE + 0x30) = plaintext[63:32]
  *(ASCON_BASE + 0x34) = plaintext[31:0]

Bước 4: Chọn chế độ
  *(ASCON_BASE + 0x08) = 0  // 0=mã hóa, 1=giải mã

Bước 5: Kích hoạt
  *(ASCON_BASE + 0x00) = 1  // CTRL.START = 1

Bước 6: Chờ hoàn thành (polling)
  while ((*(ASCON_BASE + 0x04) & 0x2) == 0);  // Chờ STATUS.DONE = 1

Bước 7: Đọc kết quả
  ctext[63:32] = *(ASCON_BASE + 0x40)
  ctext[31:0]  = *(ASCON_BASE + 0x44)
  tag[127:96]  = *(ASCON_BASE + 0x48)
  ... (tiếp tục đọc tag)

Bước 8: Reset cho lần tiếp theo
  *(ASCON_BASE + 0x00) = 2  // CTRL.SOFT_RST = 1
```

---

## 7. Yêu cầu hành vi

1. **Khi ghi CTRL.START=1 mà STATUS.BUSY=1:** Bỏ qua lệnh start, trả về OKAY (không phải SLVERR). Phần mềm có trách nhiệm kiểm tra STATUS trước khi ghi START.

2. **CTEXT và TAG:** Không được thay đổi sau khi DONE=1 cho đến khi SOFT_RST được ghi. Điều này cho phép phần mềm đọc nhiều lần.

3. **Ghi vào thanh ghi read-only (CTEXT, TAG, STATUS):** Chấp nhận giao dịch (trả về OKAY), bỏ qua dữ liệu.

4. **Ghi vào thanh ghi write-only (KEY, NONCE, PTEXT):** Chấp nhận và lưu. Đọc về `32'h0000_0000`.

5. **Ghi vào thanh ghi CTRL.START trong khi DONE=1:** Hành vi undefined trong Phase 1 — phần mềm phải ghi SOFT_RST trước.

6. **Tính chính xác:** Output của `ascon_core` phải khớp với test vector chính thức của ASCON-128. Tham khảo: https://ascon.iaik.tugraz.at/

---

## 8. Ví dụ code C sử dụng ASCON

```c
#include <stdint.h>

#define ASCON_BASE    0x20000000UL
#define REG(off)      (*((volatile uint32_t *)(ASCON_BASE + (off))))

#define ASCON_CTRL    REG(0x00)
#define ASCON_STATUS  REG(0x04)
#define ASCON_MODE    REG(0x08)
#define ASCON_KEY0    REG(0x10)
#define ASCON_KEY1    REG(0x14)
#define ASCON_KEY2    REG(0x18)
#define ASCON_KEY3    REG(0x1C)
#define ASCON_NONCE0  REG(0x20)
#define ASCON_NONCE1  REG(0x24)
#define ASCON_NONCE2  REG(0x28)
#define ASCON_NONCE3  REG(0x2C)
#define ASCON_PTEXT0  REG(0x30)
#define ASCON_PTEXT1  REG(0x34)
#define ASCON_CTEXT0  REG(0x40)
#define ASCON_CTEXT1  REG(0x44)
#define ASCON_TAG0    REG(0x48)
#define ASCON_TAG1    REG(0x4C)
#define ASCON_TAG2    REG(0x50)
#define ASCON_TAG3    REG(0x54)

void ascon_encrypt(
    uint32_t key[4], uint32_t nonce[4],
    uint32_t ptext[2],
    uint32_t ctext[2], uint32_t tag[4])
{
    // Reset core
    ASCON_CTRL = 0x2;

    // Ghi key
    ASCON_KEY0 = key[0]; ASCON_KEY1 = key[1];
    ASCON_KEY2 = key[2]; ASCON_KEY3 = key[3];

    // Ghi nonce
    ASCON_NONCE0 = nonce[0]; ASCON_NONCE1 = nonce[1];
    ASCON_NONCE2 = nonce[2]; ASCON_NONCE3 = nonce[3];

    // Ghi plaintext
    ASCON_PTEXT0 = ptext[0];
    ASCON_PTEXT1 = ptext[1];

    // Chế độ mã hóa
    ASCON_MODE = 0;

    // Bắt đầu
    ASCON_CTRL = 0x1;

    // Chờ hoàn thành
    while (!(ASCON_STATUS & 0x2));

    // Đọc kết quả
    ctext[0] = ASCON_CTEXT0; ctext[1] = ASCON_CTEXT1;
    tag[0] = ASCON_TAG0; tag[1] = ASCON_TAG1;
    tag[2] = ASCON_TAG2; tag[3] = ASCON_TAG3;
}
```

---

*Tiếp theo: Xem `06_SPEC_SOC_CONTROLLER.md` để biết đặc tả SoC Controller.*
