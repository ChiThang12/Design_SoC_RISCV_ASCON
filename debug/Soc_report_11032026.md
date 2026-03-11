# README — High Priority Fixes cho RISC-V + ASCON SoC v3

> **Mục tiêu:** Đưa SoC lên mức "correctness đầy đủ" — mọi tính năng đã thiết kế
> hoạt động đúng, không có bug âm thầm, không có wire treo.  
> Tất cả fix dưới đây là **bắt buộc trước khi chạy simulation thực tế**.

---

## Tổng quan — 5 vấn đề High Priority

| # | ID | Vấn đề | File cần sửa | Độ khó |
|---|---|---|---|---|
| 1 | `SRST` | `soft_rst_pulse` không reset được fabric | `soc_top.v` | Thấp |
| 2 | `FENCE` | `flush=0` / `fence=0` hardcode — cache coherency bug | `soc_top.v` + `riscv_cpu_core_v2.v` | Trung bình |
| 3 | `CLINT` | Không có timer interrupt — RISC-V thiếu `mtime`/`mtimecmp` | `clint.v` (mới) + `soc_top.v` | Trung bình |
| 4 | `STAT-WIRE` | Cache stats vừa là `output` vừa đọc nội bộ — Verilog illegal | `soc_top.v` | Rất thấp |
| 5 | `POR` | Không có Power-On Reset stretcher — rst_n quá ngắn | `soc_top.v` | Thấp |

---

## Fix 1 — `SRST`: soft_rst_pulse phải reset toàn bộ fabric

### Vấn đề hiện tại
```verilog
// soc_top.v hiện tại:
assign soft_rst_pulse_out = soft_rst_pulse;
// soft_rst_pulse CHỈ wire ra output port — không reset bất cứ thứ gì trong SoC
```
Khi CPU ghi `SYS_CTRL[0]=1`, `cycle_cnt_r` reset (đúng) nhưng:
- Crossbar **không** reset → transaction đang pending bị treo
- ICache / DCache **không** reset → stale state còn đó
- ASCON DMA **không** reset → có thể tiếp tục DMA cũ

### File cần sửa: `soc_top.v`

**Bước 1** — Tạo `srst_n` (synchronous active-low reset) từ `soft_rst_pulse`:
```verilog
// Thêm vào phần wire declarations (sau rst_sync):
reg  srst_n_r;   // synchronous fabric reset, active-low
wire fabric_rst_n = rst_n & srst_n_r;  // kết hợp POR reset + soft reset

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        srst_n_r <= 1'b0;
    else if (soft_rst_pulse)
        srst_n_r <= 1'b0;   // assert reset 1 cycle khi soft_rst
    else
        srst_n_r <= 1'b1;   // de-assert ngay cycle sau
end
```

**Bước 2** — Thay `rst_n` bằng `fabric_rst_n` trong tất cả instantiation (trừ CPU đã có riêng):
```verilog
// Thay đổi trong: u_icache, u_dcache, xbar, imem, dmem, u_ascon_ip, u_wconv, u_ctrl
// TỪ:   .rst_n (rst_n),
// THÀNH: .rst_n (fabric_rst_n),
```

**Bước 3** — CPU dùng `cpu_rst` riêng (đã có 2-flop sync), không cần thay đổi.

> **Lưu ý:** `srst_n_r` chỉ giữ reset 1 cycle. Nếu muốn reset dài hơn (đảm bảo
> tất cả pipeline flush xong), tăng lên 4-8 cycle bằng counter nhỏ.

---

## Fix 2 — `FENCE`: Cache Coherency — flush/fence hardcode = 0

### Vấn đề hiện tại
```verilog
// soc_top.v — icache_top instantiation:
.flush (1'b0),    // BUG: không bao giờ invalidate ICache

// soc_top.v — dcache_top instantiation:
.fence (1'b0),    // BUG: không bao giờ flush DCache
```

**Hậu quả thực tế:**
- ASCON DMA ghi data vào DMEM → DCache **không biết** → CPU đọc cache cũ → **data sai âm thầm**
- Sau self-modifying code (hoặc DMA ghi code vào IMEM) → ICache **không invalidate** → CPU chạy code cũ

### File cần sửa

#### 2a. `riscv_cpu_core_v2.v` — Thêm 2 output port

Tìm phần `module riscv_cpu_core_v2` và thêm 2 output:
```verilog
// Thêm vào port list của riscv_cpu_core_v2:
output wire  fence_i_pulse,   // HIGH 1 cycle khi decode fence.i instruction
output wire  fence_pulse      // HIGH 1 cycle khi decode fence instruction
```

Trong pipeline decode stage, khi gặp `fence.i` (opcode=`0x0000100F`):
```verilog
// Trong decode logic:
assign fence_i_pulse = (instruction[6:0] == 7'b0001111) && (instruction[14:12] == 3'b001);
assign fence_pulse   = (instruction[6:0] == 7'b0001111) && (instruction[14:12] == 3'b000);
```

#### 2b. `soc_top.v` — Wire flush/fence từ CPU

**Bước 1** — Thêm 2 wire từ CPU:
```verilog
// Thêm vào CPU ↔ Cache wires section:
wire cpu_fence_i;   // từ CPU decode: fence.i instruction
wire cpu_fence;     // từ CPU decode: fence instruction
```

**Bước 2** — Kết nối trong CPU instantiation:
```verilog
// Trong riscv_cpu_core instantiation, thêm:
.fence_i_pulse (cpu_fence_i),
.fence_pulse   (cpu_fence)
```

**Bước 3** — Thay `1'b0` bằng wire thực:
```verilog
// Trong u_icache instantiation:
// TỪ:   .flush (1'b0),
// THÀNH:
.flush (cpu_fence_i),

// Trong u_dcache instantiation:
// TỪ:   .fence (1'b0),
// THÀNH:
.fence (cpu_fence)
```

> **Quan trọng:** Nếu CPU pipeline chưa có port này, tối thiểu cần thêm
> một decoder đơn giản trong `riscv_cpu_core_v2.v` tại stage ID/EX.
> Không thể để `1'b0` mãi nếu SoC có DMA.

---

## Fix 3 — `CLINT`: Thêm RISC-V CLINT (Timer Interrupt)

### Vấn đề hiện tại
Không có `mtime` / `mtimecmp` → CPU không nhận được **machine timer interrupt** (`mip.MTIP`).  
Mọi RISC-V implementation chuẩn đều **bắt buộc** có CLINT.

### Cần tạo file mới: `clint.v`

**Spec tối thiểu:**

| Offset | Register | Access | Mô tả |
|---|---|---|---|
| `0x0000` | `msip` | RW | Software interrupt (bit[0]) |
| `0x4000` | `mtimecmp_lo` | RW | Timer compare — 32-bit thấp |
| `0x4004` | `mtimecmp_hi` | RW | Timer compare — 32-bit cao |
| `0xBFF8` | `mtime_lo` | RO | Current time — 32-bit thấp |
| `0xBFFC` | `mtime_hi` | RO | Current time — 32-bit cao |

**Interface cần có:**
```verilog
module clint #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire clk,
    input  wire rst_n,

    // AXI4 Slave port (S4 @ 0x4000_0000)
    // ... AXI signals ...

    // Interrupt outputs → CPU
    output wire timer_irq,    // → CPU mip.MTIP
    output wire sw_irq        // → CPU mip.MSIP
);
```

**Logic core:**
```verilog
// 64-bit mtime counter — tăng mỗi cycle (hoặc theo rtc_clk nếu có)
reg [63:0] mtime_r;
reg [63:0] mtimecmp_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) mtime_r <= 64'd0;
    else        mtime_r <= mtime_r + 64'd1;
end

assign timer_irq = (mtime_r >= mtimecmp_r);  // level-triggered
```

### File cần sửa: `soc_top.v`

**Bước 1** — Thêm include và wire:
```verilog
`include "clint.v"

// Thêm wire:
wire clint_timer_irq;
wire clint_sw_irq;

// Thêm S4 wires (s4_arid, s4_awid, ... tương tự s3_*)
```

**Bước 2** — Mở rộng crossbar từ `3m4s` → `3m5s`:
```
// Nếu crossbar không có sẵn 5 slave, có 2 lựa chọn:
// Option A: Viết axi4_crossbar_3m5s mới (khuyến nghị)
// Option B: Dùng AXI4 decoder đơn giản trước crossbar để split S3 address space
//           0x3000_0000 → soc_ctrl_slave
//           0x4000_0000 → clint
```

**Bước 3** — Instantiate CLINT:
```verilog
clint #(
    .ADDR_WIDTH (AXI_ADDR_WIDTH),
    .DATA_WIDTH (AXI_DATA_WIDTH),
    .ID_WIDTH   (AXI_ID_WIDTH)
) u_clint (
    .clk        (clk),
    .rst_n      (fabric_rst_n),
    // AXI S4 signals...
    .timer_irq  (clint_timer_irq),
    .sw_irq     (clint_sw_irq)
);
```

**Bước 4** — Nối vào CPU:
```verilog
// Trong riscv_cpu_core instantiation, thêm:
.timer_irq    (clint_timer_irq),   // → mip.MTIP
.sw_irq       (clint_sw_irq)       // → mip.MSIP
// external_irq đã có (từ soc_ctrl_slave irq_out → mip.MEIP)
```

> **Lưu ý crossbar:** Nếu không muốn viết lại crossbar ngay, có thể map CLINT
> vào address space của S3 (chia địa chỉ bên trong `soc_ctrl_slave`),
> nhưng đây là workaround không clean.

---

## Fix 4 — `STAT-WIRE`: Cache statistics wire conflict

### Vấn đề hiện tại
```verilog
// soc_top.v port list:
output wire [31:0] icache_hits,    // ← đây là OUTPUT PORT

// soc_top.v u_ctrl instantiation:
.icache_hits (icache_hits),        // ← đọc lại output port nội bộ
```

Trong Verilog 2001, `output wire` không thể được đọc bên trong module cùng lúc
khi nó được driven từ submodule khác. Cần intermediate wire.

### File cần sửa: `soc_top.v`

**Thay đổi:** Tách thành internal wire, rồi assign ra output:

```verilog
// THAY: output wire [31:0] icache_hits,
// BẰNG: output wire [31:0] icache_hits,   (giữ nguyên port)

// THÊM internal wires (trong phần wire declarations):
wire [31:0] icache_hits_w;
wire [31:0] icache_misses_w;
wire [31:0] dcache_hits_w;
wire [31:0] dcache_misses_w;
wire [31:0] dcache_writes_w;

// THÊM assign ra output ports:
assign icache_hits   = icache_hits_w;
assign icache_misses = icache_misses_w;
assign dcache_hits   = dcache_hits_w;
assign dcache_misses = dcache_misses_w;
assign dcache_writes = dcache_writes_w;

// SỬA trong u_icache instantiation:
// TỪ:   .stat_hits   (icache_hits),
// THÀNH:.stat_hits   (icache_hits_w),
//       .stat_misses (icache_misses_w),

// SỬA trong u_dcache instantiation:
// TỪ:   .stat_hits   (dcache_hits),
// THÀNH:.stat_hits   (dcache_hits_w),
//       .stat_misses (dcache_misses_w),
//       .stat_writes (dcache_writes_w),

// SỬA trong u_ctrl instantiation:
// TỪ:   .icache_hits (icache_hits),
// THÀNH:.icache_hits (icache_hits_w),
//       .icache_misses (icache_misses_w),
//       .dcache_hits   (dcache_hits_w),
//       .dcache_misses (dcache_misses_w),
//       .dcache_writes (dcache_writes_w),
```

---

## Fix 5 — `POR`: Power-On Reset Stretcher

### Vấn đề hiện tại
`rst_n` từ testbench hoặc external pin có thể chỉ dài 1-2 cycle. Một số
flip-flop sâu trong pipeline có thể chưa kịp reset trước khi `rst_n` de-assert.

### File cần sửa: `soc_top.v`

**Thêm POR counter** (16 cycle) vào đầu module, trước tất cả instantiation:

```verilog
// ========================================================================
// Power-On Reset Stretcher (16 cycle)
//   Đảm bảo rst_n được giữ ít nhất 16 cycle bất kể input ngắn bao nhiêu.
//   por_rst_n chỉ de-assert sau khi counter đếm đủ 16 cycle.
// ========================================================================
reg [3:0] por_cnt;          // 4-bit = đếm tới 15
reg       por_rst_n_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        por_cnt    <= 4'd0;
        por_rst_n_r <= 1'b0;
    end else begin
        if (por_cnt == 4'd15)
            por_rst_n_r <= 1'b1;   // de-assert sau 16 cycle
        else
            por_cnt <= por_cnt + 4'd1;
    end
end

wire por_rst_n = por_rst_n_r;

// Dùng por_rst_n thay vì rst_n trong fabric_rst_n:
// TỪ:   wire fabric_rst_n = rst_n & srst_n_r;
// THÀNH:
wire fabric_rst_n = por_rst_n & srst_n_r;

// Reset synchronizer cho CPU cũng dùng por_rst_n:
// TỪ:   always @(posedge clk or negedge rst_n)
// THÀNH:
// always @(posedge clk or negedge por_rst_n)
//     if (!por_rst_n) {rst_sync_2, rst_sync_1} <= 2'b11;
```

---

## Checklist — Thứ tự thực hiện

```
[ ] Fix 4 (STAT-WIRE)   — 5 phút  — sửa trước vì compile error
[ ] Fix 5 (POR)         — 10 phút — thêm trước khi sửa reset logic
[ ] Fix 1 (SRST)        — 15 phút — phụ thuộc POR xong
[ ] Fix 2 (FENCE)       — 30 phút — cần sửa cả CPU core
[ ] Fix 3 (CLINT)       — 60 phút — viết module mới + mở rộng crossbar
```

---

## Sau khi hoàn thành 5 fix này

SoC sẽ đạt được:

| Tiêu chí | Trước | Sau |
|---|---|---|
| Compile clean (Icarus) | ⚠️ Warning wire conflict | ✅ Clean |
| Soft reset hoạt động | ❌ Chỉ reset counter | ✅ Reset toàn fabric |
| DMA coherency | ❌ CPU đọc stale data | ✅ DCache flush khi fence |
| Timer interrupt | ❌ Không có | ✅ mtime/mtimecmp |
| Reset đủ dài khi power-on | ⚠️ Phụ thuộc testbench | ✅ 16-cycle guaranteed |

---

## Files cần tạo mới

| File | Mô tả |
|---|---|
| `clint.v` | RISC-V CLINT — mtime, mtimecmp, msip |
| `axi4_crossbar_3m5s.v` | Mở rộng crossbar thêm S4 cho CLINT (hoặc dùng decoder) |

## Files cần sửa

| File | Số chỗ sửa | Fix liên quan |
|---|---|---|
| `soc_top.v` | ~15 chỗ | Fix 1, 2, 4, 5 |
| `riscv_cpu_core_v2.v` | 2 output port + decode logic | Fix 2, 3 |
| `soc_ctrl_slave.v` | Không cần sửa thêm | — |

---

*Tài liệu này được tạo tự động từ phân tích code — RISC-V + ASCON SoC v3*