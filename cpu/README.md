OK 👍 mình mô tả lại **cấu trúc thư mục + vai trò từng thành phần**, với **`riscv_core_axi.v` là top module**, đúng theo hình bạn gửi.

---

## 🧠 Tổng quan kiến trúc CPU trong SoC

Thư mục `cpu/` chứa **toàn bộ IP RISC-V CPU**, được thiết kế để **kết nối với SoC thông qua bus AXI**.
Module trung tâm (top) là:

👉 **`riscv_core_axi.v`**
→ đây là **điểm vào duy nhất** của CPU khi tích hợp vào SoC.

---

## 🧩 Phân tích cấu trúc thư mục

```
cpu/
├── core/
├── interface/
├── memory/
├── riscv5stagedemo/
├── riscv_core_axi.v        ⭐ TOP MODULE
├── datapath.v              ⭐ TOP CPU
├── tb_riscv_core_axi.v
├── tb_riscv_core_axi_hex.v
├── *.vcd / *.log
├── program.hex
├── example.c / example.s
├── build.sh / run.sh
└── README.md
```

---

## ⭐ `riscv_core_axi.v` — TOP MODULE (QUAN TRỌNG NHẤT)

### Vai trò

* Là **wrapper top-level** của CPU
* Kết nối:

  * **Core RISC-V nội bộ**
  * **AXI interface**
  * **Instruction / Data memory**
* Là module mà:

  * SoC top
  * AXI interconnect
  * hoặc testbench
    sẽ **instantiate trực tiếp**

👉 Trong SoC:

```verilog
riscv_core_axi u_cpu (
    .aclk       (...),
    .aresetn    (...),
    .m_axi_*    (...)
);
```

---

## 📂 `core/` — RISC-V CORE LOGIC

Chứa **phần “não” của CPU**:

* FSM điều khiển pipeline
* Instruction Decode
* Register File
* ALU / Branch / Control logic
* Các stage pipeline (5-stage)

👉 Không biết AXI là gì
👉 Không giao tiếp trực tiếp với SoC

📌 **Core = thuần CPU**

---

## 📂 `datapath.v`

* Mô tả **datapath tổng thể**:

  * PC
  * ALU input/output
  * mux chọn nguồn
* Kết nối giữa:

  * register file
  * ALU
  * control

👉 Có thể xem như **xương sống của core**

---

## 📂 `interface/` — AXI / BUS INTERFACE

Chứa logic:

* AXI Master interface
* Chuyển đổi:

  * Load / Store instruction
  * ↔ AXI Read / Write transaction

👉 Đây là cầu nối:

```
CORE  <---->  AXI BUS (SoC)
```

📌 Rất quan trọng khi tích hợp ASCON / UART / SRAM sau này

---

## 📂 `memory/`

* Instruction Memory
* Data Memory
* ROM / RAM model cho simulation
* Load file `.hex`

👉 Dùng cho:

* Simulation
* FPGA demo
* Chưa phải SRAM/DRAM thật của SoC

---

## 📂 `riscv5stagedemo/`

* Demo chương trình
* Test pipeline 5-stage
* Ví dụ:

  * hazard
  * branch
  * load/store

📌 Dùng để **verify CPU hoạt động đúng**

---

## 🧪 Testbench

### `tb_riscv_core_axi.v`

* Testbench chính
* Instantiate:

  * `riscv_core_axi`
* Clock / reset
* Monitor AXI transaction

### `tb_riscv_core_axi_hex.v`

* Testbench chạy chương trình từ `program.hex`
* Phù hợp để:

  * So sánh với ISS
  * Debug instruction

---

## 📄 File phần mềm / toolchain

| File                  | Vai trò                    |
| --------------------- | -------------------------- |
| `example.c`           | Chương trình C test        |
| `example.s`           | Assembly sau compile       |
| `example.dump`        | Disassembly                |
| `program.hex`         | Nạp vào instruction memory |
| `compile_c_to_hex.sh` | C → HEX                    |
| `run.sh`, `build.sh`  | Script automate            |

👉 Đây là **flow phần mềm → phần cứng** chuẩn của CPU

---

## 🧠 Nhìn dưới góc độ SoC

Trong kiến trúc SoC của bạn:

```
SoC TOP
 ├── AXI Interconnect
 │    ├── riscv_core_axi   ⭐
 │    ├── ASCON
 │    ├── UART
 │    └── SRAM
```

👉 `riscv_core_axi.v` là **AXI Master**
👉 ASCON / UART / SRAM là **AXI Slave**

---

