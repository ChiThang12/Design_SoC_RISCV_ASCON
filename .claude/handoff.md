# Handoff Log

---

## 2026-05-07 Session Summary

### Mục tiêu sprint
Xác minh UART, GPIO, DMA hoạt động đúng trong simulation SoC full-chip.
Testbench: `run_soc_periph.v`. Firmware test: `gnu_toolchain/tests/test_uart_simple.c`.

---

### Đã làm (COMPLETED)

1. **Tăng TIMEOUT và halt-delay trong testbench**
   - `run_soc_periph.v`: `` `define TIMEOUT 900000 `` (từ 500K)
   - halt detection delay: `#(CLK_PERIOD * 350000)` (từ 2 cycle) để UART TX FIFO drain hết
   - Áp dụng tương tự cho 2-CYCLE và 4-CYCLE loop detectors

2. **Fix UART-W logger**
   - `run_soc_periph.v` line ~523: đổi `if (s5_wvalid)` → `if (s5_wvalid && s5_wready)` để chỉ log khi handshake thực sự xảy ra

3. **Fix program.hex sai**
   - `memory/program.hex` ban đầu chứa firmware DMA cũ (khác test_uart_simple)
   - Fix: copy `gnu_toolchain/tests/test_uart_simple_O1.hex` → `memory/program.hex`
   - Dấu hiệu nhận ra: output 'H' (0x48) thay vì 'U', và có DMA activity

4. **Thêm nc_just_completed fix vào dcache_controller.v**
   - Thêm `reg nc_just_completed;`
   - Default clear mỗi cycle: `nc_just_completed <= 1'b0;`
   - Set = 1 khi NC_WRITE hoàn thành: `if (evict_done) nc_just_completed <= 1'b1;`
   - Guard trong IDLE combinational: `!nc_just_completed`
   - Guard trong IDLE sequential output: `!nc_just_completed`
   - **Kết quả: Fix đã apply nhưng KHÔNG fix được bug**

---

### Bug đang còn: UART TX duplicate character

#### Triệu chứng
- Mỗi ký tự được ghi 2 lần lên UART TX
- Ví dụ: `uart_putc('U')` → AXI write 'U' lần 1 tại cycle 4138, lần 2 tại cycle 4145 (7 cycle sau)
- Kết quả: nhận 26 byte thay vì 29 byte → `[PASS] uart_simple` không được nhận đủ → `[PASS] count = 0`

#### Kiến trúc liên quan
```
CPU (SW 'U') → LSU Store Buffer (SB) → drain_state machine → dcache_req
→ dcache_controller (IDLE → NC_WRITE) → evict_engine (AXI AW/W/B) → UART
```

**LSU drain state machine** (`cpu/core/LSU.v` line 282-327):
```verilog
// drain_state: DRAIN_IDLE(0) → DRAIN_REQ(1) khi !sb_empty
// dcache_req COMBINATIONAL từ drain_state == DRAIN_REQ
// do_drain_pop khi drain_state==DRAIN_REQ && dcache_ready && !load_using_dcache
```

**dcache_controller NC path** (`cache_interface/dcache/dcache_controller.v`):
```
IDLE (cpu_req, addr_is_nc, cpu_we) → NC_WRITE → (evict_done) → IDLE
cpu_ready = 1 khi evict_done=1 trong NC_WRITE state (combinational)
```

**evict_engine** (`cache_interface/dcache/dcache_axi_interface.v`):
- `evict_done` là 1-cycle PULSE (registered, set trong EV_B khi BVALID&&BREADY, clear bởi default)
- AXI sequence: evict_start → EV_IDLE → EV_AW → EV_W → EV_B → evict_done=1

#### nc_just_completed fix đang có (nhưng không work)
```verilog
// dcache_controller.v line 550: default clear
nc_just_completed  <= 1'b0;
// line 601: guard trong sequential IDLE
if (cpu_req && !fence_any && !nc_just_completed) begin
// line 299: guard trong combinational IDLE
if (!flush_busy && cpu_req && !fence_any && !nc_just_completed) begin
// line 756: set khi NC_WRITE done
DCACHE_STATE_NC_WRITE: begin
    if (evict_done) nc_just_completed <= 1'b1;
end
```

#### 3 hypothesis về nguyên nhân (chưa xác nhận)

**Hypothesis 1 — flush_busy=1 khi evict_done fires (MOST LIKELY)**
- `uart_putc` dùng inline asm có `fence w, w` sau SW instruction
- FENCE kích hoạt flush FSM trong dcache_controller → `flush_busy=1`
- Sequential output block có `if (!flush_busy) begin ... end` bao quanh tất cả
- Nếu flush_busy=1 khi evict_done fires → `nc_just_completed <= 1'b1` bị SKIP
- → nc_just_completed vẫn=0 → IDLE case mở → second NC_WRITE fire khi flush xong

```verilog
// Vấn đề: nc_just_completed set nằm trong if (!flush_busy)
if (!flush_busy) begin
    case (state)
        DCACHE_STATE_NC_WRITE: begin
            if (evict_done) nc_just_completed <= 1'b1;  // SKIPPED khi flush_busy=1!
        end
    endcase
end
```

**Fix cho H1**: Move nc_just_completed ra NGOÀI `if (!flush_busy)`:
```verilog
// NGOÀI if (!flush_busy):
if (state == DCACHE_STATE_NC_WRITE && evict_done)
    nc_just_completed <= 1'b1;

// TRONG if (!flush_busy):  -- chỉ giữ guard, bỏ set
```

**Hypothesis 2 — Store Buffer có 2 entries**
- CPU re-issue SW instruction do pipeline flush/replay
- SB count=2 → drain 2 lần → 2 NC_WRITE
- nc_just_completed không giúp vì đây là 2 giao dịch riêng biệt
- Fix cần ở CPU pipeline, không phải dcache

**Hypothesis 3 — dcache_ready high quá nhiều cycle**
- Nếu cpu_ready=1 kéo dài (không phải 1 cycle), drain popping nhiều lần
- Kém khả năng vì evict_done là 1-cycle pulse và cpu_ready = combinational từ state

---

### Debug plan cho session sau

**Bước 1: Confirm hypothesis bằng $display**

Thêm vào `run_soc_periph.v` (trong `always @(posedge clk)` existing block):
```verilog
wire nc_just = chip.u_soc_top.u_dcache_top.u_dcache_ctrl.nc_just_completed;
wire flush_busy_w = chip.u_soc_top.u_dcache_top.u_dcache_ctrl.flush_busy;
wire [2:0] dcache_state_w = chip.u_soc_top.u_dcache_top.u_dcache_ctrl.state;

// Trong always @(posedge clk):
if (cycle_count >= 4130 && cycle_count <= 4160) begin
    $display("[%6d] [DBG] dc_state=%0d flush_busy=%b nc_just=%b dcache_req=%b sb_count=%0d drain_state=%b",
        cycle_count, dcache_state_w, flush_busy_w, nc_just,
        chip.u_soc_top.cpu_dcache_req,
        chip.u_soc_top.u_cpu.u_lsu.sb_count,
        chip.u_soc_top.u_cpu.u_lsu.drain_state);
end
```

**Bước 2: Nếu H1 đúng** → Move nc_just_completed set ra ngoài `if (!flush_busy)` trong `dcache_controller.v`

**Bước 3: Nếu H2 đúng** → Tìm tại sao CPU re-issues SW. Check:
- `sb_count` max value trong khi draining 'U'
- Pipeline flush signal (`flush_if_id`, `mispredict_ex`) tại thời điểm đó

**Bước 4: Sau fix** → Run simulation, verify `[PASS] uart_simple` xuất hiện và `uart_pass_cnt=1`

---

### Files đã thay đổi trong session này

| File | Thay đổi |
|------|---------|
| `run_soc_periph.v` | TIMEOUT, halt delay, UART-W logger fix |
| `memory/program.hex` | Replaced với test_uart_simple_O1.hex |
| `cache_interface/dcache/dcache_controller.v` | nc_just_completed fix (present but not working) |

---

### Files quan trọng cần đọc khi bắt đầu session mới

1. **Bug location**: `cache_interface/dcache/dcache_controller.v` — tìm `nc_just_completed`
2. **LSU drain**: `cpu/core/LSU.v` line 282–327 (drain state machine) và 309–327 (dcache_req combinational)
3. **Evict engine**: `cache_interface/dcache/dcache_axi_interface.v` line 260–355 (EV_IDLE→EV_B)
4. **Testbench**: `run_soc_periph.v` — signal taps tại line ~183-215

---

### Chưa làm
- [ ] Fix UART duplicate character (bug trên)
- [ ] Verify GPIO
- [ ] Verify DMA

---

## 2026-05-07 (continued) — Fix UART duplicate

### Đã làm
1. **Confirm hypothesis bằng $display** trong `run_soc_periph.v`:
   tap `nc_just_completed`, `flush_busy`, `dc_state`, `evict_done`, `do_store`,
   `do_drain_pop`, `lsu_req_*`, `memwrite_mem`, `memread_mem`.
   Hypothesis H1/H2/H3 trong handoff cũ đều **sai**. Root cause khác:
   **LSU concurrency bug** — load và store cùng lúc share `dcache_ready`.

2. **Phân tích trace cycle 4134–4148**:
   - 4134: SW 'U' fire, push SB. NC_WRITE bắt đầu cycle 4137.
   - 4138: LW UART_STATUS fire (do uart_putc('A') vào status-loop) — load vào
     LQ, do_load_dequeue→1, load_state=LOAD_DCACHE ngay khi NC_WRITE đang chạy.
   - 4141: `evict_done=1` → `dcache_ready=1` (cho store completion).
     - LOAD_DCACHE thấy `dcache_ready=1` → capture `rdata=0` (sai data).
     - **`do_drain_pop = (drain==REQ) && dcache_ready && !load_using_dcache`**
       → `load_using_dcache=1` → **drain pop=0** → store vẫn ở SB.
   - 4143–4148: drain restart → NC_WRITE thứ 2 ghi 'U' lần 2.

3. **Fix tại `cpu/core/LSU.v` line 152–155** [FIX-LSU-CONFLICT]:
   ```verilog
   wire do_load_dequeue = !lq_empty && load_fsm_ready && !fence
                       && (lq_fwd[lq_rd_ptr] || sb_empty);
   ```
   Forwarded loads dequeue tự do; non-forwarded loads phải đợi SB drain để
   không xung đột dcache_ready với drain. (`nc_just_completed` fix cũ trong
   `dcache_controller.v` vẫn giữ — vô hại, defense-in-depth).

4. **Kết quả simulation**:
   - ✅ Không còn duplicate char.
   - ✅ `[TEST-RESULT] *** PASS #1 ***` detected.
   - ⚠️ Còn drop 2 char riêng: 't' giữa 'r'/'_', '\r' giữa 'e'/'\n'
     → UART nhận "uar_simple\n" thay vì "uart_simple\r\n".
     Disassembly xác nhận firmware có đủ 29 SW (`test_uart_simple.dump`),
     nên drop là pipeline issue khác.

### Files thay đổi
| File | Thay đổi |
|------|---------|
| `cpu/core/LSU.v` | [FIX-LSU-CONFLICT] gate do_load_dequeue by sb_empty when no fwd |
| `run_soc_periph.v` | Thêm signal taps `dbg_*` và $display block (gated `1'b0`, bật khi cần debug) |

### Bug còn lại — Drop 2 char ('t', '\r')

#### Triệu chứng
- Firmware gọi đủ 29 lần `uart_putc` (xác nhận từ `test_uart_simple.dump`,
  29 lệnh `sw x14, 0(x15)` tại các PC riêng biệt 0x64..0x454).
- UART chỉ nhận 27 AW writes. Pattern: drop sau 'r' của "uart" (vị trí #20 expected),
  drop sau 'e' của "simple" (vị trí #28 expected).

#### Hypothesis cho session sau
- **H-A**: FIX-DOUBLE-ISSUE (`cpu/riscv_cpu_core_v2.v:711-738`) có hash collision —
  `lsu_req_sig = {memread, memwrite, rd, wstrb, alu_result, pc_plus_4}`.
  Có thể `lsu_req_sent` không reset đúng giữa 2 SW liên tiếp khi pipeline stall
  do TX_FULL polling loop. Cần trace `lsu_req_sent`, `lsu_req_new`, `lsu_req_fire`
  quanh PC=0x310→0x334 (SW 'r' → SW 't').
- **H-B**: Pipeline replay/flush khi drain SB completes — instruction sau SW
  bị flush nhầm, nhưng PC++ đã commit nên SW kế tiếp bị skip.
- **H-C**: Tương tác giữa fix mới (load đợi sb_empty) và scoreboard logic —
  load result delivery có thể trễ → MEM stage bị stall sai cách.

#### Debug plan
1. Bật lại $display block trong `run_soc_periph.v` (đổi `1'b0` → `1'b1` line 524),
   mở rộng cycle window đến ~24370–24400 (gap giữa SW 'r' và SW 't').
2. Thêm tap `pc_if`, `pc_id`, `pc_ex`, `pc_mem`, `flush_*` signals.
3. Search log: PC=0x334 (SW 't') có đến MEM stage không? Nếu có, lsu_req_fire có lên không?
4. Nếu PC=0x334 không đến MEM → flush_if_id/flush_id_ex bị assert sai → check
   branch predictor / hazard logic.

### Lệnh chạy lại
```bash
./workflow/urun_verilog.sh run_soc_periph.v
rtk read log/run_soc_periph.log
```

---

### Lệnh chạy simulation
```bash
./workflow/urun_verilog.sh run_soc_periph.v
rtk read log/run_soc_periph.log
```

### Signal path trong testbench (đã có wire)
```verilog
wire s5_awvalid = chip.u_soc_top.s5_awvalid;  // UART AW
wire s5_awready = chip.u_soc_top.s5_awready;
wire s5_wvalid  = chip.u_soc_top.s5_wvalid;   // UART W data
wire s5_wready  = chip.u_soc_top.s5_wready;
wire [31:0] s5_wdata = chip.u_soc_top.s5_wdata;
```

---

## 2026-05-07 (session 3) — Trace drop bug 't' / '\r'

### Đã làm

1. **Bật $display block và trace cycle 24340–24440 + 24900–24915**
   - Thêm signal taps vào `run_soc_periph.v`:
     `dbg_scoreboard`, `dbg_rs1_id`, `dbg_rs1_used`, `dbg_memtoreg_wb`,
     `dbg_rd_wb`, `dbg_wbdata`, `dbg_lsu_commit`, `dbg_lsu_rd`,
     `dbg_fwd_a_wb`, `dbg_fwd_a_mem`, `dbg_mw_ex`
   - Mở rộng $display window: cycle 24340–24440 và 24900–25100
   - Chạy lại simulation và đọc log

2. **Xác nhận root cause: `pc_id` và `instr_id` lệch nhau 1 cycle**

#### Bằng chứng từ trace (cycle 24378–24382):

```
cycle | pc_id | instruction      | rs1_id | scb15 | lds
------|-------|------------------|--------|-------|----
24378 | 0x308 | LUI  x15,0x50000 |   0    |   1   |  0  ← LUI rs1=x0 → đúng
24379 | 0x30c | ADDI x14,x0,116  |   0    |   1   |  0  ← ADDI rs1=x0 → đúng
24380 | 0x310 | SW x14,0(x15)    |   0    |   1   |  0  ← SW rs1=x15=15 → SAI (hiện 0)
24381 | 0x314 | FENCE            |   0    |   1   |  0  ← SW 't' đã ở EX!
24382 | MEM=0x310 mW=0 alu=0    |        |       |     ← SW không issue AXI → 't' DROP
```

Tại cycle 24380, `pc_id=0x310` (SW 't') nhưng `rs1_id=0`, không phải 15.
Trong khi đó với ANDI x15 tại 0x324 (cycle 24385), `rs1_id=15` đúng → stall OK.

**Điểm mấu chốt**: `rs1_id = instr_id[19:15]` phản ánh instruction từ cycle TRƯỚC, không phải instruction hiện tại ở ID stage. Khi `pc_id` update lên 0x310, `instr_id` vẫn chứa ADDI (0x30c) — rs1=0 → hazard miss.

3. **Cross-check với các trường hợp khác**:
   - Cycle 24355: `ID=0x2d8` (LUI x14, rs1 phải=0), nhưng hiện `rs1=14` → instr_id từ lệnh trước có rs1=14
   - Cycle 24356: `ID=0x2dc` (ADDI x14,x14,8, rs1 phải=14), nhưng hiện `rs1=15`
   - → Systematic: `rs1_id` luôn trễ 1 instruction so với `pc_id`

4. **Xác nhận ANDI/BNE stall loop vẫn hoạt động đúng**:
   - ANDI (0x324) nhờ đã qua 1 stall cycle trước (LW 0x320 vào MEM gây lds=1) nên lần ANDI vào ID có stall từ trước → instr_id đã sync → rs1=15 đúng
   - SW 't' thì vào ID ngay sau ADDI (không có stall trước), bị misalign

---

### Root Cause Chính Xác

**`instr_id` lệch 1 cycle so với `pc_id`**

Khi IF/ID register latch tại posedge:
- `pc_id <= pc_if` (new PC)
- `instr_id <= instr_if` (instruction tương ứng với pc_if)

Nhưng tại CÙNG posedge đó, `PIPELINE_REG_ID_EX` latch với `instr_id` cũ (trước NBA update). Hazard detection chạy từ `instr_id` cũ → `rs1_id` sai.

Hiệu quả: **instruction đầu tiên vào ID stage bị decode sai** — sau 1 stall cycle thì instr_id mới đúng.

Đây là IFU timing bug. Cần đọc `cpu/core/IFU.v` (hoặc tương đương) để xem:
- IMEM có latency 1 cycle không (registered output)?
- `instr_if` lấy từ registered hay combinational IMEM output?
- `pc_if` là register hay wire?

---

### Bug còn lại — Drop 2 char ('t', '\r')

#### Hypothesis sau trace (CONFIRMED root cause, fix chưa thực hiện)

**pc_id / instr_id 1-cycle misalignment trong IFU→IF/ID pipeline**

Cơ chế:
```
IF/ID latch tại posedge N:
  instr_id <= instr_if   (SW 't')   — NBA update cycle N
  pc_id    <= pc_if      (0x310)    — NBA update cycle N

PIPELINE_REG_ID_EX latch tại CÙNG posedge N:
  reads instr_id = ADDI (0x30c)    — PRE-NBA value (old)
  → rs1_decoded = 0, memwrite=0
  → lsu_dep_stall = 0 (hazard MISS)
  → ID/EX latches ADDI decode → no store issued → 't' dropped
```

#### Fix options

**Option A — Đọc IFU.v, align instr_if với pc_if**
- Nếu IMEM output là registered: thêm 1-cycle pipeline cho pc_if để pc_id và instr_id sync
- Nếu IMEM output là combinational: kiểm tra tại sao instr_id bị stale khi IF/ID latch

**Option B — Hazard detection dùng `instr_if` thay vì `instr_id`**
- `rs1_hazard = instr_if[19:15]` (1 cycle trước → cùng instruction đang vào ID)
- Rủi ro: cần đảm bảo instr_if valid khi có flush/stall

**Recommendation: Option A** — fix ở gốc (IFU timing), ít tác dụng phụ hơn.

#### Debug plan cho session sau

1. **Đọc IFU module**:
   ```bash
   rtk grep "module.*IFU\|module.*fetch\|module.*ifu" cpu/
   rtk read cpu/core/IFU.v   # hoặc tên tương đương
   ```
   Tìm: IMEM interface, pc register, instr_if timing

2. **Xác định IMEM output type**:
   - Nếu `imem_rdata` là `reg` → registered (1 cycle lag) → fix: delay pc_if 1 cycle trước khi vào IF/ID
   - Nếu `imem_rdata` là `wire`/combinational → fix ở nơi khác

3. **Apply fix** và chạy lại simulation

4. **Verify**: `pc_id=0x310` → `rs1_id=15` → `lds=1` → SW 't' stalls → UART nhận đủ 29 chars

---

### Files thay đổi trong session 3

| File | Thay đổi |
|------|---------|
| `run_soc_periph.v` | Thêm dbg_* signal taps (scoreboard, rs1_id, lsu_commit, fwd_*); mở rộng $display window 24340-24440, 24900-25100 |

### Chưa làm
- [ ] Fix pc_id/instr_id misalignment (drop 't' và '\r')
- [ ] Verify GPIO
- [ ] Verify DMA
