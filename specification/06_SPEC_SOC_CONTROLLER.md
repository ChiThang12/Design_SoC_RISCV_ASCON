# 06 — Đặc Tả Module: `soc_controller`

**Tên module:** `soc_controller`  
**File đầu ra:** `soc_ctrl/soc_controller.v`  
**Ưu tiên:** Trung bình — cần cho bring-up và debug nhưng không blocking ASCON  
**Đọc trước:** `02_QUY_UONG_AXI4.md`, `03_SO_DO_DIA_CHI.md`

---

## Mục lục

1. [Vai trò và lý do cần thiết](#1-vai-trò-và-lý-do-cần-thiết)
2. [Register Map](#2-register-map)
3. [Danh sách Port](#3-danh-sách-port)
4. [Verilog Parameters](#4-verilog-parameters)
5. [Yêu cầu hành vi](#5-yêu-cầu-hành-vi)
6. [Ví dụ code C sử dụng SoC Controller](#6-ví-dụ-code-c-sử-dụng-soc-controller)
7. [Mở rộng trong tương lai (Phase 2)](#7-mở-rộng-trong-tương-lai-phase-2)

---

## 1. Vai trò và lý do cần thiết

SoC Controller là block đơn giản nhất trong Phase 1 nhưng không thể thiếu vì:

- **Chip ID:** Phần mềm cần đọc để xác nhận đang chạy đúng trên chip này (không phải mô phỏng hay chip khác)
- **Version register:** Giúp debug khi có nhiều phiên bản SoC khác nhau
- **Feature flags:** Phần mềm có thể tự phát hiện tính năng thay vì hardcode
- **Scratch registers:** Dùng để kiểm tra bus đang hoạt động đúng (write rồi read back)

Trong thực tế sản xuất, đây thường là thanh ghi đầu tiên phần mềm đọc khi boot để xác nhận phần cứng hoạt động.

---

## 2. Register Map

**Địa chỉ base:** `0x3000_0000` (xem `03_SO_DO_DIA_CHI.md`)

| Offset | Tên | Quyền | Giá trị Reset | Mô tả |
|---|---|---|---|---|
| `0x00` | `CHIP_ID` | RO | `0xA5C0_0001` | Định danh chip cố định |
| `0x04` | `SOC_VERSION` | RO | `0x0003_0000` | Phiên bản: Major.Minor.Patch = 3.0.0 |
| `0x08` | `BUILD_DATE` | RO | (tham số) | Ngày build mã hóa BCD: YYYYMMDD |
| `0x0C` | `FEATURE_FLAGS` | RO | `0x0000_0007` | Bit flags tính năng (xem bên dưới) |
| `0x10` | `SCRATCH_0` | R/W | `0x0000_0000` | Thanh ghi scratch đa năng 0 |
| `0x14` | `SCRATCH_1` | R/W | `0x0000_0000` | Thanh ghi scratch đa năng 1 |
| `0x18` | *(dự phòng)* | — | `0x0` | Không sử dụng, đọc về 0 |
| `0x1C` | *(dự phòng)* | — | `0x0` | Không sử dụng, đọc về 0 |

### Chi tiết FEATURE_FLAGS (0x0C)

| Bit | Tên | Giá trị trong Phase 1 | Mô tả |
|---|---|---|---|
| [0] | `ICACHE_PRESENT` | 1 | ICache 4KB có mặt |
| [1] | `DCACHE_PRESENT` | 1 | DCache 8KB có mặt |
| [2] | `ASCON_PRESENT` | 1 | ASCON accelerator có mặt |
| [3] | `TIMER_PRESENT` | 0 | Timer chưa có (Phase 2) |
| [4] | `UART_PRESENT` | 0 | UART chưa có (Phase 2) |
| [5] | `PLIC_PRESENT` | 0 | PLIC chưa có (Phase 2) |
| [31:6] | *(dự phòng)* | 0 | — |

### Chi tiết SOC_VERSION (0x04)

Mã hóa theo định dạng Major.Minor.Patch:

| Bit | Nội dung | Giá trị Phase 1 |
|---|---|---|
| [31:24] | Major version | `0x03` (Phase 1 = version 3) |
| [23:16] | Minor version | `0x00` |
| [15:8] | Patch | `0x00` |
| [7:0] | Build variant | `0x00` |

**Ví dụ đọc version trong C:**
```c
uint32_t ver = SOC_VERSION;
uint8_t major = (ver >> 24) & 0xFF;  // = 3
uint8_t minor = (ver >> 16) & 0xFF;  // = 0
```

---

## 3. Danh sách Port

```verilog
module soc_controller #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter ID_WIDTH    = 4,
    parameter BUILD_DATE  = 32'h2025_0101  // YYYYMMDD dạng BCD, override khi build
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI4 Lite Slave Interface
    // Read Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [7:0]              S_AXI_ARLEN,    // bỏ qua
    input  wire [2:0]              S_AXI_ARSIZE,   // bỏ qua
    input  wire [1:0]              S_AXI_ARBURST,  // bỏ qua
    input  wire [2:0]              S_AXI_ARPROT,
    input  wire                    S_AXI_ARVALID,
    output reg                     S_AXI_ARREADY,

    // Read Data Channel
    output reg  [ID_WIDTH-1:0]     S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output reg  [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,    // luôn = 1
    output reg                     S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [7:0]              S_AXI_AWLEN,    // bỏ qua
    input  wire [2:0]              S_AXI_AWSIZE,   // bỏ qua
    input  wire [1:0]              S_AXI_AWBURST,  // bỏ qua
    input  wire [2:0]              S_AXI_AWPROT,
    input  wire                    S_AXI_AWVALID,
    output reg                     S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WLAST,    // bỏ qua
    input  wire                    S_AXI_WVALID,
    output reg                     S_AXI_WREADY,

    // Write Response Channel
    output reg  [ID_WIDTH-1:0]     S_AXI_BID,
    output reg  [1:0]              S_AXI_BRESP,
    output reg                     S_AXI_BVALID,
    input  wire                    S_AXI_BREADY
);
```

---

## 4. Verilog Parameters

```verilog
// Các tham số build-time — override bằng defparam hoặc khi instantiate
parameter DATA_WIDTH  = 32,
parameter ADDR_WIDTH  = 32,
parameter ID_WIDTH    = 4,

// Giá trị mặc định — override theo ngày build thực tế
parameter [31:0] BUILD_DATE = 32'h2025_0101,

// Cấu hình tính năng — set khi instantiate trong soc_top_v3.v
parameter ICACHE_EN = 1'b1,
parameter DCACHE_EN = 1'b1,
parameter ASCON_EN  = 1'b1,
parameter TIMER_EN  = 1'b0,
parameter UART_EN   = 1'b0,
parameter PLIC_EN   = 1'b0
```

**Cách instantiate trong `soc_top_v3.v`:**
```verilog
soc_controller #(
    .BUILD_DATE  (32'h2025_0115),  // override ngày build
    .ICACHE_EN   (1'b1),
    .DCACHE_EN   (1'b1),
    .ASCON_EN    (1'b1)
) u_soc_ctrl (
    .clk    (clk),
    .rst_n  (rst_n),
    .S_AXI_ARADDR  (s3_araddr),
    // ... kết nối từ crossbar slave port S3
);
```

---

## 5. Yêu cầu hành vi

### 5.1 Ghi vào thanh ghi read-only

Khi phần mềm ghi vào `CHIP_ID`, `SOC_VERSION`, `BUILD_DATE`, hoặc `FEATURE_FLAGS`:
- Chấp nhận giao dịch AXI4 bình thường
- Trả về `BRESP = 2'b00` (OKAY)
- **Bỏ qua dữ liệu** — giá trị thanh ghi không thay đổi

### 5.2 Đọc thanh ghi dự phòng

Đọc offset `0x18`, `0x1C`, hoặc bất kỳ offset nào từ `0x20` trở lên (trong vùng 4KB):
- Trả về `RDATA = 32'h0000_0000`
- Trả về `RRESP = 2'b00` (OKAY)

### 5.3 Scratch registers

`SCRATCH_0` và `SCRATCH_1` là read-write thực sự:
- Ghi giá trị nào thì đọc về giá trị đó
- Reset về `0x0000_0000` khi `rst_n` assert
- Dùng cho mục đích test bus: ghi pattern, đọc lại, so sánh

### 5.4 Latency

Module này nên trả lời trong **1–2 chu kỳ clock** (không có logic phức tạp). Đây là peripheral đơn giản nhất trong SoC.

### 5.5 AXI4 Handshake

Module phải tuân thủ đầy đủ quy tắc AXI4 handshake trong `02_QUY_UONG_AXI4.md`. Cụ thể:
- `RVALID` chỉ phát sau khi `ARVALID` đã được nhận
- `BVALID` chỉ phát sau khi nhận cả `AWVALID` và `WVALID`
- Giữ nguyên `RDATA` và `RRESP` cho đến khi `RREADY = 1`

---

## 6. Ví dụ code C sử dụng SoC Controller

```c
#include <stdint.h>

#define SOC_CTRL_BASE   0x30000000UL
#define SOC_REG(off)    (*((volatile uint32_t *)(SOC_CTRL_BASE + (off))))

#define SOC_CHIP_ID     SOC_REG(0x00)
#define SOC_VERSION     SOC_REG(0x04)
#define SOC_BUILD_DATE  SOC_REG(0x08)
#define SOC_FEATURES    SOC_REG(0x0C)
#define SOC_SCRATCH0    SOC_REG(0x10)
#define SOC_SCRATCH1    SOC_REG(0x14)

/* Hàm kiểm tra chip khi boot */
int soc_init(void) {
    // Kiểm tra chip ID
    if (SOC_CHIP_ID != 0xA5C00001) {
        return -1;  // Không phải chip đúng
    }

    // Kiểm tra bus hoạt động bằng scratch test
    SOC_SCRATCH0 = 0xDEADBEEF;
    SOC_SCRATCH1 = 0xCAFEBABE;
    if (SOC_SCRATCH0 != 0xDEADBEEF) return -2;
    if (SOC_SCRATCH1 != 0xCAFEBABE) return -3;

    // Kiểm tra ASCON có mặt không
    if (!(SOC_FEATURES & (1 << 2))) {
        return -4;  // ASCON không có
    }

    return 0;  // OK
}

/* Đọc phiên bản SoC */
void print_soc_info(void) {
    uint32_t ver  = SOC_VERSION;
    uint32_t date = SOC_BUILD_DATE;

    // Phân tích version
    int major = (ver >> 24) & 0xFF;
    int minor = (ver >> 16) & 0xFF;
    int patch = (ver >>  8) & 0xFF;

    // Phân tích ngày build BCD YYYYMMDD
    int year  = ((date >> 16) & 0xFF) * 100 + ((date >> 24) & 0xFF);
    // (parse đầy đủ tùy theo thứ tự byte BCD)
}
```

---

## 7. Mở rộng trong tương lai (Phase 2)

Khi Phase 2 thêm các peripheral mới, SoC Controller sẽ được mở rộng với:

| Offset (dự kiến) | Thanh ghi | Mô tả |
|---|---|---|
| `0x20` | `CLK_CTRL` | Clock gating control cho từng peripheral |
| `0x24` | `RST_CTRL` | Soft reset riêng cho từng peripheral |
| `0x28` | `POWER_CTRL` | Power domain control |
| `0x2C` | `IRQ_STATUS` | Tổng hợp trạng thái interrupt |

Các offset này **không được dùng trong Phase 1** và phải đọc về `0x0000_0000`.

---

*Đây là tài liệu cuối cùng trong bộ spec Phase 1. Quay lại `README.md` để xem tổng quan.*
