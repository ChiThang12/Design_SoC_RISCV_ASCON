# DMA-First Benchmark Plan

Tài liệu này mô tả benchmark plan cho paper mới, tập trung vào DMA bulk transfer và pipeline throughput của ASCON engine.

H3 reference benchmark vẫn được giữ lại để so sánh control-plane. Benchmark mới phải trả lời được câu hỏi chính:

> DMA-first ASCON engine đẩy được bao nhiêu dữ liệu hữu ích, với bao nhiêu overhead điều khiển, và nhanh hơn baseline/H3 reference bao nhiêu?

## 1. Mục tiêu đo

### Primary metrics

- end-to-end throughput theo payload lớn
- DMA start-to-last-write completion cycles
- burst efficiency
- control overhead per message
- throughput improvement vs H3 reference và baseline no-CRF

### Secondary metrics

- snoop hit ratio
- invalidate count
- AXI read/write transaction count
- pipeline utilization
- CPU intervention count

## 2. Workload sweep

Benchmark nên sweep theo payload size:

| Payload | Mục đích |
| ---: | --- |
| 128B | nhỏ đủ để thấy control overhead còn đáng kể |
| 256B | mid-range, thường là điểm cân bằng tốt |
| 512B | payload trung bình, amortize control tốt hơn |
| 1024B | payload lớn, test khả năng giữ throughput |

Nếu có thời gian, có thể mở thêm:

- 2048B
- 4096B

Nhưng chỉ khi memory map đủ an toàn, tránh overlap với stack/metadata.

## 3. Sweep theo burst policy

Để chứng minh DMA “thông minh”, không chỉ sweep payload mà còn sweep policy liên quan đến burst:

| Biến số | Giá trị gợi ý | Ý nghĩa |
| --- | --- | --- |
| burst size | 1, 2, 4, 8, 16 beats | xem throughput có scale theo burst không |
| watermark | low / medium / high | xem FIFO fill level ảnh hưởng latency thế nào |
| coherency mode | legacy / full coherent / selective coherent | tách correctness và throughput |
| context mode | single / H3 2-context reference | đo control-plane cost khi multi-session |

### Gợi ý priority

1. payload sweep
2. coherency mode sweep
3. burst size sweep
4. watermark sweep

## 4. Benchmark matrix

### A. DMA bulk throughput

Đây là bảng chính cho paper.

Đo:

- 128B, 256B, 512B, 1024B
- `DMA_START -> last M2_B`
- throughput Mbps tại clock 100 MHz

So sánh:

- baseline software-fenced
- H3 reference fair path
- DMA-first target

### B. Coherency mode comparison

Đo cùng payload, đổi mode:

- `COH_CTRL=0` legacy
- `COH_CTRL=1` selective coherent
- `COH_CTRL=3` full coherent

Mục tiêu:

- chứng minh selective coherent là sweet spot
- giữ input no-fence correctness
- giảm write-side invalidation

### C. Control-plane comparison

Đo:

- H3 `CONTEXT_SEL` interval
- no-CRF reload lower-bound
- DMA-first path setup cost

Mục tiêu:

- chứng minh H3 control-plane vẫn tốt hơn reload
- nhưng throughput headline vẫn phải từ DMA path

## 5. Benchmark flow

### Step 1: Setup

Firmware ghi:

- source address
- destination address
- length
- DMA control
- optional context select

### Step 2: Start DMA

Ghi `START` và bắt đầu counter.

### Step 3: Measure completion

Dừng khi thấy:

- DMA done
- last AXI B response
- output verification pass

### Step 4: Read counters

Ghi:

- cycles
- request count
- snoop count
- invalidate count
- active throughput

### Step 5: Compare

So sánh với:

- H3 reference
- baseline no-CRF
- legacy fence path

## 6. Metric definitions

### Fair throughput

Nên dùng:

```text
fair throughput = payload_bits / (DMA_START -> last M2_B cycles) * clock
```

### Control overhead

Nên tách:

- firmware setup cycles
- context select cycles
- reload cycles trong baseline

### Burst efficiency

Định nghĩa gợi ý:

```text
burst efficiency = payload_bytes / number_of_DMA_transactions
```

Hoặc:

```text
burst efficiency = useful_bytes / total_moved_bytes
```

## 7. Expected benchmark table

### A. H3 reference table

Giữ bảng hiện có:

- 128B: 800.00 Mbps
- 256B: 1044.90 Mbps
- 512B: 1177.01 Mbps
- 1024B: 1321.29 Mbps

### B. DMA-first target table

Table này để paper mới fill sau khi benchmark chạy:

| Payload | Legacy fenced | H3 reference | DMA-first target | Gain vs H3 |
| ---: | ---: | ---: | ---: | ---: |
| 128B | TBD | 800.00 Mbps | TBD | TBD |
| 256B | TBD | 1044.90 Mbps | TBD | TBD |
| 512B | TBD | 1177.01 Mbps | TBD | TBD |
| 1024B | TBD | 1321.29 Mbps | TBD | TBD |

## 8. What to report in the paper

### Main figure

- throughput vs payload
- include H3 reference curve
- include baseline no-CRF or software-fenced curve
- show DMA-first curve as headline

### Supporting figure

- cycles breakdown: setup, fetch, pipeline, writeback
- compare full coherent vs selective coherent

### Supporting table

- snoop hits
- invalidate hits
- AXI AR/AW counts
- context select cycles

## 9. Benchmark rules

- dùng clock 100 MHz cho tất cả throughput conversions
- dùng cùng testbench
- dùng cùng memory layout khi so baseline và H3
- không dùng diagnostic 8B end-to-end làm headline
- không trộn control-plane reference với bulk throughput headline

## 10. Implementation checklist

- thêm hoặc giữ benchmark firmware cho payload sweep
- export CSV cho các sweep
- ghi log `DMA_START`, `core_start`, `core_done`, `DMA_DONE`
- lưu separate result cho:
  - legacy
  - full coherent
  - selective coherent
  - H3 reference

## 11. Kết luận

Benchmark plan này được thiết kế để paper trả lời được một câu rất cụ thể:

> DMA-first ASCON engine có thực sự đẩy nhiều dữ liệu hơn, với throughput end-to-end cao hơn, trong khi H3 chỉ còn là reference control-plane cho multi-session?

Nếu câu trả lời là có, paper sẽ đúng title và dễ defend hơn nhiều.
