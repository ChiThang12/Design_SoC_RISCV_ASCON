# Kiến Trúc Đột Phá H

## 1. Định vị mới của nhánh H

Nhánh `H` không dừng lại ở mức “DMA-first đã chạy được”.

Từ thời điểm này, định vị kỹ thuật của `H` là:

- `streaming DMA pipeline` là đột phá chính
- `direction-aware coherence` là policy hiệu năng mặc định
- `ping-pong buffering` là mức mở rộng thực dụng đầu tiên
- `H3` tiếp tục chỉ là baseline control-plane

Nói ngắn gọn:

- `H3 = reference control-plane`
- `Dot C cũ = baseline payload datapath`
- `H mới = streaming coherent accelerator datapath`

## 2. Vấn đề của datapath hiện tại

Datapath hiện tại đã chứng minh được:

- CPU không còn là data mover chính
- DMA payload path chạy đúng
- coherent read policy có giá trị

Tuy nhiên, trước khi nâng tiếp, nó vẫn chưa đủ mạnh để trở thành “đột phá kiến trúc” nếu chưa giải quyết rõ các điểm sau:

1. datapath vẫn còn dấu vết phase-sequential
2. full coherent write vẫn có nguy cơ bị kéo lùi bởi pre-invalidate blocking
3. overlap `read / process / write` cần được chứng minh bằng số đo runtime, không chỉ bằng cấu trúc RTL

## 3. Kiến trúc mục tiêu mới

Kiến trúc mục tiêu của `H` nên được trình bày như sau:

```text
CPU/Firmware
  -> cấu hình transaction registers
  -> kick streaming DMA transaction

Ingress side
  -> read scheduler
  -> coherent read / AXI read fallback
  -> ping-pong ingress buffer

ASCON side
  -> payload feeder
  -> pipelined ASCON core
  -> result collector

Egress side
  -> ping-pong egress buffer
  -> direction-aware write policy
  -> AXI writeback
```

## 4. Bốn quyết định kiến trúc cần khóa

### 4.1 Streaming là headline chính

Mục tiêu không còn là:

- đọc xong rồi mới feed
- feed xong rồi mới write

Mục tiêu mới là:

- read đang nạp block kế tiếp
- core đang xử lý block hiện tại
- write đang drain block trước đó

Nói cách khác, `H` phải tiến từ `phase-based DMA` sang `overlap-based DMA`.

### 4.2 Read side phải tiến tới credit-based multi-outstanding

Trên read side, đích không chỉ là “refill đúng lúc”, mà là:

- issue read liên tục khi còn credit
- không để ingress cạn dữ liệu quá sớm
- tận dụng được nhiều giao dịch AR outstanding ở steady-state

RTL hiện tại đã bắt đầu đi đúng hướng này:

- có `credit planner`
- có policy refill theo vai trò của bank
- có cửa sổ issue để read side không chỉ đợi một burst hoàn tất rồi mới xin burst tiếp

Điểm quan trọng nhất vừa được khóa bằng test chuyên dụng:

- trong `tb_dma_overlap_metrics.v`, read side đã đo được `peak accepted outstanding AR = 2`

Điều này cho phép narrative của `H` chuyển từ:

- “read side thông minh hơn một chút”

sang:

- “read side đã bắt đầu có hành vi multi-outstanding thực sự”

### 4.3 Write side phải giảm phụ thuộc vào `BVALID`

Trên write side, mục tiêu không còn là:

- burst xong rồi đợi `BRESP`
- sau đó mới tính burst kế tiếp

Mục tiêu mới là:

- burst hiện tại đang drain
- burst kế tiếp đã có thể được issue sớm hơn
- response chỉ còn là lớp bookkeeping / correctness, không phải nút chặn chính của steady-state

RTL hiện tại đã tiến thêm một bước rõ ràng:

- write side có queue response nhỏ nội bộ
- `chain issue` không còn chỉ phụ thuộc cách nghĩ tuần tự cũ
- policy chain đã được tách khỏi ràng buộc `wr_busy` của burst hiện tại

Bằng chứng mới:

- trong `tb_dma_overlap_metrics.v`, write side đã đo được `peak pending BRESP = 2`

Đây là bằng chứng rất quan trọng, vì nó cho thấy write path đã bắt đầu có ý nghĩa pipeline thực sự, thay vì chỉ nối tiếp từng burst một cách đơn giản.

### 4.4 Ingress/egress buffering phải đủ sâu để che độ trễ

Ping-pong buffering không chỉ là “có hai bank”.

Muốn nó có giá trị về throughput thì:

- độ sâu mỗi bank phải đủ để che trễ AXI
- planner phải nhìn được backlog và vai trò của từng bank
- scheduler/engine phải dùng thông tin đó để issue sớm

Một thay đổi quan trọng đã được đưa vào RTL:

- `RD_FIFO_DEPTH` mặc định đã tăng từ `4` lên `8` mỗi bank ingress

Ý nghĩa:

- tăng headroom cho read side credit-based issue
- giảm nguy cơ read side bị bó cổ chai bởi buffer quá nông
- tạo điều kiện để overlap `read -> core -> write` nhìn rõ hơn ở payload dài

## 5. Thành phần RTL cần nhấn mạnh trong H

### 5.1 Top-level DMA wrapper

`ascon/dma/rtl/ascon_dma.v`

Khi trình bày H, file này không nên được mô tả như một wrapper phase-based nữa.

Vai trò đúng của nó bây giờ là:

- nơi nối `read scheduler`
- `ingress buffer manager`
- `payload feeder`
- `write engine`
- `runtime counter`

Headline nên là:

- `layered streaming DMA control`

không còn là:

- `single large phase FSM`

### 5.2 Read side

`ascon/dma/rtl/dma_read_engine.v`

Read engine mới cần được mô tả đúng như sau:

- có issue theo credit window
- theo dõi outstanding reads
- có thể xin thêm AR khi dữ liệu cũ vẫn đang về
- dùng buffer fill level để tránh tự bó nghẽn

Đây là bước nâng cấp có ý nghĩa kiến trúc thực sự, không chỉ là tinh chỉnh threshold.

### 5.3 Write side

`ascon/dma/rtl/dma_write_engine.v`

Write engine mới cần được mô tả như sau:

- có response queue nhỏ để tách issue khỏi completion
- có chain issue sớm hơn, không bị khóa hoàn toàn bởi `BVALID`
- dùng invalidate range calculator riêng
- vẫn giữ full coherent output như correctness fallback khi cần

### 5.4 Testbench chứng minh kiến trúc

`ascon/dma/tb/tb_dma_overlap_metrics.v`

Đây là một bổ sung rất quan trọng cho H vì:

- nó không chỉ kiểm tra chức năng
- nó trực tiếp kiểm tra dấu hiệu micro-architecture

Cụ thể, testbench này đang dùng để khóa hai điểm:

- `peak accepted outstanding AR = 2`
- `peak pending BRESP = 2`

## 6. Định nghĩa benchmark mới

Khi chuyển sang kiến trúc mới, benchmark headline của `H` cũng phải đổi theo.

Cần nhấn mạnh 3 lớp:

1. `Baseline control-plane`
   - H3 context switch
   - H3 isolation

2. `Baseline payload datapath`
   - Dot C cũ
   - DMA payload path hiện tại

3. `Streaming headline datapath`
   - overlap `read / process / write`
   - direction-aware coherence
   - ping-pong throughput
   - bằng chứng `outstanding AR` và `pending BRESP`

Không được trộn 3 lớp này vào một bảng duy nhất.

## 7. Thứ tự thực thi khuyến nghị

Thứ tự đúng cho nhánh `H` từ lúc này:

1. khóa tài liệu kiến trúc mới
2. tái cấu trúc roadmap và checklist theo hướng mới
3. tái cấu trúc kế hoạch RTL theo streaming datapath
4. định nghĩa lại benchmark steady-state
5. thực hiện RTL theo bước an toàn nhất:
   - decouple control
   - ingress/egress buffering
   - credit-based issue
   - early chain write
   - direction-aware coherence
6. cập nhật testbench và benchmark

## 8. Definition of done của nhánh H mới

Nhánh `H` chỉ được xem là đạt đúng mục tiêu mới khi:

- datapath không còn bị hiểu như phase-sequential flow cũ
- read side có bằng chứng multi-outstanding
- write side có bằng chứng pending response > 1
- selective output policy trở thành mode hiệu năng mặc định
- full coherent output được giữ như correctness fallback có chủ đích
- có bảng số liệu tách riêng `baseline payload` và `streaming headline`
