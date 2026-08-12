# H1 RTL Closure Checklist

Ngày cập nhật: 2026-06-29

## Định hướng H1

H1 phải đi đúng với briefing trong `paper2/paper2_2/H1+H3.md`: baseline selective coherent DMA và dual-core MESI đã là nền ổn định, H3 sẽ chốt Multi-Context ASCON trước, sau đó H1 mới mở bài toán Compute-in-Cache.

Vì vậy, H1 không phải là thêm một accelerator ASCON thứ ba. H1 thay đổi kiến trúc của DCache để:

- nhận biết cache line thuộc vùng crypto
- đánh dấu line đang chờ xử lý (`crypto_pending`)
- đưa line vào queue xử lý
- cho phép commit ciphertext/tag trở lại line cache mà vẫn giữ coherency đúng

Kết quả mong muốn của H1 là một DCache có khả năng xử lý crypto tại chỗ cho một address window cụ thể, giảm data movement qua bus/accelerator và tạo số liệu latency, throughput, bus traffic, queue occupancy làm mốc paper.

## Ranh giới với baseline và H3

Cần giữ rõ ba lớp sau:

- Baseline: dual-core coherency, MESI DCache, peer snoop, DMA sideband snoop đã pass và không phải mục tiêu sửa chính của H1.
- H3: Multi-Context ASCON, thêm `context_id`/CRF vào control plane của accelerator/DMA.
- H1: Compute-in-Cache, thêm crypto metadata, queue, datapath và commit policy vào nhánh DCache riêng.

Nguyên tắc quan trọng:

- `cache_interface/dcache` là baseline regression, không sửa nếu không bắt buộc.
- `cache_interface/dcache_ascon` là nơi phát triển H1.
- H1 PoC nên dùng được độc lập ở mức DCache-local trước khi thay thế DCache trong `soc_top.v`.
- Mỗi thay đổi H1 phải có câu trả lời cho snoop/fence/flush, vì đây là phần để làm vỡ baseline nhất.

## Nhánh RTL để sửa

Nhánh H1 nên làm việc trên:

- [dcache_ascon README](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/cache_interface/dcache_ascon/README.md>)
- [dcache_top.v](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/cache_interface/dcache_ascon/dcache_top.v>)
- [dcache_controller.v](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/cache_interface/dcache_ascon/dcache_controller.v>)
- [dcache_tag_array.v](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/cache_interface/dcache_ascon/dcache_tag_array.v>)

## Cần sửa gì để H1 hoàn thiện RTL

Mục tiêu closure không chỉ là "có datapath ASCON chạy". Closure của H1 nghĩa là cache controller có policy hoàn chỉnh cho line crypto từ lúc detect, enqueue, wait, commit cho đến các tương tác coherency.

### 1. `dcache_tag_array.v`

Cần thêm metadata mới cho mỗi line:

- `crypto_pending`
- `crypto_done` hoặc có thể tái sử dụng state phụ nếu muốn tối ưu bit
- tùy chọn sau H3: `crypto_ctx` nếu H1 cần kế thừa `context_id`
- tùy chọn: `crypto_owner`, `crypto_op`

Cần quyết:

- metadata lưu cùng tag/state hay tách thành `dcache_crypto_meta.v`
- line đang `M` mà `crypto_pending=1` có được CPU đọc/ghi tiếp hay phải stall
- snoop invalidate/coherent write có được phép hủy line pending hay phải flush/abort

### 2. `dcache_controller.v`

Đây là file trung tâm của H1. Cần thêm theo đúng thứ tự:

- region detect: địa chỉ nào được xem là crypto region
- trigger policy: CPU write, CPU read, DMA access hay MMIO command nào làm line được enqueue
- state mới trong FSM:
  - `CRYPTO_ENQUEUE`
  - `CRYPTO_WAIT`
  - `CRYPTO_COMMIT`
  - nếu cần: `CRYPTO_ABORT`
- queue/batching:
  - 1-deep pending line cho PoC là đủ
  - nếu muốn paper mạnh hơn thì thêm `dcache_crypto_queue.v`
- stall policy:
  - hit vào line `crypto_pending` => CPU stall hay trả busy
  - miss vào line `crypto_pending` bị evict => cấm evict hay force wait
- visibility policy:
  - line pending có được đọc plaintext cũ hay phải đổi ciphertext
  - line done được xem như modified data hay clean transformed data
- commit policy:
  - ciphertext ghi đè in-place vào data array
  - tag lưu ở đâu? trong line, shadow buffer, hay MMIO side register

Cần đặc biệt giữ đúng:

- fence path
- flush path
- snoop invalidate/read path
- peer snoop miss path

Nếu bỏ qua các tương tác này, H1 sẽ để vỡ coherency đã chốt cho H3.

### 3. `dcache_top.v`

Cần thêm giao tiếp cho datapath crypto:

- start/valid/ready cho line input
- output line commit
- tag output nếu H1 cần AEAD full

Cần quyết H1 PoC dùng cách nào:

- cách A: nhúng datapath ASCON nhỏ trực tiếp trong cache
- cách B: cache controller gọi một submodule `dcache_ascon_datapath.v`

Khuyến nghị cho RTL closure:

- dùng cách B
- giữ `dcache_top.v` là nơi đi dây + instantiate
- dồn phần FSM/chính sách về `dcache_controller.v`

### 4. `dcache_data_array.v`

Có thể chưa cần sửa nhiều nếu H1 commit in-place từng word như writeback hiện tại.

Nhưng cần xem:

- có cần đọc full 128-bit line trong 1 chu kỳ cho datapath không
- có cần writeback full line atomically không
- có cần shadow registers cho line đang crypto không

Nếu cần read/write nguyên line, có thể thêm helper readout full-line thay vì bước qua 4 offset riêng.

### 5. `dcache_snoop_ctrl.v` và coherency path

Cần quy định rõ:

- line `crypto_pending` gặp snoop read => đề xuất PoC: stall/delay response đến khi commit xong
- line `crypto_pending` gặp snoop invalidate => đề xuất PoC: delay invalidate đến khi commit xong, sau đó invalidate
- line `crypto_done` nhưng chưa CPU consume => đề xuất PoC: xem như modified line nếu ciphertext mới chỉ nằm trong cache

Đây là cho reviewer rất dễ hỏi, nên cần một policy ngắn gọn và nhất quán. PoC nên ưu tiên policy đơn giản, dùng chức năng và để chứng minh trên waveform/testbench, sau đó mới tối ưu thành abort/rollback.

### 6. `soc_top.v`

Chưa cần sửa ngay nếu H1 đang ở mức DCache-local PoC.

Nhưng để hoàn thiện RTL H1 sau này sẽ cần:

- instantiate `dcache_ascon` thay cho `dcache`
- route thêm perf/debug counter nếu muốn đo H1 latency/queue occupancy
- có thể thêm address-window define cho crypto region

## Module mới nên thêm

Để tránh nhét qua nhiều vào `dcache_controller.v`, H1 nên thêm các module theo thứ tự ưu tiên:

1. `dcache_crypto_meta.v`
2. `dcache_crypto_queue.v`
3. `dcache_ascon_datapath.v`

Trong PoC rất nhỏ, `dcache_crypto_meta.v` có thể tạm thời nằm trong tag array, nhưng tài liệu/paper nên mô tả nó như metadata riêng của line để story rõ ràng hơn.

## Thứ tự sửa hợp lý

1. Thêm metadata `crypto_pending` trong `dcache_tag_array.v`
2. Thêm region detect + stall policy trong `dcache_controller.v`
3. Thêm queue 1-deep cho line crypto
4. Thêm datapath wrapper `dcache_ascon_datapath.v`
5. Thêm commit path về `data_array`
6. Xử lý snoop/fence/flush interactions trước khi tuyên bố closure
7. Thêm counter H1: crypto enqueue count, pending cycles, commit count, stall cycles, queue full cycles
8. Cuối cùng mới nối vào `soc_top.v` để chạy system-level comparison

## Testbench cần có để đóng H1

Tối thiểu cần 5 bài:

1. CPU ghi plaintext vào crypto region -> cache xử lý -> CPU đọc ciphertext
2. CPU đọc lại line khi `crypto_pending=1`
3. Snoop invalidate vào line `crypto_pending`
4. Fence/flush khi queue crypto chưa rỗng
5. Non-crypto address đi qua DCache bình thường, không bị ảnh hưởng bởi H1

Nếu muốn paper-ready hơn:

6. DMA đọc line đã crypto xong
7. Dual-core: CPU1 đọc line do CPU0 vừa crypto trong cache
8. So sánh path baseline DMA accelerator với H1 in-cache cho cùng payload

## Số liệu cần đo cho paper H1

Cần thêm counter hoặc log để đo:

- latency từ enqueue đến commit
- CPU stall cycles vì `crypto_pending`
- số line crypto processed
- queue occupancy hoặc queue full cycles
- DCache request count/miss count trên crypto benchmark
- bus traffic proxy so với baseline DMA/accelerator path
- completion cycles cho payload nhỏ, vừa và lớn

## Kết luận thực tế

Để H1 "hoàn thiện RTL" đúng định hướng, phần khó nhất không nằm ở datapath ASCON mà nằm ở:

- metadata line
- queue/stall policy
- coherency khi line đang `crypto_pending`
- cách đo số liệu chứng minh data movement giảm

Nếu các điểm này chưa chốt rõ, H1 mới chỉ là ý tưởng kiến trúc. Khi metadata, policy, coherency interaction và counter đo lường được code và testbench hóa, H1 mới thực sự đặt mốc RTL closure và có thể dùng làm câu chuyện paper sau H3.
