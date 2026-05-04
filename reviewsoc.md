# SoC Review — Completeness & HS Roadmap

## Context
Review `soc_top.v` để xác định: (A) những gì cần hoàn thiện cho SoC cơ bản,
(B) những gì cần làm để đạt HS (high-performance + low-power), và
(C) cách verify/benchmark kết quả. Không làm cả hai cùng lúc — A trước, B sau.

---

## Kiến trúc hiện tại — Snapshot

**5M × 12S AXI4 Crossbar** · RV32IM 5-stage · ICache + DCache · ASCON crypto accelerator

| Domain | Clock | Gated bởi |
|--------|-------|-----------|
| Core | `clk_core` | ICG — WFI + ascon_busy + bus_active |
| Periph | `clk_periph` | ICG — periph_busy + wake_req + bus_active |
| AON | `clk_aon` = `clk_in` | **Không gate — always-on** |

**Clock gating đã HOÀN CHỈNH** trong `clk_reset_ctrl`:
- ICG cell (`clk_buf.v`) — glitch-free, latch-based, synthesis-mapped
- `cpu_wfi` đã kết nối vào gating policy
- AON domain riêng biệt (chỉ bị POR + ext_rst_n)
- `wake_ack` handshake đã có

---

## Trạng thái hiện tại — Đã OK ✅

| Component | File | Ghi chú |
|-----------|------|---------|
| CPU RV32IM 5-stage | `cpu/riscv_cpu_core_v2.v` | ICache + DCache, JTAG debug |
| Boot controller | `boot/uart_boot_ctrl.v` | Load IMEM, gate cpu_rst_n |
| Clock/Reset AON | `clk_reset_ctrl/` | ICG, WFI gating, 4 reset domains |
| ASCON accelerator | `ascon/ascon_top.v` | DMA streaming, 64→32 width conv |
| CLINT | `clint.v` | mtime/mtimecmp/msip |
| PLIC | `plic/plic_top.v` | 32 sources, priority encoder |
| UART | `peripheral/uart/uart_top.v` | TX/RX FIFO, baud config, IRQ |
| GPIO | `peripheral/gpio/gpio_top.v` | 32-bit, level/edge IRQ |
| Timer/WDT | `peripheral/timer/timer_top.v` | T0 + T1 + WDT |
| SoC Ctrl | `controller/soc_ctrl_slave.v` | SYS_ID, soft_rst, cache stats |
| General DMA | `dma/dma_ctrl.v` | 4-ch mem-to-mem, round-robin |
| Pad ring | `soc_hs.v` | GPIO tri-state, JTAG TDO |

---

## PHASE A — Hoàn thiện SoC (trước HS)

### A1. Flexible DMA — **Ưu tiên cao**

**Hiện trạng:** `dma_ctrl.v` chỉ hỗ trợ mem-to-mem. Thiếu:
- Peripheral req/ack handshake (UART-RX→DMEM, DMEM→UART-TX)
- Chained/linked descriptor transfer
- Width adaptation (32-bit ↔ 8/16-bit peripheral bus)

**Việc cần làm:**
```
- Thêm port: dma_req[3:0], dma_ack[3:0] (per-channel peripheral handshake)
- Thêm mode: MODE_MEM=0, MODE_PERIPH_RX=1, MODE_PERIPH_TX=2
- Wiring trong soc_top.v: UART/GPIO/ASCON → dma_req
- Update gnu_toolchain/include/dma.h: thêm dma_ch_setup_periph()
```

**Files:** `dma/dma_ctrl.v`, `dma/dma_ch.v`, `soc_top.v`, `gnu_toolchain/include/dma.h`

---

### A2. Hardware Performance Counter — **Ưu tiên cao**

**Hiện trạng:** CPI/IPC chỉ đo trong testbench (`run_soc_ascon.v`, `integer` vars). Không có hardware counter đọc được từ firmware.

**Việc cần làm:**
```
Thêm module perf_counter_top.v (Slave S12, hoặc mở rộng soc_ctrl):

Registers @ base_addr:
  [0x000] PERF_CTRL    — [0]=enable, [1]=reset_on_read
  [0x004] CYCLE_LO     — mcycle[31:0]  (100 MHz)
  [0x008] CYCLE_HI     — mcycle[63:32]
  [0x00C] INSTR_LO     — minstret[31:0]
  [0x010] INSTR_HI     — minstret[63:32]
  [0x014] STALL_CYCLES — stall count
  [0x018] CACHE_IHIT   — ICache hit count
  [0x01C] CACHE_IMISS  — ICache miss count
  [0x020] CACHE_DHIT   — DCache hit count
  [0x024] CACHE_DMISS  — DCache miss count

Signals tapped từ CPU:
  - instr_valid_wb (instruction retired)
  - stall_any (pipeline stalled)
  - icache_hit / icache_miss (từ ICache)
  - dcache_hit / dcache_miss (từ DCache)
```

**Option đơn giản hơn:** Mở rộng `soc_ctrl_slave.v` thêm 10 registers vào space còn trống.
**Files:** `controller/soc_ctrl_slave.v`, `soc_top.v`, `gnu_toolchain/include/soc_ctrl.h`

---

### A3. IMEM/DMEM 16KB — **Cần làm, nhưng user tự handle**

**Hiện trạng:** 8KB mỗi bộ. Đủ cho simulation hiện tại.

**Khi nâng lên 16KB cần sửa:**
```
RTL:
  - soc_top.v: parameter IMEM_SIZE = 16*1024, DMEM_SIZE = 16*1024
  - inst_mem_axi_slave.v: depth parameter
  - data_mem_axi4_slave.v: depth parameter
  - Crossbar address mask: IMEM mask 0xFFFFC000 (thay vì 0xFFFFE000)

Firmware:
  - compile_c_to_hex.sh: IMEM_SIZE / DMEM_SIZE
  - linker_minimal.ld: MEMORY regions
  - dmem_layout.h: static_assert nếu có
```

---

### A4. OTP — stub nên thêm register read-only đơn giản

**Hiện trạng:** DECERR stub.

**Đề xuất minimal:** Thêm `otp_stub_slave.v` — trả về fixed data (device ID, chip config) thay vì DECERR. Không cần real OTP.

```verilog
// Trả về: 0xDEAD_BEEF cho unknown offset, và device ID/version cho offset 0x0/0x4
```

**Files:** Tạo mới `peripheral/otp/otp_stub_slave.v`, update `soc_top.v`, `gnu_toolchain/include/memory_map.h`

---

### A5. CDC Crossbar Verify

**Hiện trạng:** `clk_core` và `clk_periph` là hai clock gated khác nhau. Nếu `clk_core ≠ clk_periph` (tần số khác) → cần CDC boundary trong crossbar.

**Việc cần làm:**
```
1. Đọc axi4_crossbar_5m12s.v — tìm xem có axi_cdc_fifo hay 2FF sync không
2. Nếu chưa có: thêm axi_cdc_fifo ở boundary M3 (DMA clk_periph) và S5-S11
3. Nếu clk_core = clk_periph (same source, gated independently) → CDC không cần,
   chỉ cần verify hold time khi gating
```

**Files:** `interconnect/axi4_crossbar_5m12s.v`

---

### A6. Wakeup Interrupt (Sleep/Wake)

**Hiện trạng:** `periph_wake_req` input đã có trong `clk_reset_ctrl`, nhưng cần verify nó được drive từ GPIO/UART edge detect ở AON domain.

**Việc cần làm:**
```
- Kiểm tra soc_top.v: periph_wake_req kết nối từ đâu?
  Nếu tied to 0 → cần add AON wake logic
- AON wake sources: GPIO edge detect, UART RX start-bit detect, CLINT timeout
- Thêm port gpio_wake_n (nếu chưa có) vào soc_top.v
```

---

## PHASE B — HS: High Performance + Low Power

> Clock gating (WFI-based auto) đã có sẵn. Phase B tập trung vào throughput và power efficiency.

### B1. AXI QoS / Priority Tuning

**Hiện trạng:** Round-robin cho tất cả 5 masters.

**HS target:** CPU instruction fetch (M0) không bao giờ bị stall vì DMA (M2/M3).
```
Đề xuất priority order:
  M0 (ICache)      = Highest priority (latency-critical)
  M1 (DCache)      = High (load/store stall = CPI tăng)
  M2 (ASCON DMA)   = Medium (throughput-sensitive nhưng bursty)
  M3 (General DMA) = Low (background transfer)
  M4 (JTAG)        = Lowest (debug only)
```
**Files:** `interconnect/axi4_crossbar_5m12s.v` — tìm priority parameter

---

### B2. ASCON DMA Burst Optimization

**Hiện trạng:** ASCON DMA đọc 1 beat (ARLEN=0) mỗi block 8 bytes. Write 3 beats.

**HS target:** Đọc nhiều block trước (prefetch FIFO), tăng ARLEN để tận dụng burst efficiency.
```
- Tăng rd_fifo depth → buffer nhiều block hơn
- ARLEN = 7 (8 beats × 8 bytes = 64 bytes = 8 blocks) — prefetch
- Giảm AR channel overhead từ N transactions xuống N/8
```

---

### B3. Cache Configuration Tuning

**Hiện trạng:** ICache/DCache — cần đọc để biết way/size mặc định.

**HS target:** Dựa trên cache miss counter (Phase A2), điều chỉnh:
- ICache: tăng associativity nếu miss rate cao
- DCache: tăng line size cho workload có spatial locality (ASCON block processing)

---

### B4. CPU Pipeline — mcycle/minstret CSR

**Hiện trạng:** Testbench tính CPI bằng cách tap `stall_if + instr_if`. Không có CSR đọc từ firmware.

**HS target:** Thêm `mcycle` và `minstret` CSRs vào CPU nếu chưa có → firmware tự đo không cần testbench.
Phối hợp với Phase A2 (hardware perf counter).

---

## PHASE C — Verify & Benchmark

### C1. Simulation Regression Suite

```bash
# 1. Lint
./workflow/ulint_verilog.sh soc_top.v

# 2. SoC simulation
./workflow/urun_verilog.sh run_soc_ascon.v
# Kiểm tra: [PASS] trong log, không có ERROR/FAIL

# 3. ASCON unit test
iverilog -g2005 -o build_test ascon/tb/ascon_top_tb.v && vvp build_test
# So sánh với Python golden model: ascon/tb/sw_reference.py

# 4. Firmware build
cd gnu_toolchain && ./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c
```

### C2. Benchmark Targets (firmware-based, @100MHz)

| Metric | Cách đo | Target HS |
|--------|---------|-----------|
| CPI baseline | perf_counter CSR (Phase A2) | < 1.5 CPI |
| ASCON throughput | PERF_TOTAL cycles (đã có) | > 500 Mbps |
| DMA overhead | cycle(DMA) vs cycle(CPU-direct) | DMA > 2× speedup cho N≥4 |
| Clock gating effectiveness | Cycles with clk_core ON / total | < 60% khi idle |
| ICache miss rate | CACHE_IMISS / (HIT+MISS) | < 5% cho benchmark loops |

### C3. Waveform Checkpoints

```
gtkwave waveform_soc.gtkw

Signals quan trọng cho HS verification:
  clk_core, clk_periph          — xem gating khi WFI
  u_cpu.cpu_wfi                 — CPU vào idle
  u_clkrst.core_clk_dyn_en_r   — clock gate state
  u_clkrst.core_idle_hold_r    — hold counter đếm ngược
  u_ascon.u_dma.rd_fifo_count  — DMA pipeline fill level
  crossbar.m0_grant             — ICache arbitration win rate
```

---

## Thứ tự thực hiện

```
Phase A (completeness):
  A2 → A1 → A5 → A6 → A4
  (perf counter trước để đo baseline trước khi optimize)

Phase B (HS):
  B1 → B2 → B3 → B4
  (priority tuning ảnh hưởng nhiều nhất, làm trước)

Phase C (verify):
  C1 chạy sau mỗi A-step (regression)
  C2 + C3 sau Phase B complete
```

---

## Files cần đọc/sửa — Index

| File | Phase | Việc |
|------|-------|------|
| `controller/soc_ctrl_slave.v` | A2 | Thêm perf counter registers |
| `gnu_toolchain/include/soc_ctrl.h` | A2 | Thêm PERF_* defines |
| `dma/dma_ctrl.v` | A1 | Thêm peripheral mode |
| `soc_top.v` | A1, A2, A6 | Wiring mới |
| `interconnect/axi4_crossbar_5m12s.v` | A5, B1 | CDC verify, priority |
| `ascon/dma/ascon_dma.v` | B2 | Burst optimization |
| `cpu/riscv_cpu_core_v2.v` | B4 | CSR check |
