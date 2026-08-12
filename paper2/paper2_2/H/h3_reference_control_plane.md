# H3 Reference Control-Plane Baseline

## 1. Muc dich cua tai lieu nay

Tai lieu nay khoa vai tro cua `H3` ben trong nhanh `H`.

`H3` chi duoc dung nhu:

- baseline control-plane
- baseline multi-session correctness
- baseline context-switch cost

`H3` khong duoc dung nhu:

- headline datapath cua nhanh `H`
- kien truc paper chinh
- nguon speedup throughput chinh

## 2. Pham vi H3 duoc phep dai dien

Pham vi ma H3 duoc dai dien trong nhanh `H` gom:

- `CONTEXT_SEL`
- `context_id_active`
- 2 context banks
- context isolation
- switch-back correctness
- context-switch overhead

Nhung pham vi sau khong nen quy ve H3:

- DMA bulk throughput
- pipelined payload feed efficiency
- coherency-driven end-to-end throughput
- output policy optimization

## 3. Cau hoi H3 dung de tra loi

Khi trinh bay voi reviewer hoac ban giam khao, H3 nen duoc dung de tra loi cac cau hoi:

- neu doi session thi sao
- context cu co bi ghi de khong
- control-plane cost la bao nhieu
- firmware co the giu nhieu session ma khong reload toan bo state khong

## 4. Metric H3 can co

H3 can co bo metric rieng, tach khoi DMA-first benchmark:

- context switch latency
- firmware MMIO context-switch interval
- RTL context select latency
- context isolation pass/fail
- switch-back pass/fail

Neu can bang so lieu:

- H3 metric phai dat trong bang `reference control-plane`
- khong tron vao bang throughput payload

## 5. Test H3 nen duoc khoa

Nhung test sau nen duoc xem la bo khoa control-plane reference:

- `test_dualcore_h3_context`
- `test_dualcore_h3_busy_switch`
- `test_dualcore_h3_stress_switchback`
- `test_dualcore_h3_dma_context_smoke`
- `test_dualcore_h3_benchmark`

## 6. Dinh nghia done cho Dot B

Dot B duoc xem la xong khi:

- H3 duoc gan nhan ro la baseline control-plane
- test H3 reference duoc liet ke ro
- metric H3 duoc tach khoi metric DMA-first
- claim trong nhanh `H` khong con dua H3 len thanh headline throughput
