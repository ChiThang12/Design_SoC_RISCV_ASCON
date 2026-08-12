# Kiến Trúc Đề Tài

## 1. Sơ đồ khối

Luồng chính của đề tài:

```text
CPU/firmware
  -> ghi thanh ghi điều khiển
  -> read scheduler + coherent read policy
  -> ingress ping-pong buffering
  -> ASCON xử lý theo pipeline
  -> egress buffering + write policy
  -> DMA ghi ciphertext/tag về memory
```

## 2. Vai trò từng khối

- CPU/firmware: cấu hình, khởi động, kiểm tra, và báo cáo kết quả.
- H3 reference: giữ state theo từng context để làm baseline control-plane.
- DMA streaming subsystem: đọc, đệm, feed core, thu kết quả, và ghi trả dữ liệu ra memory.
- ASCON core: xử lý mã hóa/giải mã và tạo tag.
- Coherency logic: đảm bảo dữ liệu đầu vào/đầu ra đúng theo cache contract, nhưng không đối xử giống nhau cho mọi hướng dữ liệu.

## 3. Ý tưởng kiến trúc

Điểm mạnh của hướng này là:

- giảm số lần CPU phải can thiệp
- overlap read / process / write thay vì chạy tuần tự
- dùng coherence theo vai trò của buffer
- tận dụng context bank như baseline để chứng minh control-plane đã được giải quyết riêng

Trong nhánh `H`, cần tách thành hai lớp:

- lớp reference control-plane: H3 context banking, context isolation, context switch cost
- lớp headline data-plane: streaming DMA path, ping-pong buffering, direction-aware coherence, throughput steady-state

## 4. Điểm cần giữ chặt

- `CONTEXT_SEL` phải được latch đúng thời điểm start.
- DMA không được lấy nhầm context khi firmware đổi bank giữa chừng.
- Output phải theo đúng policy cache/coherency đã công bố.
- Benchmark phải đo đúng đường data steady-state, không đo lẫn boot hay sync phụ.
- H3 benchmark phải đứng riêng, không trộn vào throughput headline.
