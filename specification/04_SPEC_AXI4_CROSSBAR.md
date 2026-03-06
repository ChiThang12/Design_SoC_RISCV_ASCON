# 04 — Đặc Tả Module: `axi4_crossbar`

**Tên module:** `axi4_crossbar`  
**File đầu ra:** `interconnect/axi4_crossbar.v`  
**Ưu tiên:** Cao nhất — tất cả module Phase 1 khác phụ thuộc vào module này  
**Đọc trước:** `02_QUY_UONG_AXI4.md`, `03_SO_DO_DIA_CHI.md`

---

## Mục lục

1. [Vai trò và lý do cần thiết](#1-vai-trò-và-lý-do-cần-thiết)
2. [Cấu hình Phase 1](#2-cấu-hình-phase-1)
3. [Sơ đồ kiến trúc](#3-sơ-đồ-kiến-trúc)
4. [Danh sách Port](#4-danh-sách-port)
5. [Verilog Parameters](#5-verilog-parameters)
6. [Logic phân giải địa chỉ (Address Decoding)](#6-logic-phân-giải-địa-chỉ-address-decoding)
7. [Xử lý Transaction ID](#7-xử-lý-transaction-id)
8. [Logic arbitration (khi có tranh chấp)](#8-logic-arbitration-khi-có-tranh-chấp)
9. [Yêu cầu hành vi](#9-yêu-cầu-hành-vi)
10. [Xử lý địa chỉ không ánh xạ](#10-xử-lý-địa-chỉ-không-ánh-xạ)
11. [Ràng buộc hiệu suất](#11-ràng-buộc-hiệu-suất)
12. [Thay đổi cần thực hiện trên module Cache](#12-thay-đổi-cần-thực-hiện-trên-module-cache)

---

## 1. Vai trò và lý do cần thiết

### Vấn đề hiện tại

Trong v2.0, ICache và DCache mỗi cái có đường dây AXI4 riêng trực tiếp tới bộ nhớ riêng:

```
ICache ──── (AXI4 wire) ──── IMEM
DCache ──── (AXI4 wire) ──── DMEM
```

Cấu trúc này không thể mở rộng. Không thể thêm ASCON hay bất kỳ peripheral nào vì DCache chỉ có 1 kết nối duy nhất.

### Giải pháp

AXI4 Crossbar hoạt động như một "bưu điện": nhận giao dịch từ các master, đọc địa chỉ đích, và chuyển tới đúng slave.

```
ICache (M0) ─┐
              ├──▶ AXI4 Crossbar ──▶ S0: IMEM       (0x0000_0000)
DCache (M1) ─┘                   ──▶ S1: DMEM       (0x1000_0000)
                                  ──▶ S2: ASCON      (0x2000_0000)
                                  ──▶ S3: SoC Ctrl   (0x3000_0000)
```

---

## 2. Cấu hình Phase 1

| Thông số | Giá trị |
|---|---|
| Số master | 2 (M0: ICache, M1: DCache) |
| Số slave | 4 (S0: IMEM, S1: DMEM, S2: ASCON, S3: SoC Controller) |
| Data width | 32 bit |
| Address width | 32 bit |
| ID width | 4 bit |
| Kiểu arbitration | Fixed priority (M0/ICache ưu tiên cao hơn M1/DCache) |
| Kiểu crossbar | Non-blocking (M0 và M1 có thể đồng thời truy cập các slave khác nhau) |

---

## 3. Sơ đồ kiến trúc

```
                    ┌──────────────────────────────────────────┐
                    │              axi4_crossbar                │
                    │                                          │
M0 (ICache)         │  ┌──────────┐      ┌──────────────────┐  │
─── AR/R ──────────▶│  │  Master  │      │  Address         │  │
                    │  │  Port 0  │─────▶│  Decoder         │──┼──▶ S0 (IMEM)
M0 (ICache)         │  │ (R only) │      │                  │  │
─── AW/W/B ────────▶│  └──────────┘      │  0x0xxx → S0     │──┼──▶ S1 (DMEM)
   (DECERR)         │                    │  0x1xxx → S1     │  │
                    │  ┌──────────┐      │  0x2xxx → S2     │──┼──▶ S2 (ASCON)
M1 (DCache)         │  │  Master  │      │  0x3xxx → S3     │  │
─── AR/R ──────────▶│  │  Port 1  │─────▶│  other  → ERR   │──┼──▶ S3 (SoC Ctrl)
─── AW/W/B ────────▶│  │ (R+W)   │      └──────────────────┘  │
                    │  └──────────┘                            │
                    └──────────────────────────────────────────┘
```

---

## 4. Danh sách Port

### Port Master 0 (M0 — ICache, chỉ đọc)

```verilog
// Read Address Channel
input  [ID_WIDTH-1:0]   M0_AXI_ARID,
input  [ADDR_WIDTH-1:0] M0_AXI_ARADDR,
input  [7:0]            M0_AXI_ARLEN,
input  [2:0]            M0_AXI_ARSIZE,
input  [1:0]            M0_AXI_ARBURST,
input  [2:0]            M0_AXI_ARPROT,
input                   M0_AXI_ARVALID,
output                  M0_AXI_ARREADY,

// Read Data Channel
output [ID_WIDTH-1:0]   M0_AXI_RID,
output [DATA_WIDTH-1:0] M0_AXI_RDATA,
output [1:0]            M0_AXI_RRESP,
output                  M0_AXI_RLAST,
output                  M0_AXI_RVALID,
input                   M0_AXI_RREADY,

// Write Address Channel (không dùng — trả về DECERR)
input  [ID_WIDTH-1:0]   M0_AXI_AWID,
input  [ADDR_WIDTH-1:0] M0_AXI_AWADDR,
input  [7:0]            M0_AXI_AWLEN,
input  [2:0]            M0_AXI_AWSIZE,
input  [1:0]            M0_AXI_AWBURST,
input  [2:0]            M0_AXI_AWPROT,
input                   M0_AXI_AWVALID,
output                  M0_AXI_AWREADY,

// Write Data Channel (không dùng — consume và bỏ qua)
input  [DATA_WIDTH-1:0] M0_AXI_WDATA,
input  [STRB_WIDTH-1:0] M0_AXI_WSTRB,
input                   M0_AXI_WLAST,
input                   M0_AXI_WVALID,
output                  M0_AXI_WREADY,

// Write Response Channel (trả về DECERR)
output [ID_WIDTH-1:0]   M0_AXI_BID,
output [1:0]            M0_AXI_BRESP,
output                  M0_AXI_BVALID,
input                   M0_AXI_BREADY,
```

### Port Master 1 (M1 — DCache, đọc + ghi)

Tương tự M0 nhưng thay tiền tố `M0_` thành `M1_`. Tất cả 5 kênh đều hoạt động bình thường.

### Port Slave 0–3 (S0: IMEM, S1: DMEM, S2: ASCON, S3: SoC Ctrl)

```verilog
// Lặp lại cho mỗi slave Sx (x = 0, 1, 2, 3)
// Read Address Channel
output [ID_WIDTH-1:0]   Sx_AXI_ARID,
output [ADDR_WIDTH-1:0] Sx_AXI_ARADDR,
output [7:0]            Sx_AXI_ARLEN,
output [2:0]            Sx_AXI_ARSIZE,
output [1:0]            Sx_AXI_ARBURST,
output [2:0]            Sx_AXI_ARPROT,
output                  Sx_AXI_ARVALID,
input                   Sx_AXI_ARREADY,

// Read Data Channel
input  [ID_WIDTH-1:0]   Sx_AXI_RID,
input  [DATA_WIDTH-1:0] Sx_AXI_RDATA,
input  [1:0]            Sx_AXI_RRESP,
input                   Sx_AXI_RLAST,
input                   Sx_AXI_RVALID,
output                  Sx_AXI_RREADY,

// Write Address Channel
output [ID_WIDTH-1:0]   Sx_AXI_AWID,
output [ADDR_WIDTH-1:0] Sx_AXI_AWADDR,
output [7:0]            Sx_AXI_AWLEN,
output [2:0]            Sx_AXI_AWSIZE,
output [1:0]            Sx_AXI_AWBURST,
output [2:0]            Sx_AXI_AWPROT,
output                  Sx_AXI_AWVALID,
input                   Sx_AXI_AWREADY,

// Write Data Channel
output [DATA_WIDTH-1:0] Sx_AXI_WDATA,
output [STRB_WIDTH-1:0] Sx_AXI_WSTRB,
output                  Sx_AXI_WLAST,
output                  Sx_AXI_WVALID,
input                   Sx_AXI_WREADY,

// Write Response Channel
input  [ID_WIDTH-1:0]   Sx_AXI_BID,
input  [1:0]            Sx_AXI_BRESP,
input                   Sx_AXI_BVALID,
output                  Sx_AXI_BREADY,
```

---

## 5. Verilog Parameters

```verilog
module axi4_crossbar #(
    parameter NUM_MASTERS  = 2,
    parameter NUM_SLAVES   = 4,
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 4,
    parameter STRB_WIDTH   = DATA_WIDTH / 8,

    // Địa chỉ base và mask cho mỗi slave
    // Slave được chọn khi: (ADDR & SLAVE_MASK[i]) == SLAVE_BASE[i]
    parameter [ADDR_WIDTH-1:0] SLAVE_BASE [0:NUM_SLAVES-1] = '{
        32'h0000_0000,  // S0: IMEM
        32'h1000_0000,  // S1: DMEM
        32'h2000_0000,  // S2: ASCON
        32'h3000_0000   // S3: SoC Controller
    },
    parameter [ADDR_WIDTH-1:0] SLAVE_MASK [0:NUM_SLAVES-1] = '{
        32'hFFFF_0000,  // S0: 64KB window
        32'hFFFF_0000,  // S1: 64KB window
        32'hFFFF_F000,  // S2: 4KB window
        32'hFFFF_F000   // S3: 4KB window
    }
) (
    input wire clk,
    input wire rst_n,
    // ... tất cả port như Section 4
);
```

---

## 6. Logic phân giải địa chỉ (Address Decoding)

```verilog
// Hàm decode địa chỉ — trả về index slave (0-3) hoặc NUM_SLAVES nếu không tìm thấy
function automatic [2:0] decode_addr;
    input [ADDR_WIDTH-1:0] addr;
    integer i;
    begin
        decode_addr = NUM_SLAVES; // mặc định: không ánh xạ
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            if ((addr & SLAVE_MASK[i]) == SLAVE_BASE[i]) begin
                decode_addr = i;
            end
        end
    end
endfunction
```

**Ví dụ decode:**

| Địa chỉ | Phép AND mask | So sánh base | Kết quả |
|---|---|---|---|
| `0x0000_1234` | `& 0xFFFF_0000 = 0x0000_0000` | `== 0x0000_0000` ✓ | → S0 (IMEM) |
| `0x1000_AB00` | `& 0xFFFF_0000 = 0x1000_0000` | `== 0x1000_0000` ✓ | → S1 (DMEM) |
| `0x2000_0010` | `& 0xFFFF_F000 = 0x2000_0000` | `== 0x2000_0000` ✓ | → S2 (ASCON) |
| `0x5000_0000` | Không match mask nào | — | → DECERR |

---

## 7. Xử lý Transaction ID

### Mục đích

Khi M0 và M1 đều gửi giao dịch tới cùng một slave, slave nhận được hai giao dịch với ID có thể trùng nhau. Cần đánh tag master ID để slave trả phản hồi đúng master.

### Cơ chế

Khi crossbar forward giao dịch từ master Mx tới slave Sy:
- **ARID/AWID gửi tới slave** = `{master_index[0], original_id[ID_WIDTH-2:0]}`
  - Bit cao nhất = index của master (0 hoặc 1)
  - Các bit còn lại = ID gốc từ master

Khi crossbar nhận phản hồi từ slave (RID hoặc BID):
- Lấy bit cao nhất để xác định master đích
- Phát lại `RID/BID` với bit cao nhất bị bỏ về giá trị ID gốc

```
Master 0 gửi ARID=0x3  →  Crossbar gửi ARID=0x3 (bit[3]=0, master 0)
Master 1 gửi ARID=0x3  →  Crossbar gửi ARID=0xB (bit[3]=1, master 1)

Slave trả  RID=0x3     →  Crossbar forward về Master 0 với RID=0x3
Slave trả  RID=0xB     →  Crossbar forward về Master 1 với RID=0x3
```

---

## 8. Logic arbitration (khi có tranh chấp)

**Khi nào có tranh chấp:** M0 và M1 cùng muốn truy cập cùng một slave đồng thời.

**Chính sách:** Fixed priority — M0 (ICache) có ưu tiên cao hơn M1 (DCache).

Lý do: Instruction fetch thường nằm trên critical path của pipeline. Nếu ICache bị chờ, CPU sẽ stall toàn bộ.

**Hành vi khi M1 thua arbitration:**
- Crossbar giữ `M1_AXI_ARREADY = 0` (hoặc `AWREADY = 0`) cho đến khi M0 giải phóng slave
- M1 phải giữ nguyên `ARVALID = 1` và địa chỉ trong khi chờ
- DCache đã có cơ chế chờ ready, nên điều này tự nhiên hỗ trợ back-pressure

---

## 9. Yêu cầu hành vi

1. **Non-blocking:** Nếu M0 đang truy cập S0 và M1 muốn truy cập S2, cả hai giao dịch phải được xử lý song song mà không chặn nhau.

2. **Burst nguyên vẹn:** Không cắt đứt burst ở giữa. Nếu M1 đang thực hiện burst 8-beat tới S1, M0 không thể chen vào giữa burst đó.

3. **Thứ tự phản hồi:** Trong mỗi kênh (Read hoặc Write), phản hồi phải trả về đúng thứ tự giao dịch được gửi (trong-order per master).

4. **Không deadlock:** Thiết kế phải đảm bảo không có tình huống deadlock khi cả hai master cùng bị chờ.

5. **Không latch:** Tất cả logic combinational trong crossbar phải có default assignment.

6. **Reset sạch:** Sau `rst_n`, tất cả VALID output của crossbar phải = 0, tất cả READY output phải = 1.

---

## 10. Xử lý địa chỉ không ánh xạ

Crossbar phải có một "dummy slave" nội bộ để xử lý địa chỉ DECERR:

**Đối với read (AR channel):**
```verilog
// Ngay khi nhận ARVALID với địa chỉ không hợp lệ:
// 1. Phát ARREADY = 1 (chấp nhận địa chỉ)
// 2. Sau 1 cycle, phát:
//    RDATA  = 32'hDEAD_BEEF
//    RRESP  = 2'b11 (DECERR)
//    RLAST  = 1'b1
//    RVALID = 1'b1
// 3. Chờ RREADY = 1 rồi kết thúc giao dịch
```

**Đối với write (AW + W channel):**
```verilog
// 1. Phát AWREADY = 1 (chấp nhận địa chỉ)
// 2. Phát WREADY = 1 (consume toàn bộ dữ liệu và WLAST)
// 3. Sau khi nhận WLAST, phát:
//    BRESP  = 2'b11 (DECERR)
//    BVALID = 1'b1
// 4. Chờ BREADY = 1 rồi kết thúc
```

---

## 11. Ràng buộc hiệu suất

| Chỉ tiêu | Yêu cầu |
|---|---|
| Latency thêm vào (best case) | ≤ 1 chu kỳ clock (crossbar chỉ mux, không thêm pipeline stage) |
| Throughput khi không tranh chấp | 1 giao dịch/cycle (same as direct connection) |
| Throughput khi tranh chấp | M0 được phục vụ đầy đủ, M1 bị trễ |

---

## 12. Thay đổi cần thực hiện trên module Cache

Để kết nối vào crossbar, các module cache hiện tại phải được cập nhật (hoặc wrapper):

### ICache (`icache_top`)

Cần thêm các tín hiệu ID vào AXI4 master port:
```verilog
// Thêm vào port list của icache_top:
output [ID_WIDTH-1:0] mem_arid,   // thêm mới
output [ID_WIDTH-1:0] mem_awid,   // thêm mới
input  [ID_WIDTH-1:0] mem_rid,    // thêm mới
input  [ID_WIDTH-1:0] mem_bid,    // thêm mới
output [ID_WIDTH-1:0] mem_wid,    // thêm mới (tùy chọn)
```

Có thể dùng wrapper module nếu không muốn sửa trực tiếp `icache_top`:
```verilog
module icache_axi_wrapper (
    // CPU side: không đổi
    // AXI4 side: thêm ID signals
    // Nội bộ: tie ARID = 0, bỏ qua RID
);
```

### DCache (`dcache_top`)

Tương tự ICache — thêm ID signals vào AXI4 master port.

---

*Tiếp theo: Xem `05_SPEC_ASCON.md` để biết đặc tả module ASCON.*
