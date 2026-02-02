# Design_SoC_RISCV_ASCON

# Architecture
<img width="1433" height="848" alt="image" src="https://github.com/user-attachments/assets/d733e4b3-514e-47d7-b8be-5655e80607b8" />
# RISC-V SoC with Cache & ASCON Accelerator – Architecture README

## 1. Tổng quan kiến trúc

Thiết kế này là một **RISC-V SoC hiện đại**, tập trung vào:

* RISC-V core pipeline 5 stage (RV32IM – custom)
* Kiến trúc **Harvard** với **ICache & DCache**
* Kết nối memory thông qua **AXI4 Full (burst-capable)**
* Tích hợp **ASCON Crypto Accelerator** dùng cho mã hóa/xác thực
* Giao tiếp điều khiển qua **AXI4-Lite**, dữ liệu lớn qua **DMA (AXI Master)**

Kiến trúc được thiết kế theo hướng **scalable – cache-aware – accelerator-friendly**, phù hợp cho SoC nghiên cứu hoặc embedded security SoC.

---

## 2. Sơ đồ khối tổng thể

Luồng chính của hệ thống:

```
            +----------------------+
            |   System Control     |
            | PLL / Clock / Reset  |
            +----------+-----------+
                       |
        +--------------v--------------+
        |        Interrupt Ctrl        |
        |        (CLINT / PLIC)        |
        +--------------+--------------+
                       |

+----------------------------------------------------+
|                  RISC-V Core                        |
|            RV32IM – 5-stage Pipeline                |
|                                                    |
|  IF  →  ID  →  EX  →  MEM  →  WB                     |
|                                                    |
|  I-PORT (AXI4)              D-PORT (AXI4)           |
|  ITLB → ICache              DTLB → DCache           |
|                                                    |
+----------------------+-----------------------------+
                       |
                AXI Interconnect
                       |
      +----------------+------------------+
      |                                   |
+-----v------+                    +-------v--------+
| Instr Mem |                    |   Data Mem       |
| ROM/Flash |                    |   SRAM           |
| 128 KB    |                    |   128 KB         |
+------------+                    +-----------------+

                       |
                       |
          +------------v-------------------+
          |     ASCON Crypto Accelerator    |
          |                                |
          |  AXI4-Lite (Control Registers) |
          |  DMA (AXI Master – Data Path)  |
          +--------------------------------+
```

---

## 3. RISC-V Core Subsystem

### 3.1 Core Pipeline

* ISA: **RV32IM (Custom)**
* Pipeline: **5 stages**

  * IF (Fetch)
  * ID (Decode / Register File / ImmGen)
  * EX (ALU, Branch, Multiply)
  * MEM (Load/Store)
  * WB (Write Back)

Core được thiết kế **bus-agnostic**, mọi truy cập bộ nhớ đều đi qua cache + AXI.

---

### 3.2 Instruction Path (I-PORT)

```
PC → ITLB → ICache → AXI4 Read → Instruction Memory
```

* ICache hỗ trợ **burst read** (cache line fill)
* AXI4 Full: ARLEN, ARSIZE, ARBURST, RLAST
* Instruction Memory:

  * ROM / Flash
  * Read-only
  * Burst-capable

📌 Mục tiêu: giảm instruction fetch latency và tối ưu IPC.

---

### 3.3 Data Path (D-PORT)

```
Load/Store → DTLB → DCache → AXI4 Read/Write → Data Memory
```

* DCache hỗ trợ:

  * Burst read (cache line fill)
  * Single write / burst write (tùy policy)
* AXI4 Full cho data path
* Data Memory:

  * SRAM
  * Read / Write
  * Burst-capable

📌 Đây là điểm khác biệt chính so với kiến trúc AXI4-Lite cũ.

---

## 4. AXI Interconnect

* Chuẩn bus chính: **AXI4 Full**
* Kết nối:

  * ICache → Instruction Memory
  * DCache → Data Memory
  * CPU / DMA → Accelerator

AXI được dùng để:

* Hỗ trợ **burst transaction**
* Cho phép **DMA & accelerator hoạt động song song với CPU**

---

## 5. ASCON Crypto Accelerator Subsystem

### 5.1 Tổng quan

ASCON accelerator được thiết kế theo mô hình **Control Plane + Data Plane**:

* Control: AXI4-Lite
* Data: DMA (AXI4 Master)

---

### 5.2 Control Registers (AXI4-Lite Slave)

Dùng cho CPU cấu hình accelerator:

* Config
* Status
* Key / Nonce
* Mode (Encrypt / Decrypt / Hash)
* Command
* Message length

📌 AXI4-Lite **chỉ dùng cho control**, không truyền dữ liệu lớn.

---

### 5.3 DMA Engine (AXI4 Master)

```
Memory → DMA Read Channel  → Input FIFO
Output FIFO → DMA Write Channel → Memory
```

* Hỗ trợ burst transfer
* Giảm tải CPU
* Cho phép xử lý dữ liệu lớn hiệu quả

---

### 5.4 ASCON Core

* Thành phần chính:

  * Key Register
  * State Memory
  * Permutation Engine

* Controller:

  * FSM điều phối các pha ASCON

* Buffering:

  * Input FIFO
  * Data Buffer
  * Output FIFO

📌 Thiết kế fully decoupled giữa compute và memory.

---

## 6. System Control Subsystem

Bao gồm:

* PLL / Clock Generator
* Clock Gating & Power Management
* Reset Manager

Vai trò:

* Quản lý clock domain
* Reset toàn hệ thống
* Tối ưu power

---

## 7. Interrupt Subsystem

* CLINT:

  * Timer interrupt
  * Software interrupt

* PLIC:

  * External interrupts
  * Accelerator interrupt (ASCON done)

CPU nhận interrupt để đồng bộ với accelerator và system events.

---

## 8. Đặc điểm kiến trúc nổi bật

* Cache-aware design (ICache + DCache)
* AXI4 Full cho data-intensive path
* AXI4-Lite chỉ dùng cho control
* Accelerator tích hợp đúng chuẩn SoC
* DMA giúp accelerator hoạt động song song CPU

---

## 9. So sánh với kiến trúc cũ

| Tiêu chí      | Kiến trúc cũ | Kiến trúc hiện tại |
| ------------- | ------------ | ------------------ |
| Memory access | AXI4-Lite    | AXI4 Full + Burst  |
| Cache         | Không / giả  | ICache + DCache    |
| Accelerator   | CPU-driven   | DMA-driven         |
| Performance   | Thấp         | Cao                |
| Scalability   | Kém          | Tốt                |

---

## 10. Kết luận

Kiến trúc này là một **SoC RISC-V hoàn chỉnh và đúng chuẩn**, phù hợp cho:

* Nghiên cứu kiến trúc SoC
* Cache & memory system
* Hardware accelerator integration
* Security-focused embedded systems

👉 Đây là nền tảng tốt để mở rộng thêm:

* MMU đầy đủ
* Multi-core
* Advanced power management
* Các accelerator khác
