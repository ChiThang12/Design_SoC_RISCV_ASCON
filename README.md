# RISC-V–ASCON SoC Design

## 1. Project Overview

The **RISC-V–ASCON SoC** project is a custom-designed **32-bit RISC-V System-on-Chip**, focusing on **hands-on microarchitecture design**, **memory subsystem implementation**, **AXI-based interconnect**, and **integration of a cryptographic accelerator**.

Instead of assembling pre-built IPs, this project emphasizes **understanding and building each major component from scratch**, following industry-style design practices.

### Project Goals

| Goal          | Description                                       |
| ------------- | ------------------------------------------------- |
| CPU Design    | Understand and implement a pipelined RISC-V CPU   |
| Memory System | Design cache-based instruction & data memory      |
| Interconnect  | Use AXI4 / AXI4-Lite buses                        |
| Security      | Integrate ASCON cryptographic accelerator         |
| Practice      | Approach real-world SoC & enterprise design flows |

This project is intended for:

* Advanced learning in **SoC & CPU design**
* **FPGA prototyping**
* Demonstrating skills for **IC Design / SoC Engineer** roles

---

## 2. System Architecture
<img width="704" height="455" alt="image" src="https://github.com/user-attachments/assets/4baf43f4-5838-4eec-9da7-d5703e37b191" />

The SoC follows a **Harvard architecture**, separating instruction and data paths for higher performance and scalability.

### Top-Level Components

| Component         | Description                           |
| ----------------- | ------------------------------------- |
| RISC-V CPU Core   | Custom 32-bit pipelined processor     |
| Instruction Cache | Dedicated cache for instruction fetch |
| Data Cache        | Load/store cache for data access      |
| AXI4 Interconnect | High-bandwidth system bus             |
| ASCON Accelerator | Cryptographic offload engine          |
| External Memory   | SRAM / DRAM / FPGA memory             |

### Architecture Highlights

* Separate **instruction** and **data** memory paths
* High-bandwidth traffic via **AXI4 Full**
* Low-latency control via **AXI4-Lite**
* DMA-capable crypto accelerator

---

## 3. RISC-V CPU Core

The CPU core is **fully custom-designed**, demonstrating a clear understanding of **RISC-V microarchitecture**.

### ISA Support

| Extension         | Supported |
| ----------------- | --------- |
| RV32I             | ✔         |
| RV32M             | ✔         |
| Custom Extensions | Planned   |

### Pipeline Architecture

| Stage | Description                        |
| ----- | ---------------------------------- |
| IF    | Instruction Fetch                  |
| ID    | Instruction Decode & Register Read |
| EX    | Execute / ALU / Branch             |
| MEM   | Data Memory Access                 |
| WB    | Write Back                         |

### Hazard Handling

| Hazard Type    | Handling Method        |
| -------------- | ---------------------- |
| Data Hazard    | Forwarding / Bypassing |
| Load-Use       | Pipeline Stall         |
| Control Hazard | Pipeline Flush         |

### Control Flow

* Branch decision at **EX stage**
* PC redirection for:

  * Branch taken
  * JAL / JALR
* Pipeline flush on misprediction

> This core is **not a black box** — all datapath and control logic are explicitly designed.

---

## 4. Memory Subsystem & AXI Interface

The memory subsystem is designed using **industry-standard AXI protocols**, making it suitable for real-world SoC integration.

### Memory Architecture

| Path        | Description           |
| ----------- | --------------------- |
| Instruction | ICache → AXI → Memory |
| Data        | DCache → AXI → Memory |

### Cache Design

| Feature       | Description                  |
| ------------- | ---------------------------- |
| Mapping       | Direct-mapped (configurable) |
| Policy        | Write-through / Write-back   |
| Miss Handling | AXI burst transaction        |
| Controller    | Decoupled from CPU           |

### AXI Interface Usage

| Interface | Purpose                   |
| --------- | ------------------------- |
| AXI4 Full | Memory & DMA transactions |
| AXI4-Lite | Control & configuration   |

### AXI Concepts Applied

* Valid / Ready handshake
* Independent read & write channels
* Burst transfers
* Latency hiding via cache

---

## 5. ASCON Cryptographic Accelerator

ASCON is a **lightweight authenticated encryption algorithm**, well-suited for embedded and IoT systems.

### Role in the SoC

| Function       | Description                    |
| -------------- | ------------------------------ |
| Encryption     | Secure data encryption         |
| Decryption     | Secure data decryption         |
| Authentication | Message integrity verification |

### Integration Strategy

| Interface           | Usage                         |
| ------------------- | ----------------------------- |
| AXI4-Lite (Slave)   | Control & status registers    |
| AXI4 (Master / DMA) | High-throughput data transfer |

### Security-Oriented Design

* Clear separation between:

  * Control registers
  * Data processing logic
* Designed for future extensions:

  * Secure boot
  * Trusted execution environments

---

## 6. Verification & Simulation

Verification is treated as a **first-class citizen** in the design process.

### Simulation Tools

| Tool           | Purpose            |
| -------------- | ------------------ |
| Icarus Verilog | RTL simulation     |
| GTKWave        | Waveform debugging |

### Testbench Strategy

* Clock & reset generation
* Memory models
* AXI behavioral models
* Basic assertions and monitors

### Automation Scripts

| Script            | Description                |
| ----------------- | -------------------------- |
| `run_verilog.sh`  | Compile & simulate RTL     |
| `lint_verilog.sh` | Lint & code quality checks |
| `clean.sh`        | Clean build artifacts      |

> Many student projects skip verification — this project does not.

