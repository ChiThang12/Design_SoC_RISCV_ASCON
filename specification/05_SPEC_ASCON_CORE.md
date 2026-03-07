# 05A — Đặc Tả Module: ASCON Accelerator IP

**Tên module:** `ascon_top` / `ascon_core` / `ascon_axi_slave`  
**File đầu ra:**
- `crypto/ascon/ascon_permutation.v` — permutation datapath (đã có sẵn)
- `crypto/ascon/ascon_core.v` — ASCON-128 state machine + control
- `crypto/ascon/ascon_axi_slave.v` — AXI4-Lite register interface
- `crypto/ascon/ascon_top.v` — top-level integration (core + DMA + AXI slave)

**Ưu tiên:** Cao — deliverable khoa học chính  
**Đọc trước:** `02_QUY_UONG_AXI4.md`, `03_SO_DO_DIA_CHI.md`, `05B_SPEC_ASCON_DMA.md`  
**Phụ thuộc module:** `ASCON_PERMUTATION` (xem port list bên dưới)

---

## Mục lục

1. [Tổng quan thuật toán ASCON-128](#1-tổng-quan)
2. [Kiến trúc tổng thể IP](#2-kiến-trúc-tổng-thể)
3. [Module ASCON_PERMUTATION (đã có)](#3-module-ascon_permutation)
4. [Đặc tả ascon_core](#4-đặc-tả-ascon_core)
5. [Register Map của ascon_axi_slave](#5-register-map)
6. [Danh sách Port ascon_axi_slave](#6-port-list-ascon_axi_slave)
7. [Danh sách Port ascon_top](#7-port-list-ascon_top)
8. [Luồng hoạt động](#8-luồng-hoạt-động)
9. [Yêu cầu hành vi](#9-yêu-cầu-hành-vi)
10. [Timing & Performance](#10-timing--performance)
11. [Ví dụ code C driver](#11-ví-dụ-code-c)

---

## 1. Tổng quan

ASCON là thuật toán AEAD (Authenticated Encryption with Associated Data) hạng nhẹ, được NIST chọn làm chuẩn Lightweight Cryptography năm 2023.

**Thông số ASCON-128:**

| Thông số | Giá trị |
|---|---|
| Kích thước key | 128 bit |
| Kích thước nonce | 128 bit |
| Rate (block size) | 64 bit |
| Tag size | 128 bit |
| State nội bộ | 320 bit (5 × 64-bit word: x0..x4) |
| Rounds khởi tạo (pa) | 12 |
| Rounds dữ liệu (pb) | 6 |

**Initialization Vector cố định cho ASCON-128:**
```
IV = 0x80400C0600000000
```

**Cấu trúc state 320-bit:**
```
state[319:256] = x0  (64-bit)
state[255:192] = x1  (64-bit)
state[191:128] = x2  (64-bit)
state[127:64]  = x3  (64-bit)
state[63:0]    = x4  (64-bit)
```

**Các bước mã hóa ASCON-128 (1 block, no AD):**
```
Step 1 — Init:
    state = IV[63:0] || Key[127:0] || Nonce[127:0]
    state = PERMUTATION(state, 12 rounds)
    state[127:0] ^= Key[127:0]          // XOR key vào x3, x4

Step 2 — Associated Data:
    (Phase 1: bỏ qua — không có AD)
    state[63:0] ^= 0x01                  // domain separation

Step 3 — Encrypt 1 block:
    ctext[63:0] = state[319:256] ^ plaintext[63:0]
    state[319:256] = ctext[63:0]
    state = PERMUTATION(state, 6 rounds)

Step 4 — Finalize:
    state[191:64] ^= Key[127:0]          // XOR key vào x2, x3
    state = PERMUTATION(state, 12 rounds)
    state[127:0] ^= Key[127:0]           // XOR key vào x3, x4
    tag[127:0] = state[127:0]            // x3 || x4
```

> **Phase 1:** Chỉ hỗ trợ 1 block 64-bit, không có Associated Data.  
> **Phase 2:** Multi-block + AD — implement sau.

---

## 2. Kiến trúc tổng thể IP

```
┌──────────────────────────────────────────────────────────────────┐
│                        ascon_top                                 │
│                                                                  │
│  ┌──────────────────────┐    ┌───────────────────────────────┐   │
│  │   ascon_axi_slave    │    │        ascon_dma              │   │
│  │  (register map,      │    │  (AXI4-Full Master,           │   │
│  │   control FSM)       │    │   descriptor engine)          │   │
│  └─────────┬────────────┘    └─────────────┬─────────────────┘   │
│            │ reg_if (control,data)          │ dma_data_if         │
│            └────────────────┬──────────────┘                     │
│                             │                                    │
│                    ┌────────▼────────┐                           │
│                    │   ascon_core    │                           │
│                    │  (ASCON-128     │                           │
│                    │   state machine)│                           │
│                    └────────┬────────┘                           │
│                             │                                    │
│                    ┌────────▼────────┐                           │
│                    │ ASCON_PERMUT-   │                           │
│                    │ ATION (extern)  │                           │
│                    └─────────────────┘                           │
└──────────────────────────────────────────────────────────────────┘
         │                          │
         │ AXI4-Lite (S_AXI_*)      │ AXI4-Full Master (M_AXI_DMA_*)
         │                          │
    AXI Crossbar                AXI Crossbar / DDR controller
```

**Hai loại interface AXI trên ascon_top:**

| Interface | Loại | Vai trò |
|---|---|---|
| `S_AXI_*` | AXI4-Lite Slave | CPU đọc/ghi thanh ghi điều khiển |
| `M_AXI_DMA_*` | AXI4-Full Master | DMA đọc plaintext / ghi ciphertext+tag từ/ra DDR |

---

## 3. Module ASCON_PERMUTATION

Module này đã được implement sẵn. `ascon_core` sẽ **instantiate** module này.

```verilog
module ASCON_PERMUTATION (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [319:0] state_in,
    input  wire [3:0]   rounds,      // 6 hoặc 12
    input  wire         start_perm,  // pulse 1 cycle để bắt đầu
    input  wire         mode,        // 0: iterative, 1: pipelined

    output reg  [319:0] state_out,
    output reg          valid,       // state_out hợp lệ
    output reg          done         // pulse 1 cycle khi xong
);
```

**Lưu ý khi sử dụng:**
- `start_perm` phải là pulse 1 cycle duy nhất
- Chờ `done` trước khi đọc `state_out`
- `valid` và `done` có thể cùng assert trong 1 cycle
- Không restart khi đang chạy (`done` chưa về)
- Phase 1: dùng `mode = 0` (iterative) để tiết kiệm tài nguyên

---

## 4. Đặc tả `ascon_core`

### 4.1 Port List

```verilog
module ascon_core (
    input  wire         clk,
    input  wire         rst_n,

    // --- Control ---
    input  wire         start,        // Pulse 1 cycle để bắt đầu
    input  wire         mode,         // 0 = encrypt, 1 = decrypt
    output reg          busy,         // 1 khi đang xử lý
    output reg          done,         // Pulse 1 cycle khi hoàn thành

    // --- Key (128-bit, ghi trước start) ---
    input  wire [31:0]  key_0,        // bits [127:96]
    input  wire [31:0]  key_1,        // bits [95:64]
    input  wire [31:0]  key_2,        // bits [63:32]
    input  wire [31:0]  key_3,        // bits [31:0]

    // --- Nonce (128-bit) ---
    input  wire [31:0]  nonce_0,      // bits [127:96]
    input  wire [31:0]  nonce_1,      // bits [95:64]
    input  wire [31:0]  nonce_2,      // bits [63:32]
    input  wire [31:0]  nonce_3,      // bits [31:0]

    // --- Plaintext / Ciphertext input (64-bit) ---
    input  wire [31:0]  ptext_0,      // bits [63:32]
    input  wire [31:0]  ptext_1,      // bits [31:0]

    // --- Outputs ---
    output reg  [31:0]  ctext_0,      // ciphertext bits [63:32]
    output reg  [31:0]  ctext_1,      // ciphertext bits [31:0]
    output reg  [31:0]  tag_0,        // tag bits [127:96]
    output reg  [31:0]  tag_1,        // tag bits [95:64]
    output reg  [31:0]  tag_2,        // tag bits [63:32]
    output reg  [31:0]  tag_3         // tag bits [31:0]
);
```

### 4.2 Internal State Machine

```
        ┌──────────────────────────────────────────────────────────────┐
        │                                                              │
        ▼                                                              │
      IDLE ──(start=1)──▶ LOAD_STATE ──▶ INIT_PERM
                                              │
                                    (wait done from PERMUTATION,
                                     rounds=12)
                                              │
                                              ▼
                                        XOR_KEY_POST_INIT
                                              │
                                              ▼
                                        DOMAIN_SEP        ← XOR 0x01 vào state[63:0]
                                              │
                                              ▼
                                        ENCRYPT_BLOCK     ← ctext = ptext ^ state[319:256]
                                              │
                                              ▼
                                        DATA_PERM
                                              │
                                    (wait done, rounds=6)
                                              │
                                              ▼
                                        XOR_KEY_FINAL_1   ← state[191:64] ^= key
                                              │
                                              ▼
                                        FINAL_PERM
                                              │
                                    (wait done, rounds=12)
                                              │
                                              ▼
                                        XOR_KEY_FINAL_2   ← state[127:0] ^= key
                                              │
                                              ▼
                                        OUTPUT_TAG        ← tag = state[127:0]
                                              │
                                              ▼
                                           DONE ──▶ IDLE
```

**Chi tiết từng state:**

| State | Mô tả | Cycles |
|---|---|---|
| `IDLE` | Chờ `start` | — |
| `LOAD_STATE` | Ghép `IV \|\| Key \|\| Nonce` thành 320-bit state | 1 |
| `INIT_PERM` | Gọi PERMUTATION 12 rounds, chờ `done` | 12+ |
| `XOR_KEY_POST_INIT` | `state[127:0] ^= key` | 1 |
| `DOMAIN_SEP` | `state[63:0] ^= 64'h01` (no AD) | 1 |
| `ENCRYPT_BLOCK` | `ctext = state[319:256] ^ ptext`, cập nhật state | 1 |
| `DATA_PERM` | Gọi PERMUTATION 6 rounds, chờ `done` | 6+ |
| `XOR_KEY_FINAL_1` | `state[191:64] ^= key` | 1 |
| `FINAL_PERM` | Gọi PERMUTATION 12 rounds, chờ `done` | 12+ |
| `XOR_KEY_FINAL_2` | `state[127:0] ^= key` | 1 |
| `OUTPUT_TAG` | Capture tag, assert `done` | 1 |

### 4.3 Kết nối với ASCON_PERMUTATION

```verilog
// Instantiation trong ascon_core
ASCON_PERMUTATION u_perm (
    .clk        (clk),
    .rst_n      (rst_n),
    .state_in   (perm_state_in),   // reg 320-bit
    .rounds     (perm_rounds),     // 4 hoặc 12 (wire từ FSM)
    .start_perm (perm_start),      // pulse từ FSM
    .mode       (1'b0),            // iterative
    .state_out  (perm_state_out),
    .valid      (perm_valid),
    .done       (perm_done)
);
```

### 4.4 Ước tính số chu kỳ (iterative mode)

| Giai đoạn | Cycles |
|---|---|
| LOAD + XOR setup | 3 |
| INIT_PERM (12 rounds) | 12 |
| DOMAIN_SEP + ENCRYPT | 2 |
| DATA_PERM (6 rounds) | 6 |
| XOR_KEY + FINAL_PERM setup | 2 |
| FINAL_PERM (12 rounds) | 12 |
| OUTPUT_TAG | 1 |
| **Tổng** | **~38 cycles** |

> Số chu kỳ chính xác phụ thuộc vào latency nội bộ của `ASCON_PERMUTATION`. Phải ghi rõ trong header comment sau khi đo simulation.

---

## 5. Register Map

**Địa chỉ base:** `0x2000_0000` (xem `03_SO_DO_DIA_CHI.md`)

### 5.1 Bảng thanh ghi đầy đủ

| Offset | Tên | Access | Reset | Mô tả |
|---|---|---|---|---|
| `0x000` | `CTRL` | R/W | `0x0` | Điều khiển core |
| `0x004` | `STATUS` | RO | `0x0` | Trạng thái core |
| `0x008` | `MODE` | R/W | `0x0` | Encrypt/Decrypt |
| `0x00C` | `IRQ_EN` | R/W | `0x0` | Interrupt enable |
| `0x010` | `KEY_0` | WO | `—` | Key [127:96] |
| `0x014` | `KEY_1` | WO | `—` | Key [95:64] |
| `0x018` | `KEY_2` | WO | `—` | Key [63:32] |
| `0x01C` | `KEY_3` | WO | `—` | Key [31:0] |
| `0x020` | `NONCE_0` | WO | `—` | Nonce [127:96] |
| `0x024` | `NONCE_1` | WO | `—` | Nonce [95:64] |
| `0x028` | `NONCE_2` | WO | `—` | Nonce [63:32] |
| `0x02C` | `NONCE_3` | WO | `—` | Nonce [31:0] |
| `0x030` | `PTEXT_0` | WO | `—` | Plaintext [63:32] |
| `0x034` | `PTEXT_1` | WO | `—` | Plaintext [31:0] |
| `0x038` | *(rsvd)* | — | — | — |
| `0x03C` | *(rsvd)* | — | — | — |
| `0x040` | `CTEXT_0` | RO | `0x0` | Ciphertext [63:32] |
| `0x044` | `CTEXT_1` | RO | `0x0` | Ciphertext [31:0] |
| `0x048` | `TAG_0` | RO | `0x0` | Auth Tag [127:96] |
| `0x04C` | `TAG_1` | RO | `0x0` | Auth Tag [95:64] |
| `0x050` | `TAG_2` | RO | `0x0` | Auth Tag [63:32] |
| `0x054` | `TAG_3` | RO | `0x0` | Auth Tag [31:0] |
| `0x058–0x0FC` | *(rsvd)* | — | — | Reserved cho Phase 2 |
| `0x100–0x1FF` | DMA Registers | — | — | Xem `05B_SPEC_ASCON_DMA.md` |

### 5.2 Chi tiết bit từng thanh ghi

**CTRL (0x000):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `START` | Ghi 1 để bắt đầu. Auto-clear sau 1 cycle. Ignored nếu BUSY=1 |
| [1] | `SOFT_RST` | Ghi 1 để reset toàn bộ core. Auto-clear |
| [2] | `DMA_EN` | 1 = dùng DMA làm nguồn data; 0 = dùng thanh ghi PTEXT/KEY/NONCE |
| [31:3] | *(rsvd)* | Bỏ qua khi ghi, đọc về 0 |

**STATUS (0x004):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `BUSY` | 1 khi core đang tính toán |
| [1] | `DONE` | 1 khi hoàn thành. Sticky — giữ đến khi SOFT_RST=1 |
| [2] | `DMA_BUSY` | 1 khi DMA engine đang chạy |
| [3] | `DMA_DONE` | 1 khi DMA hoàn thành. Sticky |
| [4] | `ERROR` | 1 nếu có lỗi (Phase 2) |
| [5] | `DMA_ERROR` | 1 nếu DMA gặp lỗi AXI (SLVERR / DECERR) |
| [31:6] | *(rsvd)* | Đọc về 0 |

**MODE (0x008):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `ENC_DEC` | 0 = encrypt, 1 = decrypt |
| [1] | `PERM_MODE` | 0 = iterative permutation, 1 = pipelined (nếu ASCON_PERMUTATION hỗ trợ) |
| [31:2] | *(rsvd)* | Bỏ qua khi ghi |

**IRQ_EN (0x00C):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `DONE_IRQ_EN` | 1 = cho phép interrupt khi DONE=1 |
| [1] | `DMA_DONE_IRQ_EN` | 1 = cho phép interrupt khi DMA_DONE=1 |
| [2] | `ERROR_IRQ_EN` | 1 = cho phép interrupt khi ERROR=1 |
| [31:3] | *(rsvd)* | — |

---

## 6. Port List `ascon_axi_slave`

```verilog
module ascon_axi_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  wire                      clk,
    input  wire                      rst_n,

    // ── AXI4-Lite Slave ───────────────────────────────────────────
    // Write Address Channel
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire                      S_AXI_AWVALID,
    output wire                      S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0]   S_AXI_WSTRB,
    input  wire                      S_AXI_WVALID,
    output wire                      S_AXI_WREADY,

    // Write Response Channel
    output wire [ID_WIDTH-1:0]       S_AXI_BID,
    output wire [1:0]                S_AXI_BRESP,   // 2'b00 = OKAY
    output wire                      S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    // Read Address Channel
    input  wire [ID_WIDTH-1:0]       S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire                      S_AXI_ARVALID,
    output wire                      S_AXI_ARREADY,

    // Read Data Channel
    output wire [ID_WIDTH-1:0]       S_AXI_RID,
    output wire [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output wire [1:0]                S_AXI_RRESP,
    output wire                      S_AXI_RLAST,
    output wire                      S_AXI_RVALID,
    input  wire                      S_AXI_RREADY,

    // ── Internal interface đến ascon_core ─────────────────────────
    output wire [31:0]  key_0, key_1, key_2, key_3,
    output wire [31:0]  nonce_0, nonce_1, nonce_2, nonce_3,
    output wire [31:0]  ptext_0, ptext_1,
    output wire         core_start,
    output wire         core_mode,
    output wire         core_soft_rst,
    output wire         dma_en,

    input  wire         core_busy,
    input  wire         core_done,
    input  wire         dma_busy,
    input  wire         dma_done,
    input  wire         dma_error,
    input  wire [31:0]  ctext_0, ctext_1,
    input  wire [31:0]  tag_0, tag_1, tag_2, tag_3,

    // ── DMA register interface ────────────────────────────────────
    output wire [31:0]  dma_src_addr,
    output wire [31:0]  dma_dst_addr,
    output wire [31:0]  dma_length,
    output wire         dma_start,
    output wire         dma_soft_rst,

    // ── Interrupt output ──────────────────────────────────────────
    output wire         irq          // kết nối đến GIC hoặc PLIC
);
```

---

## 7. Port List `ascon_top`

```verilog
module ascon_top #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter ID_WIDTH       = 4,
    parameter DMA_ID_WIDTH   = 4,
    parameter DMA_DATA_WIDTH = 64    // AXI4 Full Master bus width
) (
    input  wire  clk,
    input  wire  rst_n,

    // ── AXI4-Lite Slave (từ CPU) ──────────────────────────────────
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire                      S_AXI_AWVALID,
    output wire                      S_AXI_AWREADY,
    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0]   S_AXI_WSTRB,
    input  wire                      S_AXI_WVALID,
    output wire                      S_AXI_WREADY,
    output wire [ID_WIDTH-1:0]       S_AXI_BID,
    output wire [1:0]                S_AXI_BRESP,
    output wire                      S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,
    input  wire [ID_WIDTH-1:0]       S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire                      S_AXI_ARVALID,
    output wire                      S_AXI_ARREADY,
    output wire [ID_WIDTH-1:0]       S_AXI_RID,
    output wire [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output wire [1:0]                S_AXI_RRESP,
    output wire                      S_AXI_RLAST,
    output wire                      S_AXI_RVALID,
    input  wire                      S_AXI_RREADY,

    // ── AXI4-Full Master (DMA ra ngoài DDR) ───────────────────────
    output wire [DMA_ID_WIDTH-1:0]   M_AXI_AWID,
    output wire [ADDR_WIDTH-1:0]     M_AXI_AWADDR,
    output wire [7:0]                M_AXI_AWLEN,
    output wire [2:0]                M_AXI_AWSIZE,
    output wire [1:0]                M_AXI_AWBURST,
    output wire                      M_AXI_AWVALID,
    input  wire                      M_AXI_AWREADY,
    output wire [DMA_DATA_WIDTH-1:0] M_AXI_WDATA,
    output wire [DMA_DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output wire                      M_AXI_WLAST,
    output wire                      M_AXI_WVALID,
    input  wire                      M_AXI_WREADY,
    input  wire [DMA_ID_WIDTH-1:0]   M_AXI_BID,
    input  wire [1:0]                M_AXI_BRESP,
    input  wire                      M_AXI_BVALID,
    output wire                      M_AXI_BREADY,
    output wire [DMA_ID_WIDTH-1:0]   M_AXI_ARID,
    output wire [ADDR_WIDTH-1:0]     M_AXI_ARADDR,
    output wire [7:0]                M_AXI_ARLEN,
    output wire [2:0]                M_AXI_ARSIZE,
    output wire [1:0]                M_AXI_ARBURST,
    output wire                      M_AXI_ARVALID,
    input  wire                      M_AXI_ARREADY,
    input  wire [DMA_ID_WIDTH-1:0]   M_AXI_RID,
    input  wire [DMA_DATA_WIDTH-1:0] M_AXI_RDATA,
    input  wire [1:0]                M_AXI_RRESP,
    input  wire                      M_AXI_RLAST,
    input  wire                      M_AXI_RVALID,
    output wire                      M_AXI_RREADY,

    // ── Interrupt ─────────────────────────────────────────────────
    output wire  irq
);
```

---

## 8. Luồng hoạt động

### 8.1 Chế độ thanh ghi (CTRL.DMA_EN = 0)

```
CPU:
1. Ghi SOFT_RST       → CTRL[1] = 1
2. Ghi KEY (4 words)  → KEY_0..KEY_3
3. Ghi NONCE (4 words)→ NONCE_0..NONCE_3
4. Ghi PTEXT (2 words)→ PTEXT_0, PTEXT_1
5. Ghi MODE           → MODE[0] = 0 (encrypt)
6. Ghi START          → CTRL[0] = 1
7. Poll DONE          → while (!(STATUS & 0x2));
8. Đọc CTEXT, TAG
9. SOFT_RST cho lần tiếp theo
```

### 8.2 Chế độ DMA (CTRL.DMA_EN = 1)

```
CPU:
1. Ghi SOFT_RST
2. Ghi KEY, NONCE (vẫn qua thanh ghi — key/nonce không qua DMA)
3. Ghi DMA_SRC_ADDR  → địa chỉ DDR chứa plaintext
4. Ghi DMA_DST_ADDR  → địa chỉ DDR để ghi ciphertext + tag
5. Ghi DMA_LEN       → số bytes (Phase 1: luôn = 8)
6. Ghi MODE, DMA_EN  → CTRL[2] = 1
7. Ghi START         → CTRL[0] = 1
   (DMA tự động fetch plaintext → feed ascon_core → write ctext+tag)
8. Poll DMA_DONE      → while (!(STATUS & 0x8));
9. Đọc kết quả từ DDR tại DMA_DST_ADDR
```

---

## 9. Yêu cầu hành vi

1. **START khi BUSY=1:** Bỏ qua, trả AXI OKAY. Phần mềm chịu trách nhiệm kiểm tra STATUS trước.

2. **CTEXT/TAG sticky:** Không thay đổi sau DONE=1 cho đến khi SOFT_RST=1. Cho phép CPU đọc nhiều lần.

3. **Ghi vào RO registers (CTEXT, TAG, STATUS):** Chấp nhận giao dịch AXI (OKAY), bỏ qua data.

4. **Ghi vào WO registers (KEY, NONCE, PTEXT):** Ghi vào register, đọc trả về `32'h0000_0000`.

5. **SOFT_RST:** Reset toàn bộ state machine về IDLE, clear DONE, clear DMA_DONE. Không clear KEY/NONCE/PTEXT registers (để dùng lại key nếu muốn).

6. **DMA_EN=1 + START=1:** Core chờ DMA fetch xong plaintext rồi mới bắt đầu tính. ascon_core không nhận `start` trực tiếp mà nhận từ DMA engine khi data ready.

7. **Interrupt:** `irq` được assert khi `(DONE & IRQ_EN[0]) | (DMA_DONE & IRQ_EN[1]) | (ERROR & IRQ_EN[2])`. Level-triggered, giữ cho đến khi bit tương ứng được clear bởi SOFT_RST.

8. **Correctness:** Output phải khớp test vector chính thức ASCON-128.  
   Tham khảo: https://ascon.iaik.tugraz.at/

---

## 10. Timing & Performance

| Thông số | Giá trị (mục tiêu) |
|---|---|
| Target frequency | 100 MHz |
| Latency 1 block (iterative) | ~38 cycles = 380 ns @ 100 MHz |
| Throughput 1 block (không pipeline) | 64 bit / 380 ns ≈ 168 Mbps |
| AXI4-Lite max register latency | 2 cycles (1-cycle accept + 1-cycle response) |
| DMA burst length | 1–16 beats (configurable qua `DMA_BURST_LEN`) |

---

## 11. Ví dụ code C

```c
#include <stdint.h>

#define ASCON_BASE    0x20000000UL
#define REG(off)      (*((volatile uint32_t *)(ASCON_BASE + (off))))

// Control / Status
#define ASCON_CTRL    REG(0x000)
#define ASCON_STATUS  REG(0x004)
#define ASCON_MODE    REG(0x008)
#define ASCON_IRQ_EN  REG(0x00C)

// Key
#define ASCON_KEY0    REG(0x010)
#define ASCON_KEY1    REG(0x014)
#define ASCON_KEY2    REG(0x018)
#define ASCON_KEY3    REG(0x01C)

// Nonce
#define ASCON_NONCE0  REG(0x020)
#define ASCON_NONCE1  REG(0x024)
#define ASCON_NONCE2  REG(0x028)
#define ASCON_NONCE3  REG(0x02C)

// Plaintext
#define ASCON_PTEXT0  REG(0x030)
#define ASCON_PTEXT1  REG(0x034)

// Ciphertext + Tag
#define ASCON_CTEXT0  REG(0x040)
#define ASCON_CTEXT1  REG(0x044)
#define ASCON_TAG0    REG(0x048)
#define ASCON_TAG1    REG(0x04C)
#define ASCON_TAG2    REG(0x050)
#define ASCON_TAG3    REG(0x054)

// DMA
#define ASCON_DMA_SRC REG(0x100)
#define ASCON_DMA_DST REG(0x104)
#define ASCON_DMA_LEN REG(0x108)

// CTRL bits
#define CTRL_START    (1u << 0)
#define CTRL_SOFT_RST (1u << 1)
#define CTRL_DMA_EN   (1u << 2)

// STATUS bits
#define STATUS_BUSY      (1u << 0)
#define STATUS_DONE      (1u << 1)
#define STATUS_DMA_BUSY  (1u << 2)
#define STATUS_DMA_DONE  (1u << 3)
#define STATUS_ERROR     (1u << 4)
#define STATUS_DMA_ERROR (1u << 5)

/* Mã hóa qua thanh ghi (không DMA) */
int ascon_encrypt_reg(
    const uint32_t key[4], const uint32_t nonce[4],
    const uint32_t ptext[2],
    uint32_t ctext[2], uint32_t tag[4])
{
    // Reset
    ASCON_CTRL = CTRL_SOFT_RST;

    // Key + Nonce + Plaintext
    ASCON_KEY0 = key[0]; ASCON_KEY1 = key[1];
    ASCON_KEY2 = key[2]; ASCON_KEY3 = key[3];
    ASCON_NONCE0 = nonce[0]; ASCON_NONCE1 = nonce[1];
    ASCON_NONCE2 = nonce[2]; ASCON_NONCE3 = nonce[3];
    ASCON_PTEXT0 = ptext[0]; ASCON_PTEXT1 = ptext[1];

    ASCON_MODE = 0;               // encrypt
    ASCON_CTRL = CTRL_START;

    // Poll DONE
    while (!(ASCON_STATUS & STATUS_DONE));

    if (ASCON_STATUS & STATUS_ERROR) return -1;

    ctext[0] = ASCON_CTEXT0; ctext[1] = ASCON_CTEXT1;
    tag[0] = ASCON_TAG0; tag[1] = ASCON_TAG1;
    tag[2] = ASCON_TAG2; tag[3] = ASCON_TAG3;
    return 0;
}

/* Mã hóa qua DMA */
int ascon_encrypt_dma(
    const uint32_t key[4], const uint32_t nonce[4],
    uint32_t src_phys_addr,   // địa chỉ vật lý của plaintext trong DDR
    uint32_t dst_phys_addr)   // địa chỉ vật lý để ghi ctext+tag
{
    ASCON_CTRL = CTRL_SOFT_RST;

    ASCON_KEY0 = key[0]; ASCON_KEY1 = key[1];
    ASCON_KEY2 = key[2]; ASCON_KEY3 = key[3];
    ASCON_NONCE0 = nonce[0]; ASCON_NONCE1 = nonce[1];
    ASCON_NONCE2 = nonce[2]; ASCON_NONCE3 = nonce[3];

    ASCON_DMA_SRC = src_phys_addr;
    ASCON_DMA_DST = dst_phys_addr;
    ASCON_DMA_LEN = 8;   // 1 block = 8 bytes

    ASCON_MODE = 0;
    ASCON_CTRL = CTRL_DMA_EN | CTRL_START;

    while (!(ASCON_STATUS & STATUS_DMA_DONE));

    if (ASCON_STATUS & (STATUS_ERROR | STATUS_DMA_ERROR)) return -1;
    return 0;
}
```

---

*Tiếp theo: Đọc `05B_SPEC_ASCON_DMA.md` để biết chi tiết DMA engine.*  
*Xem thêm: `06_SPEC_SOC_CONTROLLER.md`*
