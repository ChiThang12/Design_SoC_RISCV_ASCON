# Roadmap Triển Khai H

## 1. Định vị đúng của H

Hướng `H` không đồng nhất với `H3`.

- `H3` chỉ giữ vai trò reference control-plane
- `H` là nhánh triển khai streaming coherent datapath để làm nổi bật đề tài:
  - `A High-Throughput RISC-V SoC with DMA-Enabled Pipelined ASCON Engine for Efficient Secure Communications`

Điều cần giữ rất rõ trong toàn bộ quá trình triển khai:

- không biến H thành “bản đóng gói lại của H3”
- không lấy context banking làm headline chính
- không để reviewer hiểu nhầm speedup đến từ trick control-plane

Headline của H phải nằm ở:

- streaming overlap `read / process / write`
- pipelined ASCON feed path
- ping-pong buffering
- coherency policy phục vụ throughput end-to-end

## 2. Vai trò của H3 trong nhánh H

H3 vẫn rất có giá trị, nhưng chỉ ở vai trò tham chiếu:

- reference cho `CONTEXT_SEL`
- reference cho `context_id_active`
- reference cho context isolation
- reference benchmark cho control-plane cost
- reference để trả lời câu hỏi multi-session correctness

Nhưng H3 không phải đích đến của H:

- H3 không phải datapath headline
- H3 không phải kiến trúc paper chính
- H3 không phải mục tiêu tối ưu throughput

Nói ngắn gọn:

- `H3 = control-plane baseline`
- `Dot C cũ = baseline payload datapath`
- `H mới = streaming coherent accelerator implementation`

## 3. Mục tiêu triển khai của H

Mục tiêu kỹ thuật của H là tạo ra một datapath có thể chứng minh 4 điều:

1. CPU chỉ setup và kick, không phải data mover chính
2. `read / process / write` overlap được ở steady-state
3. pipeline ASCON được giữ bận, không bị starvation không cần thiết
4. output được ghi về memory theo coherency policy theo hướng dữ liệu

Từ thời điểm hiện tại, roadmap của H còn cần khóa thêm 2 bằng chứng vi kiến trúc:

5. read side có thể tạo `outstanding AR > 1`
6. write side có thể tạo `pending BRESP > 1`

## 4. Kiến trúc H nên trình bày

Kiến trúc của H nên được trình bày thành 2 lớp:

### Lớp 1: Reference control-plane

- context select
- context state retention
- session isolation

Lớp này dùng H3 làm mốc tham chiếu.

### Lớp 2: Headline data-plane

- streaming read scheduler
- ingress buffering
- ASCON processing pipeline
- egress buffering
- direction-aware coherent policy
- runtime counters và overlap metrics

Nếu cần mô tả ngắn gọn:

```text
CPU/firmware
  -> ghi DMA/config registers
  -> streaming read path with coherent input policy
  -> ASCON pipelined processing
  -> streaming write path with direction-aware output policy
  -> firmware checks result and metrics
```

## 5. Roadmap mới theo giai đoạn

## Giai đoạn 1 - Khóa kiến trúc mới

Mục tiêu:

- chốt `streaming DMA pipeline` là đột phá chính
- hạ cấp payload path cũ thành baseline tham chiếu
- giữ `H3` ở đúng vai trò control-plane baseline

Definition of done:

- bộ tài liệu `H` không còn coi Dot C cũ là đích cuối
- kiến trúc mới được mô tả thống nhất ở mọi file

## Giai đoạn 2 - Tái cấu trúc control của datapath

Mục tiêu:

- bỏ phase-level FSM lớn
- đổi sang micro-control theo `credit / counter / scoreboard`

Phạm vi:

- `ascon_dma.v`
- `dma_ctrl_fsm.v`

Definition of done:

- read, core, write được decouple về control
- transaction done được tính theo trạng thái tổng thể, không theo phase cũ

## Giai đoạn 3 - Đưa ping-pong buffering vào datapath

Mục tiêu:

- tạo khả năng overlap `read / process / write`

Phạm vi:

- ingress buffering
- egress buffering
- handoff logic giữa scheduler và core

Definition of done:

- có steady-state datapath có ý nghĩa
- có benchmark nói được overlap không còn là lý thuyết
- RTL đã có `ping-pong bank state`, `read/write policy`, và `credit planner`

## Giai đoạn 4 - Khóa credit-based issue và write chain sớm

Mục tiêu:

- read side không chỉ refill đúng lúc, mà bắt đầu multi-outstanding
- write side không còn phụ thuộc hoàn toàn vào `BVALID` mới issue tiếp

Phạm vi:

- `dma_read_engine.v`
- `dma_write_engine.v`
- testbench metrics riêng

Definition of done:

- read side có log chứng minh `peak accepted outstanding AR = 2`
- write side có log chứng minh `peak pending BRESP = 2`
- suite functional cũ vẫn pass sau khi mở rộng kiến trúc

## Giai đoạn 5 - Khóa direction-aware coherence

Mục tiêu:

- giữ read coherence cho input
- đưa output policy hiệu năng trở thành mặc định

Phạm vi:

- source coherent read
- destination non-temporal / producer-owned mode
- full coherent output làm correctness fallback
- invalidate range calculator cho write side

Definition of done:

- có benchmark tách riêng baseline payload / streaming / fallback full coherent
- có contract firmware rõ cho từng output mode

## 5.1 Tình trạng đã triển khai trong RTL

Tại thời điểm hiện tại, phần implementation headline đã có những mốc sau:

- `dma_read_scheduler` được tách khỏi scoreboard và chỉ còn giữ phần phase/control cần thiết
- `dma_completion_scoreboard` giữ bookkeeping cho done/error
- `dma_ingress_buffer_mgr` và `dma_egress_buffer_mgr` đã dùng ping-pong bank thật
- `dma_pingpong_bank_state` đã tách riêng khỏi buffer manager
- `dma_read_refill_policy` và `dma_write_drain_policy` đã đưa role/readiness của bank vào quyết định
- `dma_read_bank_credit_planner` và `dma_write_bank_credit_planner` đã đưa target burst theo bank vào scheduler/engine
- `dma_payload_feeder` đã được tách thành submodule riêng và có chain-feed có điều kiện
- `dma_runtime_counters` đã có hook nội bộ cho benchmark steady-state
- `dma_read_engine` đã có credit window và behavior hướng multi-outstanding
- `dma_write_engine` đã có response queue nhỏ và chain policy tách khỏi trường hợp `wr_busy`
- `dma_write_inval_range` đã được thêm để tính invalidate theo range của burst

Ngoài ra, testbench cũng đã được khóa thành 2 lớp:

- `tb_ascon_dma.v`: suite functional chính, hiện vẫn giữ `66 PASS / 0 FAIL`
- `tb_dma_overlap_metrics.v`: suite chuyên dụng cho bằng chứng overlap, hiện đo được:
  - `peak accepted outstanding AR = 2`
  - `peak pending BRESP = 2`

Nói ngắn gọn, datapath hiện tại đã đi từ:

- `phase-based DMA`

sang:

- `bank-aware streaming DMA control`
- `credit-aware read issue`
- `early-chained write issue`

Đây chưa phải điểm cuối cùng của H, nhưng đã là lớp kiến trúc trung gian đủ mạnh để trình bày như một hướng tăng throughput có cơ sở.

## Giai đoạn 6 - AD integration trên kiến trúc mới

Mục tiêu:

- đưa AD vào mà không phá payload streaming headline

Definition of done:

- có đường AD chạy trên micro-architecture mới
- có test AEAD full path trên streaming datapath

## Giai đoạn 7 - Chốt benchmark đề tài

Mục tiêu:

- chốt bảng số liệu đúng tinh thần kiến trúc mới

Bảng số liệu nên có:

- H3 control-plane benchmark
- baseline payload datapath
- streaming payload benchmark
- direction-aware coherence sweep
- overlap metrics ở mức engine
- output contract behavior

Nguyên tắc:

- không trộn control-plane metric vào datapath throughput
- không lấy baseline payload để đại diện cho streaming headline
- không viết claim vượt quá log đo được

Definition of done:

- có bảng benchmark dùng được để đưa thẳng vào paper/cuộc thi

## 6. File/nhóm việc nên gán nhãn lại

### Nhóm reference

- tài liệu `H3/`
- test context switching
- benchmark context overhead

### Nhóm baseline datapath

- Dot C
- payload sweep hiện tại
- coherent benchmark cũ

### Nhóm implementation headline

- streaming DMA RTL
- buffering / overlap logic
- credit-based issue
- early write chain
- direction-aware coherence
- firmware streaming benchmark

### Nhóm presentation

- bảng benchmark
- checklist demo
- narrative kiến trúc

## 7. Tiêu chí thành công của H

Hướng H được xem là thành công khi:

- reviewer thấy rõ H3 chỉ là control-plane reference
- reviewer thấy rõ baseline payload chỉ là mốc tham chiếu
- reviewer thấy rõ streaming datapath mới là nguồn throughput headline
- reviewer thấy rõ có bằng chứng vi kiến trúc chứ không chỉ lời mô tả
- simulation và firmware cùng ủng hộ cùng một câu chuyện
- benchmark trả lời đúng title của đề tài
