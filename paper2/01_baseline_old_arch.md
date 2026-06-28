# Paper 2 — Baseline kiến trúc cũ

## Mục đích
Tài liệu này ghi lại **kiến trúc hiện tại** và **các số đo baseline** trước khi triển khai kiến trúc mới.

Mục tiêu của baseline là:
- đo đúng trạng thái “cũ” của SoC
- làm mốc so sánh cho bản kiến trúc mới
- không trộn lẫn với các thay đổi sideband snoop, ATU, hoặc DMA-cache coherence

## Phạm vi baseline
- CPU RISC-V 5-stage hiện tại
- DCache/ICache hiện tại
- ASCON DMA theo kiến trúc hiện hữu
- firmware hiện tại với cơ chế coherence bằng phần mềm

## Điều kiện đo
- chạy đúng cùng benchmark / testbench
- giữ nguyên toolchain, clock, memory map, và tham số mô phỏng
- ghi rõ commit / snapshot RTL khi đo
- không bật bất kỳ thay đổi kiến trúc mới nào

## Số đo cần lưu
- số chu kỳ chạy
- thời gian mô phỏng thực tế
- throughput ASCON
- latency khởi động và hoàn tất DMA
- số lần cache miss / refill / evict
- số lần dùng `fence`
- kết quả `[PASS]` / `[FAIL]`

## Phân loại throughput ASCON
Cần tách rõ các lớp đo để tránh so sánh sai:

| Loại số đo | Đường dữ liệu | Ý nghĩa | Dùng để so sánh kiến trúc mới? |
|---|---|---|---|
| Core-only peak | Testbench feed trực tiếp vào `ascon_CORE` | Giới hạn lý tưởng của crypto core, bỏ qua SoC/DMA/AXI/cache | Không dùng làm số throughput SoC; chỉ dùng làm trần lý thuyết |
| SoC DMA active | `DMA_START` → `DMA_DONE` trong SoC | Throughput thực tế của ASCON DMA khi dữ liệu đi qua AXI/DMEM/FIFO/writeback | Có, nếu cùng payload và testbench |
| End-to-end firmware | Bao gồm setup register, key/nonce, fence/poll/UART nếu có | Chi phí toàn hệ thống từ góc nhìn phần mềm | Có, nhưng phải báo riêng với SoC DMA active |

## Baseline số đo hiện tại
Snapshot hiện tại dùng clock 100 MHz. Các số dưới đây là mốc tham chiếu trước khi triển khai kiến trúc hardware-coherent DMA.

| Metric | Giá trị baseline | Nguồn đo | Ghi chú |
|---|---:|---|---|
| ASCON core-only peak, 16B/block | ~4.25 Gbps | `log/tb_core_tput.log`, `ascon/tb/tb_core_tput.v` | Feed trực tiếp vào core, không qua SoC/DMA/AXI |
| ASCON core-only peak, 8B/block | ~2.125 Gbps | `log/tb_core_tput.log`, `ascon/tb/tb_core_tput.v` | Core-only, tương đương rate 64-bit |
| SoC ASCON-DMA active, 128B payload | ~1.0 Gbps | `log/test_ascon.log`, `run_soc_ascon.v` | DMA active window; khoảng 102 cycles cho 128B steady runs |
| SoC ASCON-DMA write-complete, 128B software-fenced control | ~1.125 Gbps | `run_soc_fence_128b.v` | Fair metric `DMA_START→last M2_B = 91 cycles`; dirty DCache data được flush bằng software fence trước DMA, sau đó DMA đọc qua AXI (`M2_AR=2`) |
| SoC ASCON-DMA active, 8B payload | ~188 Mbps | `log/run_perf_bench.log`, `run_perf_bench.v` | Payload nhỏ, bị overhead start/done chi phối; 34 cycles cho 8B |
| Baseline benchmark completion | PASS / complete | `log/run_perf_bench.log` | Không còn stall sau khi `DMA_BURST` khớp số block đo |

## Baseline sweep software-fenced

Các số dưới đây dùng cùng metric với bảng so sánh paper2: `DMA_START→last M2_B`, clock 100 MHz, `COH_CTRL=0`, không có sideband snoop. Firmware dùng software fence trước khi start DMA để flush dirty plaintext từ DCache ra DMEM.

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW | Snoop read/inv | Nguồn đo |
|---:|---:|---:|---:|---:|---:|---|
| 128B | 91 | 1125.27 Mbps | 2 | 2 | 0/0 | `run_fence_sweep.sh 128` |
| 256B | 159 | 1288.05 Mbps | 4 | 3 | 0/0 | `run_fence_sweep.sh 256` |
| 512B | 295 | 1388.47 Mbps | 8 | 5 | 0/0 | `run_fence_sweep.sh 512` |
| 1024B | 567 | 1444.80 Mbps | 16 | 9 | 0/0 | `run_fence_sweep.sh 1024` |

## Diễn giải số đo
- Số ~4.25 Gbps là **trần core-only**, không đại diện cho throughput SoC tích hợp.
- Số ~1.0 Gbps là **peak measured SoC-DMA active throughput** hiện tại cho payload 128B ở 100 MHz.
- Số ~1.125 Gbps là mốc **fair software-fenced control** cho so sánh với kiến trúc mới 128B bằng cùng metric `DMA_START→last M2_B`.
- Số ~188 Mbps ở payload 8B không mâu thuẫn với 1.0 Gbps; đó là trường hợp latency-dominated do payload quá nhỏ.
- Khi nâng cấp kiến trúc mới, so sánh chính nên dùng cùng payload, ưu tiên 128B hoặc sweep nhiều kích thước payload để thấy hiệu ứng amortization.

## Trạng thái hiện tại cần theo dõi
Baseline từng có lỗi stall sau benchmark ASCON do firmware ghi `DMA_BURST=7` ngay cả khi chỉ đo 1 block 8B. Trạng thái hiện tại đã sửa để `DMA_BURST` khớp số block đo, nhưng kiến trúc phần cứng vẫn là **baseline cũ**, chưa có sideband snoop/ATU/DMA-cache coherence.

## Kết luận baseline
Baseline là mốc tham chiếu để so sánh sau này với kiến trúc hardware-coherent DMA.
Mọi số đo ở đây phải được hiểu là **kiến trúc cũ**, trước khi thêm sideband snoop và ATU.
