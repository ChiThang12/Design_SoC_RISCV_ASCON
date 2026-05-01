# Quy tắc viết code Verilog — Design_SoC_RISCV_ASCON

## 1. Naming Conventions
- Module, signal, wire, reg: `snake_case` (VD: `alu_result`, `data_valid`)
- Parameter, Macro, Localparam: `UPPER_CASE` (VD: `DATA_WIDTH`, `STATE_IDLE`)
- Port suffixes (KHÔNG bắt buộc nhưng khuyến khích):
  - `_w`: wire nội bộ (VD: `core_busy_w`)
  - `_r` hoặc `_ff`: register (VD: `slave_core_start_d`)
  - `_lat`: latched value (VD: `wr_addr_lat`, `wr_id_lat`)
  - `_n`: active-low (VD: `rst_n`, `fabric_rst_n`)
- AXI signal naming: `{M|S}{N}_AXI_{channel}{signal}` hoặc `m{n}_{signal}` / `s{n}_{signal}`
  VD: `S_AXI_AWVALID`, `m0_araddr`, `s2_rdata`

## 2. Cấu trúc Module
- **Tách rõ combinational vs sequential**:
  - Sequential: `always @(posedge clk or negedge rst_n)` → dùng `<=`
  - Combinational: `always @*` hoặc `always @(...)` → dùng `=`
- **KHÔNG mix logic phức tạp** vào sequential block.
- Dự án dùng Verilog-2005 (`-g2005`), KHÔNG dùng `always_ff`/`always_comb`.

## 3. Reset Convention
- Hầu hết module: **async active-low** (`negedge rst_n`)
  ```verilog
  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin ... end
      else begin ... end
  end
  ```
- **NGOẠI LỆ**: `riscv_cpu_core` (và các core sub-module) dùng **active-high** (`posedge rst`):
  ```verilog
  always @(posedge clk or posedge rst) begin
      if (rst) begin ... end
      else begin ... end
  end
  ```
- ASCON DMA module có **soft_rst** (synchronous): check `dma_soft_rst` sau `!rst_n`.
  Thứ tự priority: `!rst_n` → `dma_soft_rst` → normal logic.

## 4. FSM (Finite State Machine)
- Dùng `localparam` cho state encoding:
  ```verilog
  localparam [1:0] STATE_IDLE = 2'd0;
  localparam [1:0] STATE_RUN  = 2'd1;
  ```
- Ưu tiên 2-block hoặc 3-block FSM. Luôn có `default` trong case.
- Ví dụ thực tế trong dự án:
  - `dma_ctrl_fsm.v`: PUMP_IDLE → PUMP_WAIT_FIRST → PUMP_STREAM → PUMP_WAIT_TAG
  - `ascon_CONTROLLER.v`: S_IDLE → S_INIT → S_POST_INIT → S_AD_LOAD → S_DOM_SEP → S_DATA_LOAD → S_DATA_WAIT → S_FIN → S_TAG
  - `ascon_axi_slave.v`: WR_IDLE → WR_DATA → WR_RESP → WR_DONE

## 5. AXI4-Full Protocol Rules
- **Valid KHÔNG ĐƯỢC đợi Ready**: assert `AWVALID`/`WVALID`/`ARVALID` trước hoặc
  cùng cycle với `AWREADY`/`WREADY`/`ARREADY`. Không bao giờ gate valid bằng ready.
- Transaction handshake: hoàn tất khi `valid && ready` tại posedge clk.
- Burst support: slave phải xử lý `AWLEN`/`ARLEN` (số beat = LEN+1).
  - `WLAST` phải assert tại beat cuối. Slave chỉ phát B response sau `WLAST`.
  - `RLAST` phải assert tại beat đọc cuối.
- Write channel: AW và W có thể handshake cùng cycle hoặc khác cycle.
  Slave phải latch AW info (addr, id, len) và chờ W data.
- ID routing: slave phải trả `BID = AWID`, `RID = ARID`.

## 6. Tối ưu Timing & Critical Path
- Tránh nested `? :` quá sâu → dùng AND-OR flat mux:
  ```verilog
  // BAD:
  result = (sel_a) ? val_a : (sel_b) ? val_b : (sel_c) ? val_c : val_d;

  // GOOD:
  assign result = ({32{sel_a}} & val_a) |
                  ({32{sel_b}} & val_b) |
                  ({32{sel_c}} & val_c) |
                  ({32{sel_d}} & val_d);
  ```
- Nếu đường logic quá dài (qua MUL hoặc forwarding chain): thêm pipeline stage.
- Pre-compute trong stage sớm hơn (VD: branch_target tính ở ID thay vì EX).

## 7. Module Instantiation
- Dùng named port connection (`.port_name(wire_name)`), KHÔNG dùng positional.
- Include qua `include "relative/path/to/module.v"` tại top.
- Dự án dùng `include` chain: `soc_top.v` → `cpu/riscv_cpu_core_v2.v` → `cpu/core/*.v`
- `ascon_top.v` → `ascon/interface/*.v`, `ascon/rtl/*.v`, `ascon/dma/*.v`

## 8. Verilator / Icarus Compatibility
- Dùng `/* verilator lint_off UNUSEDSIGNAL */` cho tín hiệu intentionally unused.
- Dùng `/* verilator lint_off PINCONNECTEMPTY */` cho port intentionally unconnected.
- Tránh implicit net declaration → khai báo tường minh tất cả wire.
- Không dùng token-pasting macro (`` ` ``) trên Icarus → khai báo thủ công.