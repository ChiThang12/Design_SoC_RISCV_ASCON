# Kế Hoạch RTL

## 1. Mục tiêu RTL

Mục tiêu của bước RTL là tái cấu trúc datapath hiện tại thành một streaming accelerator datapath:

- chạy được trên mô phỏng
- không deadlock
- có thể overlap `read / process / write`
- bám firmware để kiểm chứng
- có bằng chứng vi kiến trúc đủ rõ để dùng trong narrative của H

Trong nhánh `H`, kế hoạch RTL phải luôn tách thành hai phần:

- phần reference: chỉ khóa H3 như control-plane baseline
- phần implementation headline: tái cấu trúc streaming DMA, buffering, và coherence policy

## 2. Ưu tiên triển khai

### Ưu tiên 1

- chốt kiến trúc streaming mới
- chốt nhãn reference vs implementation
- chốt register map tối thiểu cho policy mới
- chốt H3 context bank như baseline control-plane
- chốt baseline payload path cũ như mốc tham chiếu, không phải đích cuối

### Ưu tiên 2

- tách control phase-based thành micro-control streaming
- chốt ingress/egress buffering
- chốt direction-aware coherence
- chốt sticky status/error theo transaction
- chốt `bank credit planner` và `urgency-aware issue`

### Ưu tiên 3

- chốt read side theo credit-based issue thật sự
- chốt write side chain sớm hơn, không đợi hoàn toàn vào `BVALID`
- chốt invalidate theo range cho write side
- chốt benchmark hooks và metrics testbench

### Ưu tiên 4

- chốt AD path trên nền streaming
- chốt log signal cho testbench
- chốt output buffer format

## 3. File RTL cần theo dõi

### File reference baseline

- `ascon_H3/ascon_top.v`
- `ascon_H3/interface/ascon_axi_slave.v`
- `tb_soc/tb_soc_dualcore_suite.v`

### File implementation headline

- `soc_top.v`
- `cache_interface/dcache/dcache_top.v`
- `cache_interface/dcache/dcache_controller.v`
- `cache_interface/dcache/dcache_snoop_ctrl.v`
- `cache_interface/dcache/dcache_snoop_arb_3to1.v`
- `cache_interface/dcache/dcache_snoop_bus_2way.v`
- `cache_interface/dcache/dcache_tag_array.v`
- `ascon/dma/rtl/ascon_dma.v`
- `ascon/dma/rtl/dma_ctrl_fsm.v`
- `ascon/dma/rtl/dma_read_engine.v`
- `ascon/dma/rtl/dma_write_engine.v`
- `ascon/dma/rtl/dma_write_inval_range.v`
- `ascon/dma/rtl/dma_snoop_arb.v`
- `ascon/dma/tb/tb_ascon_dma.v`
- `ascon/dma/tb/tb_dma_overlap_metrics.v`

## 4. Danh sách việc cần kiểm

### Nhóm reference

- kiểm tra mux context
- kiểm tra context latch
- kiểm tra start/busy/done theo context

### Nhóm implementation

- kiểm tra clock/reset
- kiểm tra control decouple `read / core / write`
- kiểm tra buffering ingress/egress
- kiểm tra burst read/write trong steady-state
- kiểm tra planner target burst theo bank
- kiểm tra urgency-driven re-issue / chain issue
- kiểm tra output tag/ciphertext theo write policy
- kiểm tra DMA `DC_SNOOP_*` request/response đi qua đúng DCache snoop fabric
- kiểm tra read snoop hit trả dữ liệu mới nhất khi line còn nằm trong DCache
- kiểm tra write invalidate không để output stale khi dùng fallback coherent mode
- kiểm tra miss-snoop/C2C fill giữa CPU0/CPU1 DCache
- kiểm tra invalidate range theo burst write
- kiểm tra error path

### Nhóm chứng minh overlap

- kiểm tra `outstanding AR > 1`
- kiểm tra `pending BRESP > 1`
- kiểm tra `payload_chain_pulse`
- kiểm tra `write_chain_pulse`
- kiểm tra các counter runtime cho benchmark

## 5. Quy tắc làm RTL

- Mỗi thay đổi RTL phải có test đi kèm.
- Không sửa sâu một lần nhiều khối nếu chưa có test khóa.
- Nếu đổi register map thì firmware và testbench phải đổi cùng lúc.
- Không dùng H3 để đại diện cho streaming datapath.
- Không gộp control-plane fix và datapath optimization vào cùng một claim benchmark.
- Không coi payload path phase-based hiện tại là đích cuối nếu chưa có overlap thực sự.
- Với các thay đổi “đột phá”, phải có test chứng minh ở mức vi kiến trúc, không chỉ ở mức `dma_done`.

## 6. Tình trạng RTL hiện tại

### Đã có trong RTL

- `dma_read_scheduler`
- `dma_completion_scoreboard`
- `dma_pingpong_bank_state`
- `dma_read_refill_policy`
- `dma_write_drain_policy`
- `dma_read_bank_credit_planner`
- `dma_write_bank_credit_planner`
- `dma_payload_feeder`
- `dma_runtime_counters`
- `dma_write_inval_range`
- `dcache_snoop_ctrl`
- `dcache_snoop_arb_3to1`
- `dcache_snoop_bus_2way`

### Đã khóa ở mức hành vi

- `urgency-aware issue` ở read scheduler
- `chain issue` có điều kiện ở write engine
- read side có credit window và issue thêm AR khi điều kiện phù hợp
- write side có response queue nhỏ để giảm phụ thuộc hoàn toàn vào `BVALID`
- ingress mặc định đã tăng độ sâu để hỗ trợ overlap tốt hơn
- DMA có sideband snoop để hỗ trợ direction-aware coherence
- DCache có miss-snoop/C2C path và thống kê peer snoop/C2C forwarding

### Đã khóa ở mức test

- `tb_ascon_dma.v`: giữ regression functional `66 PASS / 0 FAIL`
- `tb_dma_overlap_metrics.v`: chứng minh được:
  - `peak accepted outstanding AR = 2`
  - `peak pending BRESP = 2`
- `tb_dcache_mesi.v` và `tb_dcache_dualcore_protocol.v`: là nhóm test nên giữ làm bằng chứng riêng cho DCache coherence fabric

## 7. Các bước RTL tiếp theo sau mốc hiện tại

Các bước còn lại nên đi tiếp theo thứ tự:

1. nâng benchmark SoC payload dài để phản ánh steady-state rõ hơn
2. đẩy runtime counters ra đường quan sát thuận tiện hơn cho firmware
3. nếu cần, tối ưu tiếp coherent output path ở mode fallback
4. chốt bảng benchmark cho paper/cuộc thi

## 8. Kết luận trạng thái hiện tại

Tại thời điểm này, phần RTL của H đã vượt mức:

- “payload path chạy đúng”

và đang ở mức:

- “streaming DMA datapath có bằng chứng overlap ở mức engine”

Đây là mốc rất quan trọng vì nó cho phép tài liệu H nói về:

- kiến trúc mới
- cơ chế tăng throughput
- bằng chứng đo được

thay vì chỉ dừng ở mô tả ý tưởng.
