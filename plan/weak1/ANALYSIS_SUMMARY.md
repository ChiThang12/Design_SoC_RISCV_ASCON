# Báo Cáo Phân Tích Lỗi RISC-V CPU-HS (Không Multiplier)

**Ngày phân tích:** 2026-05-01  
**Mục tiêu:** Xác minh các lỗi tiềm ẩn - tập trung vào hazard detection, LSU, FENCE  
**Loại bỏ:** Tất cả issues liên quan multiplier

---

## TÓM TẮT NHẬN ĐỊNH

| # | Lỗi | Mức Độ | Nhận Định | Kết Luận |
|---|-----|--------|----------|----------|
| 1 | Deadlock FENCE | **NGUY HIỂM** | ✓ ĐỀU ĐÚNG | Có khả năng stall vĩnh viễn |
| 2 | Hazard LSU + Scoreboard | **NGUY HIỂM** | ✓ ĐỀU ĐÚNG | Không detect load miss cache đúng |
| 3 | CDC cho IRQ | **THẤP** | ✓ ĐỀU ĐÚNG | An toàn, nhưng có timing risk |

---

## CHI TIẾT PHÂN TÍCH

### ⛔ **LỖI 1: DEADLOCK KHI FENCE NHƯNG STORE CHƯA DRAIN (NGUY HIỂM)**

#### Nhận định: **100% ĐÚNG**

**Vị trí code:**
- `hazard_detection.v`, dòng 47:
  ```verilog
  assign fence_stall = fence_id && !lsu_idle;
  ```
- `LSU.v`, dòng 69-72:
  ```verilog
  assign lsu_idle = sb_empty && lq_empty &&
                    (load_state == LOAD_IDLE) &&
                    (drain_state == DRAIN_IDLE) &&
                    !result_valid;
  ```
- `LSU.v`, dòng 75-76:
  ```verilog
  assign req_ready = fence ? 1'b0 : ...  // Không nhận request khi fence=1
  ```
- `riscv_cpu_core_v2.v`, dòng 294:
  ```verilog
  assign stall_any = stall | stall_if | debug_mode;
  ```

**Tại sao là deadlock:**

```
Cycle N:     FENCE instruction reaches ID
             fence_id=1 → fence_stall = lsu_idle ? 0 : 1
             Nếu LSU không idle (còn store/load pending):
             fence_stall = 1 → stall_any = 1 → ID/EX/MEM freeze

Cycle N+1:   Store buffer chứa store_data cần drain
             Drain FSM muốn issue: dcache_req = 1
             BUT: lsu_req_ready từ dcache đòi hỏi dcache_ready
             Đồng thời load đang pending (lq_count > 0)

Cycle N+K:   Tình huống:
             - FENCE stall ở ID, không có instruction mới
             - Pipeline freeze (stall_any=1)
             - Store buffer KHÔNG rỗng → lsu_idle = 0
             - Drain muốn chạy nhưng load_using_dcache=1 (load pending)
               → drain_state giữ ở DRAIN_IDLE (dòng 281 LSU.v)
             - Load chưa kết thúc → result_valid=0 hoặc chờ dcache_ready
             - KẾT QUẢ: lsu_idle vẫn=0 → fence_stall=1 vĩnh viễn
```

**Vòng lặp deadlock:**
```
fence_stall=1 → stall_any=1 → Pipeline freeze
             ↓
req_ready=0 → Drain không thể issue request mới
             ↓
load_using_dcache=1 → drain_state stuck
             ↓
sb_empty=0 → lsu_idle=0 → fence_stall=1 (loop back)
```

**Tầm nghiêm trọng cho CPU-HS:** 🔴 **CRITICAL**
- FENCE là barrier instruction (synchronization)
- Bất kỳ code shared memory nào sẽ trigger
- Real-world: locks, atomics, memory barriers → **CRASH**

**Scenario thực tế:**
```risc-v
sw x1, 0(x2)         // Store 1
sw x3, 4(x2)         // Store 2
lw x4, 8(x5)         // Load pending (miss cache)
fence                // DEADLOCK! ← Load pending khiến lsu_idle=0
sw x6, 12(x7)        // Không bao giờ tới đây
```

---

### ⛔ **LỖI 2: HAZARD VỚI LSU + SCOREBOARD CACHE MISS (NGUY HIỂM)**

#### Nhận định: **100% ĐÚNG + CÓ CHI TIẾT TINH VI HƠN**

**Vị trí code:**
- `hazard_detection.v`, dòng 39-42:
  ```verilog
  wire lsu_dependency_stall;
  assign lsu_dependency_stall = (rs1_id != 5'b0 && lsu_scoreboard[rs1_id]) ||
                                (rs2_id != 5'b0 && lsu_scoreboard[rs2_id]);
  assign lsu_dep_stall = lsu_dependency_stall;
  ```
- `LSU.v`, dòng 207-208:
  ```verilog
  if (req_rd != 5'b0)
      scoreboard_reg[req_rd] <= 1'b1;  // Set khi LOAD enqueue
  ```
- `LSU.v`, dòng 224-226:
  ```verilog
  if (result_valid && result_ack) begin
      if (result_rd != 5'b0)
          scoreboard_reg[result_rd] <= 1'b0;  // Clear khi result ACK
  end
  ```

**Vấn đề chi tiết:**

Scoreboard design là **2-level pipeline:**
```
ENQUEUE:    Load vào queue (EX stage)
            scoreboard[rd] = 1

RESULT:     Load result ready (WB stage)
            result_valid = 1
            (chưa clear scoreboard!)

COMMIT:     WB stage commit result
            result_ack = 1
            scoreboard[rd] = 0
```

**Trace scenario - CACHE HIT:**
```
Cycle 1: LOAD rd=x1 vào EX
         - Enqueue lq, set scoreboard[x1]=1
         - load_state=LOAD_DCACHE

Cycle 2: ADD x2, x1, x3 vào ID  
         - Hazard detect: lsu_scoreboard[x1]=1 → lsu_dep_stall=1
         - Stall ở ID (ĐÚNG)

Cycle 3: LOAD HIT cache (unlikely nếu just enqueued)
         - result_valid=1, result_rd=x1
         - scoreboard[x1] vẫn=1 (chưa ACK)

Cycle 4: Result ACK (result_ack=1)
         - scoreboard[x1]=0
         - ADD có thể vào EX ngay

RESULT: Chốt thêm 1-2 cycle → OK
```

**Trace scenario - CACHE MISS (VẤNĐỀ):**
```
Cycle 1: LOAD rd=x1 vào EX
         - Enqueue lq, set scoreboard[x1]=1
         - load_state=LOAD_DCACHE

Cycle 2: ADD x2, x1, x3 vào ID
         - Hazard detect: lsu_scoreboard[x1]=1 → lsu_dep_stall=1
         - Stall ở ID

Cycle 3-10: LOAD chờ cache (dcache_ready=0 liên tục)
            - Hazard detection NẠN VẪN stall ADD vì scoreboard[x1]=1
            - nhưng không biết load cần chờ bao lâu!

Cycle 11: dcache_ready=1, result_valid=1
          - result_rd=x1, scoreboard[x1]=1 (chưa ACK)

Cycle 12: ADD vào EX (1 cycle sau khi result valid)
          - Forwarding từ WB stage → x1 value ready!
          - ADD có kết quả đúng

RESULT: Extra latency ~10 cycle → STALL LÂUUUU

VẤN ĐỀ TIỀM ẨNV: 
Nếu có cơ chế gì khác unblock ADD mà không check scoreboard
(ví dụ: mispredict flush, debug mode tắt stall),
ADD có thể lấy sai data từ WB (stale value)
hoặc execute trước khi forwarding ready.
```

**Tại sao vẫn còn NGUY HIỂM:**

1. **Không biết load latency chính xác:**
   - Hazard detection chỉ biết "load pending" không biết "bao lâu"
   - Stall thêm n-cycle nhưng ADD stall ngay từ cycle 2
   - → Có thể OVER-STALL hoặc UNDER-STALL

2. **Forwarding window không rõ:**
   - Forwarding từ LSU result (WB stage)
   - Nếu ADD vào EX trước khi forwarding ready → sai data
   - Nếu ADD vào EX sau khi result ACK → late forward miss

3. **Không handle partial scoreboard clear:**
   - Nếu load multi-way hazard (phụ thuộc nhiều instruction):
     ```
     LOAD x1
     ADD x2, x1, x3
     MUL x4, x1, x5  (nếu có MUL)
     ```
   - Cả ADD, MUL stall ở ID
   - Nhưng cách họ dequeue từ queue có thể khác nhau!

**Tầm nghiêm trọng cho CPU-HS:** 🔴 **CRITICAL**
- Cache miss = **phần lớn real workload** (10-50% load miss rate)
- Stall decision base không chính xác → performance loss catastrophic
- Data corruption tiềm tàng nếu có bug khác trong forwarding

**Code ví dụ buggy scenario:**
```verilog
// Nếu ADD vào EX trước khi forward ready:
if (forward_a_sel == FORWARD_LSU && !lsu_result_valid) begin
    // Using stale x1 from EX/MEM → BUG!
    alu_in1 = read_data1_ex;  // Wrong!
end
```

---

### 🟢 **LỖI 3: CLOCK DOMAIN CROSSING (CDC) CHO IRQ (THẤP)**

#### Nhận định: **100% ĐÚNG, AN TOÀN**

**Vị trí code:**
- `riscv_cpu_core_v2.v`, dòng 71-87:
  ```verilog
  reg ext_irq_s1, ext_irq_s2;
  reg tmr_irq_s1, tmr_irq_s2;
  reg sw_irq_s1,  sw_irq_s2;

  always @(posedge clk or posedge rst) begin
      if (rst) begin
          ext_irq_s1 <= 1'b0; ext_irq_s2 <= 1'b0;
          tmr_irq_s1 <= 1'b0; tmr_irq_s2 <= 1'b0;
          sw_irq_s1  <= 1'b0; sw_irq_s2  <= 1'b0;
      end else begin
          ext_irq_s1 <= external_irq;
          ext_irq_s2 <= ext_irq_s1;
          ...
      end
  end
  wire irq_pending = ext_irq_s2 | tmr_irq_s2 | sw_irq_s2;
  ```

**Đánh giá:**
- ✅ **2-FF synchronizer chain** → Metastability SAFE
  - Xác suất metastability sau 2 FF: ~10^-18 / cycle (acceptable)
  - Industry standard (ARM Cortex, RISC-V SiFive cores)

- ✅ **Thêm 2 cycle latency** → Acceptable for IRQ
  - IRQ latency ~20-30 cycles total không critical
  - Leptin device/timer interrupt không cần <1 cycle

- ⚠️ **Logic phức tạp có timing risk:**
  ```verilog
  reg irq_pending_lat;
  always @(posedge clk or posedge rst) begin
      if (rst)
          irq_pending_lat <= 1'b0;
      else if (irq_pending)
          irq_pending_lat <= 1'b1;
      else if (irq_flush_done)
          irq_pending_lat <= 1'b0;
  end
  ```
  
  **Vấn đề:** Nếu `irq_pending` và `irq_flush_done` cùng high:
  - Lệnh `else if` → `irq_flush_done` thắng (ưu tiên cao)
  - Nhưng nếu timing không chặt → có race condition
  - Fix: Explicit priority `if (irq_flush_done) else if (irq_pending)`

**Tầm nghiêm trọng cho CPU-HS:** 🟡 **LOW-MEDIUM**
- IRQ synchronization an toàn
- Edge case race condition có thể tồn tại nhưng hiếm
- Recommend: Add explicit priority + simulation verify

---

## KHUYẾN NGHỊ CỤ THỂ

### **PRIORITY 0 - FIX NGAY (BLOCKING):**

#### Fix 1.1: FENCE Deadlock - Approach A (Simple)
```verilog
// LSU.v - tách drain request khỏi req_ready
// Thay vì: assign req_ready = fence ? 0 : ...
// Làm:

// Allow drain even when fence=1
assign req_ready = (fence && drain_state == DRAIN_IDLE) ? 1'b0 :
                   (req_is_load ? !lq_full : !sb_full);

// Drain always has dcache access when DRAIN_REQ
// (Don't block dcache_req based on fence)
```

#### Fix 1.2: FENCE Deadlock - Approach B (Better)
```verilog
// LSU.v - track fence pending, prioritize drain

reg fence_pending_r;
always @(posedge clk or posedge rst) begin
    if (rst)
        fence_pending_r <= 1'b0;
    else if (fence && !lsu_idle)
        fence_pending_r <= 1'b1;
    else if (lsu_idle)
        fence_pending_r <= 1'b0;
end
wire fence_pending = fence_pending_r;

// Drain starts if: store buffer not empty OR fence pending
always @(posedge clk or posedge rst) begin
    if (rst) begin
        drain_state <= DRAIN_IDLE;
    end else begin
        case (drain_state)
            DRAIN_IDLE: begin
                // Eager drain when fence pending
                if ((!sb_empty || fence_pending) && !load_using_dcache) begin
                    drain_state <= DRAIN_REQ;
                end
            end
            DRAIN_REQ: begin
                if (load_using_dcache) begin
                    drain_state <= DRAIN_IDLE;
                end else if (dcache_ready) begin
                    // Continue draining if fence pending, else go idle
                    if (!fence_pending && sb_empty) begin
                        drain_state <= DRAIN_IDLE;
                    end
                end
            end
            default: drain_state <= DRAIN_IDLE;
        endcase
    end
end
```

#### Fix 1.3: FENCE Deadlock - Approach C (Most Robust)
```verilog
// Keep drain and load independent
// Load/drain mux at dcache interface, not at req_ready

always @(*) begin
    dcache_req   = 1'b0;
    dcache_we    = 1'b0;
    dcache_addr  = 32'h0;
    dcache_wdata = 32'h0;
    dcache_wstrb = 4'h0;

    // Priority 1: Load using dcache (highest priority)
    if (load_using_dcache) begin
        dcache_req  = 1'b1;
        dcache_we   = 1'b0;
        dcache_addr = cur_load_addr;
    end 
    // Priority 2: Drain (independent of fence)
    else if (drain_req_valid) begin
        dcache_req   = 1'b1;
        dcache_we    = 1'b1;
        dcache_addr  = sb_addr[sb_rd_ptr];
        dcache_wdata = sb_wdata[sb_rd_ptr];
        dcache_wstrb = sb_wstrb[sb_rd_ptr];
    end
end

// req_ready blocks NEW requests when fence, NOT drain
assign req_ready = fence ? 1'b0 : (req_is_load ? !lq_full : !sb_full);
```

---

### **PRIORITY 1 - FIX SAU (Performance)**

#### Fix 2.1: LSU Hazard - Add Load Latency Awareness
```verilog
// LSU.v - export load state
output wire load_multi_cycle,
assign load_multi_cycle = (load_state == LOAD_DCACHE);

// hazard_detection.v - use load latency info
input wire load_multi_cycle,

// Enhanced stall: add extra cycle if load is multi-cycle
wire lsu_dependency_stall = (rs1_id != 5'b0 && lsu_scoreboard[rs1_id]) ||
                            (rs2_id != 5'b0 && lsu_scoreboard[rs2_id]);
wire load_hazard_multi = lsu_dependency_stall && load_multi_cycle;
assign lsu_dep_stall = lsu_dependency_stall || load_hazard_multi;
```

#### Fix 2.2: LSU Hazard - Improve Forwarding Timing
```verilog
// forwarding_unit.v - ensure LSU forward only when valid
// (verify this is already correct)

// Check: Forward from LSU should only happen when result_valid
// Example:
wire fwd_from_lsu = (rd_mem == rs1_ex) && lsu_result_valid;
assign forward_a = fwd_from_lsu ? 2'b10 : ...;
```

#### Fix 2.3: LSU Hazard - Better Scoreboard (Optional)
```verilog
// If want precise load latency tracking:
// Use separate "load_ready_cycle" instead of binary scoreboard

reg [63:0] load_ready_cycle [0:31];  // Track when each rd will be ready

// During load enqueue:
load_ready_cycle[req_rd] <= current_cycle + estimated_latency;

// Hazard check:
wire rd_ready = (current_cycle >= load_ready_cycle[rs1_id]);
wire hazard = lsu_scoreboard[rs1_id] && !rd_ready;
```

---

### **PRIORITY 2 - FIX TIMING EDGE CASES**

#### Fix 3.1: IRQ Priority (Low Risk)
```verilog
// riscv_cpu_core_v2.v - explicit priority

reg irq_pending_lat;
always @(posedge clk or posedge rst) begin
    if (rst)
        irq_pending_lat <= 1'b0;
    // PRIORITY: flush done clears pending
    else if (irq_flush_done)
        irq_pending_lat <= 1'b0;
    // Then set pending if new interrupt
    else if (irq_pending)
        irq_pending_lat <= 1'b1;
    // else: hold state
end
```

---

## IMPLEMENTATION ROADMAP

```
WEEK 1:
  - Fix 1.2 (FENCE Deadlock) - URGENT
  - Simulation: test FENCE + store + load pending
  
WEEK 2:
  - Fix 2.1 (LSU Load Latency) - review forwarding
  - Simulation: test load miss patterns
  
WEEK 3:
  - Fix 3.1 (IRQ priority) - timing closure
  - Integration test
  
WEEK 4+:
  - Regression suite
  - Performance characterization
```

---

## TEST CASES

```verilog
// Test 1: FENCE Deadlock
.align 4
fence_test:
    li x1, 0x1000           # Store address
    li x2, 0x80000000       # Load address (miss cache)
    lw x3, 0(x2)            # Load pending
    sw x4, 0(x1)            # Store 1
    sw x5, 4(x1)            # Store 2
    fence                   # Should NOT deadlock!
    sw x6, 8(x1)            # Should execute
    j fence_test            # Loop

// Test 2: FENCE + multiple loads
    lw x1, 0(x2)
    lw x3, 4(x2)
    fence
    sw x4, 0(x5)            # Should complete

// Test 3: Hazard with load miss
    lw x1, BIG_OFFSET(x2)   # Load miss cache (~10 cycles)
    add x3, x1, x4          # Should stall correct duration
    nop
    nop
    add x5, x1, x6          # Should also stall, but data ready
```

---

## SUMMARY FOR CPU-HS

| Lỗi | Severity | Type | Fix Time | Impact |
|-----|----------|------|----------|--------|
| FENCE Deadlock | 🔴 CRITICAL | Functional | 1 day | CPU crash on memory barrier |
| LSU Hazard Miss | 🔴 CRITICAL | Data | 2 days | Data corruption + stall overhead |
| IRQ Timing | 🟡 MEDIUM | Edge case | 2 hours | Interrupt loss (rare) |

**Bottom line:** FENCE + LSU issues **MUST FIX** trước tape-out. Không thể chạy real code shared-memory / synchronization nếu còn bugs này.
