# Bản Đồ Thanh Ghi

Tài liệu này chốt bản đồ thanh ghi dùng cho nhánh `H` ở thời điểm hiện tại.

Nguyên tắc chốt:

- giữ tương thích với đường baseline đã chạy được
- không thêm thanh ghi mới chỉ để làm đẹp narrative
- chỉ dùng các thanh ghi đã có trong RTL/interface hiện tại
- mọi benchmark của `H` phải dùng đúng map này

## 1. Thanh ghi control-plane reference

| Offset | Tên | Truy cập | Ý nghĩa |
| ---: | --- | --- | --- |
| `0x008` | `CONTEXT_SEL` | `R/W` | Chọn bank context đang hoạt động ở phía core-facing register bank |

Quy ước:

- `CONTEXT_SEL` thuộc lớp `H3 reference control-plane`
- firmware phải ghi xong `CONTEXT_SEL` trước khi nạp state hoặc start transaction cho context đó
- DMA headline của `H` không dùng `CONTEXT_SEL` làm claim throughput

## 2. Thanh ghi DMA headline dùng cho H

| Offset | Tên | Truy cập | Ý nghĩa |
| ---: | --- | --- | --- |
| `0x100` | `DMA_SRC_ADDR` | `R/W` | Địa chỉ nguồn payload plaintext trong memory |
| `0x104` | `DMA_DST_ADDR` | `R/W` | Địa chỉ đích chứa ciphertext và tag |
| `0x108` | `DMA_LEN` | `R/W` | Độ dài payload tính theo byte |
| `0x10C` | `DMA_CTRL` | `W` | Điều khiển DMA: `bit0=START`, `bit1=SOFT_RST`, `bit2=RD_ONLY`, `bit3=WR_ONLY` |
| `0x110` | `DMA_STATUS` | `R` | Trạng thái DMA: `bit0=BUSY`, `bit1=DONE`, `bit2=RD_DONE`, `bit3=WR_DONE` |
| `0x114` | `DMA_BURST_LEN` | `R/W` | Độ dài burst AXI, mã hóa theo `ARLEN/AWLEN`: `0 -> 1 beat` |
| `0x120` | `AD_ADDR` | `R/W` | Địa chỉ Associated Data trong memory |
| `0x124` | `AD_LEN` | `R/W` | Độ dài Associated Data theo byte |
| `0x158` | `DMA_COH_CTRL` | `R/W` | Chọn policy coherence cho datapath DMA |

## 2.1 Ý nghĩa tối thiểu firmware phải hiểu

- `DMA_LEN` là số byte payload thật, không tính phần tag
- `DMA_DST_ADDR` là nơi firmware mong đợi nhận `ciphertext + tag`
- `DMA_BURST_LEN` tinh chỉnh hành vi burst, nhưng không đổi semantic transaction
- `AD_ADDR` và `AD_LEN` chỉ có ý nghĩa khi chạy luồng AEAD có AD
- `DMA_COH_CTRL` là thanh ghi policy quan trọng nhất của headline `H`

## 2.2 Quy ước dùng `DMA_COH_CTRL`

Để narrative của `H` không bị mơ hồ, cần khóa cách hiểu tối thiểu như sau:

- `COH_CTRL=1`: mode hiệu năng chính cho output contract kiểu stale/non-temporal theo policy đã công bố
- `COH_CTRL=3`: mode coherent/fallback để ưu tiên correctness hoặc refresh output mạnh hơn
- không dùng `DMA_COH_CTRL` để che khuyết điểm functional; nó là policy knob, không phải nút sửa lỗi

## 2.3 Trình tự firmware chuẩn cho một transaction payload

1. Chọn `CONTEXT_SEL` nếu bài test có liên quan H3 reference.
2. Ghi `DMA_SRC_ADDR`, `DMA_DST_ADDR`, `DMA_LEN`.
3. Nếu có AD, ghi thêm `AD_ADDR`, `AD_LEN`.
4. Ghi `DMA_BURST_LEN` và `DMA_COH_CTRL`.
5. Phát `DMA_CTRL.START`.
6. Poll `DMA_STATUS` hoặc trạng thái mirror ở lớp top-level nếu bài test dùng đường đó.
7. Đọc và so khớp dữ liệu output theo golden tương ứng.

## 3. Thanh ghi AEAD và core-facing cần giữ thống nhất

| Nhóm | Thành phần |
| --- | --- |
| Mode/điều khiển core | `MODE` |
| Key | `KEY_0..KEY_3` |
| Nonce | `NONCE_0..NONCE_3` |
| Payload ingress | `PTEXT_0..PTEXT_1` |
| Payload egress | `CTEXT_0..CTEXT_1` |
| Tag output | `TAG_0..TAG_3` |
| Tag input/verify | `TAG_IN_0..TAG_IN_3` |

Các thanh ghi này thuộc lớp core-facing chung, còn headline `H` tập trung vào lớp DMA/streaming ở mục 2.

## 4. Những gì không chốt thêm trong vòng này

- không thêm descriptor queue register mới
- không thêm thanh ghi debug-only vào contract firmware chính
- không tách riêng source/destination policy thành nhiều field mới khi RTL chưa chốt interface đó
- không đổi offset các thanh ghi DMA đã dùng trong baseline và H3

## 5. Kết luận chốt register map cuối

Register map cuối của `H` cho package hiện tại là:

- dùng `CONTEXT_SEL` như reference control-plane
- dùng bộ `DMA_*`, `AD_*`, `DMA_COH_CTRL` như contract chính cho headline streaming datapath
- không mở rộng thêm thanh ghi mới trong vòng đóng gói này

Từ thời điểm này, đây là bản đồ thanh ghi chuẩn duy nhất giữa RTL, firmware, testbench và tài liệu `H`.
