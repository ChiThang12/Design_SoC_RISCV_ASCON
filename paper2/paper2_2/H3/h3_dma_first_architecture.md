# DMA-First ASCON Architecture for the Paper

Tài liệu này mô tả phiên bản kiến trúc nên được đưa vào paper mới theo đúng tinh thần:

> A High-Throughput RISC-V SoC with DMA-Enabled Pipelined ASCON Engine for Efficient Secure Communications

H3 multi-context vẫn giữ vai trò reference design cho control-plane. Phần headline của paper mới nên đặt vào DMA bulk transfer, pipelined ASCON datapath, và coherent delivery để đạt throughput end-to-end cao hơn.

## 1. Mục tiêu kiến trúc

DMA-first ASCON không chỉ là "copy dữ liệu bằng DMA". Mục tiêu là:

- nạp payload lớn hơn vào engine trong mỗi lần service
- giữ pipeline ASCON đầy dữ liệu thay vì chờ CPU/MMIO từng bước
- giảm số lần round-trip giữa CPU và accelerator
- tận dụng coherent input để không cần fence/flush software trước DMA start
- dùng output policy phù hợp để tránh write-invalidate không cần thiết

Nói ngắn gọn, DMA phải làm đúng 3 việc:

1. gom burst tốt
2. overlap control path với data path
3. giữ coherency đúng chỗ, không trả giá quá mức

## 2. Bản đồ block-level

Kiến trúc mục tiêu có thể mô tả bằng pipeline 4 tầng:

1. CPU/firmware chuẩn bị descriptor và chọn mode
2. DMA đọc input từ memory/cache theo burst
3. ASCON engine xử lý dữ liệu theo pipeline
4. DMA ghi output/tags trở lại memory theo policy coherent thích hợp

Luồng dữ liệu chính:

```text
CPU firmware
  -> DMA registers / start
  -> DMA read engine (burst + snoop read)
  -> ASCON core / pipeline
  -> DMA write engine (burst + optional invalidate)
  -> memory / cache-visible output
```

Trong H3 hiện tại, `CONTEXT_SEL` chỉ là sideband cho multi-session. Trong DMA-first paper story, nó nên được xem là control-plane reference giúp chứng minh rằng throughput tăng lên không đến từ control-path trick.

## 3. DMA register map hiện có

DMA controller hiện tại đã có những thanh ghi cơ bản sau:

| Offset | Thanh ghi | Ý nghĩa |
| ---: | --- | --- |
| `CHn_SRC` | nguồn dữ liệu | địa chỉ đọc input |
| `CHn_DST` | đích dữ liệu | địa chỉ ghi output |
| `CHn_LEN` | độ dài | số byte transfer |
| `CHn_CTRL` | điều khiển channel | `EN`, `START`, `MODE` |
| `STATUS` | trạng thái | done / error / busy |
| `IRQ_EN` | interrupt enable | bật IRQ per channel |
| `IRQ_STATUS` | interrupt status | RW1C |

Với paper mới, điểm quan trọng không phải thêm thật nhiều thanh ghi mới ngay lập tức mà là khai thác tốt các control hiện có:

- `SRC/DST/LEN` để mô tả payload lớn
- `CTRL.START` để kích hoạt transfer theo burst
- `STATUS` để đo latency và done path

Nếu cần mở rộng sau này, register map nên thêm:

- `DMA_BURST_LEN`
- `DMA_PREFETCH_DEPTH`
- `DMA_WATERMARK`
- `DMA_POLICY`

Nhưng ở giai đoạn paper, có thể dùng cấu hình hiện tại để chứng minh throughput và pipeline behavior.

## 4. Burst policy

Burst policy là phần quyết định DMA có “thông minh” hay không.

### 4.1 Payload burst

DMA nên làm việc theo burst payload lớn thay vì nhiều MMIO start nhỏ:

- 128B
- 256B
- 512B
- 1024B

Lý do:

- đủ lớn để amortize control overhead
- đủ nhỏ để vẫn nhìn rõ scaling theo payload
- phù hợp so sánh fair với baseline no-CRF và H3 reference

### 4.2 Burst aggregation

DMA nên gom nhiều beat trong một lần service nếu source/destination alignment cho phép.

Mục tiêu:

- giảm số lần arbitration
- giảm số lần re-enter FSM
- tăng tỷ lệ data per control event

### 4.3 Cache-line awareness

Với coherent path, burst policy cần phân biệt:

- input/source owned bởi CPU cache, cần snoop read để lấy dirty data
- output/destination nên tránh write-invalidate nếu software contract cho phép

Đây chính là lý do selective coherent mode có ý nghĩa:

- input vẫn correct
- output tránh invalidate thừa
- throughput tăng rõ hơn full coherent mode

## 5. Pipeline flow

Paper nên mô tả pipeline theo các stage sau:

### Stage A: Descriptor setup

CPU ghi:

- source address
- destination address
- length
- channel control
- optional context select

### Stage B: Input fetch

DMA fetch dữ liệu đầu vào theo burst.

Nếu cache line dirty:

- coherent read mode dùng snoop hit để lấy data đúng mà không cần fence

Nếu cache line clean hoặc cold:

- DMA có thể fallback AXI read

### Stage C: ASCON processing

ASCON engine nhận dữ liệu từ FIFO/pump path.

Điểm paper cần nhấn:

- pipeline của engine không nên bị starvation bởi DMA
- data path phải đều đặn để throughput ổn định

### Stage D: Output commit

DMA ghi ciphertext/tag ra memory.

Hai mode nên được mô tả rõ:

- full coherent: correct nhưng tốn invalidate/writeback hơn
- selective coherent: vẫn correct cho output producer-owned/cold nhưng throughput cao hơn

## 6. Ý nghĩa của H3 reference

H3 multi-context/context banking không phải headline chính, nhưng có vai trò rất tốt trong paper:

- chứng minh control-plane isolation
- chứng minh multi-session không phá dữ liệu cũ
- làm reference baseline khi review hỏi “nếu đổi session thì sao”

Điểm nên nói rất rõ:

- H3 không phải datapath tăng tốc chính
- DMA-first path mới là nguồn high-throughput
- H3 là bằng chứng rằng control-plane đã được xử lý đúng và đo được

## 7. Câu narrative nên dùng trong paper

Có thể dùng các ý sau:

- “The accelerator combines DMA-driven bulk movement with a pipelined ASCON engine to minimize CPU intervention and maximize payload per service.”
- “Selective coherent DMA preserves no-fence input correctness while avoiding unnecessary output invalidation.”
- “The H3 multi-context design serves as a reference control-plane baseline for multi-session secure communication workloads.”

## 8. What makes DMA smart

Nếu reviewer hỏi DMA “thông minh” ở đâu, câu trả lời nên là:

1. biết gom burst
2. biết giữ pipeline đầy dữ liệu
3. biết chọn coherent mode theo hướng dữ liệu
4. biết tránh write-side invalidation nếu không cần
5. biết để CPU ở vai trò setup, không phải data mover

## 9. Kết luận

Trong paper mới, DMA-first architecture nên được trình bày như data-plane chủ đạo:

- bulk transfer là trung tâm
- burst policy là lever để tăng throughput
- pipeline là cơ chế giữ engine bận
- H3 context banking là reference control-plane cho multi-session correctness

Nếu cần, file kế tiếp nên là benchmark plan để gắn architecture này với metric đo được.
