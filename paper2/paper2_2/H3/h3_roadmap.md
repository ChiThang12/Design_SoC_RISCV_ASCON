# H3 Roadmap for DMA-First Paper Story

Ngày tạo: 2026-06-29

Tài liệu này là roadmap triển khai nhanh để nâng H3 từ mức "paper được" lên mức "paper vững", tức là khó bị bắt bẻ hơn ở baseline, cost, và claim.

## Mục tiêu

- Chuyển headline của đề tài sang DMA-enabled, pipelined ASCON engine để tối đa hóa throughput end-to-end.
- Giữ H3 làm reference design cho so sánh control-plane và multi-session.
- Có số đo bulk DMA throughput thật, không chỉ MMIO hoặc diagnostic 8B.
- Chứng minh DMA path có burst aggregation, pipeline overlap, và coherency đủ tốt để đẩy nhiều data vào ASCON nhất có thể.
- Có baseline no-CRF và H3 context-bank reference để reviewer đối chiếu mức cải thiện của DMA-first revision.

## Entry point cho OpenLane2

Đã chuẩn bị 2 wrapper top-level ở root repo:

- `ascon_base.v` cho baseline no-CRF
- `ascon_H3.v` cho bản H3 multi-context

Dùng chúng làm `top_module` riêng trong OpenLane2 để đo area/timing trên cùng một flow.

Khi sang DMA-first revision, entry point synthesis nên tách thêm một top để đo:

- area/timing của DMA control + datapath
- hiệu quả pipeline ASCON khi stream dữ liệu lớn
- cost của burst handling và coherency logic

## Ưu tiên triển khai

### P0 - Bắt buộc

#### 1. Chốt DMA data path làm trục chính

Mục tiêu:

- Xác định đường DMA bulk transfer nào đem lại nhiều data nhất cho ASCON với overhead nhỏ nhất.
- Ưu tiên burst aggregation, line-coalescing, và overlap với engine pipeline.
- Giữ coherency để CPU không phải quay về path copy/MMIO chậm.

Bằng chứng cần có:

- bulk throughput
- DMA service latency
- burst efficiency
- end-to-end cycles trên payload lớn

#### 2. Baseline no-CRF và H3 reference để so sánh

Mục tiêu:

- Dùng baseline no-CRF để làm reference cho control-plane cost.
- Dùng H3 context-banked design để làm reference cho multi-session cost.
- Không để hai reference này lấn át câu chuyện DMA-first, mà chỉ dùng chúng để giải thích lợi ích của kiến trúc mới.

Bằng chứng cần có:

- cycles
- throughput
- context/control overhead
- so sánh trực tiếp với DMA-first implementation

### P1 - Rất nên có

#### 3. DMA intelligence test

Mục tiêu:

- Chứng minh DMA không chỉ là đường chuyển dữ liệu, mà còn biết gom burst và giữ pipeline đầy.
- Xác nhận DMA có thể phục vụ payload lớn mà không mất đồng bộ với ASCON engine.

Test tối thiểu:

- Start DMA với payload lớn
- Quan sát burst coalescing / service interval
- Switch hoặc interleave request khác để xem DMA vẫn giữ throughput
- Verify output không lệch data path

#### 4. Negative tests

Mục tiêu:

- Tăng độ tin cậy của claim throughput và coherency.

Test gợi ý:

- đổi `CONTEXT_SEL` khi core đang busy
- xen kẽ DMA request trong lúc engine đang chạy
- cố tình gây điều kiện burst không đẹp để verify hệ thống vẫn trả data đúng

### P2 - Nâng chất lượng

#### 5. Mở rộng scale hoặc stress workload

Hai hướng:

- Mở rộng payload sweep và burst size sweep để chứng minh DMA throughput thật sự scale.
- Hoặc giữ cùng payload nhưng chạy nhiều session xen kẽ hơn để đo end-to-end secure communication throughput.

Mục tiêu:

- Cho thấy DMA-first design hoạt động ổn định trên workload lặp và xen kẽ.
- Tránh cảm giác đây chỉ là demo control path.

#### 6. Bổ sung diagram và bảng register map rõ hơn

Mục tiêu:

- Làm paper dễ đọc hơn.
- Tránh reviewer hỏi vì sao DMA burst control, coherency, và ASCON control được tách như thế nào.

## Thứ tự làm nhanh nhất

1. Chốt DMA bulk path và burst policy
2. Baseline no-CRF và H3 reference để làm điểm so sánh
3. Area/timing
4. DMA intelligence test
5. Stress workload hoặc burst sweep
6. Chốt lại text và bảng số liệu trong paper

## Timeline gợi ý

### Ngày 1-2

- Tạo build/config cho DMA-first path.
- Giữ H3 reference để đối chiếu.
- Chạy lại test functional tương tự H3 và ghi throughput theo payload lớn.

### Ngày 3

- Chạy synthesis cho DMA-first top, baseline, và H3 reference.
- Ghi area/timing vào bảng so sánh.

### Ngày 4

- Thêm DMA intelligence smoke test.
- Xác nhận burst service, pipeline fill, và coherency khi busy.

### Ngày 5

- Làm stress benchmark hoặc mở rộng payload/burst sweep.
- Chạy lại benchmark sweep nếu cần.

### Ngày 6-7

- Update `README.md`, `h3_results.md`, `h3_benchmark.md`, `h3_closure_checklist.md`, `h3_paper_skeleton_vi.md`.
- Chốt câu chữ paper và bảng final theo DMA-first narrative.

## File cần sửa

- `README.md`
- `h3_results.md`
- `h3_benchmark.md`
- `h3_closure_checklist.md`
- `h3_paper_skeleton_vi.md`
- `h3_dma_first_architecture.md`
- `h3_dma_benchmark_plan.md`
- RTL ASCON slave / DMA / top-level
- firmware helper và tests dualcore

## Tiêu chí xong việc

Kiến trúc DMA-first được xem là paper-ready hơn khi có đủ:

- baseline no-CRF thật
- area/timing cost của DMA-first path và H3 reference
- ít nhất một smoke test DMA intelligence / burst behavior
- một benchmark stress hoặc payload/burst mở rộng
- claim và bảng số liệu đã được chỉnh cho nhất quán theo title mới

## Kết luận ngắn

H3 hiện tại đã đủ để bắt đầu viết paper. Để paper đứng vững hơn, phải bổ sung bằng chứng về baseline, cost phần cứng, và độ bền của claim khi chạy nhiều context hoặc nhiều session liên tiếp.
