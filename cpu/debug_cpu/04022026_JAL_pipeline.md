Ok, mình **chuyển toàn bộ phân tích này sang tiếng Việt**, viết theo kiểu **technical + dễ đưa thẳng vào `debug.md`**, có cấu trúc rõ ràng, không lan man.

---

# 🐞 PIPELINE DEBUG – PHÂN TÍCH LỖI PC / JAL

## 1️⃣ Hiện tượng lỗi quan sát được

* Lệnh `jal x0, 0` (`0x0000006F`) **đáng lẽ phải giữ nguyên PC**
* Nhưng trong waveform:

  ```
  PC: 0x14 → 0x18 → 0x1C
  ```
* Nghĩa là **PC vẫn bị auto-increment**, JAL **không có tác dụng**

👉 Lỗi này **không phải do instruction hex**, mà do **điều khiển pipeline / timing PC sai**

---

## 2️⃣ Kiểm tra logic hiện tại

Code hiện tại:

```verilog
assign jal_target = pc_ex + imm_ex;              
assign pc_src_ex = (branch_ex & branch_taken_ex) | jump_ex;
```

✔ Về mặt **logic lý thuyết là đúng**

Nhưng CPU vẫn chạy sai ⇒ lỗi nằm ở **THỜI ĐIỂM (timing)**, không phải biểu thức.

---

## 3️⃣ Nguyên nhân gốc: PC update sai thời điểm trong pipeline

### Pipeline thực tế đang hoạt động như sau

```
Cycle N:
  IF  : fetch JAL tại PC = 0x14

Cycle N+1:
  ID  : decode JAL
  IF  : PC đã tăng lên 0x18

Cycle N+2:
  EX  : tính target = 0x14 + 0 = 0x14
  IF  : PC đã là 0x1C
```

💥 **Quá muộn!**

* Khi `pc_src_ex` lên 1 → PC đã bị tăng **2 lần**
* Việc gán `pc <= target` không còn đúng thời điểm

👉 **PC đã increment trước khi JAL có hiệu lực**

---

## 4️⃣ Lỗi kiến trúc cụ thể

### ❌ PC bị update trước khi jump/branch resolve

PC update hiện tại tương đương:

```verilog
pc <= pc + 4;   // luôn chạy mỗi cycle
```

Trong khi:

* `pc_src_ex` chỉ valid **sau 2 stage**
* Không có cơ chế:

  * override PC đúng cycle
  * hoặc flush instruction sai

---

## 5️⃣ Lỗi phụ: thiếu flush pipeline

Khi JAL/branch xảy ra:

* Instruction ở `PC+4` **đã bị fetch**
* Nhưng **không bị flush**
* Dẫn tới:

  * pipeline chạy tiếp instruction sai
  * PC càng lệch thêm

👉 Đây là lỗi **control hazard chưa xử lý**

---

## 6️⃣ Immediate (imm_ex) KHÔNG phải nguyên nhân chính

Với lệnh:

```
0x0000006F  → jal x0, 0
```

* imm[20:0] = 0
* `imm_ex = 0x00000000` ✔
* `jal_target = pc_ex` ✔

➡ Immediate decode **đúng**, không phải thủ phạm

---

## 7️⃣ Nguyên nhân chính (KẾT LUẬN)

> **PC bị auto-increment trước khi tín hiệu `pc_src_ex` có hiệu lực**

Nói ngắn gọn:

❌ Jump resolve quá muộn
❌ PC không ưu tiên jump/branch
❌ Không flush IF/ID khi control-flow thay đổi

---

## 8️⃣ Cách sửa đúng (khuyến nghị)

### ✅ Fix 1: Ưu tiên jump/branch khi update PC

```verilog
always @(posedge clk) begin
    if (rst) begin
        pc <= 32'h0;
    end else if (pc_src_ex) begin
        pc <= target_pc_ex;      // ƯU TIÊN CAO NHẤT
    end else if (stall) begin
        pc <= pc;                // giữ nguyên
    end else begin
        pc <= pc + 4;
    end
end
```

---

### ✅ Fix 2: Flush IF/ID khi jump hoặc branch

```verilog
assign if_id_flush = pc_src_ex;

always @(posedge clk) begin
    if (rst || if_id_flush) begin
        instr_id <= 32'h00000013; // NOP
    end else begin
        instr_id <= instr_if;
    end
end
```

---

### ✅ Fix 3 (chuẩn kiến trúc hơn): Resolve JAL sớm ở ID stage

* JAL **không phụ thuộc ALU**
* Có thể resolve ngay ở ID

```verilog
pc <= pc_id + jal_imm;
```

➡ Giảm penalty pipeline
➡ Tránh PC bị lệch nhiều chu kỳ

---

## 9️⃣ Checklist debug nhanh (để verify)

* [ ] Khi JAL ở EX:

  * `pc_src_ex == 1`
  * `target_pc_ex` đúng
* [ ] PC update **trong cùng cycle**
* [ ] IF/ID bị flush
* [ ] `jal x0, 0` → PC đứng yên
* [ ] `jal x0, -4` → PC quay lại

---

## 🔚 Tổng kết 1 câu

> **Đây là lỗi pipeline timing: PC tăng trước khi jump/branch có hiệu lực, không phải lỗi decode hay instruction.**

