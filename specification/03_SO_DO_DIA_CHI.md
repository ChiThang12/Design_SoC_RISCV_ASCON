# 03 — Bản Đồ Địa Chỉ (Address Map)

**Áp dụng cho:** `axi4_crossbar`, tất cả AXI4 slave module, linker script  
**Đọc file này khi:** Trước khi thiết kế crossbar, peripheral, hoặc viết phần mềm chạy trên SoC

---

## Mục lục

1. [Tình trạng hiện tại (v2.0)](#1-tình-trạng-hiện-tại-v20)
2. [Bản đồ địa chỉ mục tiêu (v3.0 — Phase 1)](#2-bản-đồ-địa-chỉ-mục-tiêu-v30--phase-1)
3. [Dự phòng cho Phase 2](#3-dự-phòng-cho-phase-2)
4. [Memory model cho linker script](#4-memory-model-cho-linker-script)
5. [Quy tắc phân vùng địa chỉ](#5-quy-tắc-phân-vùng-địa-chỉ)
6. [Hành vi khi truy cập địa chỉ không hợp lệ](#6-hành-vi-khi-truy-cập-địa-chỉ-không-hợp-lệ)

---

## 1. Tình trạng hiện tại (v2.0)

**Hiện tại không có bản đồ địa chỉ.** DCache gửi địa chỉ thẳng tới DMEM, ICache gửi thẳng tới IMEM — không có decoding. CPU không thể truy cập bất kỳ vùng nào ngoài những gì IMEM và DMEM hỗ trợ nội bộ.

Đây là vấn đề cốt lõi mà Phase 1 phải giải quyết.

---

## 2. Bản đồ địa chỉ mục tiêu (v3.0 — Phase 1)

| Vùng | Địa chỉ bắt đầu | Địa chỉ kết thúc | Kích thước | Module Slave | Truy cập bởi |
|---|---|---|---|---|---|
| Instruction Memory | `0x0000_0000` | `0x0000_FFFF` | 64KB | `inst_mem_axi_slave` | ICache (M0) + DCache (M1) |
| Data Memory | `0x1000_0000` | `0x1000_FFFF` | 64KB | `data_mem_axi4_slave` | DCache (M1) |
| ASCON Accelerator | `0x2000_0000` | `0x2000_0FFF` | 4KB | `ascon_axi_slave` | DCache (M1) |
| SoC Controller | `0x3000_0000` | `0x3000_0FFF` | 4KB | `soc_controller` | DCache (M1) |
| *(Dự phòng Phase 2)* | `0x4000_0000` | `0x4FFF_FFFF` | 256MB | Timer, UART, PLIC | DCache (M1) |
| *(Không ánh xạ)* | Tất cả còn lại | — | — | — | Trả về DECERR |

### Sơ đồ phân vùng địa chỉ

```
0xFFFF_FFFF ┬─────────────────────────┐
            │                         │
            │      Không ánh xạ       │  → DECERR
            │                         │
0x5000_0000 ┼─────────────────────────┤
            │   Dự phòng Phase 2      │  (256MB)
            │   Timer / UART / PLIC   │
0x4000_0000 ┼─────────────────────────┤
            │                         │
            │      Không ánh xạ       │  → DECERR
            │                         │
0x3000_1000 ┼─────────────────────────┤
            │    SoC Controller       │  (4KB)  slave S3
0x3000_0000 ┼─────────────────────────┤
            │                         │
            │      Không ánh xạ       │  → DECERR
            │                         │
0x2000_1000 ┼─────────────────────────┤
            │   ASCON Accelerator     │  (4KB)  slave S2
0x2000_0000 ┼─────────────────────────┤
            │                         │
            │      Không ánh xạ       │  → DECERR
            │                         │
0x1001_0000 ┼─────────────────────────┤
            │      Data Memory        │  (64KB) slave S1
0x1000_0000 ┼─────────────────────────┤
            │                         │
            │      Không ánh xạ       │  → DECERR
            │                         │
0x0001_0000 ┼─────────────────────────┤
            │  Instruction Memory     │  (64KB) slave S0
0x0000_0000 ┴─────────────────────────┘
```

---

## 3. Dự phòng cho Phase 2

Vùng `0x4000_0000 – 0x4FFF_FFFF` (256MB) được dành cho các peripheral Phase 2. Phân bổ dự kiến:

| Peripheral | Địa chỉ dự kiến | Kích thước |
|---|---|---|
| Timer 0 | `0x4000_0000` | 4KB |
| Timer 1 | `0x4000_1000` | 4KB |
| UART 0 | `0x4001_0000` | 4KB |
| PLIC | `0x4010_0000` | 64KB |
| GPIO | `0x4020_0000` | 4KB |
| Boot ROM | Ghi đè `0x0000_0000` khi boot | 4KB |

> **Lưu ý:** Các địa chỉ Phase 2 là dự kiến, có thể thay đổi. Không hardcode vào Phase 1.

---

## 4. Memory model cho linker script

Phần mềm chạy trên SoC phải dùng linker script với phân vùng sau:

```ld
/* Linker script cho RISC-V ASCON SoC v3.0 */
MEMORY {
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K
}

SECTIONS {
    .text   : { *(.text*)   } > IMEM
    .rodata : { *(.rodata*) } > IMEM

    .data   : { *(.data*)   } > DMEM
    .bss    : { *(.bss*)    } > DMEM

    /* Stack — cuối DMEM */
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
```

### Địa chỉ peripheral trong code C

```c
/* Định nghĩa địa chỉ cơ sở cho peripheral */
#define ASCON_BASE      0x20000000UL
#define SOC_CTRL_BASE   0x30000000UL

/* Macro truy cập thanh ghi */
#define REG32(base, offset) (*((volatile uint32_t *)((base) + (offset))))

/* Truy cập thanh ghi ASCON */
#define ASCON_CTRL      REG32(ASCON_BASE, 0x00)
#define ASCON_STATUS    REG32(ASCON_BASE, 0x04)
#define ASCON_KEY_0     REG32(ASCON_BASE, 0x10)
/* ... xem 05_SPEC_ASCON.md để biết đầy đủ register map */

/* Truy cập thanh ghi SoC Controller */
#define SOC_CHIP_ID     REG32(SOC_CTRL_BASE, 0x00)
#define SOC_VERSION     REG32(SOC_CTRL_BASE, 0x04)
```

---

## 5. Quy tắc phân vùng địa chỉ

1. **Kích thước tối thiểu:** Mỗi slave được cấp phát tối thiểu 4KB (12-bit địa chỉ nội bộ)
2. **Căn chỉnh:** Địa chỉ base của mỗi slave phải căn chỉnh theo kích thước của nó (4KB slave base phải chia hết cho 4KB)
3. **Không chồng lấp:** Không có hai slave nào có vùng địa chỉ chồng lên nhau
4. **Crossbar decoding:** AXI4 Crossbar sử dụng các bit cao của địa chỉ để phân vùng:
   - Bit [31:28] = `0x0` → IMEM (S0)
   - Bit [31:28] = `0x1` → DMEM (S1)
   - Bit [31:28] = `0x2` → ASCON (S2)
   - Bit [31:28] = `0x3` → SoC Controller (S3)
   - Bit [31:28] = `0x4` → Dự phòng Phase 2
   - Tất cả còn lại → DECERR

---

## 6. Hành vi khi truy cập địa chỉ không hợp lệ

Khi CPU truy cập địa chỉ không được ánh xạ, AXI4 Crossbar phải:

**Đối với giao dịch đọc (Read):**
- Phát `RVALID = 1` với `RDATA = 32'hDEAD_BEEF` (giá trị debug dễ nhận biết)
- Phát `RRESP = 2'b11` (DECERR)
- Phát `RLAST = 1`

**Đối với giao dịch ghi (Write):**
- Chấp nhận dữ liệu ghi (consume toàn bộ burst)
- Phát `BVALID = 1` với `BRESP = 2'b11` (DECERR)
- Dữ liệu ghi bị bỏ qua (không thực sự ghi đi đâu)

**Mục đích:** CPU phải nhận được phản hồi hợp lệ (không bị treo bus) ngay cả khi truy cập địa chỉ sai. Phần mềm có thể phát hiện lỗi bằng cách đọc `RRESP` nếu CPU hỗ trợ.

---

*Tiếp theo: Xem `04_SPEC_AXI4_CROSSBAR.md` để biết đặc tả chi tiết module crossbar.*
