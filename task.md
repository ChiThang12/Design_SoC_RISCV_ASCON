# ASCON SoC Throughput Optimization — Task Tracker

## Phase 1: Quick Wins — Firmware & Config
- `[ ]` 1.0 Pre-research: verify IRQ path, burst support, DMA FSM state
- `[ ]` 1.1 Enable interrupt + `wfi` in main.c (replace poll loop)
- `[ ]` 1.2 Set DMA_BURST for burst transfers (if RTL supports)
- `[ ]` 1.3 Increase payload 64B → 1024B
- `[ ]` 1.4 Optimize ASCON_WRITE macro (reduce fence overhead)
- `[ ]` 1.5 Rebuild firmware + re-run simulation
- `[ ]` 1.6 Compare throughput results

## Phase 2: DMA Pipeline — RTL
- `[ ]` 2.1 Refactor DMA FSM: separate Read/Core/Write engines
- `[ ]` 2.2 Add input FIFO between Read engine and ASCON core
- `[ ]` 2.3 Implement AXI burst (configurable ARLEN)
- `[ ]` 2.4 Verify data_valid/data_ready handshake pipelined
- `[ ]` 2.5 Re-run simulation + verify correctness + measure throughput

## Phase 3: Bus Architecture — SoC RTL
- `[ ]` 3.1 Remove/bypass 64→32 width converter
- `[ ]` 3.2 Dual-port DMEM for CPU + DMA
- `[ ]` 3.3 Verify ASCON DMA interrupt via PLIC
- `[ ]` 3.4 Final throughput measurement
