# Quy trình Debug — Design_SoC_RISCV_ASCON

## 1. Compile & Lint — Xử lý lỗi từ dưới lên

### 1.1. Chạy lint trước simulation
```bash
./workflow/ulint_verilog.sh <file.v>
# Hoặc: iverilog -g2005 -Wall -tnull <file.v>
```

### 1.2. Lỗi phổ biến & cách fix
| Lỗi | Nguyên nhân | Fix |
|-----|-------------|-----|
| `is not a port` | Port name typo hoặc thiếu trong module definition | Kiểm tra port list của module con |
| `Implicit definition of wire` | Wire chưa khai báo | Thêm `wire [W-1:0] signal_name;` |
| `Target wider than source` | Bit-width mismatch | Align width hoặc dùng explicit zero-extend |
| `Unable to bind wire/reg` | `include` thiếu hoặc sai path | Kiểm tra `include chain từ top module |

### 1.3. Thứ tự fix: Bottom-up
1. Fix lỗi ở leaf module (VD: `sync_fifo.v`, `alu.v`)
2. Rồi mới fix module trung gian (VD: `ascon_CORE.v`, `dma_ctrl_fsm.v`)
3. Cuối cùng fix top (VD: `ascon_top.v`, `soc_top.v`)

## 2. Simulation — Chạy và phân tích log

### 2.1. Chạy simulation
```bash
# SoC-level
iverilog -g2005 -o run_soc_ascon.vvp run_soc_ascon.v
vvp run_soc_ascon.vvp > run_soc_ascon.log 2>&1

# ASCON unit-level
iverilog -g2005 -o build_test ascon/tb/ascon_top_tb.v
vvp build_test
```

### 2.2. Đọc log
- Tìm `ERROR`, `FAIL`, `MISMATCH` trong log file.
- Nếu testbench dùng `$display` với format `[PASS]`/`[FAIL]`: grep nhanh.
- ASCON testbench so sánh với golden model Python (`ascon/tb/sw_reference.py`).

## 3. Waveform Trace — Truy vết tín hiệu

### 3.1. Mở waveform
```bash
gtkwave waveform_soc.vcd
# ASCON-specific:
gtkwave waveform_soc.gtkw    # có preset signal groups
```

### 3.2. Quy trình trace (khi output sai)
1. **Xác định thời điểm lỗi**: Tìm cycle mà output bắt đầu sai.
2. **Trace ngược từ output**:
   - Output sai → kiểm tra tín hiệu input tạo ra nó
   - VD: `core_data_out` sai → trace `dp_state_xored` → `state_reg_out` → `perm_state_out`
3. **Chú ý đặc biệt**:
   - **AXI handshake**: Kiểm tra `valid && ready` đúng cycle
   - **FSM transitions**: Xem state machine có bị stuck không
   - **Pipeline registers**: Data có đúng ở đúng stage không
   - **DMA FIFO**: `empty`/`full` flags, `push`/`pop` timing
   - **CPU pipeline**: Kiểm tra tín hiệu IF/ID/EX/MEM/WB tại mỗi stage

### 3.3. Trace cho từng subsystem

#### ASCON DMA (phổ biến nhất hiện tại)
```
Signals quan trọng:
  u_dma.u_ctrl_fsm.pump_state         — 0=IDLE, 1=WAIT_FIRST, 2=STREAM, 3=WAIT_TAG
  u_dma.rd_fifo_fwft_valid            — FWFT data sẵn sàng
  u_dma.core_data_valid               — DMA đã feed data cho CORE
  u_dma.core_aead_start               — Session init pulse
  u_dma.core_block_feed               — Per-block feed pulse
  u_core_cpu.ctrl_busy_sig            — CORE đang xử lý
  u_core_cpu.data_out_valid           — CORE output sẵn sàng
  u_core_cpu.data_ready               — CORE sẵn sàng nhận block tiếp
  u_dma.wr_fifo_push / wr_fifo_full   — WR FIFO status
  M_AXI_ARVALID/ARREADY/RVALID/RLAST — AXI read handshake
  M_AXI_AWVALID/AWREADY/WVALID/WLAST — AXI write handshake
```

#### CPU Pipeline
```
Signals quan trọng:
  pc_if, instr_if                — IF stage
  instr_id, opcode_id            — ID stage decode
  alu_result_ex, branch_taken_ex — EX stage
  alu_result_mem, dcache_req     — MEM stage
  write_back_data_wb, rd_wb      — WB stage
  stall, stall_any, flush_if_id  — Hazard control
  mul_valid_ex, mul_result_direct — Multiplier pipeline
  debug_mode, dbg_state           — Debug FSM
```

## 4. Common Debug Scenarios

### 4.1. ASCON DMA bị stuck (dma_done không bao giờ assert)
**Checklist:**
1. `pump_state` stuck ở `PUMP_WAIT_FIRST`? → CORE chưa output `data_out_valid`
   → Kiểm tra `core_aead_start` có pulse đúng không
   → Kiểm tra `data_valid`/`data_last` feeding vào CORE
2. `pump_state` stuck ở `PUMP_STREAM`? → CORE `data_ready` không lên
   → Kiểm tra CONTROLLER FSM (`ascon_CONTROLLER.v`) state
3. WR FIFO `full` → write engine không drain kịp → AXI write channel blocked
4. Width converter 64→32 bị lệch boundary → kiểm tra `burst_len` setting

### 4.2. CPU fetch instruction sai
**Checklist:**
1. ICache miss → AXI read burst ARLEN/ARSIZE/ARBURST có đúng không?
2. `boot_done` chưa assert → CPU bắt đầu fetch khi IMEM chưa loaded
3. Branch misprediction → `mispredict_ex`, `flush_if_id`, `target_pc_ex`
4. Forwarding sai → kiểm tra `forward_a`/`forward_b` selectors

### 4.3. AXI deadlock
**Checklist:**
1. Slave `AWREADY` stuck 0 → Write FSM của slave bị stuck
2. B channel: `BVALID` lên nhưng master không assert `BREADY`
3. R channel: `RVALID` lên nhưng master không assert `RREADY`
4. Crossbar arbitration → kiểm tra priority và round-robin

## 5. Kỷ luật Fix Bug
1. **Khoanh vùng chính xác** — KHÔNG refactor cả module vì 1 lỗi nhỏ
2. **Comment rõ ràng** — Mỗi fix phải có tag (VD: `// FIX-BUG-TOP5: ...`)
3. **Regression test** — Sau mỗi fix, chạy lại testbench toàn hệ thống
4. **2-strike rule** — Nếu fix 2 lần vẫn sai, dừng lại phân tích lại từ đầu,
   không tiếp tục trial-and-error

## 6. Python Golden Model (ASCON)
```bash
cd ascon/tb
python3 sw_reference.py          # Generate test vectors
python3 ascon.py                 # Full ASCON reference implementation
# Output: ascon_hw_vectors.tv    — test vectors cho RTL testbench
```
So sánh output RTL (`$display` trong testbench) với golden model để xác định
block nào của AEAD pipeline đang sai (INIT / AD / DATA / TAG).