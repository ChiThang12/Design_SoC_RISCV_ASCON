# SoC Review — Phase A Final Status + Phase B Audit

> Ngày review: 2026-05-06  
> Mục đích: Tổng hợp chính xác những gì đã/chưa làm, tránh sửa mù gây regression.

---

## Phase A — Trạng thái cuối

| Item | Trạng thái | Files đã verify |
|------|------------|----------------|
| A1: Flexible DMA | ✅ DONE | `dma/dma_ctrl.v:138-139`, `dma/rtl/dma_channel.v:69-70` |
| A2: HW Perf Counter | ✅ DONE | `controller/soc_ctrl_slave.v:96-196`, `gnu_toolchain/include/soc_ctrl.h:48-113` |
| A3: IMEM/DMEM 16KB | ❌ PENDING | `soc_top.v:95-96`, `compile_c_to_hex.sh:43,171` |
| A4: OTP Stub | ✅ DONE | `peripheral/otp/otp_stub_slave.v` (157 dòng, crossbar mapped) |
| A5: CDC Crossbar | ✅ NO ACTION NEEDED | Single-clock source — xem phân tích bên dưới |
| A6: Wakeup Interrupt | ✅ DONE | `soc_top.v:186-188,369` periph_wake_req OR combiner |

**Kết quả: 4/6 DONE. Còn lại: A3 (pending), A5 (không cần làm).**

---

## A3 — IMEM/DMEM 16KB: Checklist thay đổi

> **Lưu ý:** Phải thay đổi RTL và Firmware đồng bộ, không được sửa một bên.

### RTL — `soc_top.v`

| Dòng | Hiện tại | Sửa thành | Lý do |
|------|----------|-----------|-------|
| L95 | `parameter IMEM_SIZE = 8192` | `= 16384` | 16 KB |
| L96 | `parameter DMEM_SIZE = 8192` | `= 16384` | 16 KB |
| L112 | `S0_MASK = 32'hFFFF_E000` | `32'hFFFF_C000` | Decode window 8 KB → 16 KB |
| L114 | `S1_MASK = 32'hFFFF_E000` | `32'hFFFF_C000` | Decode window 8 KB → 16 KB |

> `interconnect/axi4_crossbar_5m12s.v` nhận mask qua parameter từ `soc_top.v` (line 1105-1106) — **không sửa trực tiếp crossbar**.

### Firmware — `gnu_toolchain/compile_c_to_hex.sh`

| Dòng | Hiện tại | Sửa thành |
|------|----------|-----------|
| L43 | `MEM_SIZE=2048` (words = 8 KB) | `MEM_SIZE=4096` (words = 16 KB) |
| L171 | `ROM (rx) : LENGTH = 8K` | `LENGTH = 16K` |

> **Không thay đổi DMEM layout** (stack/data/guard zones). Nếu muốn mở rộng DMEM cần thêm bước update `dmem_layout.h` và `DMEM_DATA`/`DMEM_STACK` regions — để riêng.

### Verification sau A3

```bash
# 1. Lint RTL
~/workflow/ulint_verilog.sh soc_top.v

# 2. SoC simulation
~/workflow/urun_verilog.sh run_soc_ascon.v
# Kiểm tra: không ERROR/FAIL, ASCON [PASS]

# 3. Firmware build
cd gnu_toolchain
./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c
rtk read main.map
# Verify: ROM section fit trong 16K, stack không overflow
```

---

## A5 — CDC Crossbar: Không cần thay đổi

**Phân tích clock domain:**

| Signal | Nguồn | Loại |
|--------|-------|------|
| `clk_core` | `clk_in` → ICG latch `u_clk_core` | Gated |
| `clk_periph` | `clk_in` → ICG latch `u_clk_periph` | Gated |
| `clk_aon` | `clk_in` (direct assign) | Always-on |
| Crossbar `.clk` | `clk` = raw pad clock = `clk_in` | Always-on |

**Kết luận:** Tất cả clock đều từ **1 nguồn duy nhất `clk_in`** — đây là single-clock domain với clock gating, không phải multi-clock domain thực sự. Crossbar dùng raw `clk` (always-on), các module được kết nối qua registered AXI interface — không có metastability risk. ICG cell (`clk_buf.v`) là glitch-free latch-based.

**CDC không cần thêm.**

---

## Phase B — Audit: Cái gì thực sự cần làm

### B1: AXI QoS / Priority — ✅ ĐÃ DONE

**Bằng chứng** (`interconnect/axi4_master_mux_5m.v`):
- Fixed Priority đã implement đúng thứ tự: **M0 > M1 > M2 > M3 > M4**
- M0 (ICache) = Highest, M4 (JTAG) = Lowest
- Arbitration giữ grant đến `RLAST`/B-handshake — không cắt burst giữa chừng

**Kết luận: No action.**

---

### B2: ASCON DMA Burst Optimization — ✅ ĐÃ DONE

**Bằng chứng:**

| Component | Cấu hình | File |
|-----------|----------|------|
| Read Engine ARLEN | **7** (8 beats = 64 bytes = 8 blocks/transaction) | `main.c:96` |
| Write Engine MAX_BURST | **15** (16 beats, dynamic) | `ascon/dma/rtl/dma_write_engine.v:43` |
| Register offset DMA_BURST | `0x114` | `ascon/interface/ascon_axi_slave.v:161` |
| Firmware define | `ASCON_OFS_DMA_BURST = 0x114` | `gnu_toolchain/include/ascon.h:69` |

**Kết luận: No action.** ARLEN=7 đã set, write engine dynamic burst tối ưu.

---

### B3: Cache Configuration Tuning — ⏸ DEFER

**Trạng thái hiện tại:**

| Cache | Size | Lines | Line size | Associativity |
|-------|------|-------|-----------|---------------|
| ICache | **1 KB** | 32 | 32 bytes (8 words) | Direct-mapped |
| DCache | **8 KB** | 64 | 16 bytes (4 words) | Direct-mapped, Write-Back |

**Tại sao chưa thay đổi:**
- ICache 1 KB rất nhỏ — miss rate có thể cao với firmware loop lớn
- Nhưng tăng size đòi thay đổi **index bit width** trong `icache_controller.v` (address decode `[9:5]` → `[10:5]`) — cascade change: tag bits, `ctrl_valid[]` array, SRAM depth
- Nếu sửa sai index/tag decode → silent wrong hit, rất khó debug

**Action required trước khi B3:**
1. Bật perf counter A2: `soc_perf_enable()` trong firmware
2. Chạy benchmark → đọc `SOC_ICACHE_MISS` / `SOC_ICACHE_HIT`
3. Nếu miss rate > 5% → mới lên plan chi tiết B3

**Kết luận: Không sửa khi chưa có data.**

---

### B4: mcycle/minstret Standard CSR — ✅ KHÔNG CẦN THÊM

**Trạng thái thực tế:**
- CPU pipeline **không implement** `csrr mcycle` / `csrr instret` (địa chỉ CSR 0xB00/0xC00)
- Thay vào đó: MMIO performance counters tại `SOC_CTRL_BASE + 0x024–0x038`
- Firmware API đầy đủ: `soc_perf_cycle64()`, `soc_perf_instr64()` trong `soc_ctrl.h`

**Tại sao không thêm standard CSR:**
- Cần sửa decode unit + hazard logic + WB mux trong `riscv_cpu_core_v2.v` — nguy cơ regression CPU pipeline cao
- MMIO approach hoàn toàn đủ cho mọi benchmark firmware hiện tại

**Nếu sau này cần `rdcycle`:** Implement trap-and-emulate trong firmware ISR (mtvec handler) — ít risk hơn nhiều so với sửa pipeline.

**Kết luận: No action.**

---

## Tóm tắt — Việc thực sự cần làm

| Priority | Task | Files | Rủi ro |
|----------|------|-------|--------|
| **Làm ngay** | A3 IMEM 16KB | `soc_top.v:L95,L112` | Thấp |
| **Làm ngay** | A3 FW sync | `compile_c_to_hex.sh:L43,L171` | Thấp |
| **Sau khi có perf data** | B3 ICache resize | `icache_top.v`, `icache_controller.v` | Cao — cần data trước |
| **Không làm** | A5 CDC | — | Single-clock, không cần |
| **Không làm** | B1 QoS | — | Đã done |
| **Không làm** | B2 Burst | — | Đã done |
| **Không làm** | B4 CSR | — | MMIO đủ dùng, pipeline risk cao |
