# SoC RISC-V / ASCON — System Overview

## 1. Tổng quan

SoC 32-bit tích hợp CPU RISC-V (RV32IM) + hardware accelerator ASCON-128/128a (AEAD cipher).
Viết hoàn toàn bằng Verilog-2005, mô phỏng bằng Icarus Verilog.
Firmware bare-metal C chạy trực tiếp trên CPU (không có OS).

**Mục tiêu thiết kế:**
- Minh hoạ tích hợp crypto IP vào SoC với 2 chế độ: CPU-direct và DMA streaming
- Pipeline 5 tầng RV32IM với ICache/DCache
- AXI4-Full crossbar kết nối toàn bộ hệ thống

---

## 2. Block Diagram

```
  External: clk(100MHz), por_n, ext_rst_n, UART(TX/RX), JTAG, GPIO
                                  │
                         ┌────────┴────────┐
                         │  clk_reset_ctrl │  (POR stretcher, 3 reset domains)
                         └────────┬────────┘
                                  │ fabric_rst_n / cpu_rst_n / periph_rst_n
                                  │
              ┌───────────────────┴──────────────────────────┐
              │          AXI4 Crossbar — 5M × 12S            │
              │    Priority: M0 > M1 > M2 > M3 > M4          │
              └──┬────┬────┬────┬────┬────┬────┬────┬────┬───┘
                 │    │    │    │    │    │    │    │    │
    ┌────────────┘    │    │    │    │    │    │    │    └────── S11: DMA-Ctrl Config
    │                 │    │    │    │    │    │    └─────────── S9:  PLIC
    ▼         S0      │    │    │    │    │    └──────────────── S5:  UART
┌──────────┐ IMEM     │    │    │    │    └───────────────────── S4:  CLINT
│ RISC-V   │ (8KB)    │    │    │    └────────────────────────── S3:  SoC-Ctrl
│ CPU Core │◄────  S1 │    │    └─────────────────────────────── S2:  ASCON Accel
│ (RV32IM) │  DMEM    │    └───────────────────────────────────── S1:  DMEM (8KB)
│ 5-stage  │  (8KB)   └────────────────────────────────────────── S0:  IMEM (8KB)
└────┬─────┘
     │   ┌──────────┐  Masters:
     ├──►│  ICache  │  M0 ← ICache (read-only)
     └──►│  DCache  │  M1 ← DCache (read/write)
         └──────────┘  M2 ← ASCON DMA (64b→32b width conv)
                       M3 ← DMA Controller
                       M4 ← JTAG Debug Module
```

---

## 3. AXI4 Bus Topology — 5M × 12S

### Masters

| ID | Tên         | Data Width | Vai trò                              |
|----|-------------|-----------|---------------------------------------|
| M0 | ICache      | 32-bit    | Fetch instruction cho CPU             |
| M1 | DCache      | 32-bit    | Load/store data của CPU               |
| M2 | ASCON DMA   | 32-bit*   | DMA engine trong ASCON (64→32 conv)  |
| M3 | DMA-Ctrl    | 32-bit    | System-level DMA controller           |
| M4 | JTAG DM     | 32-bit    | Debug Module (System Bus Access)      |

*64-bit nội bộ, qua `axi_width_converter_64to32` trước crossbar

### Slaves (Address Map)

| ID  | Tên           | Base Addr   | Size  | Mô tả                            |
|-----|---------------|-------------|-------|----------------------------------|
| S0  | IMEM          | 0x0000_0000 | 8 KB  | Instruction RAM (boot code)      |
| S1  | DMEM          | 0x1000_0000 | 8 KB  | Data RAM (stack + globals)       |
| S2  | ASCON         | 0x2000_0000 | 4 KB  | Crypto accelerator registers     |
| S3  | SoC-Ctrl      | 0x3000_0000 | 4 KB  | Soft reset, cache stats          |
| S4  | CLINT         | 0x4000_0000 | 64 KB | mtime, mtimecmp, msip            |
| S5  | UART          | 0x5000_0000 | 4 KB  | Serial 115200 baud               |
| S6  | GPIO          | 0x5001_0000 | 4 KB  | 32-bit parallel I/O              |
| S7  | SPI           | 0x5002_0000 | 4 KB  | Stub (DECERR)                    |
| S8  | Timer/WDT     | 0x5003_0000 | 4 KB  | Timer0, Timer1, Watchdog         |
| S9  | PLIC          | 0x5004_0000 | 4 KB  | Interrupt aggregator → meip      |
| S10 | OTP           | 0x6000_0000 | 4 KB  | Stub (DECERR)                    |
| S11 | DMA-Ctrl Cfg  | 0x6001_0000 | 4 KB  | DMA channel configuration        |

---

## 4. Module Hierarchy

```
soc_top
├── clk_reset_ctrl          — POR stretcher, 3-domain reset sync
├── boot_ctrl               — Nạp IMEM từ boot ROM, giải phóng cpu_rst_n
├── riscv_cpu_core (RV32IM) — 5-stage pipeline
│   ├── PC, Decoder, ALU
│   ├── MUL/DIV (RV32M)
│   ├── Registers (x0–x31)
│   ├── CSR, Hazard logic
│   └── Interrupt handler
├── icache_top              — Direct-mapped instruction cache (M0)
├── dcache_top              — Direct-mapped data cache (M1)
├── ascon_ip_top            — ASCON-128/128a accelerator (S2 + M2)
│   ├── ascon_axi_slave     — AXI4-Full register interface
│   ├── ascon_CORE          — Crypto engine (AEAD pipeline)
│   │   ├── ascon_CONTROLLER    — FSM: IDLE→INIT→AD→DATA→FIN→TAG
│   │   ├── ascon_datapath
│   │   ├── ascon_STATE_REGISTER — 320-bit state
│   │   ├── ascon_PERMUTATION    — p12/p8/p6 rounds
│   │   ├── ascon_TAG_GENERATOR
│   │   └── ascon_TAG_COMPARATOR
│   └── ascon_dma           — DMA streaming engine
│       ├── dma_ctrl_fsm        — IDLE→WAIT_FIRST→STREAM→WAIT_TAG
│       ├── dma_read_engine
│       ├── dma_write_engine
│       └── sync_fifo (RD/WR)
├── axi_width_converter_64to32 — Chuyển đổi width M2
├── axi4_crossbar_5m12s     — Crossbar chính
├── inst_mem_axi_slave      — IMEM 8 KB (S0)
├── data_mem_axi4_slave     — DMEM 8 KB (S1)
├── soc_ctrl_slave          — SoC control (S3)
├── clint                   — Timer interrupt (S4)
├── uart_top                — UART (S5)
├── gpio_top                — GPIO (S6)
├── timer_top               — Timer/WDT (S8)
├── plic_top                — PLIC (S9)
├── jtag_debug_top          — JTAG DTM + DM (M4)
└── dma_ctrl                — System DMA (S11 + M3)
```

---

## 5. ASCON Accelerator

**Thuật toán:** ASCON-128 và ASCON-128a (AEAD — Authenticated Encryption with Associated Data)  
**State:** 320-bit nội bộ, permutation p12/p8/p6  
**Input:** 128-bit key + 128-bit nonce + plaintext + associated data  
**Output:** ciphertext + 128-bit authentication tag

### Hai chế độ hoạt động

| Chế độ | Trigger | Dùng khi |
|--------|---------|----------|
| **CPU-Direct** | `CTRL[0]=1` (start) | Block đơn ≤ 64-bit plaintext |
| **DMA Streaming** | `CTRL[4:0]=0x5` (DMA_EN + START) | Multi-block, lên đến vài KB |

### Register Map tóm tắt (base 0x2000_0000)

| Offset | Tên       | RW | Mô tả                                  |
|--------|-----------|----|----------------------------------------|
| 0x000  | MODE      | RW | [0]=variant(128/128a) [1]=dir(enc/dec) |
| 0x004  | STATUS    | RO | [0]busy [1]done [2]dma_busy [3]dma_done|
| 0x010  | KEY_0..3  | RW | 128-bit key (4×32-bit)                 |
| 0x020  | CTRL      | RW | [0]start [1]soft_rst [2]dma_en         |
| 0x024  | NONCE_0..3| RW | 128-bit nonce                          |
| 0x034  | PTEXT_0/1 | RW | 64-bit plaintext input                 |
| 0x040  | CTEXT_0/1 | RO | 64-bit ciphertext output               |
| 0x048  | TAG_0..3  | RO | 128-bit authentication tag             |
| 0x100  | DMA_SRC   | RW | Source address (DMEM)                  |
| 0x104  | DMA_DST   | RW | Destination address (DMEM)             |
| 0x108  | DMA_LEN   | RW | Byte length                            |
| 0x200  | PERF_TOTAL| RO | Total DMA cycles (hardware counter)    |
| 0x204  | PERF_CORE | RO | Core busy cycles                       |

---

## 6. CPU Core

| Thuộc tính   | Chi tiết                                          |
|-------------|---------------------------------------------------|
| ISA         | RV32I + RV32M (multiply/divide)                   |
| Pipeline    | 5 tầng: IF → ID → EX → MEM → WB                  |
| Hazard      | Forwarding + stalls (load-use), flush (branch)    |
| Reset       | Active-HIGH posedge rst (ngoại lệ so với phần còn lại) |
| Debug       | JTAG DTM, halt/resume/SBA qua M4                  |
| Interrupts  | meip (PLIC), mtip/msip (CLINT)                    |

---

## 7. Firmware Stack

```
gnu_toolchain/
├── main.c                  — Firmware chính (DMA 16-block demo)
├── compile_c_to_hex.sh     — Build script: C → ELF → HEX
├── include/
│   ├── memory_map.h        — Tất cả base address
│   ├── ascon.h             — ASCON driver (inline asm MMIO)
│   ├── dma.h               — DMA driver
│   ├── uart.h, gpio.h      — Peripheral drivers
│   ├── plic.h, irq.h       — Interrupt helpers
│   └── clint.h, clint.h    — Timer driver
└── tests/
    ├── test_ascon.c         — ASCON 16-block DMA test
    ├── test_uart/gpio/...   — Unit tests per peripheral
    ├── test_integration.c   — Unity build: tất cả 6 tests
    ├── bench_cpu_direct.c   — Benchmark N=1,4,16 CPU-direct
    ├── bench_dma_poll.c     — Benchmark DMA + poll
    └── bench_dma_irq.c      — Benchmark DMA + WFI interrupt
```

**Build command:**
```bash
cd gnu_toolchain
./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c
```

**Toolchain:** `riscv64-unknown-elf-gcc`, `-march=rv32im_zicsr -mabi=ilp32`, `-ffreestanding -nostdlib`

---

## 8. Key Numbers

| Thông số             | Giá trị               |
|---------------------|-----------------------|
| Clock               | 100 MHz               |
| IMEM / DMEM         | 8 KB / 8 KB           |
| CPU ISA             | RV32IM                |
| Pipeline stages     | 5                     |
| ASCON state size    | 320-bit               |
| AXI data width      | 32-bit (M2: 64→32)    |
| AXI ID width        | 4-bit                 |
| Crossbar size       | 5 Masters × 12 Slaves |
| Interrupt sources   | 9 (qua PLIC)          |
| UART baud           | 115200                |
| GPIO width          | 32-bit                |
| Simulation timeout  | 200,000 cycles        |

---

## 9. Interrupt Routing

```
Peripheral IRQs (qua PLIC):
  uart_irq, gpio_irq, timer0_irq, timer1_irq, wdt_irq, ascon_irq, dma_irq
  └──────────────────────────────────────────────────► PLIC → meip → CPU.external_irq

Timer/Software IRQs (bypass PLIC, trực tiếp vào CPU):
  CLINT.mtip ──────────────────────────────────────► CPU.timer_irq
  CLINT.msip ──────────────────────────────────────► CPU.sw_irq
```

---

## 10. Verification Flow

```bash
# Bước 1: Lint
./workflow/ulint_verilog.sh <file.v>

# Bước 2: SoC simulation
./workflow/urun_verilog.sh run_soc_ascon.v

# Bước 3: ASCON unit test
iverilog -g2005 -o build_test ascon/tb/ascon_top_tb.v && vvp build_test

# Bước 4: Firmware build
cd gnu_toolchain && ./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c
```

Dừng tại bước đầu tiên fail. Waveform: `waveform_soc.vcd` → mở bằng GTKWave.

---

## 11. Cấu trúc File Quan Trọng

| File                                | Vai trò                               |
|------------------------------------|---------------------------------------|
| `soc_top.v`                        | Top-level integration (1640 lines)    |
| `run_soc_ascon.v`                  | Testbench với signal taps + monitors  |
| `cpu/riscv_cpu_core_v2.v`         | CPU top (include chain vào core/)     |
| `ascon/ascon_top.v`               | ASCON IP wrapper                      |
| `ascon/interface/ascon_axi_slave.v`| Register map + DMA control            |
| `ascon/dma/ascon_dma.v`           | DMA streaming engine                  |
| `interconnect/axi4_crossbar_5m12s.v`| AXI crossbar                         |
| `gnu_toolchain/include/ascon.h`   | Firmware ASCON driver                 |
| `gnu_toolchain/include/memory_map.h`| Canonical address map               |
| `gnu_toolchain/main.c`            | Demo firmware (DMA 16-block)          |
