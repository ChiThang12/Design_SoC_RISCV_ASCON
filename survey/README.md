# Survey — Positioning Research Contribution

## Mục tiêu Survey
Xác định **khoảng trống nghiên cứu** (research gap) để định vị đóng góp của luận văn
trong bối cảnh các công trình đã có về:
1. Hardware ASCON implementations
2. RISC-V SoC designs
3. Lightweight crypto + FPGA
4. Secure IoT/Edge communication platforms

---

## Câu hỏi nghiên cứu chính
> *Làm thế nào để tích hợp hiệu quả một ASCON cryptographic accelerator tự trị
> (autonomous DMA-enabled) vào một custom RISC-V SoC, và hệ thống này mang lại
> cải thiện throughput/latency như thế nào so với software-only baseline trong
> ứng dụng secure image transmission?*

---

## Thư mục con

```
survey/
├── README.md               ← File này: hướng dẫn + research positioning
├── related_work/
│   ├── hw_ascon.md         ← Hardware ASCON implementations (FPGA/ASIC)
│   ├── riscv_soc.md        ← Custom RISC-V SoC papers
│   ├── crypto_soc.md       ← SoC với crypto accelerator (AES/SHA/ASCON)
│   └── iot_security.md     ← IoT secure comm platforms
├── positioning.md          ← Gap analysis + novelty statement
└── comparison/             ← Khi có Excel → phân tích ở đây
    └── .gitkeep
```

---

## Phân loại Related Work

### Nhóm 1 — Hardware ASCON Implementations (thuần accelerator)
Các paper triển khai ASCON hardware **không có full SoC**:
- Benchmark metric: throughput (Gbps/Mbps), area (LUT/GE), cycles/byte
- Hầu hết: pure combinational hoặc round-based pipeline, không có DMA
- **Gap**: Thiếu autonomous operation — CPU phải poll/feed từng block

Key papers cần tìm:
- [x] Bansod et al. — ASCON hardware implementation survey
- [x] NIST LWC hardware benchmarking project (GMU)
- [ ] ISAP, Elephant, TinyJAMBU comparison (cùng NIST finalists)
- [ ] Masked ASCON (side-channel protection) — khác use-case

### Nhóm 2 — RISC-V SoC Papers
Các custom RISC-V SoC có tích hợp crypto:
- **PULP Platform (ETH Zurich)**: RV32IMC + hardware AES, no ASCON
- **CVA6 / Ariane**: RV64GC, không focus crypto
- **PicoRV32**: Nhỏ, không có cache, không có DMA
- **SiFive FE310**: Commercial, phổ biến nhưng không open crypto hw
- **Gap**: Không có RISC-V SoC nào tích hợp ASCON (NIST LWC standard) với DMA offload

### Nhóm 3 — FPGA-based Crypto SoC
- Zynq + AES (Xilinx SecureIP): closed-source, không custom
- MicroBlaze/NIOS II + crypto: soft-core, performance thấp hơn custom pipeline
- **Gap**: Custom RISC-V (không soft-core) + ASCON DMA trên FPGA chưa có demo

### Nhóm 4 — IoT Secure Communication
- ARM Cortex-M33 + TrustZone-M: HW security nhưng dùng AES, không ASCON
- ESP32 + SW ASCON: software-only, không accelerated
- **Gap**: End-to-end demo ASCON hardware encrypt → channel → SW decrypt với
  image payload trên FPGA prototype chưa được công bố

---

## Novelty Statement (draft)

**Đóng góp của luận văn này:**

1. **Full custom RISC-V SoC** với pipelined 5-stage CPU (RV32IM), dual cache,
   AXI4 crossbar — không dùng IP core (MicroBlaze/NIOS).

2. **Autonomous DMA-enabled ASCON engine**: không chỉ là MMIO register bank
   mà có AXI Master riêng, tự fetch plaintext + write ciphertext, CPU chỉ
   cấu hình và WFI — giảm CPU overhead ~80% so với CPU-direct mode.

3. **FPGA prototype on PYNQ-Z2**: Timing closure 100MHz, utilization report,
   end-to-end power measurement — không chỉ là simulation.

4. **End-to-end secure channel demo**: Image/video frame → HW ASCON encrypt
   (FPGA) → ciphertext → MCU SW ASCON decrypt → verified. Benchmark HW vs SW.

---

## Roadmap Survey (đến cuối tháng 7/2026)

- [ ] Tìm và đọc 10–15 paper trong 4 nhóm trên (Google Scholar, IEEE Xplore, ACM DL)
- [ ] Tạo `related_work/hw_ascon.md` — tóm tắt mỗi paper: approach, metric, limitation
- [ ] Tạo `related_work/riscv_soc.md`
- [ ] Nhận Excel từ supervisor → phân tích → `comparison/comparison_table.md`
- [ ] Viết `positioning.md` — gap analysis chính thức
- [ ] Draft "Related Work" section cho thesis (2–3 trang)

---

## Search Keywords (Google Scholar / IEEE Xplore)

```
"ASCON hardware implementation FPGA"
"lightweight cryptography hardware accelerator RISC-V"
"NIST LWC hardware benchmark"
"RISC-V SoC cryptographic accelerator"
"DMA-enabled crypto offload embedded"
"ASCON authenticated encryption hardware"
"secure IoT edge FPGA RISC-V"
```

---

## Benchmark Metrics cần so sánh

| Metric | Đơn vị | Nguồn đo |
|--------|--------|----------|
| Throughput | Mbps | PERF_TOTAL counter / mcycle CSR |
| Latency/frame | µs | cycles × (1/f_clk) |
| CPU overhead | % | cycles_CPU_busy / cycles_total |
| FPGA area | LUT, FF, BRAM | Vivado utilization report |
| Power | mW | Vivado power analysis |
| HW vs SW speedup | ×N | HW_throughput / SW_throughput |
