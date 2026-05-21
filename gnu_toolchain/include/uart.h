/* uart.h — AXI4-Full UART Driver
 *
 * Base: 0x5000_0000
 * 0x00 TX_DATA    [7:0]  WO
 * 0x04 RX_DATA    [7:0]  RO
 * 0x08 STATUS     [4:0]  RO : {rx_ovr(4), rx_full(3), rx_empty(2), tx_full(1), tx_empty(0)}
 * 0x0C CTRL       [1:0]  RW : {rx_irq_en(1), tx_irq_en(0)}
 * 0x10 BAUD_DIV   [15:0] RW
 * 0x14 IRQ_STATUS [1:0]  RW1C: {rx_irq(1), tx_irq(0)}
 */
#ifndef UART_H
#define UART_H

#include <stdint.h>
#include "memory_map.h"

/* ── Baud divisor constants (clk = 100 MHz) ─────────────────────────────── */
#define UART_BAUD_DIV(clk_hz, baud)     ((clk_hz) / (baud))
#define UART_DIV_115200_100MHZ          868u
#define UART_DIV_9600_100MHZ            10416u

/* ── STATUS register bits ────────────────────────────────────────────────── */
#define UART_ST_TX_EMPTY    (1u << 0)
#define UART_ST_TX_FULL     (1u << 1)
#define UART_ST_RX_EMPTY    (1u << 2)
#define UART_ST_RX_FULL     (1u << 3)
#define UART_ST_RX_OVR      (1u << 4)

/* ── IRQ_STATUS bits ─────────────────────────────────────────────────────── */
#define UART_IRQ_TX         (1u << 0)
#define UART_IRQ_RX         (1u << 1)

/* ── Register accessors ──────────────────────────────────────────────────── */
#define UART_TX_DATA    MMIO_REG(UART_BASE, 0x00)
#define UART_RX_DATA    MMIO_REG(UART_BASE, 0x04)
#define UART_STATUS     MMIO_REG(UART_BASE, 0x08)
#define UART_CTRL       MMIO_REG(UART_BASE, 0x0C)
#define UART_BAUD_DIV_R MMIO_REG(UART_BASE, 0x10)
#define UART_IRQ_STATUS MMIO_REG(UART_BASE, 0x14)

/* ── Init ────────────────────────────────────────────────────────────────── */
static inline void uart_init(uint32_t baud_div, uint8_t en_tx_irq, uint8_t en_rx_irq)
{
    UART_BAUD_DIV_R = (uint32_t)baud_div;
    __asm__ volatile ("fence w,w" ::: "memory");
    UART_CTRL = ((uint32_t)(en_rx_irq & 1u) << 1) | (uint32_t)(en_tx_irq & 1u);
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ── TX/RX ───────────────────────────────────────────────────────────────── */
static inline void uart_putc(char ch)
{
    while (UART_STATUS & UART_ST_TX_FULL) {}
    UART_TX_DATA = (uint32_t)(uint8_t)ch;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline char uart_getc(void)
{
    while (UART_STATUS & UART_ST_RX_EMPTY) {}
    return (char)(UART_RX_DATA & 0xFFu);
}

/* uart_puts: blocking — chờ TX_EMPTY sau khi gửi hết chuỗi */
static inline void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
    /* Wait until TX FIFO drains */
    while (!(UART_STATUS & UART_ST_TX_EMPTY)) {}
}

/* ── IRQ helpers ─────────────────────────────────────────────────────────── */
static inline void uart_tx_irq_enable(void)
{
    UART_CTRL |= 1u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void uart_rx_irq_enable(void)
{
    UART_CTRL |= 2u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void uart_irq_clear(void)
{
    UART_IRQ_STATUS = (UART_IRQ_TX | UART_IRQ_RX); /* W1C */
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline uint32_t uart_irq_status(void)
{
    return UART_IRQ_STATUS;
}

/* ── Hex print helpers ───────────────────────────────────────────────────── */
static inline void uart_puthex8(uint8_t v)
{
    const char *h = "0123456789ABCDEF";
    uart_putc(h[(v >> 4) & 0xF]);
    uart_putc(h[v & 0xF]);
}

static inline void uart_puthex32(uint32_t v)
{
    uart_puthex8((uint8_t)(v >> 24));
    uart_puthex8((uint8_t)(v >> 16));
    uart_puthex8((uint8_t)(v >>  8));
    uart_puthex8((uint8_t)v);
}

/* uart_printf: chỉ hỗ trợ %x (hex 32-bit), không dùng stdlib */
static inline void uart_printf(const char *fmt, uint32_t val)
{
    while (*fmt) {
        if (fmt[0] == '%' && (fmt[1] == 'x' || fmt[1] == 'X')) {
            uart_puts("0x");
            uart_puthex32(val);
            fmt += 2;
        } else {
            uart_putc(*fmt++);
        }
    }
}

#endif /* UART_H */
