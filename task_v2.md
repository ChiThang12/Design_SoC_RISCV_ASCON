# ASCON SoC Throughput Optimization — Task Tracker

## Step 1: Firmware Green IC
- `[/]` 1.1 main.c: WFI + interrupt thay poll loop
- `[/]` 1.2 ascon.h: Bỏ fence w,w trong ASCON_WRITE macro
- `[/]` 1.3 dmem_layout.h + main.c: Tăng payload 64→1024B
- `[/]` 1.4 main.c: Set DMA_BURST=7

## Step 2: RTL core_pump + write engine optimization
- `[x]` 2.1 sync_fifo.v: Add FWFT output — đã có sẵn trong codebase
- `[x]` 2.2 dma_ctrl_fsm.v: Bỏ PUMP_WAIT, dùng FWFT dout — v3.0 đã done
- `[x]` 2.3 dma_write_engine.v: FWFT + Dynamic AXI Burst (v4.0) — 506→1248 Mbps

## Step 3: Verification
- `[x]` 3.1 Rebuild firmware — không cần (chỉ RTL thay đổi)
- `[x]` 3.2 Re-run SoC simulation — run_soc_ascon_v4.log
- `[x]` 3.3 Compare throughput — 506 Mbps → 1248 Mbps (+2.47x), 202→82 cycles
