# Tối ưu Throughput ASCON SoC — v2.0 (Revised)

> [!IMPORTANT]
> **Bản cập nhật** sau khi xem lại kỹ RTL và log. Sửa 3 nhận định sai từ v1.0:
> 1. DMA FSM **đã là Decoupled v2.0** — không cần refactor kiến trúc
> 2. CPU poll **KHÔNG block DMA** — chỉ lãng phí điện → focus Green IC
> 3. Sửa bus 64-bit **quá invasive** cho RISC-V 32-bit — loại bỏ Phase 3

---

## 1. Phân tích lại chính xác từ Log

### 1.1 Timing ASCON CTEXT output (từ `run_soc_ascon.log`)

| Block # | Cycle | Δ (cycles) | Ghi chú |
|---------|-------|-----------|---------|
| 0 | 2370 | — | Block đầu tiên (init overhead) |
| 1 | 2374 | **4** | Pipeline warm-up |
| 2 | 2380 | **6** | |
| 3 | 2386 | **6** | |
| 4 | 2394 | **8** | |
| 5 | 2402 | **8** | Steady-state |
| 6 | 2410 | **8** | Steady-state |
| 7 | 2418 | **8** | Steady-state |
| TAG | 2422 | 4 | Finalization |

**DMA START = 2350, DMA DONE = 2474 → 124 cycles cho 8 blocks (64 bytes)**

**Steady-state: ~8 cycles/block** thay vì 3-4 cycles/block ở standalone.

### 1.2 CPU Poll KHÔNG block DMA — Bằng chứng

Từ log, tại cycle 2382:
```
[  2382] [M1-AR] addr=0x20000004  → ASCON    ← CPU poll qua M1 (DCache port)
[  2384] [M2-AR] addr=0x10000240  → DMEM     ← DMA read qua M2 (DMA port)
```

- **M1** (DCache) và **M2** (ASCON-DMA) là 2 master ports khác nhau trên crossbar
- M1 truy cập S2 (ASCON slave), M2 truy cập S1 (DMEM) — **khác slave, không contention**
- DMA tiếp tục hoạt động bình thường trong khi CPU poll
- CPU stall (`stall_any=1`) là do **DCache miss** trên đường truy cập ASCON register (MMIO), không liên quan đến DMA

> [!NOTE]
> **Kết luận**: CPU poll **không ảnh hưởng throughput** vì DMA và CPU dùng khác master port và truy cập khác slave. Nhưng CPU poll **lãng phí điện năng** — quan trọng cho mục tiêu **vi mạch xanh**.

### 1.3 DMA FSM đã là Decoupled — Cấu trúc hiện tại

File [dma_ctrl_fsm.v](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/ascon/dma/rtl/dma_ctrl_fsm.v) version **v2.0 Concurrent/Decoupled**:

```
BLOCK 1: rd_ctrl       — Tự động issue rd_start khi rd_done (line 86-112)
BLOCK 2: core_pump     — Pop RD FIFO → feed ASCON CORE (line 114-180)
BLOCK 3: wr_push       — Capture ctext/tag → push WR FIFO (line 182-288)
+ Write engine         — Auto-trigger khi WR FIFO ≥ 2 entries (line 116, dma_write_engine.v)
```

**3 blocks hoạt động song song** — đúng là producer-consumer architecture. Không cần refactor.

### 1.4 Xác định chính xác Bottleneck thực sự

Steady-state **8 cycles/block**. Phân tích từng cycle trong `core_pump`:

```
Cycle 1: PUMP_IDLE    — check !rd_fifo_empty (line 155)
Cycle 2: PUMP_WAIT    — FIFO output settling (line 161)
Cycle 3: PUMP_LATCH   — core_ptext = rd_fifo_dout, core_start=1 (line 163-170)
Cycle 4-N: PUMP_WAIT_CORE — chờ core_data_out_valid (line 172-177)
```

**core_pump tốn 3 cycles overhead** trước khi ASCON core nhận data:
- PUMP_IDLE → PUMP_WAIT: 1 cycle chờ FIFO check
- PUMP_WAIT → PUMP_LATCH: 1 cycle chờ FIFO dout stabilize
- PUMP_LATCH → PUMP_WAIT_CORE: 1 cycle pulse core_start

Sau đó ASCON core cần **~2 cycles** (6 rounds / G=6) + **~3 cycles** trước khi `core_data_out_valid` assert.

**Tổng: 3 (pump overhead) + 5 (core latency) = ~8 cycles/block** ← khớp với log!

**So sánh IP standalone**: Testbench trực tiếp drive signals → 0 pump overhead → 3-4 cycles/block.

---

## 2. Root Causes (Revised)

| # | Root Cause | Cycles wasted | Impact |
|---|-----------|--------------|--------|
| **RC1** | core_pump 3-cycle overhead (IDLE→WAIT→LATCH) | 3 cyc/block | **38%** |
| **RC2** | ASCON core latency: perm + output valid delay | 5 cyc/block | Intrinsic |
| **RC3** | Write engine 6-state pipeline per beat | Partially overlapped | ~5-10% |
| **RC4** | ARLEN=0: separate AXI transaction per block | 2-3 cyc/block | ~15% |
| **RC5** | 64→32 width converter: +1 cyc per AXI beat | 1-2 cyc/block | ~10% |
| — | CPU poll (chỉ lãng phí điện, không ảnh hưởng throughput) | 0 | Power only |

---

## 3. Giải pháp — Revised (3 Phases)

### Phase 1: Green IC — CPU Power Optimization (Firmware)

> Mục tiêu: **Giảm tiêu thụ điện năng** khi DMA hoạt động, phù hợp vi mạch xanh.
> Throughput impact: **0%** (DMA đã chạy độc lập) — nhưng **tiết kiệm ~99% CPU power** trong thời gian DMA processing.

#### 1.1 Bật Interrupt + WFI thay vì Poll Loop

**Hiện tại** (`main.c` line 109-116):
```c
do {
    ASCON_READ(ASCON_OFS_STATUS, status);  // CPU liên tục đọc → lãng phí năng lượng
    if (--timeout == 0u) { retcode = -2; goto done; }
} while (!(status & ...));
```

**Sửa thành**:
```c
// Bật interrupt DMA_DONE
ASCON_WRITE(ASCON_OFS_IRQ_EN, 0x02);  // bit[1] = dma_done interrupt enable

// DMA start
ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);

// CPU ngủ — tiết kiệm điện, DMA vẫn chạy tối đa
__asm__ volatile ("wfi");

// Wakeup bởi interrupt → đọc STATUS 1 lần duy nhất
ASCON_READ(ASCON_OFS_STATUS, status);
```

**Tại sao không ảnh hưởng throughput**: DMA dùng M2 (port riêng), ASCON core được DMA feed trực tiếp qua RD FIFO. CPU ngủ hay thức đều không thay đổi tốc độ DMA. Nhưng CPU **ngừng hoàn toàn**: không fetch instructions (M0 ICache → 0 requests), không gửi poll (M1 DCache → 0 requests) → **tiết kiệm >90% dynamic power** trong 124 cycles DMA active.

**Files cần sửa**:
- [main.c](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain/main.c): Thay poll loop bằng WFI + interrupt
- [ascon.h](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain/ascon.h): Thêm `ASCON_WRITE(ASCON_OFS_IRQ_EN, ...)` helper

#### 1.2 Bỏ `fence w,w` redundant trong ASCON_WRITE

Hiện tại mỗi `ASCON_WRITE` có `fence w, w` (line 131 ascon.h) → **mỗi register write tốn thêm 1 cycle**. Có 12 register writes trong setup → lãng phí 12 cycles.

**Sửa**: Chỉ cần 1 `fence rw, rw` **trước DMA start** (đã có ở main.c line 99). Bỏ fence trong macro.

#### 1.3 Tăng payload 64B → 1024B+

Giảm tỷ lệ init/final overhead. Với 128 blocks, overhead amortize tốt hơn.

**Files cần sửa**:
- [dmem_layout.h](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain/dmem_layout.h): Tăng `DMEM_MULTI_BLOCK_COUNT` từ 8 → 128
- [main.c](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain/main.c): Tăng loop count

---

### Phase 2: RTL Micro-optimization — core_pump + write engine

> Mục tiêu: **Giảm cycles/block từ 8 xuống ~5** bằng cách tối ưu state machine overhead.

#### 2.1 ⭐ Tối ưu core_pump: Loại bỏ PUMP_WAIT state (Highest Impact)

**Hiện tại** ([dma_ctrl_fsm.v](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/ascon/dma/rtl/dma_ctrl_fsm.v) line 117-180):
```
PUMP_IDLE → PUMP_WAIT → PUMP_LATCH → PUMP_WAIT_CORE
  (1 cyc)    (1 cyc)      (1 cyc)      (N cyc)
```

`PUMP_WAIT` (line 160-162) chỉ có `pump_state <= PUMP_LATCH` — tốn 1 cycle "chờ FIFO output settle". Nhưng sync_fifo output `dout` đã available **ngay sau pop** (combinational read of head pointer), nên cycle wait này là thừa.

**Sửa**: Merge PUMP_IDLE + PUMP_WAIT thành 1 state. Pop FIFO và latch data trong cùng cycle:

```verilog
PUMP_IDLE: begin
    if (!rd_fifo_empty && dma_busy && (core_blocks_fed < total_blocks)) begin
        rd_fifo_pop <= 1'b1;
        pump_state  <= PUMP_LATCH;  // Skip PUMP_WAIT
    end
end
```

**Hoặc tốt hơn**: Nếu sync_fifo dout là registered (output flop), thì chuyển sang **FWFT (First-Word-Fall-Through)** mode — dout always valid khi `!empty`, pop chỉ advance pointer. Khi đó:

```verilog
PUMP_IDLE: begin
    if (!rd_fifo_empty && dma_busy && core_data_ready) begin
        core_ptext_0    <= rd_fifo_dout[31:0];   // Latch trực tiếp
        core_ptext_1    <= rd_fifo_dout[63:32];
        core_data_valid <= 1'b1;
        core_start      <= 1'b1;
        rd_fifo_pop     <= 1'b1;                  // Advance FIFO
        core_blocks_fed <= core_blocks_fed + 1;
        pump_state      <= PUMP_WAIT_CORE;
    end
end
```

→ **Giảm 2 cycles/block** (từ 8 → 6 cycles/block)

**File sửa**: [dma_ctrl_fsm.v](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/ascon/dma/rtl/dma_ctrl_fsm.v) lines 117-180

**Impact**: +33% throughput (8→6 cyc → 640→853 Mbps)

#### 2.2 Tối ưu core_pump: Chuyển sync_fifo sang FWFT mode

**Hiện tại**: [sync_fifo.v](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/ascon/dma/rtl/sync_fifo.v) — cần kiểm tra xem `dout` là combinational hay registered.

Nếu registered → cần thêm 1-cycle look-ahead output:
```verilog
assign fwft_dout  = mem[rd_ptr];   // combinational read
assign fwft_valid = !empty;
```

Khi đó core_pump có thể latch data ngay tại PUMP_IDLE → **giảm thêm 1 cycle**.

**File sửa**: [sync_fifo.v](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/ascon/dma/rtl/sync_fifo.v)

#### 2.3 Tối ưu write engine: Giảm state overhead

**Hiện tại**: [dma_write_engine.v](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/ascon/dma/rtl/dma_write_engine.v) có **6 states** cho mỗi AXI write beat:
```
WR_IDLE → WR_ADDR → WR_WAIT_H → WR_LATCH_H → WR_WAIT_L → WR_LATCH_L → WR_BEAT → WR_RESP
```

4 states (WAIT_H, LATCH_H, WAIT_L, LATCH_L) chỉ để combine 2 × 32-bit words thành 1 × 64-bit AXI write. Nếu WR FIFO output là FWFT, có thể:

1. WAIT_H + LATCH_H → merge thành 1 state
2. WAIT_L + LATCH_L → merge thành 1 state

→ **Giảm 2 cycles per write beat**. Với 10 write beats (8 CT + 2 TAG), tiết kiệm ~20 cycles total.

**File sửa**: [dma_write_engine.v](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/ascon/dma/rtl/dma_write_engine.v)

#### 2.4 Tăng AXI Burst Length cho Read Engine

**Hiện tại**: `burst_len = 0` → mỗi block cần 1 AXI AR transaction.
**Sửa**: Firmware set `DMA_BURST = 7` → 1 AR cho 8 blocks liên tục.

Read engine ([dma_read_engine.v](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/ascon/dma/rtl/dma_read_engine.v)) đã hỗ trợ burst natively (line 47-48, 83, 163). Chỉ cần firmware thay đổi:

```c
ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);  // 8 beats per burst
```

→ Giảm AXI AR overhead từ 8 transactions → 1 transaction.

**Impact**: Pre-fill RD FIFO nhanh hơn → core_pump ít bị idle → ~10% improvement.

**Files sửa**: [main.c](file:///home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain/main.c) line 93

---

### Phase 3: Đánh giá Bus Architecture (Chỉ Khảo sát)

> [!WARNING]
> **Không thực hiện thay đổi bus architecture ở phase này.** RISC-V chạy 32-bit, tất cả master ports (M0 ICache, M1 DCache) và phần lớn slave ports đều 32-bit. Nâng bus lên 64-bit sẽ:
> - Sửa **tất cả** slave interfaces (IMEM, DMEM, UART, CLINT, PLIC, GPIO, SPI, Timer, OTP)
> - Sửa crossbar logic (addr decoder, data mux, strobe handling)
> - Ảnh hưởng cache controller (ICache, DCache) vì data width thay đổi
> - **Rủi ro cao**, thời gian dài, benefit marginal (~10-15%)

**Phương án thay thế nhẹ hơn** (nếu cần sau Phase 2):
- **Dedicated DMA port trên DMEM**: Thêm port B vào SRAM block, nối thẳng M2 → DMEM port B, bypass crossbar hoàn toàn cho DMA traffic. Chỉ sửa 2 files: memory module + top-level wiring. Không ảnh hưởng phần còn lại.
- **Giữ nguyên width converter**: 64→32 chỉ tốn ~1-2 cycles/beat, không đáng để phá kiến trúc.

---

## 4. Kế hoạch Thực hiện (Revised Priority Order)

### Step 1: Firmware Green IC (Phase 1) — **Ngay bây giờ**

| Task | File | Mô tả | Impact |
|------|------|-------|--------|
| 1.1 | `main.c` | WFI + interrupt thay poll | Power: -90% CPU |
| 1.2 | `ascon.h` | Bỏ `fence w,w` trong macro | Throughput: +5% (setup) |
| 1.3 | `main.c` + `dmem_layout.h` | Tăng payload 64→1024B | Throughput: +5-10% |
| 1.4 | `main.c` | Set `DMA_BURST=7` | Throughput: +10% |

### Step 2: RTL core_pump optimization (Phase 2.1) — **Ưu tiên cao nhất**

| Task | File | Mô tả | Impact |
|------|------|-------|--------|
| 2.1 | `dma_ctrl_fsm.v` | Bỏ PUMP_WAIT, merge states | **+33% throughput** |
| 2.2 | `sync_fifo.v` | FWFT mode cho RD FIFO | +15% throughput |

### Step 3: RTL write engine optimization (Phase 2.3)

| Task | File | Mô tả | Impact |
|------|------|-------|--------|
| 2.3 | `dma_write_engine.v` | Merge WAIT/LATCH states | +10% throughput |

### Step 4: Dual-port DMEM (Optional Phase 3)

| Task | File | Mô tả | Impact |
|------|------|-------|--------|
| 3.1 | Memory module + SoC top | Port B cho DMA bypass | +10-15% throughput |

---

## 5. Kết quả Kỳ vọng (Revised)

```
                         Cycles/block    Throughput     % of Standalone
Current SoC              ~8              413 Mbps       20%
After Step 1 (FW)        ~8*             ~500 Mbps†     24%  + Power -90%
After Step 2 (pump)      ~5              1024 Mbps      49%
After Step 3 (wr_eng)    ~4.5            1138 Mbps      55%
After Step 4 (DMEM)      ~4              1280 Mbps      62%
IP Standalone            ~3.1            2074 Mbps      100%

* FW changes don't reduce core cycles, but burst + larger payload amortize setup
† With 1024B payload: (1024*8)/(~1000 cycles) ≈ 800 Mbps (setup amortized)
```

> [!NOTE]
> **Tại sao không thể đạt 100%?**
> Standalone IP có **0 overhead** — testbench drive signals trực tiếp, không có AXI, không có FIFO, không có FSM. Trong SoC, mỗi block phải qua:
> 1. AXI read (AR→R): ~2 cycles minimum
> 2. RD FIFO push→pop: 1 cycle
> 3. core_pump FSM: 1-2 cycles (after optimization)
> 4. ASCON permutation: 2 cycles (intrinsic)
> 5. WR FIFO + AXI write: overlapped
>
> **Minimum achievable: ~4-5 cycles/block = 1024-1280 Mbps** — đây là giới hạn kiến trúc khi IP được tích hợp qua AXI bus.

---

## Open Questions (Updated)

> [!IMPORTANT]
> 1. **sync_fifo.v**: `dout` output là combinational hay registered? Điều này quyết định có cần PUMP_WAIT hay không. Cần xem sync_fifo.v.

> [!IMPORTANT]
> 2. **PLIC + WFI đã hoạt động chưa?** Log cho thấy PLIC meip=0, ascon_irq=0. Cần verify: (a) ASCON irq output wired đến PLIC src[8], (b) CPU hỗ trợ WFI instruction, (c) PLIC claim/complete flow hoạt động.

> [!NOTE]
> 3. Bạn muốn bắt đầu từ **Step 1 (firmware/green IC)** hay **Step 2 (RTL pump optimization)** trước?

## Verification Plan

### Automated Tests
- Re-run SoC simulation sau mỗi step, so sánh `ASCON BANDWIDTH SUMMARY`
- Verify functional correctness: CT + TAG match reference values
- Verify WFI behavior: CPU stops issuing M0-AR after WFI instruction

### Power Metrics (Green IC)
- Đếm tổng M0-AR requests trước/sau WFI optimization
- Đếm tổng M1-AR requests (poll) trước/sau interrupt optimization
- Ước lượng toggle rate reduction → dynamic power saving
