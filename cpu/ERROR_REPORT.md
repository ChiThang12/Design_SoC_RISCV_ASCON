# RISC-V SoC Test Report - Kết quả Testbench

## Tóm tắt
- **Tổng số tests**: 5
- **Passed**: 3 ✓
- **Failed**: 2 ✗

---

## Kết quả Chi tiết

### ✓ Test 1: ALU Operations & Forwarding - **PASS**
- Các phép toán ALU cơ bản hoạt động bình thường
- Forwarding logic hoạt động đúng

### ✓ Test 2: Branch & Control Flow - **PASS**
- Các lệnh branch (BEQ, BNE) hoạt động đúng
- Jump logic (JAL) hoạt động đúng

### ✓ Test 3: Memory Store & Load Word (32-bit) - **PASS**
- Word store/load (4 byte) hoạt động bình thường
- Verified: DMEM[0x10000000] = 0x0000001e ✓

### ✗ Test 4: Byte & Halfword Access - **FAIL** 
**Vấn đề quan trọng:** Lệnh halfword (SH) bị lỗi

**Dấu hiệu lỗi:**
```
[DMEM WRITE] addr=0x10000000, data=0x000000ff, strb=0001, size=0, time=2415000  ✓ (OK)
[DMEM WRITE] addr=0x10000002, data=0x000000ff, strb=1111, size=2, time=2525000  ✗ (WRONG!)
```

**Chi tiết vấn đề:**
1. **Halfword Write sai WSTRB**: SH (Store Halfword) tại địa chỉ 0x10000002 phải có `strb=0011`, nhưng lại gửi `strb=1111` (như word)
2. **Lặp lại vô hạn**: Instruction SH được execute lặp lại 17 lần liên tiếp thay vì 1 lần
3. **PC bị stuck**: PC = 0x14, không tiến tới instruction tiếp theo (0x24)
4. **Timeout**: Test timeout sau 150 cycles

### ✗ Test 5: Comprehensive - **FAIL**
**Nguyên nhân:** Vấn đề từ Test 4 (halfword operations)
```
[INTERCONNECT] Read addr=0x00000000 -> Slave 0, time=4685000
[INTERCONNECT] Read addr=0x00000000 -> Slave 0, time=4755000
...
Lặp lại 17+ lần, PC bị stuck tại 0x24
```

---

## Root Cause Analysis (Chi tiết)

### 🔴 **Lỗi Chính: WSTRB Generation sai cho Halfword**

**Vị trí chính xác:**
- File: [datapath.v](datapath.v#L440-L470)
- Dòng: 450-461
- Hàm: `byte_strobe` combinational logic

**Mã hiện tại (SAI):**
```verilog
always @(*) begin
    if (memwrite_mem) begin
        case (byte_size_mem)
            2'b00: begin  // Byte
                case (alu_result_mem[1:0])
                    2'b00: byte_strobe = 4'b0001;
                    2'b01: byte_strobe = 4'b0010;
                    2'b10: byte_strobe = 4'b0100;
                    2'b11: byte_strobe = 4'b1000;
                endcase
            end
            2'b01: begin  // Halfword - CORRECT!
                case (alu_result_mem[1:0])
                    2'b00: byte_strobe = 4'b0011;
                    2'b10: byte_strobe = 4'b1100;
                    default: byte_strobe = 4'b0011;  // ❌ LỖI: mặc định cho 0x01, 0x11, 0x12, 0x13
                endcase
            end
            2'b10: byte_strobe = 4'b1111;  // Word - OK
            default: byte_strobe = 4'b1111;  // ❌ Default là word, sai!
        endcase
    end else begin
        byte_strobe = 4'b1111;  // ❌ CRITICAL BUG! Khi đọc, vẫn gửi 1111
    end
end
```

**Vấn đề chi tiết:**

1. **Default case cho halfword (line 454):**
   - Khi `alu_result_mem[1:0] = 2'b01` (địa chỉ lẻ): gửi `0011` thay vì `1100`
   - Khi `alu_result_mem[1:0] = 2'b11` (địa chỉ lẻ): gửi `0011` thay vì `1100`

2. **Default case chính (line 457):**
   - Khi `byte_size_mem` không xác định: mặc định gửi `1111` (word)

3. **Khi NOT writing (line 461):**
   - Khi `memwrite_mem = 0` (READ operation), vẫn gửi `WSTRB=1111`
   - Điều này không ảnh hưởng data_mem_axi_slave vì không có ghi, nhưng logic không sạch

**Expected vs Actual:**
```
SH x1, 2(x2) tại địa chỉ 0x10000002 (offset [1:0] = 10)
Expected: byte_size_mem=2'b01, addr[1:0]=2'b10 → WSTRB = 1100
Actual:   Gửi WSTRB = 0011 (sai phương hướng!)

Kết quả: Dữ liệu được ghi vào bytes [1:0] thay vì [3:2]
```

### 🔴 **Lỗi Phụ: Write State Machine bị stuck**

**Triệu chứng từ Test 4:**
```
[DMEM WRITE] addr=0x10000002, data=0x000000ff, strb=0011, size=1, time=2525000
[DMEM WRITE] addr=0x10000002, data=0x000000ff, strb=0011, size=1, time=2595000
... (lặp 17 lần)
```

**Nguyên nhân:**
1. WSTRB sai → data_mem_axi_slave write không đúng
2. Nhưng do là AXI handshake issue, state machine có thể stuck
3. PC không tiến tới instruction tiếp theo

**Chi tiết flow:**
```
1. SH instruction fetch → byte_size_mem = 2'b01
2. Generate WSTRB sai (0011 thay vì 1100)
3. data_mem_axi_slave nhận write với sai WSTRB
4. Pipeline sẽ stall, chờ write complete
5. Nếu write logic có issue → stuck ở đó
```

---

## Các File cần sửa

### Priority 1 (Critical):
1. **`interface/mem_access_unit.v`** - WSTRB generation cho byte/halfword
   - Kiểm tra logic WSTRB dựa vào mem_size và address[1:0]
   
2. **`memory/data_mem_axi_slave.v`** - Có thể có vấn đề với state machine
   - Kiểm tra WR_DATA state khi S_AXI_WVALID không ổn định
   - Có thể cần timeout/error detection

### Priority 2 (Important):
3. **`core/mem_access_unit.v`** hoặc tương tự - Kiểm tra memory request generation

---

## Khuyến nghị sửa chữa

1. **Xác minh WSTRB generation:**
   ```verilog
   // Pseudocode cho mem_access_unit.v
   case({mem_size, mem_addr[1:0]})
       {SIZE_BYTE, 2'b00}: WSTRB = 4'b0001;
       {SIZE_BYTE, 2'b01}: WSTRB = 4'b0010;
       {SIZE_BYTE, 2'b10}: WSTRB = 4'b0100;
       {SIZE_BYTE, 2'b11}: WSTRB = 4'b1000;
       {SIZE_HALF, 2'b00}: WSTRB = 4'b0011;
       {SIZE_HALF, 2'b10}: WSTRB = 4'b1100;
       {SIZE_WORD, 2'b00}: WSTRB = 4'b1111;
   endcase
   ```

2. **Thêm error detection:**
   - Timeout counter cho stuck instruction
   - Monitor WVALID/WREADY toggle để detect deadlock

3. **Debug steps:**
   - Chạy simulation riêng cho test 4 với verbose mode bật
   - Kiểm tra waveform tại SH instruction
   - Trace AXI signals (AWADDR, WSTRB, WVALID, WREADY)

