# RISC-V SoC Project – Directory Structure Overview

## Tổng quan

Repository này chứa các phiên bản khác nhau của **RISC-V SoC** trong quá trình phát triển, từ kiến trúc **CPU + AXI interface trực tiếp** cho đến kiến trúc **CPU + Cache (ICache/DCache) + AXI4 Full + Memory** hiện tại.

⚠️ **Lưu ý quan trọng**: Một số thư mục/module trong repo là **phiên bản cũ (legacy / outdated)**, được giữ lại để tham khảo kiến trúc và debug. Kiến trúc đang được hướng tới hiện nay là **CPU + Cache + AXI4 Full + Memory**.

---

## Cấu trúc thư mục

```
CPU/
├── core/
├── dma/
└── interface/
│     ├── dcache/
│     ├── icache/
│     ├── tb/
│     ├── axi4_lite_master_if.v
│     ├── dmem_access_unit.v
│     └── imem_access_unit.v
│
├── memory/
│   └──
├── memory_axi4full/
│     ├── data_mem_axi_slave.v
│     ├── data_mem_burst.v
│     ├── data_mem.v
│     ├── inst_mem_axi_slave.v
│     ├── inst_mem.v
│     ├── MEMORY_UPGRADE_ANALYSIS.md
│     ├── program.hex
│     ├── tb_memory_axi_slaves.v
│     ├── tb_memory_axi_slaves.vcd
│     └── tb_memory_axi_slaves.vvp
│
├── riscv5stagedemo/           (RISCV architecture not SoC)
│
├── riscv_core_axi.v          (LEGACY)
├── riscv_cpu_core.v          (UPDATED)
├── riscv_cpu_core.vcd
├── riscv_soc_top.v
├── tb_riscv_cpu_core.v
├── tb_riscv_soc_top.v
├── FINAL_INTEGRATION_GUIDE.md
├── DEBUG_25012026.md
├── README.md
└── run.sh
```

---

## Chi tiết từng khối

### 1️⃣ CPU/

Chứa các khối logic liên quan đến CPU và các interface phụ trợ.

#### `CPU/core/`

* Core RISC-V (pipeline, control, datapath, CSR, v.v.)
* Đây là **RISC-V core chuẩn**, không phụ thuộc bus cụ thể.

#### `CPU/dma/`

* DMA engine (đang phát triển / mở rộng sau).
* Dự kiến sử dụng AXI4 Full cho burst transfer.

#### `CPU/interface/` ⚠️ (LEGACY / ĐANG THAY THẾ)

* Phiên bản cũ: CPU kết nối trực tiếp tới memory thông qua **AXI4-Lite interface**.
* **Đã lỗi thời** sau khi chuyển sang kiến trúc cache-based.

Bao gồm:

* `axi4_lite_master_if.v` – AXI4-Lite master
* `imem_access_unit.v`, `dmem_access_unit.v` – access unit không có cache
* `icache/`, `dcache/` – thư mục cache (đang là nền tảng cho kiến trúc mới)

📌 **Trạng thái**:

* Interface AXI-Lite: ❌ deprecated
* Cache logic: ✅ đang dùng cho kiến trúc mới

---

### 2️⃣ memory_axi4full/ ✅ (ACTIVE)

Khối memory **chuẩn AXI4 Full**, hỗ trợ burst – dùng cho ICache và DCache.

#### Instruction Memory

* `inst_mem.v` – instruction memory (read-only, burst-capable)
* `inst_mem_axi_slave.v` – AXI4 Full slave, hỗ trợ burst read

👉 **Sẵn sàng cho ICache – không cần chỉnh sửa**

#### Data Memory

* `data_mem.v` – data memory cơ bản
* `data_mem_burst.v` – data memory hỗ trợ burst (upgrade từ data_mem.v)
* `data_mem_axi_slave.v` – AXI4 Full slave cho DCache

👉 **Đã upgrade từ AXI4-Lite → AXI4 Full** để hỗ trợ DCache

#### Testbench & tài liệu

* `tb_memory_axi_slaves.v` – test AXI memory
* `MEMORY_UPGRADE_ANALYSIS.md` – phân tích upgrade AXI4-Lite → AXI4 Full

---

### 3️⃣ riscv_core_axi.v ❌ (LEGACY)

* Phiên bản cũ: **RISC-V core + AXI interface trực tiếp**
* Không có cache
* Dùng AXI-Lite / AXI đơn giản

📌 **Trạng thái**:

* ❌ Đã lỗi thời
* Chỉ giữ lại để tham khảo kiến trúc ban đầu

---

### 4️⃣ riscv_cpu_core.v ✅ (CURRENT)

👉 **Phiên bản hiện tại đang được sử dụng**

Kiến trúc:

```
RISC-V Core
   ↓
ICache / DCache
   ↓
AXI4 Full
   ↓
Memory subsystem
```

Đặc điểm:

* RISC-V core chuẩn
* Có ICache + DCache
* Kết nối memory qua **AXI4 Full (burst)**
* Phù hợp cho nghiên cứu SoC và benchmark hiệu năng

📌 Đây là **hướng phát triển chính của project**.

---

### 5️⃣ riscv_soc_top.v

* Top-level SoC
* Kết nối CPU, cache, memory, DMA (nếu có)
* Dùng cho mô phỏng toàn hệ thống

---

### 6️⃣ Testbench & Debug

* `tb_riscv_cpu_core.v` – test CPU core
* `tb_riscv_soc_top.v` – test toàn SoC
* `.vcd`, `.vvp` – waveform & output mô phỏng
* `DEBUG_25012026.md` – ghi chú debug

---

## Tóm tắt trạng thái kiến trúc

| Thành phần               | Trạng thái   | Ghi chú            |
| ------------------------ | ------------ | ------------------ |
| riscv_core_axi           | ❌ Legacy     | Không cache        |
| CPU/interface (AXI-Lite) | ❌ Deprecated | Đã thay bằng cache |
| ICache / DCache          | ✅ Active     | Kiến trúc mới      |
| Memory AXI4 Full         | ✅ Active     | Burst-capable      |
| riscv_cpu_core           | ✅ Main       | CPU + Cache + AXI4 |

---

## Kết luận

* Repo chứa **nhiều thế hệ kiến trúc** của cùng một SoC RISC-V
* Kiến trúc hiện tại:

> **RISC-V Core + Cache (ICache/DCache) + AXI4 Full + Memory**

* Các module AXI-Lite cũ được giữ lại **chỉ để tham khảo**, không dùng trong flow chính.

📌 Khi phát triển tiếp, nên **tập trung vào**:

* `riscv_cpu_core.v`
* `CPU/core/`
* `CPU/interface/{icache,dcache}`
* `memory/memory_axi4full/`
