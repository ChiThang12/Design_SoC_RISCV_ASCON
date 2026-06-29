# H1 - Compute-in-Cache ASCON

H1 là hướng tiếp theo sau khi baseline dual-core coherency và selective coherent DMA đã được khóa. Theo định hướng trong `paper2/paper2_2/H1+H3.md`, H1 không còn nhằm chứng minh coherency có hoạt động hay không; coherency hiện tại là nền tảng để đưa xử lý crypto đến gần DCache hơn.

Mục tiêu của H1 là xây dựng một DCache có khả năng nhận biết vùng dữ liệu crypto, đưa cache line vào xử lý ASCON tại chỗ, rồi commit kết quả trở lại cache line mà vẫn giữ đúng MESI, snoop, fence và flush behavior. Nói ngắn gọn: H1 là "ASCON-aware DCache / Compute-in-Cache", không phải thêm một ASCON accelerator rồi kết nối qua bus.

## Vị trí của H1 trong roadmap

Thứ tự tổng thể:

1. Baseline dual-core coherency đã chốt và được dùng làm mốc so sánh.
2. H3 đi trước để chốt Multi-Context ASCON và control plane `context_id`.
3. H1 mở sau H3 để đưa processing vào DCache, đưa bài toán từ coherency sang data locality và in-cache processing.

Vì lý do đó, tài liệu H1 cần đọc cùng với:

- `paper2/paper2_2/H1+H3.md`
- `paper2/paper2_2/dualcore_test_results.md`
- `paper2/paper2_2/rtl_coherency_checklist.md`
- `paper2/paper2_2/H1/h1_rtl_closure_checklist.md`

## Nguyên tắc triển khai

- Làm H1 trên nhánh riêng `cache_interface/dcache_ascon`.
- Giữ `cache_interface/dcache` làm baseline regression cho H3 và dual-core coherency.
- Chỉ kích hoạt H1 trên một crypto address window rõ ràng.
- Thêm metadata line như `crypto_pending` và `crypto_done` để biết line đang chờ xử lý hay đã có kết quả.
- Thêm queue/batching cho các line crypto, bắt đầu bằng 1-deep queue cho PoC.
- Đặt ASCON datapath dưới dạng submodule DCache-local, ví dụ `dcache_ascon_datapath.v`.
- Commit ciphertext/tag về cache theo policy rõ ràng, tránh làm vỡ snoop/fence/flush.

## Điều H1 cần chứng minh

H1 cần chứng minh ba điểm chính:

1. CPU ghi plaintext vào crypto region, DCache đưa line vào crypto pipeline, và CPU đọc lại được kết quả đã xử lý.
2. Khi line đang `crypto_pending`, cache có policy nhất quán cho CPU hit, eviction, snoop read, snoop invalidate, fence và flush.
3. Số liệu H1 cho thấy lợi ích về latency, throughput, bus traffic hoặc energy proxy so với baseline DMA/accelerator path.

## Ngoài phạm vi ban đầu

- Không thay thế baseline coherency đã chốt.
- Không cần nối ngay vào `soc_top.v` nếu PoC DCache-local chưa đóng.
- Không cần làm AEAD đầy đủ ngay từ đầu nếu PoC đầu tiên chỉ cần chứng minh in-cache transform và commit path.
- Không nên biến H1 thành một accelerator ASCON thứ ba nằm ngoài cache.

## Tài liệu quan trọng

- `h1_rtl_closure_checklist.md`
