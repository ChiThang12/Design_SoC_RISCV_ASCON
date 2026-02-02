## 1️⃣ Vấn đề cốt lõi hiện tại (root problem)

👉 **SoC của bạn đang chuẩn bị gắn Cache (ICache + DCache)**
👉 **Cache ≠ AXI4-Lite**
👉 **Cache bắt buộc phải dùng burst**

Vấn đề **không nằm ở CPU**, mà nằm ở **memory subsystem + AXI slave**.

---

## 2️⃣ Vì sao inst_mem “ổn”, còn data_mem thì “chưa”?

### 🔹 inst_mem (Instruction side) – KHÔNG CÓ VẤN ĐỀ ❌➡️✅

Bản chất truy cập instruction:

* Chỉ **READ**
* Thường **sequential**
* Cache miss → **burst read nhiều word liên tiếp**

👉 inst_mem của bạn:

* Đã là **AXI4 Full**
* Có **ARLEN / ARSIZE / ARBURST**
* Có **RLAST**
* inst_mem.v đã có **burst FSM**

📌 **Kết luận**

> inst_mem đã được thiết kế *tư duy cache-aware* ngay từ đầu
> → **ICache cắm vào là chạy liền**

👉 Không có bottleneck, không có architectural debt.

---

### 🔹 data_mem (Data side) – VẤN ĐỀ NẰM Ở ĐÂY ❌

Bản chất truy cập data:

* Read miss → **burst read cache line**
* Write → có thể:

  * write-through (single write)
  * write-back (burst write)

Nhưng hiện tại:

❌ `data_mem_axi_slave.v` = **AXI4-Lite**

* 1 request = 1 beat
* Không có:

  * ARLEN
  * RLAST
  * AWLEN
  * WLAST

❌ `data_mem.v`

* Không hiểu khái niệm “burst”
* Không biết cache line là gì

📌 **Hệ quả trực tiếp**

```
DCache miss (4 words)
→ cần 4 transaction AXI-Lite
→ latency ×4
→ cache mất ý nghĩa
```

👉 Đây là **architectural mismatch**, không phải bug nhỏ.

---

## 3️⃣ Nếu KHÔNG upgrade data_mem thì chuyện gì xảy ra?

Rất quan trọng 👇

### Trường hợp bạn vẫn cố gắn DCache:

* Cache controller yêu cầu:

  ```
  ARLEN = 3 (4 beats)
  ```
* Nhưng AXI slave:

  * không hiểu ARLEN
  * không phát RLAST

➡️ **Protocol violation**
➡️ Sim có thể:

* treo bus
* hoặc cache FSM bị deadlock
* hoặc phải downgrade cache thành “fake cache”

📌 **Kết luận**

> DCache + AXI4-Lite = cache “giả”, không đúng kiến trúc

---

## 4️⃣ Nhận định kiến trúc của bạn (rất quan trọng)

Một câu đánh giá thẳng thắn:

> **Thiết kế của bạn là đúng hướng SoC chuẩn (Harvard + Cache)**
> Nhưng **data_mem đang tụt 1 thế hệ bus**

### Kiến trúc hiện tại:

```
        ICache → inst_mem → AXI4 Full → OK ✅
CPU
        DCache → data_mem → AXI4-Lite → ❌
```

👉 Bus **không đồng cấp**
👉 Instruction path nhanh – Data path chậm
👉 Benchmark sẽ lệch hoàn toàn

---

## 5️⃣ Option 1 vs Option 2 – hiểu đúng bản chất

### 🟢 Option 2 (Burst read only) – dùng được, NHƯNG…

* Phù hợp **write-through**
* Nhanh để demo
* Nhưng:

  * sau này muốn write-back → đập lại
  * không đúng chuẩn AXI4 Full

📌 Dùng cho **prototype / deadline gấp**

---

### 🟢 Option 1 (Full upgrade) – chuẩn kiến trúc

* Read burst
* Write burst
* Đồng nhất với inst_mem
* DCache đúng nghĩa

📌 Đây là lựa chọn **đúng cho SoC lâu dài**

---

## 6️⃣ Điều QUAN TRỌNG bạn đã làm đúng (mình muốn nhấn mạnh)

Bạn đã:

✅ Nhận ra:

* Cache line ≠ single transfer
* AXI4-Lite ≠ Cache-friendly bus

✅ Phân tích đúng:

* inst_mem “đã xong từ trước”
* data_mem là điểm nghẽn duy nhất

✅ Đề xuất upgrade:

* dựa trên **reuse code**
* không overdesign

👉 Đây là **tư duy kiến trúc SoC**, không phải sinh viên làm lab.

---

## 7️⃣ Tóm lại – vấn đề hiện tại là gì?

### Một câu duy nhất:

> **Hệ thống của bạn đã sẵn sàng cho ICache, nhưng DCache đang bị bóp cổ bởi AXI4-Lite**

### Và cách giải quyết:
* KHÔNG đụng inst_mem
* CHỈ nâng cấp data_mem lên AXI4 Full
