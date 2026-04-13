/* ============================================================================
 * uart.h — AXI4-Full UART Library (Matched with RTL)
 *
 * Base Address: 0x5000_0000
 *
 * Registers:
 * 0x00 TX_DATA    [7:0] WO  : TX FIFO write
 * 0x04 RX_DATA    [7:0] RO  : RX FIFO read
 * 0x08 STATUS     [4:0] RO  : {rx_ovr(4), rx_full(3), rx_empty(2), tx_full(1), tx_empty(0)}
 * 0x0C CTRL       [1:0] RW  : {rx_irq_en(1), tx_irq_en(0)}
 * 0x10 BAUD_DIV   [15:0]RW  : Divisor
 * 0x14 IRQ_STATUS [1:0] RW1C: {rx_irq(1), tx_irq(0)}
 * ============================================================================ */

#ifndef _UART_H_
#define _UART_H_

#include <stdint.h>

/* Bit masks cho thanh ghi STATUS (0x08) */
#define UART_ST_TX_EMPTY  (1 << 0)
#define UART_ST_TX_FULL   (1 << 1)
#define UART_ST_RX_EMPTY  (1 << 2)
#define UART_ST_RX_FULL   (1 << 3)
#define UART_ST_RX_OVR    (1 << 4)

/* --------------------------------------------------------------------------
 * Khởi tạo UART: Cấu hình Baud Rate và Ngắt
 * -------------------------------------------------------------------------- */
static inline void uart_init(uint16_t baud_div, uint8_t en_tx_irq, uint8_t en_rx_irq)
{
    uint32_t ctrl_val = ((en_rx_irq & 1) << 1) | (en_tx_irq & 1);

    __asm__ volatile (
        "lui  t0, 0x50000\n"
        
        /* Ghi BAUD_DIV (0x10) */
        "sw   %0, 0x10(t0)\n"
        "fence w, w\n"
        
        /* Ghi CTRL (0x0C) */
        "sw   %1, 0x0C(t0)\n"
        "fence w, w\n"
        :: "r" ((uint32_t)baud_div), "r" (ctrl_val)
        : "t0", "memory"
    );
}

/* --------------------------------------------------------------------------
 * TX: Ghi 1 byte (Safe Poll)
 * Kiểm tra cờ TX_FIFO_FULL (Bit 1). Nhờ FIFO 16-deep, 16 ký tự đầu 
 * tiên sẽ không tốn cycle chờ. Rất an toàn cho Watchdog.
 * -------------------------------------------------------------------------- */
static inline void uart_putc(char ch)
{
    uint32_t status;
    do {
        /* Đọc thanh ghi STATUS (offset 0x08) */
        __asm__ volatile (
            "lui  t0, 0x50000\n"
            "lw   %0, 8(t0)\n"
            : "=r" (status)
            : : "t0", "memory"
        );
    } while (status & UART_ST_TX_FULL); /* Loop nếu FIFO đầy */

    /* Ghi vào TX_DATA (offset 0x00) */
    __asm__ volatile (
        "lui  t0, 0x50000\n"
        "sw   %0, 0(t0)\n"
        "fence w, w\n"
        :: "r" (ch)
        : "t0", "memory"
    );
}

/* --------------------------------------------------------------------------
 * RX: Đọc 1 byte (Blocking Poll)
 * Chờ đến khi RX_FIFO_EMPTY (Bit 2) = 0 thì mới đọc
 * -------------------------------------------------------------------------- */
static inline char uart_getc(void)
{
    uint32_t status, data;
    do {
        /* Đọc thanh ghi STATUS (offset 0x08) */
        __asm__ volatile (
            "lui  t0, 0x50000\n"
            "lw   %0, 8(t0)\n"
            : "=r" (status)
            : : "t0", "memory"
        );
    } while (status & UART_ST_RX_EMPTY); /* Loop nếu FIFO rỗng */

    /* Đọc RX_DATA (offset 0x04) */
    __asm__ volatile (
        "lui  t0, 0x50000\n"
        "lw   %0, 4(t0)\n"
        : "=r" (data)
        : : "t0", "memory"
    );

    return (char)(data & 0xFF);
}

/* --------------------------------------------------------------------------
 * Các hàm tiện ích
 * -------------------------------------------------------------------------- */
static inline void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
}

static inline void uart_puthex8(uint8_t v)
{
    const char *hex = "0123456789ABCDEF";
    uart_putc(hex[(v >> 4) & 0xF]);
    uart_putc(hex[v & 0xF]);
}

static inline void uart_puthex32(uint32_t v)
{
    uart_puthex8((uint8_t)(v >> 24));
    uart_puthex8((uint8_t)(v >> 16));
    uart_puthex8((uint8_t)(v >>  8));
    uart_puthex8((uint8_t)(v      ));
}

#endif /* _UART_H_ */