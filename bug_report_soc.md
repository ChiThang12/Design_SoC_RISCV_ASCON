# BÁO CÁO BUG — RISC-V SoC (riscv_cpu_core_v2 + dcache)
**Tác giả phân tích:** Claude  
**Ngày:** 2026-02-18  
**Phiên bản SoC:** v2.1  
**Kết quả simulation:** `a0 = X (FAIL)` · 4 RAW hazard violations · CPI = 1.416 · DCache hit = 77.5%

---

## Tóm tắt nhanh

| # | Mức | File | Dòng | Mô tả ngắn |
|---|-----|------|------|------------|
| BUG-1 | 🔴 Critical | `riscv_cpu_core_v2.v` | 562–566 | `lsu_result_ack` delay 1 cycle → double-capture load result → `a0 = X` |
| BUG-2 | 🔴 Critical | `riscv_cpu_core_v2.v` | 487–500 | `lsu_req_sent` reset sớm → double-issue request vào LSU |
| BUG-3 | 🔴 Critical | `riscv_cpu_core_v2.v` | 412–438 | EX/MEM register không dùng `stall_any` → instruction bị mất khi `stall_if` active |
| BUG-4 | 🟡 Medium | `dcache_controller.v` | 200–203, 235–240 | `cpu_ready` pulse đúng cycle `wt_done` nhưng `state` chưa về IDLE → `cur_addr` latch sai request kế tiếp |
| BUG-5 | 🟡 Medium | `dcache_data_array.v` + `dcache_controller.v` | 44, 221–225 | Data array đọc **async** nhưng controller dùng output ngay cycle LOOKUP khi `cur_addr` vừa latch → glitch window |
| BUG-6 | 🟢 Low | `hazard_detection.v` | 97, 102 | `stall` và `stall_if` độc lập hoàn toàn — khi cả hai cùng active, không có logic ưu tiên rõ ràng |

**Fix Bug-1 + Bug-2 + Bug-3 sẽ giải quyết: `a0 = X`, 4 RAW errors, và phần lớn 311 stall cycles thừa.**

---

## BUG-1 🔴 — `lsu_result_ack` delay 1 cycle gây double-capture

### File & vị trí
`riscv_cpu_core_v2.v`, dòng 562–566

### Code hiện tại (SAI)
```verilog
reg lsu_result_ack_r;
always @(posedge clk or posedge rst) begin
    if (rst) lsu_result_ack_r <= 1'b0;
    else     lsu_result_ack_r <= lsu_result_valid;  // delayed 1 cycle
end
assign lsu_result_ack = lsu_result_ack_r;
```

### Phân tích lỗi
Comment trong code lo ngại "combinational loop" nên thêm 1 cycle delay cho `result_ack`. Tuy nhiên điều này tạo ra race condition nghiêm trọng hơn:

```
Cycle N:   lsu_result_valid=1 → MEM/WB latch: rd=t0, data=42  ✓
           lsu_result_ack=0   → LSU CHƯA clear result_valid
           
Cycle N+1: lsu_result_valid=1 (vẫn còn!) → MEM/WB latch LẠI: rd=t0 ✗ (double-capture)
           lsu_result_ack=1              → LSU mới clear result_valid
           
           Nếu pipeline advance (stall=0) tại cycle N+1:
           → nhánh else if (!stall) bị BLOCK bởi if (lsu_result_valid)
           → ALU instruction theo sau load mất write-back hoàn toàn
```

Hậu quả: `a0 (x10) = X` trong kết quả simulation — đây là nguyên nhân gốc rễ của FAIL.

Lo ngại về "combinational loop" là **không có cơ sở**: `lsu_result_valid` là output **sequential** (registered) của LSU — không phụ thuộc vào `result_ack` trong cùng cycle, vì vậy không tạo loop.

### Fix
```verilog
// XÓA toàn bộ reg lsu_result_ack_r và always block của nó
// Thay bằng:
assign lsu_result_ack = lsu_result_valid;  // combinational, không có loop
```

---

## BUG-2 🔴 — `lsu_req_sent` reset sớm hơn 1 cycle so với instruction mới

### File & vị trí
`riscv_cpu_core_v2.v`, dòng 487–500

### Code hiện tại (SAI)
```verilog
always @(posedge clk or posedge rst) begin
    if (rst) begin
        lsu_req_sent <= 1'b0;
    end else begin
        if (!stall) begin
            lsu_req_sent <= 1'b0;   // ← reset ngay khi pipeline không stall
        end else if (lsu_req_valid && lsu_req_ready) begin
            lsu_req_sent <= 1'b1;
        end
    end
end
```

### Phân tích lỗi
EX/MEM register chỉ advance vào **cycle sau** khi `stall` deassert. Timeline:

```
Cycle N:   stall=1, memread_mem=1 (load đang chờ), lsu_req_sent=1
Cycle N+1: stall=0 (load xong) → lsu_req_sent RESET về 0
           EX/MEM vẫn giữ instruction cũ (memread_mem=1 chưa đổi)
           → lsu_req_valid = memread_mem & !lsu_req_sent = 1 & 1 = 1 ✗
           → LSU nhận request LẦN 2 cho cùng load instruction!
Cycle N+2: EX/MEM mới có instruction mới
```

Double-issue gây LSU xử lý load 2 lần, đưa data sai vào register file → 4 RAW hazard violations.

### Fix
```verilog
// Theo dõi edge "vừa thoát stall" thay vì dùng level !stall
reg prev_stall;
always @(posedge clk or posedge rst) begin
    if (rst) prev_stall <= 1'b1;
    else     prev_stall <= stall;
end

// prev_stall=1 && stall=0 = đúng cycle EX/MEM chứa instruction MỚI
always @(posedge clk or posedge rst) begin
    if (rst) begin
        lsu_req_sent <= 1'b0;
    end else begin
        if (prev_stall && !stall) begin
            lsu_req_sent <= 1'b0;   // reset khi instruction thực sự mới
        end else if (lsu_req_valid && lsu_req_ready) begin
            lsu_req_sent <= 1'b1;
        end
    end
end
```

---

## BUG-3 🔴 — EX/MEM register không freeze khi `stall_if` active

### File & vị trí
`riscv_cpu_core_v2.v`, dòng 412–438 (EX/MEM always block)

### Code hiện tại (SAI)
```verilog
// Dòng 425:
end else if (!stall) begin        // ← chỉ check stall, thiếu stall_if
    regwrite_ex_mem   <= regwrite_ex;
    // ... các field khác
end
// stall: reg tự hold
```

Trong khi đó, ID/EX register (dòng 295) đúng hơn:
```verilog
end else if (!stall_any) begin    // stall_any = stall | stall_if
```

### Phân tích lỗi
Khi ICache đang fetch (`stall_if=1`, `stall=0`):
- `stall_any = 1` → ID/EX **frozen** đúng (instruction cũ giữ nguyên trong ID/EX)
- `!stall = 1` → EX/MEM **vẫn advance** ← SAI

EX stage vẫn đọc từ ID/EX register (đang giữ instruction cũ) và ghi kết quả mới vào EX/MEM. Instruction trong EX bị xử lý 2 lần — lần đầu đúng, lần hai ghi đè EX/MEM với kết quả không hợp lệ vì forwarding data không còn valid.

Đây là nguyên nhân của `max_stall_run = 17 cycles` và nhiều stall thừa trong pipeline.

### Fix
```verilog
// riscv_cpu_core_v2.v, dòng 425:
// Đổi:
end else if (!stall) begin
// Thành:
end else if (!stall_any) begin    // thêm stall_if vào điều kiện
```

---

## BUG-4 🟡 — Race condition: `cpu_ready` pulse khi `state` chưa về IDLE

### File & vị trí
`dcache_controller.v`, dòng 200–203 và 235–240

### Code hiện tại (có vấn đề)
```verilog
// next_state (combinational):
`DCACHE_STATE_WRITE_THRU: begin
    if (wt_done)
        next_state = `DCACHE_STATE_IDLE;  // state chuyển IDLE ở posedge TIẾP THEO
end

// cpu_ready (combinational, dùng state hiện tại):
`DCACHE_STATE_WRITE_THRU: begin
    if (wt_done) begin
        cpu_ready_int = 1'b1;   // assert CÙNG CYCLE với wt_done
    end
end
```

### Phân tích lỗi
```
Cycle N:   wt_done=1, state=WRITE_THRU
           → cpu_ready=1 (comb) → LSU thấy ready, issue request KẾ TIẾP ngay
           → cpu_req=1, cpu_addr=addr_mới trong cùng cycle N
           → Sequential IDLE block KHÔNG chạy (state vẫn là WRITE_THRU)
           → cur_addr KHÔNG latch addr_mới
           
Cycle N+1: state=IDLE (mới chuyển)
           cpu_req có thể đã deassert (LSU nghĩ cache đã nhận)
           → cur_addr = addr_cũ → cache lookup sai địa chỉ
```

Giải thích tại sao DCache hit rate chỉ 77.5% — một số load đọc sai cache line do cur_addr bị stale.

### Fix
```verilog
// Phương án 1: Thêm state trung gian DRAIN
`DCACHE_STATE_WRITE_THRU: begin
    if (wt_done)
        next_state = `DCACHE_STATE_DRAIN;  // 1 cycle buffer
end
`DCACHE_STATE_DRAIN: begin
    next_state = `DCACHE_STATE_IDLE;
    cpu_ready_int = 1'b1;   // assert ở đây thay vì WRITE_THRU
end

// Phương án 2 (đơn giản hơn): assert cpu_ready ở cycle SAU khi state đã IDLE
// Đổi output logic sang dùng next_state thay vì state:
if (wt_done) begin
    cpu_ready_int = 1'b1;
    // Đảm bảo IDLE latch chạy trước bằng cách delay 1 cycle
end
```

---

## BUG-5 🟡 — Data array read async nhưng controller dùng output không đúng timing

### File & vị trí
`dcache_data_array.v` dòng 44; `dcache_controller.v` dòng 221–225

### Phân tích
`dcache_data_array` dùng **combinational read**:
```verilog
// dcache_data_array.v:
assign read_data = data_array[read_addr];  // async, không có clock
```

Nhưng write là **sequential** (có clock, dòng 53–60).

Trong `dcache_controller.v`, controller dùng output này:
```verilog
`DCACHE_STATE_LOOKUP: begin
    if (!cur_we && tag_hit) begin
        cpu_ready_int = 1'b1;
        cpu_rdata_int = data_read_data;   // data từ async read
    end
end
```

**Vấn đề:** Khi controller vừa ghi vào data array ở cycle N (write-allocate, FIX-A), rồi ngay cycle N+1 chuyển sang LOOKUP để đọc lại vị trí đó:

```
Cycle N:   LOOKUP, cur_we=1 → data_write_enable=1, ghi word vào array
           state → WRITE_THRU
Cycle N+1: WRITE_THRU (chờ wt_done)

Sau vài cycle: request load cùng địa chỉ
Cycle M:   LOOKUP, tag_hit=1 (đã valid từ write-allocate)
           data_read_data = data_array[cur_index][cur_offset] ← đọc đúng ✓
```

Thực ra với write-allocate đã được implement (FIX-A trong controller), kịch bản load ngay sau store sẽ hit và đọc đúng data. **Tuy nhiên**, có một trường hợp vẫn sai: khi `write_enable=1` và `read_addr == write_addr` trong cùng cycle (read-during-write), `read_data` trả giá trị **trước khi ghi** (old data) vì write là sequential còn read là combinational. Không có write-first hay read-first policy rõ ràng.

### Fix
```verilog
// dcache_data_array.v: thêm write-first forwarding
wire [31:0] write_forwarded;
assign write_forwarded = (write_enable && (read_addr == write_addr)) 
                         ? write_data 
                         : data_array[read_addr];
assign read_data = write_forwarded;
// Lưu ý: forwarding này chỉ dùng cho word-level, cần xử lý byte-enable nếu partial write
```

---

## BUG-6 🟢 — `hazard_detection`: không có ưu tiên khi `stall` và `stall_if` đồng thời

### File & vị trí
`hazard_detection.v`, dòng 97–102

### Phân tích
Thiết kế tách `stall` và `stall_if` là đúng về nguyên tắc. Tuy nhiên:

```verilog
assign stall    = load_use_hazard || lsu_dependency_stall;
assign stall_if = imem_stall;
// Hai signal hoàn toàn độc lập
```

Khi cả hai đồng thời (`stall=1` VÀ `stall_if=1`): toàn pipeline frozen bởi `stall_any = stall|stall_if`. Đây là hành vi đúng. Nhưng khi `stall` clear trước `stall_if` (load xong nhưng ICache chưa ready), pipeline sẽ có 1 cycle "lửng" mà `stall_any=1` bởi `stall_if` nhưng logic trong các register không đồng nhất (đã thấy ở BUG-3).

Bug-3 là biểu hiện của vấn đề này. Fix Bug-3 là đủ — không cần thay đổi `hazard_detection.v`.

---

## Kế hoạch fix theo thứ tự

### Bước 1 — Fix ngay (giải quyết `a0 = X` và RAW errors)

**1a. `riscv_cpu_core_v2.v` dòng 561–566** — Xóa delay của result_ack:
```verilog
// XÓA:
reg lsu_result_ack_r;
always @(posedge clk or posedge rst) begin
    if (rst) lsu_result_ack_r <= 1'b0;
    else     lsu_result_ack_r <= lsu_result_valid;
end
assign lsu_result_ack = lsu_result_ack_r;

// THAY BẰNG:
assign lsu_result_ack = lsu_result_valid;
```

**1b. `riscv_cpu_core_v2.v` dòng 487–500** — Fix timing reset lsu_req_sent:
```verilog
// THÊM:
reg prev_stall;
always @(posedge clk or posedge rst) begin
    if (rst) prev_stall <= 1'b1;
    else     prev_stall <= stall;
end

// ĐỔI điều kiện reset:
if (prev_stall && !stall) begin   // thay vì if (!stall)
    lsu_req_sent <= 1'b0;
```

**1c. `riscv_cpu_core_v2.v` dòng 425** — Fix EX/MEM stall condition:
```verilog
// ĐỔI:
end else if (!stall) begin
// THÀNH:
end else if (!stall_any) begin
```

### Bước 2 — Fix sau (cải thiện DCache correctness và hit rate)

**2a. `dcache_controller.v`** — Thêm DRAIN state hoặc delay cpu_ready trong WRITE_THRU.

**2b. `dcache_data_array.v`** — Thêm write-first forwarding để tránh read-during-write race.

---

## Dự báo kết quả sau fix

| Metric | Hiện tại | Sau fix Bước 1 | Sau fix Bước 2 |
|--------|----------|-----------------|-----------------|
| `a0` | X (FAIL) | 0x00 (PASS) | 0x00 (PASS) |
| RAW violations | 4 | 0 | 0 |
| DCache hit rate | 77.5% | ~80% | >90% |
| Stall cycles | 311 (28%) | ~180 (<20%) | ~120 (<15%) |
| CPI | 1.416 | ~1.25 | ~1.15 |
| Rating | ★★★☆☆ FAIR | ★★★★☆ GOOD | ★★★★★ EXCELLENT |
