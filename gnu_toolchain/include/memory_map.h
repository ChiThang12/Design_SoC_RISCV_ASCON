/* memory_map.h — SoC RISC-V ASCON: tập trung địa chỉ base tất cả peripheral */
#ifndef MEMORY_MAP_H
#define MEMORY_MAP_H

#include <stdint.h>

/* ── Slave ports (AXI4 bus) ──────────────────────────────────────────────── */
#define IMEM_BASE        0x00000000UL   /* S0: Instruction Memory 8 KB */
#define DMEM_BASE_ADDR   0x10000000UL   /* S1: Data Memory 8 KB */
#define ASCON_BASE       0x20000000UL   /* S2: ASCON Crypto Accelerator */
#define SOC_CTRL_BASE    0x30000000UL   /* S3: SoC Control */
#define CLINT_BASE       0x40000000UL   /* S4: CLINT */
#define UART_BASE        0x50000000UL   /* S5: UART */
#define GPIO_BASE        0x50010000UL   /* S6: GPIO */
#define SPI_BASE         0x50020000UL   /* S7: SPI stub (DECERR) */
#define TIMER_BASE       0x50030000UL   /* S8: Timer0/1 + WDT */
#define PLIC_BASE        0x50040000UL   /* S9: PLIC */
#define OTP_BASE         0x60000000UL   /* S10: OTP stub (DECERR) */
#define DMA_BASE         0x60010000UL   /* S11: DMA Controller */

/* ── MMIO register access helper ─────────────────────────────────────────── */
#define MMIO_REG(base, offset) \
    (*((volatile uint32_t *)((uint32_t)(base) + (uint32_t)(offset))))

#endif /* MEMORY_MAP_H */
