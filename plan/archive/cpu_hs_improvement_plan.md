# CPU HS Improvement Plan — riscv_cpu_core_v2.v

> Mục tiêu: đạt **High-Efficiency (HS)** — ~80–90% hiệu năng nhưng chỉ ~60% điện năng so với thiết kế thông thường.

---

## Tổng quan

| Chỉ số | Ước tính sau 4 phases |
|--------|----------------------|
| Power reduction | ~40% |
| IPC improvement | ~+15% |
| Perf/Watt gain | ~+55% |

---

## Phase 1 — Correctness (Tuần 1–2)

> **Fix trước khi optimize.** Không có ý nghĩa gì khi tối ưu một CPU có bug tiềm ẩn.

### Task 1.1 — Fix `irq_flush_done` 1-cycle
**Vấn đề:** Logic hiện tại tạo pulse chỉ 1 cycle:
```verilog
irq_flush_done_r <= irq_pending_lat & ~irq_flush_done_r;
wire irq_flush = irq_flush_done_r;
```
Nếu `irq_pending_lat` deassert sớm, flush chỉ 1 cycle — **không đủ để flush cả IF/ID lẫn ID/EX**.

**Fix:** Dùng counter 2-cycle hoặc kiểm tra từng stage rõ ràng:
```verilog
reg [1:0] irq_flush_cnt;
always @(posedge clk or posedge rst) begin
    if (rst)
        irq_flush_cnt <= 2'b00;
    else if (irq_pending && irq_flush_cnt == 2'b00)
        irq_flush_cnt <= 2'b10;
    else if (irq_flush_cnt != 2'b00)
        irq_flush_cnt <= irq_flush_cnt - 1;
end
wire irq_flush = (irq_flush_cnt != 2'b00);
```

---

### Task 1.2 — Kiểm tra conflict `lsu_result_ack` vs Multiplier WB
**Vấn đề:** ACK luôn bằng valid — WB stage có thể bị conflict khi cả `lsu_result_valid` và `is_mul_wb` đồng thời high:
```verilog
assign lsu_result_ack = lsu_result_valid;  // không có backpressure
```

**Fix:** Kiểm tra `PIPELINE_REG_MEM_WB` xử lý priority. Nếu chưa có, thêm:
```verilog
assign lsu_result_ack = lsu_result_valid & ~is_mul_wb;
```

---

### Task 1.3 — Verify MULHU / MULHSU trong `control.v`
**Vấn đề:** Multiplier chỉ decode 2 opcode:
```verilog
localparam [3:0] ALU_MUL_CODE  = 4'b1010;
localparam [3:0] ALU_MULH_CODE = 4'b1011;
// MULHU, MULHSU chưa thấy!
```
RV32IM yêu cầu đủ 4 lệnh: `MUL, MULH, MULHU, MULHSU`.

**Fix:** Mở `control.v`, kiểm tra case `funct3 == 3'b010` (MULHSU) và `funct3 == 3'b011` (MULHU). Thêm nếu thiếu và cập nhật `riscv_multiplier` để handle signed/unsigned đúng.

---

## Phase 2 — Power: WFI + Clock Gating (Tuần 3–5)

> **Đây là phase quan trọng nhất cho mục tiêu HS.** Clock gating là chìa khóa — không làm cái này thì không bao giờ đạt HS.

### Task 2.1 — Implement WFI instruction ⭐ QUAN TRỌNG NHẤT

**Tác động:** Khi CPU idle (chờ DMA, chờ interrupt), toàn bộ core domain tắt clock → tiết kiệm lớn nhất.

**Bước 1 — Decode WFI trong `control.v`:**
```verilog
// WFI: opcode=SYSTEM (7'b1110011), funct3=000, funct12=001000000101
wire is_wfi = (opcode == 7'b1110011) && (funct3 == 3'b000) && (instr[31:20] == 12'b000100000101);
```

**Bước 2 — Thêm WFI state trong `riscv_cpu_core_v2.v`:**
```verilog
reg wfi_active;
always @(posedge clk or posedge rst) begin
    if (rst)
        wfi_active <= 1'b0;
    else if (is_wfi && !stall_any)
        wfi_active <= 1'b1;
    else if (irq_pending)   // bất kỳ IRQ nào đánh thức CPU
        wfi_active <= 1'b0;
end

// WFI inject vào stall_any để freeze pipeline
assign stall_any = stall | stall_if | debug_mode | wfi_active;

// Export để SoC gate clock
assign cpu_wfi_o = wfi_active;
```

**Bước 3 — Thêm output port:**
```verilog
output wire cpu_wfi_o  // → soc_top.v để gate clk_core
```

---

### Task 2.2 — Kết nối `core_clk_en` động trong `soc_top.v`

**Hiện tại (sai):**
```verilog
.core_clk_en   (1'b1),  // hardwire = không bao giờ gate!
.periph_clk_en (1'b1),
```

**Fix — thay bằng logic động:**
```verilog
wire core_clk_en  = ~(cpu_wfi_o & ~ascon_o_busy & ~boot_done_inv);
wire periph_clk_en = uart_active | gpio_active | dma_active | timer_active;
// Fallback: giữ 1 nếu chưa có tín hiệu activity, sau đó tắt dần

clk_reset_ctrl u_clkrst (
    ...
    .core_clk_en   (core_clk_en),   // thay 1'b1
    .periph_clk_en (periph_clk_en), // thay 1'b1
    ...
);
```

---

### Task 2.3 — ASCON Clock Gate
**Vấn đề:** ASCON chạy `clk_core` liên tục kể cả khi không encrypt.

**Fix — thêm enable gated theo `ascon_o_busy`:**
```verilog
// Trong soc_top.v, thêm ICG cho ASCON:
wire ascon_clk_en = ascon_o_busy | ascon_cfg_active;
// ascon_cfg_active: CPU đang write vào S2 registers (detect từ s2_awvalid)

wire clk_ascon;
// Dùng ICG cell (FPGA: LUT + FF; ASIC: native ICG cell)
assign clk_ascon = clk_core & ascon_clk_en;

ascon_ip_top u_ascon (
    .clk  (clk_ascon),  // thay clk_core
    ...
);
```

---

### Task 2.4 — `periph_clk_en` động
```verilog
// Activity detection từ AXI valid signals
wire uart_active  = s5_awvalid | s5_arvalid | uart_irq;
wire gpio_active  = s6_awvalid | s6_arvalid | gpio_irq;
wire dma_active   = s11_awvalid | s11_arvalid | dma_irq | (m3_arvalid | m3_awvalid);
wire timer_active = s8_awvalid | s8_arvalid | timer0_irq | timer1_irq | wdt_irq;

wire periph_clk_en = uart_active | gpio_active | dma_active | timer_active;
```

---

## Phase 3 — Performance: IPC + Timing (Tuần 5–8)

### Task 3.1 — Nâng Branch Predictor lên 2-bit Saturating Counter
**Hiện tại:** Static prediction — backward branch → predict taken.

**Tác động:** +5% IPC ước tính (giảm flush pipeline cho vòng lặp lồng nhau).

**Implement:**
```verilog
// Thêm vào IFU hoặc hazard_detection:
reg [1:0] bht [0:255];  // 256-entry Branch History Table

wire [7:0] bht_idx = pc_id[9:2];  // index bằng PC[9:2]
wire [1:0] bht_state = bht[bht_idx];

// Predict taken khi state >= 2'b10 (weakly/strongly taken)
assign predict_taken_id = branch_id && (bht_state[1]) && !stall_any;

// Update BHT sau khi biết kết quả thực tế ở EX:
always @(posedge clk) begin
    if (branch_ex) begin
        if (branch_taken_ex)
            bht[bht_idx_ex] <= (bht[bht_idx_ex] == 2'b11) ? 2'b11 : bht[bht_idx_ex] + 1;
        else
            bht[bht_idx_ex] <= (bht[bht_idx_ex] == 2'b00) ? 2'b00 : bht[bht_idx_ex] - 1;
    end
end
```

---

### Task 3.2 — SDC Constraint cho `stall_any`
**Vấn đề:** `stall_any` fan-out ~15 FF, không có buffer thực sự.

**Thêm vào file SDC:**
```tcl
# stall_any high-fanout constraint
set_max_fanout 8 [get_nets stall_any]
set_dont_touch [get_nets stall_any]

# Hoặc dùng buffer insertion (DC Ultra / Genus):
set_optimize_registers true -designs riscv_cpu_core
```

**Cho Xilinx FPGA — thêm attribute trong Verilog:**
```verilog
(* KEEP = "TRUE" *) wire stall_any = stall | stall_if | debug_mode | wfi_active;
```

---

### Task 3.3 — Verify CDC M2 vs M3 tại Crossbar
**Vấn đề:** M2 (ASCON DMA) chạy `clk_core`, M3 (DMA Ctrl) chạy `clk_periph` — cùng access `axi4_crossbar_5m12s`.

**Checklist:**
- [ ] Kiểm tra `axi4_crossbar_5m12s.v` có synchronizer cho từng master port không
- [ ] Nếu crossbar là single-clock design → thêm 2-FF synchronizer cho VALID/READY của M2 và M3
- [ ] Dùng tool CDC check (Synopsys SpyGlass, Mentor Questa CDC) nếu có

---

### Task 3.4 — Giảm Load-Use Stall
**Hiện tại:** Load-use hazard gây 1 bubble cycle bắt buộc.

**Cải tiến:** Kiểm tra xem có thể overlap với non-dependent instruction không (out-of-order lite). Với pipeline in-order, giải pháp đơn giản hơn là đảm bảo compiler reorder instruction — thêm hint cho GCC:
```c
// Trong firmware: dùng __builtin_expect và manual reorder
// Hoặc compile với -O2 để GCC tự schedule load trước khi dùng
```

---

## Phase 4 — Measurement (Song song & Cuối)

> **Không đo = không biết mình có HS không.** Chạy song song từ Phase 1.

### Task 4.1 — Testbench đo IPC
```verilog
// Thêm vào testbench:
integer cycle_count = 0;
integer instr_count = 0;

always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    // Đếm instruction committed (WB stage, không phải flush)
    if (regwrite_wb && !flush_id_ex_final)
        instr_count <= instr_count + 1;
end

// In ra cuối sim:
// IPC = instr_count / cycle_count
// Stall rate = (cycle_count - instr_count) / cycle_count
```

### Task 4.2 — Dump VCD để estimate Power
```verilog
// Trong testbench:
initial begin
    $dumpfile("soc_power.vcd");
    $dumpvars(0, soc_top);  // dump toàn bộ hierarchy
end
// Sau đó dùng:
// Vivado: Report Power với VCD
// Quartus: PowerPlay với VCD
// ASIC: PrimeTime PX với SAIF convert từ VCD
```

### Task 4.3 — Benchmark đo Perf/Watt
Chạy 3 scenario và đo power từng loại:

| Scenario | Mô tả | Metric |
|----------|-------|--------|
| ASCON loop | Encrypt 1KB liên tục | Power khi compute |
| memcpy | Copy 4KB SRAM→SRAM qua DMA | Bus efficiency |
| WFI idle | CPU sleep, chờ timer IRQ | Leakage / idle power |

**Công thức:**
```
Perf/Watt = (throughput MB/s) / (avg_power_mW)
Target HS: Perf/Watt > 1.5× so với baseline (trước optimize)
```

---

## Checklist tổng

### Phase 1 — Correctness
- [ ] Fix `irq_flush` 2-cycle
- [ ] Fix `lsu_result_ack` conflict với multiplier
- [ ] Verify MULHU/MULHSU trong `control.v`

### Phase 2 — Power
- [ ] Thêm WFI decode + `cpu_wfi_o` output port
- [ ] Thay `core_clk_en(1'b1)` → dynamic trong `soc_top.v`
- [ ] Thêm `ascon_clk_en` gated theo `ascon_o_busy`
- [ ] Thêm `periph_clk_en` động từ AXI activity signals

### Phase 3 — Performance
- [ ] Nâng branch predictor lên 2-bit BHT 256-entry
- [ ] Thêm SDC constraint cho `stall_any`
- [ ] Verify CDC M2/M3 tại crossbar
- [ ] Review load-use stall, phối hợp compiler scheduling

### Phase 4 — Measurement
- [ ] Testbench đo IPC + stall rate
- [ ] VCD dump + power report
- [ ] Benchmark ASCON/memcpy/WFI — đo Perf/Watt baseline và sau optimize

---

## Kiến trúc mục tiêu sau optimize

```
+---------------------------+
|   RISC-V 5-stage CPU      |
|   + WFI → cpu_wfi_o       |
|   (clk gated khi idle)    |
+-----------+---------------+
            |
        AXI4 Bus (clk_core / clk_periph tách biệt)
            |
  +---------+-----------+
  |                     |
+------+          +------------------+
| SRAM |<--DMA--->| ASCON            |
| local|          | (clk_ascon gated)|
+------+          +------------------+
```

**Nguyên tắc HS:**
1. **Không chạy khi không cần** → WFI + clock gating
2. **Offload tối đa** → ASCON + DMA, CPU chỉ config + trigger
3. **Giảm memory access** → ICache + DCache đã có
4. **Burst thay vì lẻ tẻ** → AXI4 burst cho DMA

---

*Generated from riscv_cpu_core_v2.v + soc_top.v analysis*
