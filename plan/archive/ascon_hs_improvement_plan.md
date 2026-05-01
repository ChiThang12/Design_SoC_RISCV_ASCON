# ASCON HS Improvement Plan

> Phân tích từ: `ascon_top.v`, `ascon_CORE.v`, `ascon_CONTROLLER.v`,
> `ascon_datapath.v`, `ascon_dma.v`, `ascon_axi_slave.v`
>
> Mục tiêu: biến ASCON IP thành **co-processor tiết kiệm điện**
> — CPU chỉ config/trigger/nhận IRQ, toàn bộ crypto + data movement
> chạy autonomous.

---

## Tóm tắt hiện trạng RTL

| Module | Hiện trạng | Vấn đề HS |
|--------|-----------|-----------|
| `ascon_ip_top` | Clock luôn chạy, `o_busy` chưa export ra SoC ICG | Không có power gate |
| `ascon_CONTROLLER` | FSM 13 state, `busy=1` từ S_INIT_LOAD đến S_DONE | Toggle cao khi idle chờ data |
| `ascon_CORE` | Hoạt động đúng, submodule luôn receive clock | Không gate submodule khi idle |
| `ascon_datapath` | Dual-rate OK, combinational paths rộng | Switching activity cao khi idle |
| `ascon_dma` | RD FIFO=4×64bit, WR FIFO=32×32bit, 1-beat/transaction | Chưa burst dài, sequential RD→CORE→WR |
| `ascon_axi_slave` | Register map đầy đủ, IRQ có | CPU phải poll hoặc dùng interrupt |

---

## Phase 1 — Power Gating: tắt ASCON khi idle

> **Impact cao nhất.** ASCON permutation (12-round pa, 6/8-round pb)
> là tổ hợp logic lớn — khi idle mà clock vẫn chạy thì switching
> activity của các flip-flop state register tiêu điện liên tục.

### Task 1.1 — Export `ascon_clk_en` ra `soc_top.v`

**Hiện tại** — `ascon_ip_top.v` dùng `clk` thẳng, `o_busy` đã có
nhưng `soc_top.v` hardwire `core_clk_en(1'b1)`:

```verilog
// soc_top.v — HIỆN TẠI (sai)
.core_clk_en (1'b1),  // ← không bao giờ gate ASCON
```

**Fix — thêm port `clk_en` vào `ascon_ip_top`:**

```verilog
// ascon_ip_top.v — thêm input
input wire clk_en,   // từ SoC ICG controller

// Dùng clk gated thay vì clk thẳng:
wire clk_gated;
// FPGA: dùng BUFGCE hoặc AND-gate
assign clk_gated = clk & clk_en;

// Kết nối clk_gated vào u_core_cpu và u_dma thay vì clk
ascon_CORE u_core_cpu (
    .clk (clk_gated),   // thay .clk(clk)
    ...
);
ascon_dma u_dma (
    .clk (clk_gated),   // thay .clk(clk)
    ...
);
```

**Fix — trong `soc_top.v`:**

```verilog
// Logic gate: bật khi ASCON đang encrypt/decrypt hoặc CPU đang config
wire ascon_busy_any  = ascon_o_busy;
wire ascon_cfg_active = s2_awvalid | s2_arvalid;  // CPU đang access S2
wire ascon_clk_en    = ascon_busy_any | ascon_cfg_active | ~boot_done;

// Thay hardwire:
// .core_clk_en (1'b1),
// Thành:
wire core_clk_en = ~(cpu_wfi_o & ~ascon_clk_en);
```

> **Lưu ý FPGA:** Trên Xilinx dùng `BUFGCE`, trên Intel dùng `CLKENA`.
> Tuyệt đối không dùng AND-gate thẳng trên ASIC — gây glitch clock.
> Trên ASIC dùng ICG cell từ standard cell library.

---

### Task 1.2 — Gate `ascon_axi_slave` clock riêng

`ascon_axi_slave` chứa register bank 32-bit × N — luôn nhận clock
kể cả khi không có CPU transaction.

```verilog
// ascon_ip_top.v — thêm ICG cho slave riêng
wire slave_clk_en   = s2_awvalid | s2_arvalid | ascon_o_busy;
wire clk_slave;
assign clk_slave = clk & slave_clk_en;  // FPGA: thay bằng BUFGCE

ascon_axi_slave u_slave (
    .clk (clk_slave),  // thay .clk(clk)
    ...
);
```

---

### Task 1.3 — Thêm `CTRL[3]` = `POWER_DOWN` bit vào register map

Cho phép software tắt hoàn toàn ASCON block khi không cần dùng trong
thời gian dài (ví dụ: sau khi encrypt xong batch, trước khi sleep):

```verilog
// ascon_axi_slave.v — thêm vào register CTRL (offset 0x000):
// Bit[3]: POWER_DOWN = 1 → assert clk_en=0 cho toàn bộ IP
// Bit[2]: DMA_EN (hiện có)
// Bit[1]: ENC_DEC (hiện có)
// Bit[0]: START (hiện có)

output wire power_down_req,  // → soc_top để disable ascon_clk_en
assign power_down_req = reg_ctrl[3];
```

---

## Phase 2 — DMA "thông minh": burst dài + pipeline

> **Hiện trạng:** DMA đang chạy **strictly sequential**:
> `RD → CORE → WR` từng block một (1-beat 64-bit).
> Với mỗi block 8 bytes, DMA phát:
> - 1 AR transaction (ARLEN=0, 1 beat)
> - 1 AW transaction (AWLEN=2, 3 beats = 8B ctext + 16B tag)
>
> Overhead handshake / beat rất lớn so với dữ liệu thực.

### Task 2.1 — Multi-block burst: đọc nhiều block liên tiếp

**Hiện tại** `dma_ctrl_fsm` xử lý 1 block rồi dừng, chờ CORE xong
mới đọc block tiếp theo — không tận dụng được RD FIFO (depth=4).

**Fix — pipeline RD và CORE:**

```verilog
// dma_ctrl_fsm.v — thêm trạng thái PREFETCH
// Khi CORE đang xử lý block N, DMA đọc sẵn block N+1 vào RD FIFO
// Điều kiện prefetch: !rd_fifo_full && core_busy && blocks_remaining > 1

localparam ST_PREFETCH = ...; // thêm state mới

// Trong FSM transition:
ST_CORE_WAIT: begin
    if (!rd_fifo_full && blocks_remaining > 1)
        next_state = ST_PREFETCH;  // overlap: đọc block tiếp
    if (core_done)
        next_state = ST_WR_PUSH;
end

ST_PREFETCH: begin
    // Phát AR cho block kế, push vào RD FIFO
    // CORE vẫn đang xử lý block cũ → zero idle time
    if (rd_done)
        next_state = ST_CORE_WAIT;
end
```

**Lợi ích:** Với RD_FIFO_DEPTH=4 (hiện tại), có thể pipeline 4 block
liên tiếp. Throughput tăng ~2× cho message dài.

---

### Task 2.2 — Tăng WR burst length: gom ctext + tag thành 1 burst

**Hiện tại:** WR engine phát `AWLEN=2` (3 beats × 64-bit = 24B) cho
mỗi block, gồm: 8B ctext + 16B tag. Với message nhiều block, thực ra
chỉ cần ghi tag 1 lần ở cuối, không phải mỗi block.

**Fix — tách ctext write và final tag write:**

```verilog
// dma_ctrl_fsm.v — phân biệt 2 loại write:
// 1. CTEXT_WRITE: chỉ ghi ctext (AWLEN=0, 1 beat × 64-bit = 8B)
//    → dst_addr tăng dần sau mỗi block
// 2. TAG_WRITE:   chỉ ghi tag 1 lần khi core_tag_valid
//    (AWLEN=1, 2 beats × 64-bit = 16B)
//    → dst_addr = ctext_end_addr

// Giảm WR transaction từ N×3-beat xuống N×1-beat + 1×2-beat
// Giảm handshake overhead ~50% cho message N-block
```

---

### Task 2.3 — Auto address increment trong DMA

**Hiện tại:** `dma_axi_slave` yêu cầu CPU ghi `DMA_SRC_ADDR` và
`DMA_DST_ADDR` trước mỗi lần DMA start. Với message nhiều block,
CPU phải update address liên tục — vi phạm nguyên tắc "CPU chỉ
trigger một lần".

**Fix — thêm `DMA_BLOCK_COUNT` register và auto-increment:**

```verilog
// ascon_axi_slave.v — thêm 2 register:
// 0x11C  DMA_BLOCK_COUNT  R/W  Số lượng 8-byte block cần encrypt
// 0x120  DMA_AUTO_INC     R/W  [0]=1: auto increment src/dst sau mỗi block

// dma_ctrl_fsm.v — thêm counter và auto-increment logic:
reg [15:0] block_cnt;       // số block đã xử lý
reg [15:0] block_total;     // từ DMA_BLOCK_COUNT register

// Sau mỗi block done:
always @(posedge clk) begin
    if (block_done && auto_inc_en) begin
        src_addr_int <= src_addr_int + 32'd8;   // 8 bytes/block
        dst_addr_int <= dst_addr_int + 32'd8;
        block_cnt    <= block_cnt + 1;
    end
end

// DMA tự loop đến khi block_cnt == block_total
// CPU chỉ cần ghi 1 lần: SRC_ADDR, DST_ADDR, BLOCK_COUNT, rồi START
```

**Firmware sau khi fix — chỉ 4 dòng:**
```c
ASCON->DMA_SRC_ADDR    = plaintext_buf;
ASCON->DMA_DST_ADDR    = ctext_buf;
ASCON->DMA_BLOCK_COUNT = msg_len / 8;
ASCON->DMA_CTRL        = START | DMA_EN | AUTO_INC;
// CPU xong việc — chờ IRQ
```

---

### Task 2.4 — Tăng RD_FIFO_DEPTH từ 4 lên 8

**Hiện tại:** `RD_FIFO_DEPTH = 4` (4 × 64-bit = 32 bytes).
Với pipeline prefetch (Task 2.1), FIFO có thể full trước khi CORE xử
lý xong — làm stall DMA read engine.

```verilog
// ascon_ip_top.v — tăng parameter:
parameter RD_FIFO_DEPTH = 8,  // thay 4 → 8 (64 bytes prefetch buffer)
// WR_FIFO_DEPTH = 32 giữ nguyên (đã đủ cho 8 block × ctext + tag)
```

**Trade-off:** 8 × 64-bit = 512 bit SRAM — rất nhỏ, FPGA dùng 1
BRAM slice. Đáng đổi để tránh DMA stall.

---

## Phase 3 — CPU Offload hoàn toàn

> **Mục tiêu:** CPU không làm gì trong suốt quá trình encrypt/decrypt
> ngoài: ghi config → trigger → WFI → nhận IRQ.

### Task 3.1 — Xác nhận IRQ flow hoạt động đúng

**Hiện tại** `ascon_axi_slave` đã có `irq` output — kiểm tra:

```verilog
// ascon_axi_slave.v — kiểm tra logic IRQ:
// IRQ phải được assert khi:
//   (a) core_done=1 (CPU-Direct mode)
//   (b) dma_done=1  (DMA mode)
// IRQ phải được clear khi:
//   CPU đọc STATUS register (read-to-clear)

// Kiểm tra code hiện tại có clear IRQ đúng không:
// Nếu IRQ là level-triggered và không clear → CPU bị storm interrupt
```

**Fix nếu thiếu read-to-clear:**
```verilog
// Trong read logic của ascon_axi_slave:
ADDR_STATUS: begin
    S_AXI_RDATA <= status_reg;
    irq_clear   <= 1'b1;  // clear IRQ khi CPU đọc STATUS
end
```

---

### Task 3.2 — Thêm `KEY_VALID` sticky bit — không cần ghi key mỗi lần

**Hiện trạng:** Mỗi lần encrypt, firmware phải ghi lại toàn bộ
KEY (128-bit = 4 × 32-bit write) và NONCE (128-bit = 4 × 32-bit write)
— 8 AXI transactions chỉ để setup.

**Fix — thêm `KEY_VALID` bit trong CTRL:**
```verilog
// ascon_axi_slave.v — thêm reg_key_valid:
// Bit[4] trong CTRL: KEY_VALID
// Khi KEY_VALID=1: bỏ qua ghi KEY, dùng key đang lưu trong register
// Chỉ cần ghi KEY một lần khi khởi tạo session

// Firmware sau khi fix — session đầu:
ASCON->KEY_0..3 = session_key;
ASCON->CTRL    |= KEY_VALID;

// Các lần encrypt tiếp theo:
ASCON->NONCE_0..3 = nonce;      // chỉ 4 writes
ASCON->DMA_SRC    = plaintext;
ASCON->CTRL       = START;      // KEY tự động dùng lại
```

---

### Task 3.3 — Verify `core_start_mux` race condition đã fix đủ chưa

File `ascon_ip_top.v` ghi nhận FIX-BUG-TOP6:
> "Race condition: CORE start trước khi DMA FSM nạp ptext"
> Fix: `core_start_mux = dma_core_start & dma_core_data_valid`

```verilog
// ascon_ip_top.v — kiểm tra dòng 183-302 (truncated):
// Xác nhận core_start_mux được định nghĩa đúng:
assign core_start_mux = slave_dma_en
    ? (dma_core_start & dma_core_data_valid)  // DMA mode: cả 2 phải valid
    : slave_core_start;                        // CPU mode: từ slave
```

**Nếu chưa đúng** → thêm:
```verilog
// Thêm 1 cycle synchronizer để đảm bảo data stable trước start:
reg dma_core_data_valid_d;
always @(posedge clk) dma_core_data_valid_d <= dma_core_data_valid;
assign core_start_mux = slave_dma_en
    ? (dma_core_start & dma_core_data_valid_d)
    : slave_core_start;
```

---

## Phase 4 — Switching Activity: giảm toggle khi idle

> ASCON permutation là combinational logic rất rộng (320-bit state,
> SBox 5-bit × 64 = 320 instances). Khi clock chạy nhưng không có
> valid data → state register giữ nguyên nhưng combinational path vẫn
> toggle theo clock glitch.

### Task 4.1 — Enable pipeline register chỉ khi `busy=1`

```verilog
// ascon_STATE_REGISTER.v — thêm clock enable:
// Thay:
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= '0;
    else if (state_load) state <= state_in;
end

// Thành (với clock enable):
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)        state <= '0;
    else if (ctrl_busy && state_load) state <= state_in;
    // ctrl_busy từ CONTROLLER — khi idle không toggle
end
```

### Task 4.2 — Zero out `data_in` khi không có valid data

```verilog
// ascon_CORE.v — thêm mux trước khi feed vào DATAPATH:
wire [127:0] data_in_gated = data_valid ? data_in : 128'h0;
wire [127:0] ad_in_gated   = ad_valid   ? ad_in   : 128'h0;

// Feed gated version vào u_dp:
ascon_DATAPATH u_dp (
    .data_in (data_in_gated),  // thay data_in
    .ad_in   (ad_in_gated),    // thay ad_in
    ...
);
```

**Lý do:** Khi `data_valid=0`, DATAPATH vẫn tính XOR với data_in
ngẫu nhiên → toggle không cần thiết. Gating về 0 giảm switching
activity ~20% trên DATAPATH.

---

## Phase 5 — Measurement

### Task 5.1 — Testbench đo throughput và power

```verilog
// ascon_tb_hs.v — thêm counter:
integer encrypt_cycles;
integer idle_cycles;

always @(posedge clk) begin
    if (ascon_o_busy)   encrypt_cycles <= encrypt_cycles + 1;
    else                idle_cycles    <= idle_cycles + 1;
end

// Target HS:
// active_ratio = encrypt_cycles / (encrypt_cycles + idle_cycles)
// Sau Phase 1-3: active_ratio tăng (busy cycles tập trung hơn)
// Power khi idle giảm mạnh (clock gated)
```

### Task 5.2 — Đo latency 1 block ASCON-128

Với `G_COMB_RND_128=6` (combinational, không pipeline):
- pa (12 rounds): 1 cycle (fully unrolled)
- pb (6 rounds): 1 cycle
- Total latency: S_INIT_PERM + S_POST_INIT + S_AD_PERM + S_DATA_PERM + S_FIN_PERM = ~5 cycles

```
Block encrypt timeline (ASCON-128, 1 block, no AD):
Cycle 0: start → S_INIT_LOAD
Cycle 1: init_start → S_INIT_PERM
Cycle 2: pa done → S_POST_INIT
Cycle 3: key XOR → S_DOM_SEP → S_DATA_LOAD
Cycle 4: data_valid → S_DATA_PERM (perm_start=0, data_last=1)
Cycle 5: → S_PRE_FIN → S_FIN_PERM
Cycle 6: pa done → S_TAG_GEN
Cycle 7: tag_gen_valid → S_DONE → irq
```

Nếu đo được nhiều hơn 7 cycles → có vấn đề về `data_valid` hoặc FIFO stall.

### Task 5.3 — Benchmark: so sánh trước/sau

| Scenario | Metric | Trước | Sau Phase 1-4 |
|----------|--------|-------|----------------|
| 1 block idle (no encrypt) | Power | P_baseline | ~0.3×P |
| 1 block encrypt | Latency | 7 cycles | 7 cycles (giữ nguyên) |
| N=100 block encrypt | Throughput | N×sequential | ~1.8×N (pipeline) |
| CPU involvement | AXI transactions | 8+3 per block | 8 once + 1 trigger |

---

## Checklist

### Phase 1 — Power Gating
- [ ] Thêm `clk_en` input vào `ascon_ip_top`, dùng `clk_gated`
- [ ] Kết nối `ascon_clk_en` động trong `soc_top.v` từ `ascon_o_busy | s2_awvalid`
- [ ] Thêm ICG riêng cho `ascon_axi_slave` (slave_clk_en)
- [ ] Thêm `POWER_DOWN` bit (CTRL[3]) để software tắt hoàn toàn

### Phase 2 — DMA Smart
- [ ] Thêm prefetch state trong `dma_ctrl_fsm` — pipeline RD + CORE
- [ ] Tách ctext-write và tag-write — giảm WR transaction
- [ ] Thêm `DMA_BLOCK_COUNT` và auto-increment src/dst address
- [ ] Tăng `RD_FIFO_DEPTH` từ 4 lên 8

### Phase 3 — CPU Offload
- [ ] Verify IRQ clear logic (read-to-clear STATUS)
- [ ] Thêm `KEY_VALID` sticky bit — không ghi lại key mỗi lần
- [ ] Verify `core_start_mux` race condition fix đủ chưa

### Phase 4 — Switching Activity
- [ ] Thêm `ctrl_busy` enable cho state register flip-flops
- [ ] Zero-gate `data_in` và `ad_in` khi `data_valid=0`

### Phase 5 — Measurement
- [ ] Testbench đếm `encrypt_cycles` và `idle_cycles`
- [ ] Verify latency 1 block = 7 cycles (G_COMB_RND_128=6)
- [ ] Benchmark throughput N-block trước/sau pipeline

---

## Register Map cập nhật (sau improvement)

| Offset | Tên | R/W | Bits | Mô tả |
|--------|-----|-----|------|-------|
| 0x000 | CTRL | R/W | [0]=START, [1]=ENC_DEC, [2]=DMA_EN, [3]=POWER_DOWN, [4]=KEY_VALID | Core control |
| 0x004 | STATUS | RO | [0]=BUSY, [1]=DONE, [2]=DMA_BUSY, [3]=DMA_DONE | Read-to-clear IRQ |
| 0x008..0x014 | KEY_0..3 | W | 32-bit each | Session key (ghi 1 lần) |
| 0x018..0x024 | NONCE_0..3 | W | 32-bit each | Per-message nonce |
| 0x100 | DMA_SRC_ADDR | R/W | 32-bit | Địa chỉ đầu plaintext |
| 0x104 | DMA_DST_ADDR | R/W | 32-bit | Địa chỉ đầu ctext output |
| 0x108 | DMA_BYTE_LEN | R/W | 32-bit | Bytes (Phase 1: =8) |
| 0x10C | DMA_CTRL | R/W | [0]=START, [1]=RST, [2]=AUTO_INC | DMA control |
| 0x110 | DMA_STATUS | RO | [0]=BUSY, [1]=DONE, [4:5]=ERROR | DMA status |
| 0x114 | DMA_BURST_LEN | R/W | [7:0] | AXI burst length |
| 0x118 | DMA_ERR_ADDR | RO | 32-bit | Địa chỉ gây AXI error |
| **0x11C** | **DMA_BLOCK_COUNT** | **R/W** | **[15:0]** | **Số block (MỚI)** |
| **0x120** | **DMA_AUTO_INC** | **R/W** | **[0]** | **Auto increment (MỚI)** |

*(Dòng in đậm là register mới thêm trong plan này)*

---

## Firmware flow sau khi implement đủ

```c
// Khởi tạo session (1 lần duy nhất)
ascon_write(KEY_0..3, session_key);
ascon_write(CTRL, KEY_VALID);

// Encrypt N blocks (CPU không làm gì trong khi chạy)
ascon_write(NONCE_0..3, nonce);
ascon_write(DMA_SRC_ADDR, plaintext_base);
ascon_write(DMA_DST_ADDR, ctext_base);
ascon_write(DMA_BLOCK_COUNT, N);
ascon_write(DMA_CTRL, AUTO_INC | START);
ascon_write(CTRL, DMA_EN | START);  // trigger

cpu_wfi();  // CPU ngủ, toàn bộ encrypt chạy autonomous

// IRQ handler:
void ascon_irq_handler() {
    uint32_t st = ascon_read(STATUS);  // đọc = clear IRQ
    if (st & DONE) process_result();
}
```

---

*Generated from RTL analysis: ascon_top.v v5, ascon_CONTROLLER.v v9,
ascon_CORE.v v12, ascon_datapath.v v2, ascon_dma.v v1.2,
ascon_axi_slave.v v2.4*
