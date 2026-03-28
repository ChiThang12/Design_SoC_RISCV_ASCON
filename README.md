# RISC-V–ASCON SoC Design

## 1. Tổng quan dự án

Dự án **RISC-V–ASCON SoC** là một **System-on-Chip RISC-V 32-bit** được thiết kế hoàn toàn thủ công, tập trung vào **thiết kế microarchitecture chi tiết**, **hệ thống bộ nhớ phân cấp**, **kết nối dựa trên AXI**, và **tích hợp bộ gia tốc mật mã**.

Thay vì chỉ lắp ráp các IP có sẵn, dự án này nhấn mạnh vào **việc hiểu và xây dựng từng thành phần chính từ đầu**, tuân theo các thực tiễn thiết kế công nghiệp.

### Mục tiêu dự án

| Mục tiêu       | Mô tả                                                      |
| -------------- | ---------------------------------------------------------- |
| CPU Design     | Hiểu và triển khai CPU RISC-V pipeline                    |
| Memory System  | Thiết kế hệ thống bộ nhớ với cache instruction & data     |
| Interconnect   | Sử dụng bus AXI4 / AXI4-Lite                               |
| Security       | Tích hợp bộ gia tốc mật mã ASCON                           |
| Practice       | Tiếp cận quy trình thiết kế SoC thực tế và cấp doanh nghiệp |

Dự án này phù hợp cho:

* Học tập nâng cao về **thiết kế SoC & CPU**
* **FPGA prototyping**
* Chứng minh kỹ năng cho vị trí **IC Design / SoC Engineer**

---

## 2. Kiến trúc hệ thống
<img width="704" height="455" alt="image" src="https://github.com/user-attachments/assets/4baf43f4-5838-4eec-9da7-d5703e37b191" />

SoC tuân theo **kiến trúc Harvard**, tách biệt đường dẫn instruction và data để đạt hiệu năng và khả năng mở rộng cao hơn.

### Các thành phần cấp cao

| Thành phần         | Mô tả                                      |
| ------------------ | ------------------------------------------ |
| RISC-V CPU Core    | Processor pipeline 32-bit tự thiết kế      |
| Instruction Cache  | Cache riêng cho instruction fetch          |
| Data Cache         | Cache cho load/store data                  |
| AXI4 Interconnect  | Bus hệ thống băng thông cao                |
| ASCON Accelerator  | Engine xử lý mật mã offload                |
| External Memory    | Bộ nhớ SRAM / DRAM / FPGA memory           |

### Điểm nổi bật kiến trúc

* Đường **instruction** và **data** memory tách biệt hoàn toàn
* Lưu lượng băng thông cao thông qua **AXI4 Full**
* Điều khiển độ trễ thấp qua **AXI4-Lite**
* Crypto accelerator hỗ trợ DMA

---

## 3. RISC-V CPU Core
<img width="548" height="333" alt="image" src="https://github.com/user-attachments/assets/e9bf6e5f-9964-4cfd-b90b-5c1abc6d421b" />

CPU core được **thiết kế hoàn toàn thủ công**, thể hiện sự hiểu biết rõ ràng về **RISC-V microarchitecture**.

### Hỗ trợ ISA

| Extension         | Hỗ trợ     |
| ----------------- | ---------- |
| RV32I             | ✔          |
| RV32M             | ✔          |
| Custom Extensions | Đang lên kế hoạch |

### Kiến trúc Pipeline

| Giai đoạn | Mô tả                                  |
| --------- | -------------------------------------- |
| IF        | Instruction Fetch (Lấy lệnh)           |
| ID        | Instruction Decode & Register Read     |
| EX        | Execute / ALU / Branch                 |
| MEM       | Data Memory Access                     |
| WB        | Write Back (Ghi kết quả)               |

### Xử lý Hazard

| Loại Hazard    | Phương pháp xử lý       |
| -------------- | ----------------------- |
| Data Hazard    | Forwarding / Bypassing  |
| Load-Use       | Pipeline Stall (Đình trệ) |
| Control Hazard | Pipeline Flush (Xóa)    |

### Luồng điều khiển

* Quyết định branch tại **giai đoạn EX**
* Chuyển hướng PC cho:
  * Branch taken
  * JAL / JALR
* Xóa pipeline khi dự đoán sai (misprediction)

> Core này **không phải là black box** — tất cả datapath và control logic đều được thiết kế tường minh.

---

## 4. Hệ thống bộ nhớ & Giao diện AXI

Hệ thống bộ nhớ được thiết kế sử dụng **giao thức AXI chuẩn công nghiệp**, phù hợp cho tích hợp SoC thực tế.

### Kiến trúc bộ nhớ

| Đường dẫn   | Mô tả                 |
| ----------- | --------------------- |
| Instruction | ICache → AXI → Memory |
| Data        | DCache → AXI → Memory |

### Thiết kế Cache

| Tính năng     | Mô tả                            |
| ------------- | -------------------------------- |
| Mapping       | Direct-mapped (có thể cấu hình)  |
| Policy        | Write-through / Write-back       |
| Miss Handling | AXI burst transaction            |
| Controller    | Tách rời khỏi CPU (Decoupled)    |

### Sử dụng giao diện AXI

| Giao diện | Mục đích                      |
| --------- | ----------------------------- |
| AXI4 Full | Memory & DMA transactions     |
| AXI4-Lite | Control & configuration       |

### Các khái niệm AXI được áp dụng

* Valid / Ready handshake
* Kênh read & write độc lập
* Burst transfers
* Ẩn latency thông qua cache

---

## 5. Bộ gia tốc mật mã ASCON

ASCON là **thuật toán mã hóa xác thực nhẹ (lightweight authenticated encryption)**, rất phù hợp cho hệ thống nhúng và IoT.

### Vai trò trong SoC

| Chức năng      | Mô tả                                  |
| -------------- | -------------------------------------- |
| Encryption     | Mã hóa dữ liệu an toàn                 |
| Decryption     | Giải mã dữ liệu an toàn                |
| Authentication | Xác minh tính toàn vẹn message         |

### Chiến lược tích hợp

| Giao diện           | Công dụng                          |
| ------------------- | ---------------------------------- |
| AXI4-Lite (Slave)   | Control & status registers         |
| AXI4 (Master / DMA) | Truyền tải dữ liệu throughput cao  |

### Thiết kế hướng bảo mật

* Tách biệt rõ ràng giữa:
  * Control registers
  * Data processing logic
* Được thiết kế cho các mở rộng tương lai:
  * Secure boot
  * Trusted execution environments (môi trường thực thi tin cậy)

---

## 6. Verification & Simulation

Verification được coi là **công dân hạng nhất** trong quy trình thiết kế.

### Công cụ Simulation

| Công cụ        | Mục đích               |
| -------------- | ---------------------- |
| Icarus Verilog | RTL simulation         |
| GTKWave        | Waveform debugging     |

### Chiến lược Testbench

* Clock & reset generation
* Memory models
* AXI behavioral models
* Basic assertions và monitors

### Automation Scripts

| Script            | Mô tả                              |
| ----------------- | ---------------------------------- |
| `run_verilog.sh`  | Compile & simulate RTL             |
| `lint_verilog.sh` | Lint & kiểm tra chất lượng code    |
| `clean.sh`        | Dọn dẹp build artifacts            |

> Nhiều dự án sinh viên bỏ qua verification — dự án này thì không.

---

## 7. Cấu trúc Source Code

```
SoC_RISC-V/
├── cpu/
│   ├── core/                 # RTL core logic (pipeline, control, ALU…)
│   ├── interface/            # CPU ↔ AXI / memory / peripheral interfaces
│   ├── memory_axi4full/               # MMU / cache / memory-side logic
│   ├── dma/                  # CPU-side DMA control (if tightly coupled)
│   ├── debug_cpu/                # Debug logic (log)
│   │
│   ├── cpu_core.v            # SoC Top (official version)
│   ├── riscv_cpu_core.v       # CPU RISCV (official version)
│   │
│   ├── tb/
│   │   ├── tb_cpu_top.sv
│   │   └── tb_riscv_cpu.sv
│   │
│   ├── workflow/
│   │   ├── linux/
│   │   └── windows/
│   │
│   └── README.md
│
├── ascon/
│   ├── rtl/
│   │   ├── CONTROLLER/
│   │   ├── PERMUTATION/
│   │   │   ├── ascon_PERMUTATION.v  
│   │   │   ├── tb_ASCON_PERMUTATION.v
│   │   │   └── README.md    
│   │   ├── STATE_REGISTER/
│   │   └── ascon_top.sv
│   │
│   ├── sw_check/             # Software golden model / test vectors
│   └── README.md
│
├── dma/
│   ├── rtl/
│   │   ├── dma_defines_axi4.vh
│   │   ├── dma_engine_axi4.v
│   │   ├── dma_channel_axi4.v
│   │   ├── dma_arbiter.v
│   │   ├── dma_config_slave.v
│   │   └── dma_top_axi4.v
│   │
│   ├── tb/
│   │   └── tb_dma_top.sv
│   │
│   └── README.md
│
├── soc_top/
│   ├── rtl
│   │   └── cpu_core.v             # Integrates CPU + DMA + ASCON
│   ├── tb
│   │   └── tb_cpu_core.v  
│   └── README.md
│
├── docs/
│   ├── architecture.md
│   ├── memory_map.md
│   └── debug_notes.md
│
└── README.md
```

### Giải thích cấu trúc

#### 📁 `cpu/` - RISC-V CPU Core
Chứa toàn bộ logic của CPU core, bao gồm:
- **core/**: Pipeline logic, control unit, ALU, branch predictor
- **interface/**: AXI interface adapters, memory controllers
- **memory_axi4full/**: MMU, instruction/data cache controllers
- **debug/**: Debug interface, performance counters
- **tb/**: Testbenches riêng cho CPU

#### 📁 `ascon/` - Cryptographic Accelerator
Module mã hóa ASCON với:
- **controller/**: FSM điều khiển quá trình mã hóa/giải mã
- **permutation/**: Permutation logic (xem README riêng)
- **state_register/**: State management 320-bit
- **sw_check/**: Golden model bằng software để so sánh kết quả

#### 📁 `dma/` - DMA Controller
DMA engine với giao diện AXI4:
- Hỗ trợ multi-channel data transfer
- Arbiter cho priority scheduling
- Configuration interface qua AXI4-Lite

#### 📁 `soc_top/` - SoC Integration
Top-level module kết nối tất cả:
- CPU ↔ Memory qua AXI
- CPU ↔ ASCON qua AXI4-Lite
- DMA ↔ Memory qua AXI4
- Address map và memory mapping

---

## 8. Flow làm việc

### 8.1. Development Flow

```
1. RTL Design
   ├── Viết module Verilog/SystemVerilog
   ├── Code review & lint check
   └── Tài liệu thiết kế

2. Verification
   ├── Viết testbench
   ├── Chạy simulation
   ├── Kiểm tra waveform
   └── Coverage analysis

3. Integration
   ├── Tích hợp vào SoC top
   ├── System-level testing
   └── Performance profiling

4. FPGA Prototyping (tùy chọn)
   ├── Synthesis
   ├── Place & Route
   └── On-board testing
```

### 8.2. Simulation Flow

```bash
# Compile RTL for linux
./workflow/lrun_verilog.sh /cpu/tb/tb_cpu_core.v   

# Compile RTL for window
./workflow/wrun_verilog.bat /cpu/tb/tb_cpu_core.v 

# Xem waveform
gtkwave tb_cpu_debug.vcd

# Lint check
./lint_verilog.sh
```

---

## 9. Các tính năng nổi bật

### ✅ Đã hoàn thành

- [x] CPU RISC-V 32-bit pipeline 5 stages
- [x] RV32I base instruction set
- [x] RV32M multiply/divide extension
- [x] Instruction & Data Cache
- [x] AXI4/AXI4-Lite/FULL interfaces
- [x] ASCON permutation module
- [x] Basic testbenches SoC (RISCV <-> BUS axi4 <-> MEMORY)

### 🚧 Đang phát triển

- [ ] ASCON full encryption/decryption
- [ ] MMU với virtual memory
- [ ] Branch prediction
- [ ] Pipeline optimization
- [ ] Advanced debug features
- [ ] FPGA synthesis scripts

### 🔮 Kế hoạch tương lai

- [ ] Cache coherency protocol
- [ ] Multi-core support
- [ ] Custom RISC-V extensions
- [ ] Secure boot implementation
- [ ] Power management

---

## 10. Yêu cầu hệ thống

### Software Requirements

| Tool           | Version    | Mục đích              |
| -------------- | ---------- | --------------------- |
| Icarus Verilog | ≥ 11.0     | RTL simulation        |
| GTKWave        | ≥ 3.3      | Waveform viewer       |
| Python         | ≥ 3.8      | Test scripts          |
| Make           | Latest     | Build automation      |

### Hardware Requirements (cho FPGA)

- FPGA board: Xilinx/Intel (tùy chọn)
- RAM: ≥ 8GB (cho synthesis)
- Storage: ≥ 2GB cho project files

---

## 11. Hướng dẫn sử dụng

### Clone Repository

```bash
git clone https://github.com/your-username/RISC-V-ASCON-SoC.git
cd RISC-V-ASCON-SoC
```

### Chạy CPU Testbench

```bash
cd cpu/workflow/linux
chmod +x run_verilog.sh
cd
./workflow/lrun_verilog.sh /cpu/tb/tb_cpu_core.v  
```

### Chạy ASCON Testbench

```bash
cd ascon/tb
iverilog -o sim ascon_top_tb.v ../rtl/**/*.v
vvp sim
gtkwave ascon_permutation.vcd
```

### Chạy DMA Testbench

```bash
cd dma/workflow
./run_dma_sim.sh
```

---

## 12. Tài liệu tham khảo

### RISC-V ISA
- [RISC-V Specifications](https://riscv.org/specifications/)
- [RISC-V Assembly Programmer's Manual](https://github.com/riscv/riscv-asm-manual)

### AXI Protocol
- ARM AMBA AXI Protocol Specification
- [AXI Reference Guide (Xilinx)](https://www.xilinx.com/support/documentation.html)

### ASCON Algorithm
- [ASCON Official Website](https://ascon.iaik.tugraz.at/)
- NIST Lightweight Cryptography (2023)

### Thiết kế SoC
- "Computer Organization and Design RISC-V Edition" - Patterson & Hennessy
- "Digital Design and Computer Architecture RISC-V Edition" - Harris & Harris

---


## 13. License

Dự án này được phân phối dưới [MIT License](LICENSE).

---

## 14. Tác giả & Liên hệ

**Project Maintainer**: ChiThang  
**Email**: dodotranchithang2k5@gmail.com  

### Acknowledgments

- Cảm ơn cộng đồng RISC-V
- Đội ngũ phát triển ASCON
- Các tài liệu mở về thiết kế SoC

---

## 16. Changelog

### Version 1.0.0 (Current)
- ✅ CPU core hoàn chỉnh với RV32IM
- ✅ Cache hierarchy
- ✅ AXI interconnect
- ✅ ASCON permutation module
- ✅ DMA controller
- ✅ Basic verification environment

### Roadmap Version 1.1.0
- 🔜 Full ASCON encryption/decryption
- 🔜 Advanced cache policies
- 🔜 Performance optimizations
- 🔜 FPGA synthesis support

---

**Last Updated**: February 2026  
**Status**: 🚀 Active Development
# SoC_full
