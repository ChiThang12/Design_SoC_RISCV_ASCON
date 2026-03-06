# 01 — Kiến Trúc Hiện Tại (v2.0)

**Liên quan:** `cpu_core.v` và tất cả module trong thư mục `cpu/`  
**Đọc file này khi:** Cần hiểu trạng thái hiện tại của SoC trước khi nâng cấp

---

## Mục lục

1. [Tổng quan kiến trúc](#1-tổng-quan-kiến-trúc)
2. [Danh sách module](#2-danh-sách-module)
3. [Chi tiết kết nối tín hiệu](#3-chi-tiết-kết-nối-tín-hiệu)
4. [Technical Debt & Giới hạn đã biết](#4-technical-debt--giới-hạn-đã-biết)

---

## 1. Tổng quan kiến trúc

SoC hiện tại khởi tạo một CPU RISC-V với ICache và DCache riêng biệt. Mỗi cache được kết nối trực tiếp point-to-point qua AXI4 Full tới bộ nhớ riêng của nó. **Không có bus dùng chung, không có address decoding, không có peripheral interconnect.**

```
 ┌─────────────────────────────────────────────────────────────┐
 │                   riscv_soc_top_cached (v2.0)               │
 │                                                             │
 │  ┌────────────┐    ┌────────────┐    ┌──────────────────┐  │
 │  │            │───▶│  ICache    │───▶│  inst_mem        │  │
 │  │  RISC-V    │    │  4KB       │    │  (AXI4 Slave)    │  │
 │  │  CPU Core  │    │  direct    │    └──────────────────┘  │
 │  │            │    │  mapped    │                           │
 │  │            │    └────────────┘                           │
 │  │            │                                             │
 │  │            │    ┌────────────┐    ┌──────────────────┐  │
 │  │            │───▶│  DCache    │───▶│  data_mem        │  │
 │  │            │    │  8KB       │    │  (AXI4 Slave)    │  │
 │  └────────────┘    │  write-    │    └──────────────────┘  │
 │                    │  through   │                           │
 │                    └────────────┘                           │
 └─────────────────────────────────────────────────────────────┘
```

### Những gì hoạt động được (v2.0)

- CPU khởi động và thực thi đúng lệnh RISC-V từ Instruction Memory
- ICache chặn đúng các yêu cầu fetch lệnh và xử lý cache miss từ IMEM qua AXI4 Full burst
- DCache chặn đúng các yêu cầu load/store dữ liệu và xử lý cache miss từ DMEM qua AXI4 Full burst
- Thống kê hit/miss của cache được xuất ra port debug

### Những gì KHÔNG tồn tại (v2.0)

- Không có AXI4 Interconnect/Crossbar — mỗi cache có đường dây riêng tới bộ nhớ riêng
- Không có address decoder — CPU không thể địa chỉ hóa bất kỳ peripheral nào ngoài IMEM và DMEM
- Không có module ASCON accelerator (deliverable chính của đề tài)
- Không có SoC Controller / CSR block
- Không có Timer
- Không có UART
- Không có Interrupt Controller (PLIC)
- Không có Boot ROM với reset vector cố định

---

## 2. Danh sách module

### 2.1 `riscv_soc_top_cached` — Module top-level

| Thuộc tính | Giá trị |
|---|---|
| File | `cpu_core.v` |
| Input | `clk`, `rst_n` |
| Output | `icache_hits[31:0]`, `icache_misses[31:0]`, `dcache_hits[31:0]`, `dcache_misses[31:0]`, `dcache_writes[31:0]` |
| Vai trò | Module structural top — chỉ khởi tạo và nối dây các sub-module |

**Lưu ý quan trọng:**
- Reset ngoài là active-low (`rst_n`) nhưng bên trong đảo thành active-high `rst = ~rst_n` cho CPU core
- `flush` của ICache đang hardwire `1'b0` — chức năng flush khi branch misprediction **chưa được implement**
- `fence` của DCache đang hardwire `1'b0` — xử lý lệnh FENCE **chưa được implement**

---

### 2.2 `riscv_cpu_core` — Lõi xử lý RISC-V

| Thuộc tính | Giá trị |
|---|---|
| File | `cpu/riscv_cpu_core.v` |
| ISA | RISC-V RV32I |
| Cực tính reset | Active-high (`rst`) |
| Giao thức phía instruction | Custom valid/ready handshake (không phải AXI4 thô) |
| Giao thức phía data | Custom valid/ready handshake có `wstrb[3:0]` |

**Tín hiệu giao diện bộ nhớ của CPU:**

| Tín hiệu | Chiều | Độ rộng | Mô tả |
|---|---|---|---|
| `imem_addr` | output | 32 | Địa chỉ fetch lệnh |
| `imem_valid` | output | 1 | CPU đang yêu cầu lệnh |
| `imem_rdata` | input | 32 | Dữ liệu lệnh trả về |
| `imem_ready` | input | 1 | Dữ liệu hợp lệ trên `imem_rdata` |
| `dmem_addr` | output | 32 | Địa chỉ bộ nhớ dữ liệu |
| `dmem_wdata` | output | 32 | Dữ liệu ghi |
| `dmem_wstrb` | output | 4 | Byte write enable (1 bit/byte) |
| `dmem_valid` | output | 1 | CPU đang yêu cầu giao dịch dữ liệu |
| `dmem_we` | output | 1 | Write enable (1=ghi, 0=đọc) |
| `dmem_rdata` | input | 32 | Dữ liệu đọc trả về |
| `dmem_ready` | input | 1 | Giao dịch hoàn tất |

**Thiếu sót đã biết trong CPU core:**
- Không có port CSR (Control and Status Register) nào được expose ra top-level
- Không có input `external_irq` để xử lý ngắt ngoài
- Không có input `timer_irq`
- Không có input `software_irq`
- Không có debug interface (JTAG)

---

### 2.3 `icache_top` — Instruction Cache

| Thuộc tính | Giá trị |
|---|---|
| File | `cpu/interface/icache/icache_top.v` |
| Kích thước | 4KB |
| Kiểu ánh xạ | Direct-mapped |
| Quyền truy cập | Chỉ đọc (read-only) |
| Giao thức phía CPU | Custom valid/ready |
| Giao thức phía bộ nhớ | AXI4 Full (chỉ burst read) |

**Port phía CPU:**

| Tín hiệu | Chiều | Độ rộng | Mô tả |
|---|---|---|---|
| `cpu_addr` | input | 32 | Địa chỉ fetch từ CPU |
| `cpu_req` | input | 1 | Yêu cầu fetch hợp lệ |
| `cpu_rdata` | output | 32 | Dữ liệu lệnh |
| `cpu_ready` | output | 1 | Hit hoặc miss-fill hoàn tất |
| `flush` | input | 1 | Xóa toàn bộ cache (đang hardwire 0) |

**Phía bộ nhớ (AXI4 Full):** Kênh đọc AXI4 đầy đủ (`AR` + `R`). Các kênh ghi (`AW`, `W`, `B`) được khai báo nhưng không sử dụng vì ICache chỉ đọc.

**Output thống kê:**

| Tín hiệu | Độ rộng | Mô tả |
|---|---|---|
| `stat_hits` | 32 | Tổng cache hit từ khi reset |
| `stat_misses` | 32 | Tổng cache miss từ khi reset |

---

### 2.4 `dcache_top` — Data Cache

| Thuộc tính | Giá trị |
|---|---|
| File | `cpu/interface/dcache/dcache_top.v` |
| Kích thước | 8KB |
| Kiểu ánh xạ | Direct-mapped |
| Chính sách ghi | Write-through |
| Giao thức phía CPU | Custom valid/ready có `we` và `wstrb` |
| Giao thức phía bộ nhớ | AXI4 Full (đọc + ghi) |

**Port phía CPU:**

| Tín hiệu | Chiều | Độ rộng | Mô tả |
|---|---|---|---|
| `cpu_addr` | input | 32 | Địa chỉ dữ liệu |
| `cpu_wdata` | input | 32 | Dữ liệu ghi |
| `cpu_wstrb` | input | 4 | Byte write strobes |
| `cpu_req` | input | 1 | Yêu cầu giao dịch |
| `cpu_we` | input | 1 | Write enable |
| `cpu_rdata` | output | 32 | Dữ liệu đọc |
| `cpu_ready` | output | 1 | Giao dịch hoàn tất |
| `fence` | input | 1 | Xả dirty lines (đang hardwire 0) |

**Output thống kê:**

| Tín hiệu | Độ rộng | Mô tả |
|---|---|---|
| `stat_hits` | 32 | Tổng cache hit từ khi reset |
| `stat_misses` | 32 | Tổng cache miss từ khi reset |
| `stat_writes` | 32 | Tổng thao tác ghi |

---

### 2.5 `inst_mem_axi_slave` — Instruction Memory

| Thuộc tính | Giá trị |
|---|---|
| File | `cpu/memory_axi4full/inst_mem_axi_slave.v` |
| Giao thức | AXI4 Full Slave |
| Vai trò | Lưu trữ binary chương trình (chỉ đọc bởi ICache) |
| Kết nối hiện tại | Dây trực tiếp tới AXI4 master port của ICache |

---

### 2.6 `data_mem_axi4_slave` — Data Memory

| Thuộc tính | Giá trị |
|---|---|
| File | `cpu/memory_axi4full/data_mem_axi_slave.v` |
| Giao thức | AXI4 Full Slave |
| Vai trò | Lưu trữ heap, stack, dữ liệu toàn cục |
| Kết nối hiện tại | Dây trực tiếp tới AXI4 master port của DCache |

---

## 3. Chi tiết kết nối tín hiệu

### 3.1 CPU → ICache (Giao thức custom)

```
riscv_cpu_core.imem_addr  →  icache_top.cpu_addr
riscv_cpu_core.imem_valid →  icache_top.cpu_req
icache_top.cpu_rdata      →  riscv_cpu_core.imem_rdata
icache_top.cpu_ready      →  riscv_cpu_core.imem_ready
1'b0                      →  icache_top.flush
```

### 3.2 CPU → DCache (Giao thức custom)

```
riscv_cpu_core.dmem_addr  →  dcache_top.cpu_addr
riscv_cpu_core.dmem_wdata →  dcache_top.cpu_wdata
riscv_cpu_core.dmem_wstrb →  dcache_top.cpu_wstrb
riscv_cpu_core.dmem_valid →  dcache_top.cpu_req
riscv_cpu_core.dmem_we    →  dcache_top.cpu_we
dcache_top.cpu_rdata      →  riscv_cpu_core.dmem_rdata
dcache_top.cpu_ready      →  riscv_cpu_core.dmem_ready
1'b0                      →  dcache_top.fence
```

### 3.3 ICache → IMEM (AXI4 Full point-to-point)

AXI4 master của ICache được nối thẳng 1-1 vào AXI4 slave của IMEM. Không có routing hay address decoding.

```
icache_top.mem_ar* → inst_mem_axi_slave.S_AXI_AR*   (toàn bộ kênh AR)
icache_top.mem_r*  ← inst_mem_axi_slave.S_AXI_R*    (toàn bộ kênh R)
icache_top.mem_aw* → inst_mem_axi_slave.S_AXI_AW*   (không sử dụng)
icache_top.mem_w*  → inst_mem_axi_slave.S_AXI_W*    (không sử dụng)
icache_top.mem_b*  ← inst_mem_axi_slave.S_AXI_B*    (không sử dụng)
```

### 3.4 DCache → DMEM (AXI4 Full point-to-point)

AXI4 master của DCache được nối thẳng 1-1 vào AXI4 slave của DMEM. Không có routing hay address decoding.

```
dcache_top.mem_ar* → data_mem_axi4_slave.S_AXI_AR*
dcache_top.mem_aw* → data_mem_axi4_slave.S_AXI_AW*
dcache_top.mem_w*  → data_mem_axi4_slave.S_AXI_W*
dcache_top.mem_r*  ← data_mem_axi4_slave.S_AXI_R*
dcache_top.mem_b*  ← data_mem_axi4_slave.S_AXI_B*
```

---

## 4. Technical Debt & Giới hạn đã biết

### 4.1 Thiếu tín hiệu AXI4 ID *(Mức độ: Nghiêm trọng)*

Các kết nối AXI4 Full hiện tại **không có** tín hiệu transaction ID (`ARID`, `AWID`, `RID`, `BID`, `WID`). Đặc tả AXI4 yêu cầu các tín hiệu này để hỗ trợ giao dịch out-of-order. Hiện tại tất cả giao dịch hoạt động ngầm định với ID=0. Điều này chấp nhận được với kết nối point-to-point nhưng **phải được thêm vào** khi có interconnect/crossbar.

**Tác động khi nâng cấp Phase 1:** AXI4 Crossbar phải hỗ trợ tối thiểu 4-bit transaction ID. Các port AXI4 của cache phải được mở rộng để bao gồm tín hiệu ID.

### 4.2 Hardwire `flush` và `fence` *(Mức độ: Trung bình)*

- `icache_top.flush` = `1'b0`: Nếu CPU pipeline cần flush cache do branch misprediction hoặc context switch, tín hiệu này phải được kết nối với output flush của CPU core.
- `dcache_top.fence` = `1'b0`: Lệnh RISC-V `FENCE` (opcode `0x0000000F`) yêu cầu DCache xả dirty lines trước khi CPU tiếp tục. Hiện tại bị bỏ qua hoàn toàn.

**Tác động khi nâng cấp Phase 1:** Có thể giữ `1'b0` trong Phase 1 nhưng phải ghi chú là future work. Tích hợp ASCON có thể cần lệnh fence trước khi đọc output data.

### 4.3 Reset không đối xứng *(Mức độ: Thấp)*

- Bên ngoài top-level: active-low `rst_n`
- CPU core bên trong: active-high `rst = ~rst_n`
- Module cache: active-low `rst_n`

**Quy tắc cho Phase 1:** Tất cả module mới phải dùng active-low `rst_n` tại các port. Đảo cực tính reset là trách nhiệm nội bộ của từng module nếu cần.

### 4.4 Kênh ghi của ICache không được tie-off đúng cách *(Mức độ: Thấp)*

Port kênh ghi của ICache (`AW`, `W`, `B`) được khai báo là wire output và truyền qua tới `inst_mem_axi_slave`, nhưng chúng được drive bởi bất cứ thứ gì `icache_top` xuất ra (có thể là tied-off nội bộ). Cần verify lại rằng IMEM slave xử lý đúng các tín hiệu write channel không hoạt động này.

---

*Tiếp theo: Xem `02_QUY_UONG_AXI4.md` để hiểu convention tín hiệu và quy tắc thiết kế.*
