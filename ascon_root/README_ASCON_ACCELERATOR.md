# README: Phân Tích & Cải Tiến IP Ascon-AEAD128 Hướng Đến Hardware Accelerator

> **Mục tiêu tài liệu này:** Mô tả toàn bộ kiến trúc IP Ascon hiện tại, chỉ rõ các điểm nghẽn hiệu năng, và đề xuất cụ thể các cải tiến để biến IP này thành một **hardware accelerator** thực sự — tức là tối ưu throughput, giảm latency, và hỗ trợ tích hợp vào SoC/FPGA.

---

## 1. Tổng Quan Kiến Trúc Hiện Tại

### 1.1 Danh sách module

| File | Module | Vai trò |
|---|---|---|
| `ascon_CORE.v` | `ascon_CORE` | Top-level, kết nối tất cả sub-modules |
| `ascon_CONTROLLER.v` | `ascon_CONTROLLER` | FSM điều khiển toàn bộ luồng xử lý |
| `ascon_PERMUTATION.v` | `ascon_PERMUTATION` | Thực hiện phép hoán vị p6/p8/p12 |
| `ascon_CONSTANT_ADDITION.v` | `CONSTANT_ADDITION` | Thêm hằng số round vào word x2 |
| `ascon_SUBTITUTION_LAYER.v` | `SUBSTITUTION_LAYER` | Lớp phi tuyến — gọi 64 SBOX song song |
| `ascon_SBOX.v` | `ASCON_SBOX` | S-Box 5-bit (1 instance = 1 bit slice) |
| `ascon_LINEAR_DIFFUSION.v` | `LINEAR_DIFFUSION` | Lớp khuếch tán tuyến tính (xoay bit) |
| `ascon_DATAPATH.v` | `ascon_DATAPATH` | XOR absorb, padding, encrypt/decrypt output |
| `ascon_INITIALIZATION.v` | `ascon_INITIALIZATION` | Tạo trạng thái khởi tạo IV‖Key‖Nonce |
| `ascon_STATE_REGISTER.v` | `ascon_STATE_REGISTER` | Register 320-bit lưu trạng thái |
| `ascon_TAG_GENERATOR.v` | `ascon_TAG_GENERATOR` | Tạo authentication tag |
| `ascon_TAG_COMPARATOR.v` | `ascon_TAG_COMPARATOR` | So sánh tag nhận được (decrypt) |

### 1.2 Sơ đồ luồng xử lý (Ascon-AEAD128)

```
START
  │
  ▼
[Initialization]  Key ‖ Nonce → p12 → XOR Key  (12 cycles)
  │
  ▼
[AD Absorption]   Mỗi 16-byte AD block → XOR absorb → p8        (8 cycles/block)
  │
  ▼
[Domain Sep]      x4[MSB] ^= 1
  │
  ▼
[Data Processing] Mỗi 16-byte PT/CT block → XOR → output CT/PT → p8  (8 cycles/block)
  │
  ▼
[Finalization]    XOR Key → p12 → XOR Key → Tag               (12 cycles)
  │
  ▼
DONE
```

### 1.3 Tổng latency hiện tại (ước tính)

Với N_ad block AD và N_data block dữ liệu:

```
Latency = 4 (init setup)
        + 12 (p12 init)
        + N_ad × (2 + 8)        ← 2 cycle FSM + 8 cycle perm
        + 2 (domain sep)
        + N_data × (2 + 8)      ← 2 cycle FSM + 8 cycle perm, trừ block cuối
        + 4 (finalize setup)
        + 12 (p12 final)
        + 2 (tag gen + wait)
        ≈ 36 + 10×N_ad + 10×N_data  (cycles)
```

**Ví dụ thực tế:** 1 block AD + 1 block data = ~56 cycles.

---

## 2. Các Điểm Nghẽn Hiệu Năng (Bottlenecks)

---

### 🔴 BN-01: Permutation Iterative — 1 Round Per Cycle

**Mức độ:** Nghiêm trọng — đây là bottleneck lớn nhất.

**Vị trí:** `ascon_PERMUTATION.v`

**Mô tả vấn đề:**

Module `ascon_PERMUTATION` hiện tại chỉ instantiate **một bộ** Constant Addition + Substitution + Linear Diffusion, và thực hiện **một round mỗi clock cycle** trong một vòng lặp tuần tự. Do đó:
- p12 (init, finalize) = **12 clock cycles**
- p8 (AD/data processing) = **8 clock cycles**

Toàn bộ thời gian xử lý chủ yếu bị chiếm bởi việc chờ permutation hoàn thành.

**Đoạn code minh chứng:**
```verilog
// ascon_PERMUTATION.v — line 106–118
else if (running) begin
    current_state <= {x0_diff, x1_diff, x2_diff, x3_diff, x4_diff};
    round_counter <= round_counter + 1'b1;
    rounds_done   <= rounds_done + 1'b1;
    if (rounds_done + 1'b1 == rounds_reg) begin
        // Xong — nhưng phải đợi rounds_reg cycles
        done <= 1'b1;
        running <= 1'b0;
    end
end
```

**Giải pháp đề xuất — Full Unrolling:**

Tạo file mới `ascon_PERMUTATION_UNROLLED.v` với N bộ round stages nối tiếp nhau bằng wire, không dùng register giữa các round:

```verilog
// Mỗi round là một module tổ hợp
module round_stage (
    input  [319:0] state_in,
    input  [3:0]   round_idx,
    output [319:0] state_out
);
    // Constant Addition + Substitution + Linear Diffusion
    // Toàn bộ là combinational logic (không có clk/register)
endmodule

// p12: nối 12 stages, kết quả ra ngay trong 1 cycle
module ascon_PERMUTATION_UNROLLED_P12 (
    input  [319:0] state_in,
    output [319:0] state_out,
    output         done        // = 1'b1 (constant)
);
    wire [319:0] s[0:12];
    assign s[0] = state_in;
    genvar i;
    generate
        for (i = 0; i < 12; i = i+1) begin
            round_stage u(.state_in(s[i]), .round_idx(i), .state_out(s[i+1]));
        end
    endgenerate
    assign state_out = s[12];
    assign done = 1'b1;
endmodule
```

**Tùy chọn Partial Unrolling** (nếu diện tích bị hạn chế):
- 2 rounds/cycle → p12: 6 cycles, p8: 4 cycles
- 4 rounds/cycle → p12: 3 cycles, p8: 2 cycles

**Lợi ích kỳ vọng:**

| Phương án | p12 (cycles) | p8 (cycles) | Tăng tốc tương đối |
|---|---|---|---|
| Hiện tại (1 round/cycle) | 12 | 8 | 1× |
| Partial 2 rounds/cycle | 6 | 4 | ~2× |
| Partial 4 rounds/cycle | 3 | 2 | ~4× |
| Full unrolling (combinational) | 1* | 1* | ~8–12× |

*Với full unrolling, critical path sẽ dài hơn, cần kiểm tra timing sau P&R.

---

### 🟠 BN-02: FSM Có Nhiều State Tuần Tự Không Cần Thiết

**Mức độ:** Đáng kể — lãng phí 6–10 cycle mỗi lần encryption.

**Vị trí:** `ascon_CONTROLLER.v`

**Mô tả vấn đề:**

Nhiều state trong FSM chỉ đơn giản là **set một vài signal rồi chuyển ngay sang state tiếp theo trong cycle sau**, không thực hiện công việc thực sự nào. Đây là overhead cố định không phụ thuộc vào kích thước dữ liệu.

**Danh sách state lãng phí:**

| State | Việc làm | Vấn đề |
|---|---|---|
| `S_LOAD_KEY` | Chỉ set `load_key=1` | Có thể gộp vào `S_INIT` |
| `S_LOAD_NONCE` | Chỉ set `load_nonce=1` | Có thể gộp vào `S_INIT` |
| `S_INIT` | Chỉ set `init_start=1` | Ba state này = 3 cycles lãng phí |
| `S_ABSORB_AD` | Chỉ set `dp_block_sel=2'b00` | Có thể gộp vào `S_AD_LOAD` |
| `S_PROC_DATA` | Chỉ set `dp_block_sel=2'b01` | Có thể gộp vào `S_DATA_LOAD` |
| `S_DOM_SEP` | Không làm gì, chuyển ngay | Merge vào `S_DOM_SEP_LOAD` |
| `S_FINALIZE` | Không làm gì, chuyển ngay | Merge vào `S_FIN_LOAD` |

**Giải pháp:** Gộp các state liên tiếp không có dependency thực sự:

```
Hiện tại: S_LOAD_KEY → S_LOAD_NONCE → S_INIT → S_INIT_LOAD  (4 cycles)
Sau fix:  S_INIT_SETUP (set load_key, load_nonce, init_start cùng lúc) → S_INIT_LOAD  (2 cycles)

Hiện tại: S_ABSORB_AD → S_AD_LOAD  (2 cycles)
Sau fix:  S_AD_LOAD (set cả dp_block_sel + dp_pad_enable + state_load)  (1 cycle)
```

**Lợi ích:** Tiết kiệm ~7 cycles/lần encryption (overhead cố định), quan trọng hơn khi encrypt dữ liệu ngắn.

---

### 🟡 BN-03: Không Có Pipelining Giữa Các Block

**Mức độ:** Trung bình — cần kết hợp với BN-01 để tận dụng tối đa.

**Vị trí:** Toàn bộ luồng `CONTROLLER → PERMUTATION`

**Mô tả vấn đề:**

Sau khi permutation xong cho block thứ N, FSM phải đi qua các state `POST_AD_LOAD → ABSORB_AD → AD_LOAD` (ít nhất 2–3 cycle) trước khi bắt đầu load block N+1. Trong thời gian này, permutation unit hoàn toàn nhàn rỗi.

Với kiến trúc hiện tại (permutation 8 cycles), overhead 2–3 cycle là ~25–37%. Nếu đã unroll permutation (còn 1 cycle), overhead này chiếm tỷ lệ còn lớn hơn.

**Giải pháp — 2-Stage Pipeline:**

```
Cycle N:   [Block K: XOR absorb + output] | [Block K-1: Permutation đang chạy]
Cycle N+1: [Block K: Permutation đang chạy] | [Block K+1: XOR absorb + output]
```

Yêu cầu thay đổi:
1. Thêm 1 buffer register 320-bit để giữ state đang chờ
2. Thêm input FIFO 2 entry để prefetch block tiếp theo
3. Sửa FSM để issue permutation sớm hơn 1 cycle

---

### 🟡 BN-04: Không Có Giao Tiếp Streaming (AXI-Stream)

**Mức độ:** Trung bình — quan trọng khi tích hợp vào SoC.

**Vị trí:** Interface của `ascon_CORE.v`

**Mô tả vấn đề:**

Interface hiện tại dùng mô hình **register-based**: caller phải set `data_in`, `ad_in`, `data_len`, `data_last` và đợi FSM sẵn sàng nhận từng block một. Điều này có nghĩa là:
- Host CPU/DMA phải polling `busy` signal
- Không có buffer → mỗi lần FSM chuyển sang `S_ABSORB_AD` hoặc `S_PROC_DATA`, dữ liệu phải đã sẵn sàng
- Gây idle time nếu dữ liệu từ memory/DMA chậm hơn một chút

**Giải pháp — AXI4-Stream Slave Interface:**

Thêm một wrapper module `ascon_AXI_WRAPPER.v` bao ngoài `ascon_CORE`:

```
Host/DMA → [AXI4-Stream FIFO (depth=4)] → ascon_CORE → [AXI4-Stream Master] → Output
```

Signals chuẩn AXI-Stream cần thêm:
```verilog
// AD Input channel
input  wire [127:0] s_axis_ad_tdata,
input  wire         s_axis_ad_tvalid,
input  wire         s_axis_ad_tlast,
output wire         s_axis_ad_tready,

// Data Input channel
input  wire [127:0] s_axis_data_tdata,
input  wire         s_axis_data_tvalid,
input  wire         s_axis_data_tlast,
output wire         s_axis_data_tready,

// Data Output channel
output wire [127:0] m_axis_data_tdata,
output wire         m_axis_data_tvalid,
input  wire         m_axis_data_tready,
```

---

### 🟢 BN-05: Debug Statements Trong RTL Synthesizable Code

**Mức độ:** Nhỏ — không ảnh hưởng synthesis nhưng làm chậm simulation và không chuyên nghiệp.

**Vị trí:**
- `ascon_DATAPATH.v` — line 287–289
- `ascon_CORE.v` — line 267–277

**Mô tả vấn đề:**

Các lệnh `$display` đang nằm trong `always @(posedge clk)` block của module synthesizable. Điều này:
- Làm simulation chạy chậm hơn đáng kể với dữ liệu lớn
- Gây ra output log khổng lồ
- Không được bao bởi `` `ifdef SIMULATION `` guard

**Giải pháp:**

```verilog
// Bọc tất cả $display bằng ifdef
`ifdef SIMULATION
    always @(posedge clk) begin
        if (ctrl_state_load) begin
            $display("  [CORE DBG] ...", ...);
        end
    end
`endif
```

Hoặc xóa hoàn toàn nếu IP đã verified.

---

### 🟢 BN-06: Tag Generator Dùng Registered Output Không Cần Thiết

**Mức độ:** Nhỏ — lãng phí 1–2 cycle.

**Vị trí:** `ascon_TAG_GENERATOR.v`, `ascon_CONTROLLER.v`

**Mô tả vấn đề:**

`ascon_TAG_GENERATOR` sử dụng registered output: khi `gen_tag=1` được assert ở cycle N, `tag_valid` chỉ được set ở cycle N+1. Vì vậy controller phải có thêm state `S_WAIT_TAG_VALID` để chờ.

Tag generation chỉ là một phép XOR đơn giản — không có lý do kỹ thuật nào cần register hóa output.

**Giải pháp:** Chuyển tag generation sang combinational:

```verilog
// ascon_TAG_GENERATOR — combinational version
assign tag_out = {
    bswap64(state_in[127:64] ^ bswap64(key_in[127:64])),
    bswap64(state_in[ 63: 0] ^ bswap64(key_in[ 63: 0]))
};
assign tag_valid = gen_tag;  // valid ngay khi gen_tag được assert
```

Sau đó bỏ state `S_WAIT_TAG_VALID` trong FSM → tiết kiệm thêm 1 cycle.

---

### 🟢 BN-07: STATE_REGISTER Có Mux Nội Bộ Redundant

**Mức độ:** Nhỏ — gây phức tạp không cần thiết.

**Vị trí:** `ascon_STATE_REGISTER.v`, `ascon_CORE.v`

**Mô tả vấn đề:**

`ascon_STATE_REGISTER` có port `src_sel` và mux nội bộ để chọn giữa `init_state`, `dp_state`, `perm_state`. Tuy nhiên trong `ascon_CORE.v`, cả ba port này đều được nối vào cùng một wire `state_next_final` (mux đã được thực hiện bên ngoài ở CORE). Kết quả: mux trong STATE_REGISTER là dead logic.

**Giải pháp:** Đơn giản hóa STATE_REGISTER thành:

```verilog
module ascon_STATE_REGISTER (
    input  wire         clk, rst_n, load,
    input  wire [319:0] state_next,   // đã được mux từ CORE
    output reg  [319:0] state_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    state_out <= 320'h0;
        else if (load) state_out <= state_next;
    end
endmodule
```

---

## 3. Bảng Tóm Tắt Tất Cả Cải Tiến

| ID | Vấn đề | Module ảnh hưởng | Mức độ | Tác động | Độ phức tạp implement |
|---|---|---|---|---|---|
| BN-01 | Permutation 1 round/cycle | `ascon_PERMUTATION.v` | 🔴 Cao | Tăng throughput 8–12× | Trung bình |
| BN-02 | FSM states thừa | `ascon_CONTROLLER.v` | 🟠 Cao | Giảm ~7 cycles/op | Thấp |
| BN-03 | Không có pipeline giữa blocks | `CONTROLLER`, `PERMUTATION` | 🟡 TB | Tăng throughput multi-block | Cao |
| BN-04 | Không có AXI-Stream interface | `ascon_CORE.v` | 🟡 TB | Cần thiết cho SoC | Trung bình |
| BN-05 | `$display` không có ifdef guard | `ascon_DATAPATH.v`, `CORE.v` | 🟢 Thấp | Simulation chậm | Rất thấp |
| BN-06 | Tag gen registered thừa | `ascon_TAG_GENERATOR.v` | 🟢 Thấp | Tiết kiệm 1–2 cycles | Thấp |
| BN-07 | STATE_REGISTER mux redundant | `ascon_STATE_REGISTER.v` | 🟢 Thấp | Code sạch hơn | Rất thấp |

---

## 4. Thứ Tự Triển Khai Đề Xuất

Thực hiện theo thứ tự để tối đa hóa lợi ích, tối thiểu hóa rủi ro re-verify:

```
Giai đoạn 1 (Không thay đổi interface, dễ verify):
  ├── BN-05: Thêm ifdef guard cho $display
  ├── BN-07: Đơn giản hóa STATE_REGISTER
  ├── BN-06: Chuyển TAG_GENERATOR sang combinational
  └── BN-02: Merge FSM states thừa trong CONTROLLER

Giai đoạn 2 (Thay đổi PERMUTATION — core change):
  └── BN-01: Implement Partial Unrolling (2 rounds/cycle trước, 4 sau)

Giai đoạn 3 (Thay đổi kiến trúc — cần verify lại toàn bộ):
  ├── BN-01: Full Unrolling nếu timing cho phép
  ├── BN-03: Thêm pipeline 2-stage giữa blocks
  └── BN-04: Thêm AXI-Stream wrapper
```

---

## 5. Lưu Ý Khi Implement

### Về Full Unrolling (BN-01)
- Critical path sẽ qua 12 tầng logic tổ hợp liên tiếp. Cần chạy timing analysis sau synthesis.
- Nếu critical path quá dài, thêm pipeline register giữa mỗi 2–4 round (folded unrolling).
- Tần số clock mục tiêu sẽ quyết định mức unrolling phù hợp.

### Về AXI-Stream (BN-04)
- Nên implement như một wrapper riêng biệt, không sửa `ascon_CORE.v` để giữ nguyên khả năng verify.
- Cần backpressure handling: nếu output FIFO đầy, phải stall input.

### Về Timing Closure
- Sau khi unroll permutation, chạy lại timing analysis trên FPGA target (Xilinx/Intel).
- Nếu Fmax giảm quá nhiều, cân nhắc partial unrolling hoặc thêm register stage.

### Về Verification
- Mỗi thay đổi cần re-run toàn bộ test vector NIST Ascon-AEAD128.
- Đặc biệt kiểm tra: empty AD, empty plaintext, full-block padding edge case (`data_len == 16`).

---

## 6. Cấu Trúc File Đề Xuất Sau Khi Refactor

```
ascon/
├── rtl/
│   ├── ascon_CORE.v                    (sửa: xóa debug, đơn giản hóa mux)
│   ├── ascon_CONTROLLER.v              (sửa: merge states thừa)
│   ├── ascon_STATE_REGISTER.v          (sửa: bỏ mux nội bộ)
│   ├── ascon_DATAPATH.v                (sửa: xóa $display)
│   ├── ascon_INITIALIZATION.v          (giữ nguyên)
│   ├── ascon_TAG_GENERATOR.v           (sửa: combinational output)
│   ├── ascon_TAG_COMPARATOR.v          (giữ nguyên)
│   └── PERMUTATION/
│       ├── ascon_PERMUTATION.v                 (giữ nguyên — reference)
│       ├── ascon_PERMUTATION_UNROLL2.v         (NEW: 2 rounds/cycle)
│       ├── ascon_PERMUTATION_UNROLL4.v         (NEW: 4 rounds/cycle)
│       ├── ascon_PERMUTATION_FULL.v            (NEW: fully combinational)
│       ├── ascon_CONSTANT_ADDITION.v           (giữ nguyên)
│       ├── ascon_SUBTITUTION_LAYER.v           (giữ nguyên)
│       ├── ascon_LINEAR_DIFFUSION.v            (giữ nguyên)
│       └── ascon_ROUND_STAGE.v                 (NEW: single round combinational)
└── wrapper/
    └── ascon_AXI_WRAPPER.v             (NEW: AXI4-Stream interface)
```

---

*Tài liệu này được tạo dựa trên phân tích code RTL Ascon-AEAD128 (NIST submission). Tất cả module gốc đã được verify chức năng đúng — các cải tiến đề xuất chỉ nhằm tăng hiệu năng, không thay đổi hành vi mật mã.*
