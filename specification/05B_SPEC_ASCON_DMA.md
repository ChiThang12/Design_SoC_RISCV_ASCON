# 05B — Đặc Tả Module: ASCON DMA Engine

**Tên module:** `ascon_dma`  
**File đầu ra:** `crypto/ascon/ascon_dma.v`  
**Ưu tiên:** Cao — phần không thể thiếu để tăng tốc throughput  
**Đọc trước:** `02_QUY_UONG_AXI4.md`, `03_SO_DO_DIA_CHI.md`, `05A_SPEC_ASCON_CORE.md`

---

## Mục lục

1. [Tổng quan DMA trong IP ASCON](#1-tổng-quan)
2. [Kiến trúc DMA engine](#2-kiến-trúc)
3. [Port List](#3-port-list)
4. [Register Map DMA](#4-register-map-dma)
5. [State Machine](#5-state-machine)
6. [Giao thức AXI4-Full Master](#6-giao-thức-axi4-full-master)
7. [Giao tiếp với ascon_core](#7-giao-tiếp-với-ascon_core)
8. [Data Path & Buffering](#8-data-path--buffering)
9. [Xử lý lỗi](#9-xử-lý-lỗi)
10. [Timing & Constraints](#10-timing--constraints)
11. [Ví dụ giao dịch đầy đủ](#11-ví-dụ-giao-dịch)

---

## 1. Tổng quan

### 1.1 Mục đích

Khi không có DMA, CPU phải ghi từng word (32-bit) plaintext vào thanh ghi `PTEXT_0/1` và đọc từng word kết quả từ `CTEXT/TAG`. Với multi-block data (Phase 2), điều này tạo ra bottleneck lớn vì mỗi lần CPU ghi/đọc tiêu tốn bus cycles.

`ascon_dma` giải quyết vấn đề này bằng cách:
- **Đọc plaintext** từ DDR (hoặc bất kỳ AXI slave nào) qua AXI4-Full burst
- **Feed trực tiếp** vào `ascon_core` mà không cần CPU can thiệp
- **Ghi ciphertext + tag** ra DDR sau khi core hoàn thành

### 1.2 Phạm vi Phase 1

| Tính năng | Phase 1 | Phase 2 |
|---|---|---|
| Single block (64-bit) | ✅ | ✅ |
| Multi-block streaming | ❌ | ✅ |
| Scatter-Gather (descriptor chain) | ❌ | ✅ |
| AXI4-Full burst length | 1 beat | 1–16 beats |
| Key/Nonce qua DMA | ❌ | ✅ (optional) |

### 1.3 Vị trí trong IP

```
CPU ──AXI4-Lite──▶ ascon_axi_slave ──reg_if──▶ ascon_dma
                                                     │
                              ┌──────────────────────┤
                              │ data_if (plaintext)  │ M_AXI (AXI4-Full)
                              ▼                      ▼
                         ascon_core              DDR / SRAM
                              │
                              │ result_if (ctext+tag)
                              ▼
                         ascon_dma ──M_AXI──▶ DDR write
```

---

## 2. Kiến trúc

```
┌─────────────────────────────────────────────────────────────┐
│                       ascon_dma                             │
│                                                             │
│  ┌─────────────────┐    ┌──────────────────────────────┐    │
│  │  DMA Control    │    │     AXI4 Master FSM          │    │
│  │  FSM            │◄──►│  (Read Engine / Write Engine)│    │
│  └────────┬────────┘    └──────────────┬───────────────┘    │
│           │                            │                    │
│  ┌────────▼────────────────────────────▼───────────────┐    │
│  │              Internal Data Buffer                   │    │
│  │  ┌─────────────────┐   ┌─────────────────────────┐  │    │
│  │  │  RD FIFO        │   │  WR FIFO                │  │    │
│  │  │ (DDR→core)      │   │ (core→DDR)              │  │    │
│  │  │ depth: 4×64-bit │   │ depth: 8×32-bit         │  │    │
│  │  └────────┬────────┘   └──────────┬──────────────┘  │    │
│  └───────────┼─────────────────────  ┼─────────────────┘    │
│              │                       │                      │
└──────────────┼───────────────────────┼──────────────────────┘
               │                       │
               ▼                       ▲
          ascon_core               ascon_core
         (ptext input)           (ctext+tag output)
```

**Hai engine độc lập:**
- **Read Engine:** Fetch plaintext từ DDR → RD FIFO → `ascon_core`
- **Write Engine:** Nhận ctext+tag từ `ascon_core` → WR FIFO → Ghi ra DDR

---

## 3. Port List

```verilog
module ascon_dma #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH = 64,   // AXI4 Master bus width
    parameter AXI_ID_WIDTH   = 4,
    parameter RD_FIFO_DEPTH  = 4,    // entries (64-bit mỗi entry)
    parameter WR_FIFO_DEPTH  = 8     // entries (32-bit mỗi entry)
) (
    input  wire  clk,
    input  wire  rst_n,

    // ── Control interface (từ ascon_axi_slave) ────────────────────
    input  wire [ADDR_WIDTH-1:0]  src_addr,      // DDR addr của plaintext
    input  wire [ADDR_WIDTH-1:0]  dst_addr,      // DDR addr để ghi ctext+tag
    input  wire [31:0]            byte_len,      // số bytes cần xử lý (Phase 1: luôn = 8)
    input  wire                   dma_start,     // pulse 1 cycle từ reg slave
    input  wire                   dma_soft_rst,  // reset DMA engine

    output reg                    dma_busy,      // 1 khi đang chạy
    output reg                    dma_done,      // pulse 1 cycle khi xong
    output reg                    dma_error,     // 1 nếu AXI trả SLVERR/DECERR

    // ── Interface đến ascon_core ──────────────────────────────────
    // Data path: DMA → core (plaintext)
    output reg  [31:0]            core_ptext_0,  // plaintext word 0 [63:32]
    output reg  [31:0]            core_ptext_1,  // plaintext word 1 [31:0]
    output reg                    core_data_valid, // 1 khi ptext valid
    input  wire                   core_data_ready, // 1 khi core sẵn sàng nhận

    // Trigger: DMA kích hoạt core sau khi data ready
    output reg                    core_start,    // pulse 1 cycle
    input  wire                   core_busy,
    input  wire                   core_done,

    // Data path: core → DMA (ciphertext + tag)
    input  wire [31:0]            core_ctext_0,
    input  wire [31:0]            core_ctext_1,
    input  wire [31:0]            core_tag_0,
    input  wire [31:0]            core_tag_1,
    input  wire [31:0]            core_tag_2,
    input  wire [31:0]            core_tag_3,
    input  wire                   core_result_valid, // = core_done

    // ── AXI4-Full Master ──────────────────────────────────────────
    // Write Address Channel
    output wire [AXI_ID_WIDTH-1:0]      M_AXI_AWID,
    output wire [ADDR_WIDTH-1:0]        M_AXI_AWADDR,
    output wire [7:0]                   M_AXI_AWLEN,    // beats - 1
    output wire [2:0]                   M_AXI_AWSIZE,   // log2(bytes/beat)
    output wire [1:0]                   M_AXI_AWBURST,  // 2'b01 = INCR
    output wire [3:0]                   M_AXI_AWCACHE,
    output wire [2:0]                   M_AXI_AWPROT,
    output wire                         M_AXI_AWVALID,
    input  wire                         M_AXI_AWREADY,

    // Write Data Channel
    output wire [AXI_DATA_WIDTH-1:0]    M_AXI_WDATA,
    output wire [AXI_DATA_WIDTH/8-1:0]  M_AXI_WSTRB,
    output wire                         M_AXI_WLAST,
    output wire                         M_AXI_WVALID,
    input  wire                         M_AXI_WREADY,

    // Write Response Channel
    input  wire [AXI_ID_WIDTH-1:0]      M_AXI_BID,
    input  wire [1:0]                   M_AXI_BRESP,    // 0=OKAY, 2=SLVERR, 3=DECERR
    input  wire                         M_AXI_BVALID,
    output wire                         M_AXI_BREADY,

    // Read Address Channel
    output wire [AXI_ID_WIDTH-1:0]      M_AXI_ARID,
    output wire [ADDR_WIDTH-1:0]        M_AXI_ARADDR,
    output wire [7:0]                   M_AXI_ARLEN,
    output wire [2:0]                   M_AXI_ARSIZE,
    output wire [1:0]                   M_AXI_ARBURST,
    output wire [3:0]                   M_AXI_ARCACHE,
    output wire [2:0]                   M_AXI_ARPROT,
    output wire                         M_AXI_ARVALID,
    input  wire                         M_AXI_ARREADY,

    // Read Data Channel
    input  wire [AXI_ID_WIDTH-1:0]      M_AXI_RID,
    input  wire [AXI_DATA_WIDTH-1:0]    M_AXI_RDATA,
    input  wire [1:0]                   M_AXI_RRESP,
    input  wire                         M_AXI_RLAST,
    input  wire                         M_AXI_RVALID,
    output wire                         M_AXI_RREADY
);
```

---

## 4. Register Map DMA

Các thanh ghi DMA nằm trong không gian địa chỉ của `ascon_axi_slave`, offset từ `0x100`:

**Base address:** `0x2000_0000`

| Offset | Tên | Access | Reset | Mô tả |
|---|---|---|---|---|
| `0x100` | `DMA_SRC_ADDR` | R/W | `0x0` | Địa chỉ vật lý nguồn (plaintext) |
| `0x104` | `DMA_DST_ADDR` | R/W | `0x0` | Địa chỉ vật lý đích (ctext + tag) |
| `0x108` | `DMA_BYTE_LEN` | R/W | `0x0` | Số bytes cần đọc (Phase 1: = 8) |
| `0x10C` | `DMA_CTRL` | R/W | `0x0` | Điều khiển DMA |
| `0x110` | `DMA_STATUS` | RO | `0x0` | Trạng thái DMA |
| `0x114` | `DMA_BURST_LEN` | R/W | `0x0` | AXI burst length (0 = 1 beat) |
| `0x118` | `DMA_ERR_ADDR` | RO | `0x0` | Địa chỉ gây lỗi (debug) |
| `0x11C–0x1FC` | *(rsvd)* | — | — | Dành cho Scatter-Gather Phase 2 |

### 4.1 Chi tiết bit

**DMA_CTRL (0x10C):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `DMA_START` | Ghi 1 để kích hoạt DMA. Auto-clear. Ignored nếu DMA_BUSY=1 |
| [1] | `DMA_SOFT_RST` | Reset DMA engine, clear FIFO, clear lỗi. Auto-clear |
| [2] | `RD_ONLY` | 1 = chỉ đọc data (không ghi kết quả ra DDR, dùng cho test) |
| [3] | `WR_ONLY` | 1 = chỉ ghi kết quả (không đọc plaintext, dùng cho test) |
| [31:4] | *(rsvd)* | — |

**DMA_STATUS (0x110):**

| Bit | Tên | Mô tả |
|---|---|---|
| [0] | `DMA_BUSY` | 1 khi DMA đang chạy (read hoặc write hoặc cả hai) |
| [1] | `DMA_DONE` | 1 khi toàn bộ transaction hoàn thành. Sticky cho đến SOFT_RST |
| [2] | `RD_DONE` | 1 khi read engine hoàn thành |
| [3] | `WR_DONE` | 1 khi write engine hoàn thành |
| [4] | `RD_ERROR` | 1 nếu AXI read trả SLVERR hoặc DECERR |
| [5] | `WR_ERROR` | 1 nếu AXI write trả SLVERR hoặc DECERR |
| [6] | `FIFO_OVERFLOW` | 1 nếu RD_FIFO bị overflow (vượt capacity) |
| [31:7] | *(rsvd)* | — |

**DMA_BURST_LEN (0x114):**

| Bit | Tên | Mô tả |
|---|---|---|
| [7:0] | `BURST_LEN` | AXI AWLEN / ARLEN: số beat - 1. 0x0 = 1 beat, 0xF = 16 beats |
| [31:8] | *(rsvd)* | — |

> Phase 1: `DMA_BURST_LEN` = 0 (single beat). Phase 2 mới dùng burst.

---

## 5. State Machine

### 5.1 DMA Control FSM (top-level)

```
     IDLE
      │
      │ (dma_start=1)
      ▼
   RD_ADDR ──── issue AR channel ────▶ RD_DATA
                                           │
                                    (RLAST received,
                                     data vào RD FIFO)
                                           │
                                           ▼
                                      CORE_FEED ──── drive ptext từ FIFO ──▶ CORE_WAIT
                                                                                  │
                                                                          (core_done=1)
                                                                                  │
                                                                                  ▼
                                                                           WR_ADDR ──▶ WR_DATA ──▶ WR_RESP
                                                                                                       │
                                                                                               (BVALID received)
                                                                                                       │
                                                                                                       ▼
                                                                                                    DONE ──▶ IDLE
```

### 5.2 Chi tiết từng state

| State | Mô tả | Điều kiện chuyển |
|---|---|---|
| `IDLE` | Chờ `dma_start` | `dma_start = 1` |
| `RD_ADDR` | Assert `M_AXI_ARVALID`, gửi `src_addr` | `M_AXI_ARREADY = 1` |
| `RD_DATA` | Nhận data từ `M_AXI_RDATA`, push vào RD_FIFO | `M_AXI_RLAST = 1` và `M_AXI_RVALID = 1` |
| `CORE_FEED` | Pop RD_FIFO → drive `core_ptext_0/1`, assert `core_data_valid` | `core_data_ready = 1` |
| `CORE_WAIT` | Assert `core_start` (1 cycle), chờ `core_done` | `core_done = 1` |
| `WR_ADDR` | Assert `M_AXI_AWVALID`, gửi `dst_addr` | `M_AXI_AWREADY = 1` |
| `WR_DATA` | Push ctext+tag (24 bytes = 3 beats × 64-bit hoặc 6 beats × 32-bit) | `M_AXI_WLAST` handshake |
| `WR_RESP` | Chờ `M_AXI_BVALID` | `M_AXI_BVALID = 1` |
| `DONE` | Assert `dma_done` 1 cycle, set `DMA_STATUS.DONE` | 1 cycle |

### 5.3 Read/Write Engine phân tách

Trong implementation thực tế, Read Engine và Write Engine có thể chạy như hai sub-FSM song song trong cùng một module, hoặc tách thành hai FSM riêng biệt được điều phối bởi Control FSM.

**Phase 1:** Control FSM tuần tự (Read xong → CORE → Write). Không overlap.  
**Phase 2:** Read và Write có thể overlap nếu dùng multi-block pipeline.

---

## 6. Giao thức AXI4-Full Master

### 6.1 Read Transaction (fetch plaintext)

**Phase 1: 1 beat, 64-bit data bus**

```
Cycle:  1        2        3        4
AR:   ARVALID─┐
              └─(ARREADY) → handshake xảy ra tại cycle 2
R:             RVALID──┐  RVALID
                       └─(RREADY=1)  RLAST=1 → done
```

**Tham số AXI cho read (Phase 1):**

| Signal | Giá trị |
|---|---|
| `M_AXI_ARADDR` | `src_addr` |
| `M_AXI_ARLEN` | `8'h00` (1 beat) |
| `M_AXI_ARSIZE` | `3'b011` (8 bytes/beat, nếu bus 64-bit) |
| `M_AXI_ARBURST` | `2'b01` (INCR) |
| `M_AXI_ARCACHE` | `4'b0010` (Normal Non-cacheable Bufferable) |
| `M_AXI_ARPROT` | `3'b000` |
| `M_AXI_ARID` | `{ID_WIDTH{1'b0}}` (ID = 0) |

### 6.2 Write Transaction (ghi ctext + tag)

**Phase 1: 3 beats × 64-bit = 192 bits = 24 bytes**

```
Lần ghi ra DDR:
Beat 0: ctext[63:0]        = {ctext_0, ctext_1}
Beat 1: tag[127:64]        = {tag_0, tag_1}
Beat 2: tag[63:0]          = {tag_2, tag_3}
```

**Tham số AXI cho write (Phase 1):**

| Signal | Giá trị |
|---|---|
| `M_AXI_AWADDR` | `dst_addr` |
| `M_AXI_AWLEN` | `8'h02` (3 beats) |
| `M_AXI_AWSIZE` | `3'b011` (8 bytes/beat) |
| `M_AXI_AWBURST` | `2'b01` (INCR) |
| `M_AXI_AWCACHE` | `4'b0010` |
| `M_AXI_AWPROT` | `3'b000` |
| `M_AXI_WSTRB` | `8'hFF` (tất cả bytes valid) |

### 6.3 Alignment Requirements

- `src_addr` và `dst_addr` **phải align theo AXI_DATA_WIDTH/8** bytes.
  - 64-bit bus → align 8 bytes
- Nếu không align, phần cứng **không tự xử lý unaligned access** trong Phase 1. Driver phải đảm bảo.
- `DMA_STATUS.RD_ERROR` sẽ set nếu slave trả `RRESP != OKAY`.

### 6.4 Outstanding Transaction

Phase 1: **1 transaction outstanding duy nhất** tại một thời điểm. Không gửi AR/AW mới khi transaction cũ chưa xong.

---

## 7. Giao tiếp với ascon_core

### 7.1 Handshake plaintext

```
DMA state: CORE_FEED
                          ┌──────────┐
core_ptext_0/1 ──valid──▶│           │
core_data_valid ──1──────▶│ ascon_core│
                          │           │
core_data_ready ◄──1──────│ (sẵn sàng)│
                          └──────────┘

Sau khi core_data_ready = 1:
  → DMA chuyển sang CORE_WAIT
  → DMA assert core_start = 1 (1 cycle)
  → ascon_core bắt đầu tính toán
```

### 7.2 Nhận kết quả

```
DMA state: CORE_WAIT

core_done ──pulse──▶ DMA nhận tín hiệu
  → Latch ctext_0, ctext_1, tag_0..tag_3 vào WR FIFO
  → Chuyển sang WR_ADDR
```

### 7.3 Timing diagram tổng thể (Phase 1)

```
Cycle:  1      5      6      7     8..19   20     21    22..25
        │      │      │      │      │      │      │      │
dma_start: ┐
           └(pulse)
RD_ADDR:        ─────
RD_DATA:               ─────
CORE_FEED:                    ──
CORE_WAIT:                      ─────────────
  (core bận ~38 cycles)
WR_ADDR:                                      ─────
WR_DATA:                                            ─────────
dma_done:                                                    ┐
                                                             └(pulse)
```

---

## 8. Data Path & Buffering

### 8.1 RD FIFO (DDR → core)

| Thông số | Giá trị |
|---|---|
| Width | 64-bit |
| Depth | 4 entries |
| Loại | Synchronous FIFO |
| Mục đích | Decouple AXI read latency khỏi core |

**Luồng ghi vào RD FIFO:**
- AXI `M_AXI_RDATA` (64-bit) → push vào FIFO khi `RVALID & RREADY`
- `RREADY` = 1 khi FIFO chưa full

**Luồng đọc từ RD FIFO:**
- Pop khi `CORE_FEED` state
- Map 64-bit FIFO entry → `core_ptext_0 = [63:32]`, `core_ptext_1 = [31:0]`

### 8.2 WR FIFO (core → DDR)

| Thông số | Giá trị |
|---|---|
| Width | 32-bit |
| Depth | 8 entries |
| Loại | Synchronous FIFO |
| Mục đích | Buffer ctext+tag (6 × 32-bit = 6 entries) |

**Luồng ghi vào WR FIFO (khi core_done = 1):**
```
push: ctext_0, ctext_1, tag_0, tag_1, tag_2, tag_3
```

**Luồng đọc từ WR FIFO → AXI write:**
- 2 entries × 32-bit ghép thành 1 beat × 64-bit
- Beat 0: {ctext_0, ctext_1}
- Beat 1: {tag_0, tag_1}
- Beat 2: {tag_2, tag_3}

### 8.3 Layout bộ nhớ tại địa chỉ đích

```
dst_addr + 0x00 : ctext[63:32]   (byte 0-3)
dst_addr + 0x04 : ctext[31:0]    (byte 4-7)
dst_addr + 0x08 : tag[127:96]    (byte 8-11)
dst_addr + 0x0C : tag[95:64]     (byte 12-15)
dst_addr + 0x10 : tag[63:32]     (byte 16-19)
dst_addr + 0x14 : tag[31:0]      (byte 20-23)
```

> Tổng: 24 bytes = 6 × 32-bit words.

---

## 9. Xử lý lỗi

### 9.1 Các loại lỗi

| Lỗi | Nguồn | Bit status | Hành vi |
|---|---|---|---|
| AXI Read error | `M_AXI_RRESP != 2'b00` | `RD_ERROR` | Dừng ngay, không start core |
| AXI Write error | `M_AXI_BRESP != 2'b00` | `WR_ERROR` | Set error, assert `dma_error` |
| FIFO overflow | Write khi FIFO full | `FIFO_OVERFLOW` | Set error (không mất data nếu depth đủ) |
| Unaligned address | (kiểm tra bằng phần mềm) | — | Không xử lý trong HW Phase 1 |

### 9.2 Recovery

1. CPU nhận interrupt hoặc poll `DMA_STATUS.RD_ERROR / WR_ERROR`
2. Ghi `DMA_SOFT_RST = 1` để reset DMA engine về IDLE
3. Ghi lại `DMA_SRC_ADDR`, `DMA_DST_ADDR`, và các tham số
4. Ghi `DMA_START` lại để thử lại

### 9.3 `DMA_ERR_ADDR` register

Khi xảy ra lỗi AXI, địa chỉ giao dịch lúc lỗi được lưu vào `DMA_ERR_ADDR (0x118)` để debug.

---

## 10. Timing & Constraints

### 10.1 Timing quan trọng

| Path | Yêu cầu |
|---|---|
| `dma_start` → `M_AXI_ARVALID` | ≤ 2 cycles |
| `M_AXI_RVALID & RLAST` → `core_start` | ≤ 3 cycles |
| `core_done` → `M_AXI_AWVALID` | ≤ 2 cycles |

### 10.2 Ước tính tổng latency (Phase 1, 100 MHz)

| Giai đoạn | Cycles | Time @ 100 MHz |
|---|---|---|
| AXI Read (1 beat, assume 2-cycle latency) | 4 | 40 ns |
| Core feed + start | 2 | 20 ns |
| ASCON core (iterative) | 38 | 380 ns |
| AXI Write (3 beats, assume 2-cycle per beat) | 8 | 80 ns |
| Write response | 2 | 20 ns |
| **Tổng latency** | **~54 cycles** | **~540 ns** |

> Số chu kỳ AXI phụ thuộc vào interconnect và slave latency. Đây là ước tính optimistic.

### 10.3 Throughput (Phase 1)

```
Throughput = 64 bit / 540 ns ≈ 118 Mbps (1 block)
```

Multi-block pipelining (Phase 2) sẽ cải thiện đáng kể vì ASCON core latency chiếm phần lớn.

---

## 11. Ví dụ giao dịch

### 11.1 Waveform đọc AXI (1 beat, 64-bit)

```
         _   _   _   _   _   _   _   _
clk:   _| |_| |_| |_| |_| |_| |_| |_|

ARVALID: ____┌───┐___________________________
ARREADY: ________┌───┐_______________________
                 ^ handshake tại đây

RVALID:  _____________┌───┐________________
RREADY:  ┌───────────────────────────────────
RLAST:   _____________┌───┐________________
RDATA:   XXXXXXXXXXXX[plaintext 64-bit]XXXXXX
RRESP:   XXXXXXXXXXXX[00]XXXXXXXXXXXXXXXXXXX
```

### 11.2 Waveform ghi AXI (3 beats)

```
AWVALID: ____┌───┐___________________________
AWREADY: ________┌───┐_______________________

WVALID:  _____________┌───────────┐__________
WREADY:  ┌───────────────────────────────────
WDATA:   XXXX[ctext][tag_hi][tag_lo]XXXXXXXXX
WLAST:   _______________________┌───┐________

BVALID:  _____________________________┌───┐__
BREADY:  ┌───────────────────────────────────
BRESP:   XXXXXXXXXXXXXXXXXXXXXXXXXXXX[00]XXXX
```

### 11.3 Ví dụ C driver đầy đủ dùng DMA

```c
#include <stdint.h>
#include <string.h>  // memcpy

#define ASCON_BASE    0x20000000UL
#define REG(off)      (*((volatile uint32_t *)(ASCON_BASE + (off))))

// DMA registers
#define DMA_SRC_ADDR  REG(0x100)
#define DMA_DST_ADDR  REG(0x104)
#define DMA_BYTE_LEN  REG(0x108)
#define DMA_CTRL      REG(0x10C)
#define DMA_STATUS    REG(0x110)
#define DMA_BURST_LEN REG(0x114)
#define DMA_ERR_ADDR  REG(0x118)

// Core registers
#define ASCON_CTRL    REG(0x000)
#define ASCON_STATUS  REG(0x004)
#define ASCON_MODE    REG(0x008)
#define ASCON_KEY0    REG(0x010)
#define ASCON_KEY1    REG(0x014)
#define ASCON_KEY2    REG(0x018)
#define ASCON_KEY3    REG(0x01C)
#define ASCON_NONCE0  REG(0x020)
#define ASCON_NONCE1  REG(0x024)
#define ASCON_NONCE2  REG(0x028)
#define ASCON_NONCE3  REG(0x02C)

// Bit defs
#define CTRL_START      (1u << 0)
#define CTRL_SOFT_RST   (1u << 1)
#define CTRL_DMA_EN     (1u << 2)
#define STATUS_DMA_DONE (1u << 3)
#define STATUS_DMA_ERR  (1u << 5)
#define DMA_CTRL_START  (1u << 0)
#define DMA_CTRL_RST    (1u << 1)
#define DMA_STA_DONE    (1u << 1)
#define DMA_STA_RDERR   (1u << 4)
#define DMA_STA_WRERR   (1u << 5)

/*
 * ascon_encrypt_dma_full:
 *   Mã hóa 1 block 64-bit bằng ASCON-128, dùng DMA.
 *
 * Params:
 *   key[4]         - 128-bit key (big-endian, MSW first)
 *   nonce[4]       - 128-bit nonce
 *   src_phys       - địa chỉ vật lý của 8 bytes plaintext trong DDR
 *                    (phải align 8 bytes)
 *   dst_phys       - địa chỉ vật lý để ghi 24 bytes (ctext + tag)
 *                    (phải align 8 bytes)
 *
 * Returns: 0 nếu thành công, -1 nếu lỗi
 *
 * Layout tại dst_phys:
 *   +0x00: ctext[63:32]
 *   +0x04: ctext[31:0]
 *   +0x08: tag[127:96]
 *   +0x0C: tag[95:64]
 *   +0x10: tag[63:32]
 *   +0x14: tag[31:0]
 */
int ascon_encrypt_dma_full(
    const uint32_t key[4],
    const uint32_t nonce[4],
    uint32_t src_phys,
    uint32_t dst_phys)
{
    // 1. Reset toàn bộ
    ASCON_CTRL = CTRL_SOFT_RST;
    DMA_CTRL   = DMA_CTRL_RST;

    // 2. Kiểm tra alignment
    if ((src_phys & 0x7) || (dst_phys & 0x7)) {
        return -1;  // unaligned address
    }

    // 3. Ghi key và nonce (vẫn qua register)
    ASCON_KEY0   = key[0];   ASCON_KEY1 = key[1];
    ASCON_KEY2   = key[2];   ASCON_KEY3 = key[3];
    ASCON_NONCE0 = nonce[0]; ASCON_NONCE1 = nonce[1];
    ASCON_NONCE2 = nonce[2]; ASCON_NONCE3 = nonce[3];

    // 4. Cấu hình DMA
    DMA_SRC_ADDR  = src_phys;
    DMA_DST_ADDR  = dst_phys;
    DMA_BYTE_LEN  = 8;        // 1 block = 8 bytes
    DMA_BURST_LEN = 0;        // 1 beat

    // 5. Chế độ encrypt + enable DMA + start
    ASCON_MODE = 0;           // encrypt
    ASCON_CTRL = CTRL_DMA_EN | CTRL_START;

    // 6. Chờ DMA_DONE (polling; dùng interrupt nếu IRQ_EN được set)
    uint32_t status;
    do {
        status = ASCON_STATUS;
    } while (!(status & STATUS_DMA_DONE));

    // 7. Kiểm tra lỗi
    if (status & STATUS_DMA_ERR) {
        // Đọc địa chỉ gây lỗi nếu cần debug
        volatile uint32_t err_addr = DMA_ERR_ADDR;
        (void)err_addr;
        return -1;
    }

    return 0;
    // Caller đọc kết quả từ dst_phys
}
```

---

*Spec này mô tả DMA engine cho Phase 1 (1 block). Phase 2 sẽ bổ sung:*
- *Scatter-Gather descriptor chain*
- *Multi-block streaming với pipeline*
- *Prefetch buffer cho key/nonce*

*Xem thêm: `05A_SPEC_ASCON_CORE.md`, `06_SPEC_SOC_CONTROLLER.md`*
