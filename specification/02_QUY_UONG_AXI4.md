# 02 — Quy Ước AXI4 & Quy Tắc Thiết Kế

**Áp dụng cho:** Tất cả module trong dự án này  
**Đọc file này khi:** Trước khi viết bất kỳ module AXI4 nào trong Phase 1

---

## Mục lục

1. [Quy ước đặt tên tín hiệu AXI4](#1-quy-ước-đặt-tên-tín-hiệu-axi4)
2. [Độ rộng tín hiệu chuẩn](#2-độ-rộng-tín-hiệu-chuẩn)
3. [Clock và Reset](#3-clock-và-reset)
4. [Quy tắc thiết kế bắt buộc](#4-quy-tắc-thiết-kế-bắt-buộc)
5. [Quy tắc tuân thủ AXI4](#5-quy-tắc-tuân-thủ-axi4)
6. [Phân biệt AXI4 Full vs AXI4 Lite](#6-phân-biệt-axi4-full-vs-axi4-lite)
7. [Từ điển thuật ngữ](#7-từ-điển-thuật-ngữ)

---

## 1. Quy ước đặt tên tín hiệu AXI4

Tất cả giao diện AXI4 trong SoC này theo quy tắc đặt tên sau:

| Kênh | Prefix phía Master | Prefix phía Slave |
|---|---|---|
| Write Address (địa chỉ ghi) | `M_AXI_AW*` | `S_AXI_AW*` |
| Write Data (dữ liệu ghi) | `M_AXI_W*` | `S_AXI_W*` |
| Write Response (phản hồi ghi) | `M_AXI_B*` | `S_AXI_B*` |
| Read Address (địa chỉ đọc) | `M_AXI_AR*` | `S_AXI_AR*` |
| Read Data (dữ liệu đọc) | `M_AXI_R*` | `S_AXI_R*` |

**Ví dụ tên tín hiệu đầy đủ:**

```
// Phía Master (ICache hoặc DCache)
M_AXI_ARADDR, M_AXI_ARVALID, M_AXI_ARREADY
M_AXI_RDATA,  M_AXI_RVALID,  M_AXI_RREADY

// Phía Slave (IMEM, DMEM, ASCON, SoC Controller)
S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY
S_AXI_RDATA,  S_AXI_RVALID,  S_AXI_RREADY
```

---

## 2. Độ rộng tín hiệu chuẩn

Tất cả module trong SoC này sử dụng các độ rộng sau:

| Tín hiệu | Độ rộng | Ghi chú |
|---|---|---|
| `*ADDR` | 32 bit | Tất cả tín hiệu địa chỉ |
| `*DATA` | 32 bit | Tất cả tín hiệu dữ liệu |
| `*STRB` | 4 bit | Byte write enable (1 bit cho mỗi byte) |
| `*LEN` | 8 bit | Burst length (AXI4, không phải AXI3) |
| `*SIZE` | 3 bit | Kích thước transfer |
| `*BURST` | 2 bit | Kiểu burst (`00`=FIXED, `01`=INCR, `10`=WRAP) |
| `*PROT` | 3 bit | Protection type |
| `*RESP` | 2 bit | Mã phản hồi (xem bảng bên dưới) |
| `*ID` | 4 bit | Transaction ID (phải thêm vào Phase 1) |

**Bảng mã phản hồi (`*RESP`):**

| Giá trị | Tên | Ý nghĩa |
|---|---|---|
| `2'b00` | OKAY | Giao dịch thành công |
| `2'b01` | EXOKAY | Exclusive access thành công |
| `2'b10` | SLVERR | Slave nhận giao dịch nhưng có lỗi nội bộ |
| `2'b11` | DECERR | Địa chỉ không ánh xạ tới slave nào |

---

## 3. Clock và Reset

- **Clock:** Một miền clock duy nhất — tất cả module chạy trên cùng `clk`
- **Reset:** Active-low `rst_n` tại tất cả port module
- **Không có CDC** (Clock Domain Crossing) trong Phase 1
- **Quy tắc reset:** Tất cả logic tuần tự phải có reset bất đồng bộ active-low

```verilog
// Mẫu reset đúng chuẩn cho tất cả module Phase 1
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // khởi tạo về giá trị reset
        reg_data <= 32'h0;
    end else begin
        // logic bình thường
    end
end
```

---

## 4. Quy tắc thiết kế bắt buộc

Những quy tắc này **BẮT BUỘC** áp dụng cho tất cả module Phase 1. Agent hoặc kỹ sư nào vi phạm các quy tắc này phải sửa lại trước khi tích hợp.

### Quy tắc 1 — Ngôn ngữ RTL
Tất cả RTL phải viết bằng Verilog tổng hợp được (IEEE 1364-2001 hoặc subset SystemVerilog 2005). Không dùng `initial` block bên ngoài testbench.

### Quy tắc 2 — Reset
Tất cả logic tuần tự phải có reset bất đồng bộ active-low (`rst_n`). Trạng thái reset phải khớp với giá trị reset trong register map của từng module.

### Quy tắc 3 — Non-blocking assignment
Dùng non-blocking assignment (`<=`) cho tất cả logic flip-flop. Không dùng blocking assignment (`=`) trong `always @(posedge clk)`.

```verilog
// ĐÚNG
always @(posedge clk) begin
    reg_a <= next_a;
    reg_b <= next_b;
end

// SAI
always @(posedge clk) begin
    reg_a = next_a;  // Không dùng
    reg_b = next_b;  // Không dùng
end
```

### Quy tắc 4 — Không có latch suy diễn
Tất cả `always @(*)` combinational block phải có default assignment cho mọi output để tránh inferred latch.

```verilog
// ĐÚNG — có default
always @(*) begin
    next_state = IDLE;   // default
    output_valid = 1'b0; // default
    case (state)
        ACTIVE: begin
            next_state   = DONE;
            output_valid = 1'b1;
        end
    endcase
end

// SAI — thiếu default, gây inferred latch
always @(*) begin
    case (state)
        ACTIVE: begin
            output_valid = 1'b1; // Nếu không phải ACTIVE, output_valid sẽ là latch
        end
    endcase
end
```

### Quy tắc 5 — Tham số hóa độ rộng bus
Tất cả độ rộng bus (`DATA_WIDTH`, `ADDR_WIDTH`, `ID_WIDTH`) phải là Verilog parameter, không hardcode constant.

```verilog
// ĐÚNG
module ascon_axi_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4
) ( ... );

// SAI
module ascon_axi_slave ( ... );
// rồi dùng 32 hardcode trong thân module
```

### Quy tắc 6 — Header comment bắt buộc
Mỗi file `.v` mới phải bắt đầu bằng comment header sau:

```verilog
// ============================================================================
// Module: <tên_module>
// ============================================================================
// Mô tả:
//   <mô tả ngắn gọn chức năng module>
//
// Tác giả: ChiThang
// Ngày: <ngày tạo>
// Phiên bản: 1.0
//
// Ports:
//   clk      - Clock đầu vào
//   rst_n    - Reset bất đồng bộ, active-low
//   ...
// ============================================================================
```

### Quy tắc 7 — Đặt tên file
Module `ten_module` phải nằm trong file `ten_module.v` và đặt đúng thư mục theo cấu trúc dự án trong `README.md`.

### Quy tắc 8 — Căn chỉnh địa chỉ
Tất cả truy cập thanh ghi memory-mapped được giả định căn chỉnh 32-bit. Hành vi khi truy cập không căn chỉnh là undefined và có thể trả về SLVERR.

### Quy tắc 9 — ICache phải read-only
AXI4 master của ICache tuyệt đối không được phát giao dịch ghi. Crossbar phải thực thi điều này — giao dịch ghi từ M0 (ICache) phải trả về DECERR trên kênh B.

---

## 5. Quy tắc tuân thủ AXI4

Các quy tắc handshake AXI4 bắt buộc đối với tất cả slave module mới:

### 5.1 Kênh đọc

```
❌ SAI:  RVALID phát trước khi nhận ARVALID
✅ ĐÚNG: Slave chỉ phát RVALID sau khi ARVALID đã được nhận và ARREADY đã phát

❌ SAI:  ARREADY luôn = 0 (block master mãi mãi)
✅ ĐÚNG: ARREADY phải được phát trong thời gian hợp lý

❌ SAI:  RDATA thay đổi khi RVALID=1 và RREADY=0
✅ ĐÚNG: RDATA phải giữ nguyên cho đến khi RREADY=1
```

### 5.2 Kênh ghi

```
❌ SAI:  BVALID phát trước khi hoàn thành chuỗi AWVALID + WVALID + WLAST
✅ ĐÚNG: BVALID chỉ phát sau khi nhận xong địa chỉ ghi VÀ toàn bộ dữ liệu ghi

❌ SAI:  Chấp nhận AWVALID nhưng bỏ qua WVALID (hoặc ngược lại)
✅ ĐÚNG: Slave phải xử lý cả kênh AW và W trước khi phát BVALID
```

### 5.3 Burst transaction

```
ARLEN = N  →  Slave phải trả về đúng N+1 beat dữ liệu (RVALID N+1 lần)
RLAST = 1  →  Phải được phát cùng với beat cuối cùng (index = ARLEN)
```

### 5.4 Sơ đồ thời gian ví dụ (single read)

```
clk:     ____╱╲____╱╲____╱╲____╱╲____╱╲____
ARVALID: ____╱╲╲╲╲╲╲╲╲____________________
ARREADY: __________╱╲____________________
RVALID:  ____________╱╲╲╲╲╲╲╲____________
RREADY:  ______________╱╲╲╲╲╲╲____________
RDATA:   ____________[===DATA===]__________
RLAST:   ________________╱╲______________
```

---

## 6. Phân biệt AXI4 Full vs AXI4 Lite

| Tính năng | AXI4 Full | AXI4 Lite |
|---|---|---|
| Burst | Có (`ARLEN`, `WLAST`, `RLAST`) | Không — luôn 1 beat |
| Transaction ID | Có | Không |
| Dùng cho | Cache memory access, DMA, high bandwidth | Control registers, peripheral config |
| Module dùng trong SoC này | ICache, DCache, IMEM, DMEM | ASCON slave, SoC Controller |
| Độ phức tạp implement | Cao | Thấp |

**Ghi chú quan trọng:** ASCON slave và SoC Controller implement AXI4 Lite nhưng phải chấp nhận (và bỏ qua) các tín hiệu `*LEN`, `*SIZE`, `*BURST` của AXI4 Full vì chúng được kết nối qua AXI4 Crossbar sử dụng AXI4 Full.

---

## 7. Từ điển thuật ngữ

| Thuật ngữ | Định nghĩa |
|---|---|
| AXI4 | AMBA AXI4 — chuẩn bus của ARM, phiên bản 4. Hiệu suất cao, hỗ trợ burst. |
| AXI4 Lite | Subset đơn giản hóa của AXI4 — không burst, cố định 1 beat/giao dịch. Dành cho thanh ghi điều khiển. |
| AXI4 Full | AXI4 đầy đủ bao gồm burst (`ARLEN`, `RLAST`, `WLAST`). Dùng cho cache memory access. |
| Master | Bên khởi tạo giao dịch AXI4. Trong SoC này: ICache và DCache là master. |
| Slave | Bên phản hồi giao dịch AXI4. Trong SoC này: IMEM, DMEM, ASCON, SoC Controller là slave. |
| Handshake | Cơ chế bắt tay VALID/READY: giao dịch chỉ hoàn thành khi cả hai bên đồng thời assert VALID=1 và READY=1. |
| Back-pressure | Khi slave chưa sẵn sàng nhận, nó giữ READY=0 để làm master chờ. Master phải giữ nguyên dữ liệu và VALID=1. |
| DECERR | Decode Error — slave ảo trả về khi địa chỉ không ánh xạ tới slave nào. |
| SLVERR | Slave Error — slave thật trả về khi có lỗi nội bộ. |
| Burst | Một chuỗi transfer dữ liệu liên tục với một lần địa chỉ đăng ký duy nhất. |
| INCR burst | Kiểu burst phổ biến nhất — địa chỉ tăng tuần tự sau mỗi beat. |
| CDC | Clock Domain Crossing — vượt ranh giới giữa các miền clock khác nhau. Không có trong Phase 1. |
| CSR | Control and Status Register — thanh ghi điều khiển/trạng thái ánh xạ bộ nhớ. |

---

*Tiếp theo: Xem `03_SO_DO_DIA_CHI.md` để hiểu bản đồ địa chỉ.*
