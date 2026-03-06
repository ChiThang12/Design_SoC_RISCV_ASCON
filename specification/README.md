# RISC-V ASCON SoC — Tài Liệu Kiến Trúc & Lộ Trình Nâng Cấp

**Dự án:** RISC-V SoC tích hợp bộ tăng tốc mật mã ASCON  
**Tác giả:** ChiThang  
**Chuẩn bus:** AXI4 Full  
**Phiên bản hiện tại:** v2.0 (Có tích hợp Cache)  
**Phiên bản mục tiêu:** v3.0 (Phase 1 — Interconnect + ASCON)

---

## Mục đích tài liệu

Đây là tài liệu gốc (index) cho toàn bộ dự án SoC. Mọi AI agent và kỹ sư cần đọc file này trước, sau đó điều hướng sang file tương ứng với nhiệm vụ cụ thể.

> **Quy tắc quan trọng:** Không thiết kế, viết code, hay chỉnh sửa bất kỳ module nào nếu chưa đọc tài liệu spec tương ứng của module đó.

---

## Cấu trúc tài liệu

| File | Nội dung | Đọc khi nào |
|---|---|---|
| `README.md` *(file này)* | Index tổng quan, điều hướng | Đọc đầu tiên |
| `01_KIEN_TRUC_HIEN_TAI.md` | Trạng thái v2.0, sơ đồ kết nối, danh sách module, technical debt | Trước khi hiểu SoC hiện tại |
| `02_QUY_UONG_AXI4.md` | Convention tín hiệu AXI4, quy tắc thiết kế bắt buộc | Trước khi viết bất kỳ module AXI4 nào |
| `03_SO_DO_DIA_CHI.md` | Bản đồ địa chỉ v2.0 và v3.0, memory model cho linker | Trước khi thiết kế crossbar hoặc peripheral |
| `04_SPEC_AXI4_CROSSBAR.md` | Đặc tả đầy đủ module `axi4_crossbar` | Khi thiết kế / implement crossbar |
| `05_SPEC_ASCON.md` | Đặc tả đầy đủ module `ascon_core` + `ascon_axi_slave` | Khi thiết kế / implement ASCON |
| `06_SPEC_SOC_CONTROLLER.md` | Đặc tả đầy đủ module `soc_controller` | Khi thiết kế / implement SoC Controller |

---

## Tóm tắt nhanh — SoC hiện tại (v2.0)

```
CPU Core ──▶ ICache ──▶ (AXI4 point-to-point) ──▶ IMEM
CPU Core ──▶ DCache ──▶ (AXI4 point-to-point) ──▶ DMEM
```

- ✅ CPU thực thi lệnh đúng từ IMEM
- ✅ ICache 4KB hoạt động đúng
- ✅ DCache 8KB write-through hoạt động đúng
- ❌ Không có interconnect — không thể thêm peripheral
- ❌ Không có address decoding
- ❌ Chưa có ASCON accelerator

---

## Mục tiêu Phase 1 (v3.0)

```
CPU Core ──▶ ICache ──▶ M0 ─┐
                              ├──▶ AXI4 Crossbar ──▶ S0: IMEM
CPU Core ──▶ DCache ──▶ M1 ─┘                   ──▶ S1: DMEM
                                                  ──▶ S2: ASCON
                                                  ──▶ S3: SoC Controller
```

**Tiêu chí hoàn thành Phase 1:** CPU có thể ghi plaintext + key vào thanh ghi ASCON qua lệnh `store`, kích hoạt mã hóa, đọc kết quả ciphertext — toàn bộ thông qua DCache → AXI4 Crossbar → ASCON slave.

---

## Lộ trình tổng thể

```
Phase 1 (tài liệu này):
  axi4_crossbar  →  ascon_axi_slave  →  soc_controller  →  soc_top_v3

Phase 2 (tương lai):
  Timer  →  PLIC  →  UART  →  Boot ROM

Phase 3 (tương lai):
  DMA  →  GPIO  →  Debug Module (JTAG)
```

---

## Cấu trúc thư mục dự án

```
project_root/
├── docs/                        ← Thư mục tài liệu (file này)
│   ├── README.md
│   ├── 01_KIEN_TRUC_HIEN_TAI.md
│   ├── 02_QUY_UONG_AXI4.md
│   ├── 03_SO_DO_DIA_CHI.md
│   ├── 04_SPEC_AXI4_CROSSBAR.md
│   ├── 05_SPEC_ASCON.md
│   └── 06_SPEC_SOC_CONTROLLER.md
│
├── cpu_core.v                   ← Top module v2.0 (giữ nguyên)
├── soc_top_v3.v                 ← Top module v3.0 (cần tạo mới)
│
├── cpu/                         ← Không thay đổi từ v2.0
│   ├── riscv_cpu_core.v
│   ├── interface/
│   │   ├── icache/icache_top.v
│   │   └── dcache/dcache_top.v
│   └── memory_axi4full/
│       ├── inst_mem_axi_slave.v
│       └── data_mem_axi_slave.v
│
├── interconnect/
│   └── axi4_crossbar.v          ← Cần tạo mới (xem 04_SPEC_AXI4_CROSSBAR.md)
│
├── crypto/
│   └── ascon/
│       ├── ascon_core.v         ← Cần tạo mới (xem 05_SPEC_ASCON.md)
│       └── ascon_axi_slave.v   ← Cần tạo mới (xem 05_SPEC_ASCON.md)
│
└── soc_ctrl/
    └── soc_controller.v         ← Cần tạo mới (xem 06_SPEC_SOC_CONTROLLER.md)
```

---

*Tài liệu này được cập nhật lần cuối: Phase 1. Sẽ cập nhật khi bắt đầu Phase 2.*
