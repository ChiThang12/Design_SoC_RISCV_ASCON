# ASCON Accelerator trong SoC — Tài liệu Nghiên cứu

> Tài liệu này tổng hợp các kỹ thuật tích hợp ASCON accelerator vào SoC,
> tập trung vào các yếu tố hệ thống xung quanh ASCON core.
> Phần ASCON core sẽ được nghiên cứu và tài liệu hóa riêng.

---

## Mục lục

1. [Tổng quan kiến trúc SoC](#1-tổng-quan-kiến-trúc-soc)
2. [Near-Memory Computing](#2-near-memory-computing)
3. [Giao tiếp Bus — AXI Interface](#3-giao-tiếp-bus--axi-interface)
4. [DMA và Data Streaming](#4-dma-và-data-streaming)
5. [Quản lý bộ nhớ trong SoC](#5-quản-lý-bộ-nhớ-trong-soc)
6. [Pipeline ở cấp độ hệ thống](#6-pipeline-ở-cấp-độ-hệ-thống)
7. [Các thông số cần quan tâm khi thiết kế](#7-các-thông-số-cần-quan-tâm-khi-thiết-kế)
8. [Hướng nghiên cứu đề xuất](#8-hướng-nghiên-cứu-đề-xuất)
9. [Tài liệu tham khảo](#9-tài-liệu-tham-khảo)

---

## 1. Tổng quan kiến trúc SoC

### 1.1 Kiến trúc truyền thống (vấn đề hiện tại)

Trong hầu hết các SoC hiện tại, ASCON accelerator được tích hợp như một
IP block thông thường, giao tiếp với CPU và bộ nhớ qua bus trung tâm:

```
┌──────────┐     AXI Bus      ┌──────────────┐     AXI Bus      ┌──────────┐
│   DRAM   │ ───────────────► │ ASCON Core   │ ───────────────► │   DRAM   │
│          │ ◄─────────────── │              │ ◄─────────────── │          │
└──────────┘   ~50–100 ns     └──────────────┘   ~50–100 ns     └──────────┘
                                      ▲
                                      │ AXI-Lite (control)
                                 ┌────┴─────┐
                                 │ CPU Core │
                                 └──────────┘
```

**Vấn đề:**
- Bus latency chiếm ~30% tổng thời gian xử lý
- CPU phải chờ hoặc polling trạng thái accelerator
- Bandwidth bus bị chia sẻ với các IP khác trong SoC
- Không tận dụng được tính cục bộ của dữ liệu

### 1.2 Kiến trúc đề xuất (Near-Memory + Tối ưu hệ thống)

```
┌─────────────────────────────────────────────────────────────────┐
│                            SoC                                   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   On-chip SRAM Block                      │   │
│  │                                                           │   │
│  │   ┌─────────────────┐        ┌────────────────────────┐  │   │
│  │   │   Data Buffer   │        │    ASCON Core          │  │   │
│  │   │                 │        │    (nhúng sát SRAM)    │  │   │
│  │   │  - Plaintext    │◄──────►│                        │  │   │
│  │   │  - Key          │        │  [Xem tài liệu Core]   │  │   │
│  │   │  - Nonce        │        │                        │  │   │
│  │   │  - AD           │        │                        │  │   │
│  │   │  - Ciphertext   │        │                        │  │   │
│  │   │  - Tag          │        │                        │  │   │
│  │   └─────────────────┘        └────────────────────────┘  │   │
│  │             Local Data Path: ~2–5 ns (không qua bus)      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                          │                                       │
│              AXI Bus (chỉ cho: control + initial data load)      │
│                          │                                       │
│  ┌───────────────────────▼──────────────────────────────────┐   │
│  │                     CPU Core                              │   │
│  │  - Gửi lệnh encrypt/decrypt                              │   │
│  │  - Không cần chờ (non-blocking)                          │   │
│  │  - Nhận interrupt khi xong                               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   DMA Controller                           │  │
│  │  - Nạp data vào SRAM Buffer tự động                      │  │
│  │  - Không cần CPU can thiệp                               │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Near-Memory Computing

### 2.1 Khái niệm

Near-Memory Computing (NMC) là kỹ thuật đặt đơn vị tính toán **sát cạnh
bộ nhớ** thay vì để xa trên bus. Kỹ thuật này phổ biến trong các accelerator
hiệu năng cao (TPU, NPU) nhưng chưa được áp dụng cho ASCON.

### 2.2 Tại sao NMC phù hợp với ASCON?

ASCON có đặc điểm rất phù hợp với NMC:

| Đặc điểm ASCON | Lý do phù hợp NMC |
|---|---|
| State 320-bit cố định | Dễ dàng giữ state trong SRAM nhỏ |
| Key và Nonce ít thay đổi | Có thể cache sẵn gần core |
| Xử lý tuần tự từng block | Không cần bandwidth bus cao |
| Latency nhạy cảm (IoT real-time) | NMC giảm latency đáng kể |

### 2.3 Cấu trúc SRAM Buffer

```
SRAM Buffer Layout (đề xuất):

Offset   Size      Nội dung
0x000    16 bytes  Key (128-bit)
0x010    16 bytes  Nonce (128-bit)
0x020    8 bytes   IV (64-bit)
0x028    N bytes   Associated Data (tối đa N bytes, cấu hình được)
0x???    M bytes   Plaintext / Ciphertext
0x???    16 bytes  Tag (128-bit, output)
0x???    4 bytes   Status Register (busy/done/error)
0x???    4 bytes   Control Register (start/mode/reset)
```

### 2.4 Lợi ích định lượng

```
Trường hợp xử lý 1 block 64-bit (ASCON-128):

Kiến trúc truyền thống:
  Thời gian tính toán:    10 ns
  Bus latency (×2):      100 ns
  Tổng:                  110 ns

Kiến trúc NMC:
  Thời gian tính toán:    10 ns
  Local SRAM access:       5 ns
  Tổng:                   15 ns

Cải thiện latency: ~7.3× cho 1 block

Trường hợp streaming nhiều block:
  Truyền thống: (compute + bus) × N blocks
  NMC:          bus_load + compute × N blocks + bus_read
  Cải thiện throughput thực tế: ~2–3×
```

---

## 3. Giao tiếp Bus — AXI Interface

### 3.1 Phân loại giao tiếp AXI trong thiết kế này

Thiết kế sử dụng **2 loại AXI interface** với vai trò khác nhau:

```
┌─────────────────────────────────────────────────────┐
│                                                       │
│   AXI4-Lite (Control Plane)                          │
│   ├── CPU → ASCON: Ghi lệnh, cấu hình               │
│   ├── ASCON → CPU: Đọc trạng thái, kết quả          │
│   ├── Bandwidth thấp, latency không quan trọng       │
│   └── Register map đơn giản                         │
│                                                       │
│   AXI4 / AXI4-Stream (Data Plane)                   │
│   ├── DMA → SRAM Buffer: Nạp plaintext, key, AD     │
│   ├── SRAM Buffer → DMA: Xuất ciphertext, tag       │
│   ├── Bandwidth cao, burst transfer                  │
│   └── Chỉ dùng khi load/unload data                 │
│                                                       │
└─────────────────────────────────────────────────────┘
```

### 3.2 Register Map đề xuất (AXI4-Lite)

```
Địa chỉ    Tên              R/W   Mô tả
0x00       CTRL             W     Bit[0]: Start
                                  Bit[1]: Mode (0=Enc, 1=Dec)
                                  Bit[2]: Reset
                                  Bit[7:3]: Reserved

0x04       STATUS           R     Bit[0]: Busy
                                  Bit[1]: Done
                                  Bit[2]: Error (tag mismatch)
                                  Bit[7:3]: Reserved

0x08       AD_LEN           W     Độ dài Associated Data (bytes)
0x0C       PT_LEN           W     Độ dài Plaintext (bytes)
0x10       INT_EN           W     Bit[0]: Enable interrupt khi Done
0x14       KEY_ADDR         W     Địa chỉ Key trong SRAM Buffer
0x18       NONCE_ADDR       W     Địa chỉ Nonce trong SRAM Buffer
0x1C       AD_ADDR          W     Địa chỉ AD trong SRAM Buffer
0x20       PT_ADDR          W     Địa chỉ Plaintext trong SRAM Buffer
0x24       CT_ADDR          W     Địa chỉ Ciphertext output
0x28       TAG_ADDR         W     Địa chỉ Tag output
```

### 3.3 Quy trình giao tiếp (Encryption)

```
CPU                    DMA                 ASCON Accelerator
 │                      │                         │
 │── Config DMA ────────►│                         │
 │   (Key, Nonce, AD,   │                         │
 │    PT addresses)     │                         │
 │                      │── Transfer to ──────────►│
 │                      │   SRAM Buffer            │
 │                      │◄── Done ─────────────────│
 │── Write CTRL[Start] ─────────────────────────── ►│
 │                      │                         │
 │   (CPU tự do làm     │                  [Encrypt]
 │    việc khác)        │                         │
 │                      │                         │
 │◄── Interrupt ─────────────────────────────────── │
 │── Read STATUS ─────────────────────────────────► │
 │── Read CT/Tag via DMA ────────────────────────── │
 │                      │                         │
```

---

## 4. DMA và Data Streaming

### 4.1 Tại sao cần DMA?

Không có DMA:
```
CPU phải:
1. Đọc 1 word từ DRAM    (1 bus transaction)
2. Ghi 1 word vào Buffer (1 bus transaction)
3. Lặp lại cho tất cả data
→ CPU bị chiếm hoàn toàn trong thời gian này
```

Với DMA:
```
CPU chỉ cần:
1. Cấu hình DMA (source, destination, length)
2. Kích hoạt DMA
3. Làm việc khác trong khi DMA hoạt động
→ CPU rảnh để xử lý tác vụ khác
```

### 4.2 Cấu hình DMA cho ASCON

```
Thứ tự transfer được khuyến nghị:

Transfer 1: Key + Nonce + IV → SRAM[0x000:0x027]
            (Có thể làm 1 lần nếu key không đổi)

Transfer 2: Associated Data → SRAM[AD_ADDR]
            Length: AD_LEN bytes

Transfer 3: Plaintext → SRAM[PT_ADDR]
            Length: PT_LEN bytes

[Trigger ASCON start]

Transfer 4: SRAM[CT_ADDR] → Output buffer (DMA read)
Transfer 5: SRAM[TAG_ADDR:TAG_ADDR+16] → Tag output
```

### 4.3 Tối ưu: Key Caching

Trong nhiều ứng dụng IoT, **key không thay đổi** giữa các lần encrypt.
Có thể cache key trong SRAM Buffer và chỉ load lại khi key thay đổi:

```
Lần 1: DMA transfer Key + Nonce + AD + PT (full)
Lần 2: DMA transfer Nonce + AD + PT (bỏ qua Key)
Lần 3: DMA transfer Nonce + AD + PT
...

Tiết kiệm: 16 bytes × số lần encrypt = đáng kể với nhiều packet nhỏ
```

### 4.4 Streaming Mode (cho dữ liệu liên tục)

Với ứng dụng video/audio streaming, có thể thiết kế **streaming pipeline**:

```
                    Ping-Pong Buffer

Block N   → [Buffer A] → ASCON Core → [Output A] → gửi đi
Block N+1 → [Buffer B] ────────────────────────── (chờ)

Khi ASCON xong Block N:
Block N+1 → [Buffer A] → ASCON Core → [Output A]
Block N+2 → [Buffer B] ────────────── (chờ)

→ DMA nạp block N+1 trong khi ASCON xử lý block N
→ Không có thời gian chết giữa các block
```

---

## 5. Quản lý bộ nhớ trong SoC

### 5.1 Phân vùng bộ nhớ đề xuất

```
Memory Map (đề xuất cho SoC với ASCON):

0x0000_0000 ─ 0x0FFF_FFFF : DRAM (external) - 256 MB
0x1000_0000 ─ 0x1000_FFFF : On-chip SRAM - 64 KB
  0x1000_0000 ─ 0x1000_0FFF : ASCON Data Buffer - 4 KB
  0x1000_1000 ─ 0x1000_FFFF : General purpose SRAM - 60 KB
0x4000_0000 ─ 0x4000_00FF : ASCON Control Registers (AXI4-Lite)
0x4000_0100 ─ 0x4000_01FF : DMA Registers
```

### 5.2 Cache Coherency

Khi CPU và DMA cùng truy cập bộ nhớ, cần chú ý cache coherency:

```
Vấn đề:
CPU cache có thể giữ bản cũ của data
DMA đã ghi bản mới vào DRAM
→ ASCON đọc bản cũ → sai kết quả

Giải pháp:
Option 1: Non-cacheable region cho ASCON Buffer
          (đơn giản nhất, latency cao hơn)

Option 2: Cache flush trước khi trigger ASCON
          CPU: flush cache → DMA transfer → trigger ASCON

Option 3: Hardware cache coherency (nếu SoC hỗ trợ)
          (tự động, không cần software can thiệp)
```

---

## 6. Pipeline ở cấp độ hệ thống

### 6.1 Pipeline nhiều message

Khi SoC cần xử lý nhiều message liên tiếp (ví dụ: nhiều IoT packet):

```
Kiến trúc tuần tự (hiện tại):
Message 1: [Load] → [Encrypt] → [Unload]
Message 2:                               [Load] → [Encrypt] → [Unload]
Message 3:                                                              [Load] ...

Kiến trúc pipeline (đề xuất):
Message 1: [Load] → [Encrypt] → [Unload]
Message 2:          [Load]  → [Encrypt] → [Unload]
Message 3:                     [Load]  → [Encrypt] → [Unload]

Yêu cầu: Ping-pong buffer + DMA overlap
Kết quả: Throughput tăng ~2–3×
```

### 6.2 Interrupt vs Polling

```
Polling (đơn giản, không khuyến nghị):
while (STATUS_BUSY) { /* chờ */ }
→ CPU bị block hoàn toàn

Interrupt (khuyến nghị):
trigger_ascon();
// CPU làm việc khác
// ...
// ISR sẽ được gọi khi ASCON xong
void ascon_isr() {
    read_result();
    process_next_message();
}
→ CPU hiệu quả hơn, hệ thống responsive hơn
```

---

## 7. Các thông số cần quan tâm khi thiết kế

### 7.1 Thông số hiệu năng hệ thống

| Thông số | Mô tả | Đơn vị |
|---|---|---|
| System Throughput | Số bit mã hóa/giải mã trên giây ở cấp hệ thống | Mbps / Gbps |
| End-to-end Latency | Thời gian từ khi gửi lệnh đến khi có kết quả | ns / µs |
| Bus Utilization | Tỷ lệ sử dụng AXI bus cho ASCON | % |
| CPU Overhead | Số cycles CPU dùng để quản lý ASCON | cycles/message |
| Energy per Bit | Năng lượng tiêu thụ per bit mã hóa | pJ/bit |

### 7.2 Phân biệt Core Throughput và System Throughput

```
Core Throughput (lý thuyết):
= (Số bit/message) × Frequency / Số cycles/message
= Thông số mà các bài báo thường báo cáo

System Throughput (thực tế):
= Core Throughput × Efficiency Factor
  Efficiency Factor = Core_time / (Core_time + Bus_time + Overhead_time)
  Thường chỉ đạt 50–70% của Core Throughput

→ Mục tiêu của Near-Memory Computing là tăng Efficiency Factor lên >90%
```

### 7.3 Power Analysis

```
Tổng power của hệ thống ASCON:

P_total = P_core + P_SRAM + P_bus + P_DMA + P_CPU_overhead

Ước tính phân bổ:
P_core:          40–50% (permutation logic)
P_SRAM:          20–30% (đọc/ghi state, key, data)
P_bus:           15–25% (AXI transactions)
P_DMA:            5–10%
P_CPU_overhead:   5–10%

→ Giảm P_bus và P_SRAM = cơ hội lớn nhất ngoài core
```

---

## 8. Hướng nghiên cứu đề xuất

### 8.1 Tóm tắt 3 kỹ thuật SoC-level

```
┌────────────────────────────────────────────────────────────────┐
│                    Kiến trúc đề xuất                            │
│                                                                  │
│  Tầng 1 — System Level:                                         │
│  Near-Memory Computing                                          │
│  → Nhúng ASCON Core sát SRAM                                   │
│  → Loại bỏ bus latency trong quá trình encrypt                 │
│  → Cải thiện: ~7× latency, ~2–3× system throughput            │
│                                                                  │
│  Tầng 2 — Data Level:                                           │
│  DMA + Ping-Pong Buffer                                         │
│  → Overlap data transfer với computation                       │
│  → CPU không bị block                                           │
│  → Cải thiện: ~2× throughput khi streaming                     │
│                                                                  │
│  Tầng 3 — Interface Level:                                      │
│  AXI4-Lite Control + Interrupt                                  │
│  → Non-blocking CPU operation                                   │
│  → Tách biệt control plane và data plane                       │
│  → Cải thiện: CPU overhead giảm ~80%                          │
│                                                                  │
│  [ASCON Core — xem tài liệu riêng]                             │
│  → Pre-Permutation Merging (từ Bài 1)                         │
│  → Split-State Parallel (đề xuất mới)                         │
│  → Adaptive Unrolling (từ Bài 3)                              │
└────────────────────────────────────────────────────────────────┘
```

### 8.2 Roadmap thực hiện

```
Giai đoạn 1 — ASCON Core (ưu tiên hiện tại):
  □ Hiểu rõ kiến trúc permutation
  □ Implement baseline (loop folded)
  □ Implement Pre-Permutation Merging
  □ Đánh giá throughput và area baseline
  □ Thử nghiệm Split-State nếu feasible

Giai đoạn 2 — SoC Integration:
  □ Thiết kế SRAM Buffer layout
  □ Implement AXI4-Lite interface
  □ Kết nối ASCON Core với SRAM Buffer
  □ Kiểm tra Near-Memory vs Traditional

Giai đoạn 3 — DMA và Pipeline:
  □ Tích hợp DMA controller
  □ Implement Ping-Pong Buffer
  □ Đo system throughput thực tế
  □ So sánh với core throughput

Giai đoạn 4 — Đánh giá và tối ưu:
  □ Power analysis
  □ Area report đầy đủ
  □ So sánh với các bài báo liên quan
  □ Viết báo cáo
```

### 8.3 Điểm mới so với các bài báo đã đọc

| | Bài 1 | Bài 2 | Bài 3 | Đề xuất |
|---|---|---|---|---|
| Near-Memory Computing | ✗ | ✗ | ✗ | **✓** |
| DMA Pipeline | ✗ | ✓ (một phần) | ✗ | **✓** |
| Non-blocking CPU | ✗ | ✓ | ✗ | **✓** |
| Split-State Core | ✗ | ✗ | ✗ | **✓** |
| Pre-Perm Merging | ✓ | ✗ | ✗ | **✓** |
| Adaptive Unrolling | ✗ | ✗ | ✓ | **✓** |

---

## 9. Tài liệu tham khảo

### Bài báo đã đọc

```
[1] Koppuravuri et al., "A High Throughput ASCON Architecture for Secure
    Edge IoT Devices," VLSID 2024.
    → Nguồn: Kỹ thuật Pre-Permutation Merging, kiến trúc đơn module enc/dec

[2] Pham et al., "LiCryptor: High-Speed and Compact Multi-Grained
    Reconfigurable Accelerator for Lightweight Cryptography,"
    IEEE TCAS-I 2024.
    → Nguồn: Shared 64-bit ALU, DMA integration, CGRA approach

[3] Khan et al., "Securing the IoT ecosystem: ASIC-based hardware
    realization of Ascon lightweight cipher,"
    Int. J. Information Security 2024.
    → Nguồn: Loop unrolling analysis, trade-off area/throughput, ASIC results
```

### Tài liệu ASCON chính thức

```
[4] Dobraunig et al., "ASCON v1.2," NIST Submission 2021.
    https://csrc.nist.gov/projects/lightweight-cryptography

[5] NIST, "NIST Selects 'Lightweight Cryptography' Algorithms
    to Protect Small Devices," 2023.
    https://www.nist.gov/news-events/news/2023/02/nist-selects-lightweight-cryptography
```

### Tài liệu kỹ thuật liên quan

```
[6] ARM, "AMBA AXI and ACE Protocol Specification," ARM IHI0022E.
    → Tham khảo cho AXI interface design

[7] Xilinx/AMD, "AXI DMA v7.1 Product Guide," PG021.
    → Tham khảo cho DMA integration trên FPGA
```

---

*Tài liệu này được tạo trong quá trình nghiên cứu ASCON accelerator cho SoC.*
*Phần ASCON Core sẽ được tài liệu hóa riêng sau khi hoàn thành nghiên cứu.*
*Cập nhật lần cuối: tháng 3, 2026*
