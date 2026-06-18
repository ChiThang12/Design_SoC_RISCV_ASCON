# FPGA Implementation — PYNQ-Z2 (Zynq-7020)

## Mục tiêu
Deploy custom RISC-V SoC (RV32IM + ASCON DMA Engine) lên PYNQ-Z2 PL, chứng minh
end-to-end secure image/video transmission với hardware ASCON vs software ASCON trên MCU.

---

## Kiến trúc hệ thống

```
┌─────────────────────────────────────────────────┐
│  PYNQ-Z2                                        │
│  ┌──────────────────────┐  ┌──────────────────┐ │
│  │  PL (Programmable    │  │  PS (ARM A9)     │ │
│  │  Logic)              │  │                  │ │
│  │  ┌────────────────┐  │  │  Python/Jupyter  │ │
│  │  │ Custom RISC-V  │◄─┼──┼─ Load bitstream  │ │
│  │  │ SoC            │  │  │  Send image data │ │
│  │  │ (RV32IM +      │  │  │  Monitor UART    │ │
│  │  │  ASCON DMA)    │  │  │                  │ │
│  │  └───────┬────────┘  │  └──────────────────┘ │
│  └──────────┼───────────┘                        │
└─────────────┼───────────────────────────────────┘
              │ UART / SPI ciphertext output
              ▼
     ┌─────────────────┐
     │  MCU            │
     │  (STM32/ESP32)  │
     │  SW ASCON decrypt│
     │  → verify tag   │
     │  → output result│
     └─────────────────┘
```

---

## Thư mục con

```
fpga/
├── constraints/          ← XDC pin assignments + timing constraints (PYNQ-Z2)
├── scripts/              ← Vivado TCL: create_project, synth, impl, bitstream
├── wrapper/              ← top_pynq_z2.v: adapt SoC IOs đến PYNQ-Z2 pins
│   └── top_pynq_z2.v    ← MMCM (125→100MHz), BRAM init, IO buffer
├── ip/                   ← Vivado IP wrappers (MMCM, BRAM, JTAG BSCANE2)
├── demo/
│   ├── host/             ← Python scripts (PYNQ PS side): load hex, send frames
│   └── mcu/              ← MCU firmware: ASCON SW decrypt + verify
└── results/              ← Post-impl reports: timing, utilization, power
    ├── timing_summary.rpt
    ├── utilization.rpt
    └── power.rpt
```

---

## PYNQ-Z2 Resources (Zynq-7020)

| Resource | Available | Estimated SoC usage |
|----------|-----------|---------------------|
| LUT      | 53,200    | ~15,000–20,000      |
| FF       | 106,400   | ~8,000–12,000       |
| BRAM     | 140 × 36Kb | 4 (IMEM 8KB + DMEM 8KB + Cache) |
| DSP48    | 220       | 2–4 (multiplier)    |
| Clock    | MMCM × 4  | 1 MMCM (125→100MHz) |

---

## Roadmap FPGA (đến cuối tháng 9/2026)

### Phase 1 — Synthesis & Timing Closure (Tháng 7)
- [ ] Tạo `constraints/pynq_z2.xdc`: clock 100MHz, IO standards
- [ ] Tạo `wrapper/top_pynq_z2.v`: MMCM, BRAM primitive, UART IO
- [ ] Tạo `scripts/create_project.tcl`: add all RTL sources, IP
- [ ] Chạy synthesis → check critical path, fix timing violations
- [ ] Implementation → LUT/FF utilization < 80%
- [ ] Generate bitstream

### Phase 2 — Firmware + Boot (Tháng 7–8)
- [ ] Verify boot_ctrl load hex vào IMEM qua UART bootloader
- [ ] Test test_ascon (T1–T4) chạy đúng trên hardware thực
- [ ] UART output match simulation log

### Phase 3 — System Demo (Tháng 8)
- [ ] Python script (PS side): đọc image → chunk thành 8-byte blocks → gửi qua SPI/UART vào SoC
- [ ] SoC RISC-V firmware: nhận frame → ASCON DMA encrypt → gửi ciphertext + tag ra MCU
- [ ] MCU firmware: nhận ciphertext → SW ASCON decrypt → verify tag → output

### Phase 4 — Benchmark & Kết quả (Tháng 9)
- [ ] Đo throughput ASCON HW (Mbps) vs SW baseline trên MCU
- [ ] Đo latency per frame
- [ ] Đo power từ Vivado Power Analysis
- [ ] So sánh với related work trong survey/

---

## Lưu ý kỹ thuật — PYNQ-Z2 PL

### Clock
```tcl
# PYNQ-Z2 PL clock từ PS: 125MHz trên pin W5
# Cần MMCM scale xuống 100MHz cho SoC
create_clock -period 8.000 -name clk_pl [get_ports clk_pl_i]
```

### BRAM thay SRAM
IMEM (8KB) và DMEM (8KB) cần map vào Xilinx BRAM primitive.
Trong simulation dùng behavioral SRAM; FPGA cần BRAM wrapper với `INIT` file.

### UART pins (PYNQ-Z2)
- UART TX → `PMOD JA[0]` hoặc USB-UART chip (CP2104 trên board)
- Board đã có USB-UART bridge → dùng để monitor + bootload

### Reset
- `rst_n` kéo từ PS GPIO hoặc từ BTN0 (push button trên board)
- Power-on reset cần debounce 100ms
