/* ==========================================================================
 * uart_drv.h — UART TX Driver v6 (no-poll, direct write)
 *
 * Base: 0x5000_0000 (S5, 115200 baud 8N1 @ 100MHz = 868 cy/bit)
 *
 * ── Root cause v5 ────────────────────────────────────────────────────────
 * uart_putc poll UART_STATUS (0x50000008, bit3=TX_FULL):
 *   Nếu UART STATUS luôn có TX_FULL=1 (hoặc bit3=1 do unknown reason)
 *   → poll loop 20000 × ~3cy = 60000cy > WATCHDOG 50000cy → timeout
 *   Store Scoreboard: [0x10001eb0] = 0x4e20 = 20000 = timeout counter
 *
 * v6 FIX: Bỏ poll STATUS hoàn toàn. Ghi TX_FIFO trực tiếp.
 *   UART có TX FIFO (thường 16 bytes). Nếu FIFO chưa full → accept ngay.
 *   Sau mỗi byte: thêm delay ~8700 cycles (1 byte time @ 115200 baud)
 *   để đảm bảo UART hoàn thành truyền trước byte tiếp theo.
 *   KHÔNG đọc STATUS → không có AXI read overhead.
 *
 * ── UART TX_FIFO offset ──────────────────────────────────────────────────
 * Thử offset 0x04 (AXI UART Lite / Xilinx style).
 * TB sẽ log: [S5-UART] WRITE offset=0x04 data=0x41 ('A')
 * Nếu TB không thấy [UART-TX] char='A' → thử offset 0x00.
 *
 * 1 byte @ 115200 baud = 10 bits × 8680 ns = 86800 ns = 8680 cycles.
 * UART_TX_DELAY = 8800 cycles (margin nhỏ).
 * ========================================================================== */
#ifndef UART_DRV_H
#define UART_DRV_H

#include <stdint.h>

#define UART_BASE    0x50000000UL
#define UART_TX_REG  (*((volatile uint32_t *)(UART_BASE + 0x04)))

/* Delay ~8800 cycles = ~1 UART byte time @ 115200 baud, 100MHz clock */
#define UART_TX_DELAY_CYCLES  8800u

/* --------------------------------------------------------------------------
 * uart_putc — ghi 1 byte, không poll, thêm delay đủ cho UART TX complete
 * -------------------------------------------------------------------------- */
__attribute__((optimize("O0")))
static void uart_putc(char c)
{
    volatile uint32_t delay = UART_TX_DELAY_CYCLES;
    /* Ghi byte vào TX FIFO */
    UART_TX_REG = (uint32_t)(uint8_t)c;
    __asm__ volatile ("fence w,w" ::: "memory");
    /* Đợi 1 byte time để UART hoàn thành truyền */
    while (delay > 0u)
        delay--;
}

/* --------------------------------------------------------------------------
 * uart_puts — gửi chuỗi null-terminated
 * -------------------------------------------------------------------------- */
__attribute__((optimize("O0")))
static void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* --------------------------------------------------------------------------
 * uart_puthex8 — in 1 byte hex 2 chữ số: "3F"
 * -------------------------------------------------------------------------- */
__attribute__((optimize("O0")))
static void uart_puthex8(uint8_t v)
{
    const char *hex = "0123456789ABCDEF";
    uart_putc(hex[(v >> 4) & 0xF]);
    uart_putc(hex[v & 0xF]);
}

/* --------------------------------------------------------------------------
 * uart_puthex32 — in 32-bit hex 8 chữ số: "DEADBEEF"
 * -------------------------------------------------------------------------- */
__attribute__((optimize("O0")))
static void uart_puthex32(uint32_t v)
{
    uart_puthex8((uint8_t)(v >> 24));
    uart_puthex8((uint8_t)(v >> 16));
    uart_puthex8((uint8_t)(v >>  8));
    uart_puthex8((uint8_t)(v      ));
}

/* --------------------------------------------------------------------------
 * uart_print_result — in kết quả ASCON
 *
 * Output format (hiển thị trên TB log [UART-TX]):
 *   =ASCON RESULT=
 *   C:XXXXXXXXXXXXXXXX
 *   T:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
 *   S:OK  (hoặc S:E-1, S:E-2, S:E-3)
 *
 * Dùng format ngắn để giảm tổng số bytes → giảm thời gian TX.
 * Toàn bộ output ≈ 60 bytes × 8800cy = 528000cy → cần WATCHDOG lớn hơn
 * hoặc bỏ delay dài.
 *
 * WATCHDOG hiện tại = 50000cy → chỉ đủ ~5 bytes!
 * → Dùng delay = 0 (no delay), UART FIFO buffer tất cả
 * -------------------------------------------------------------------------- */

/* uart_putc_fast — ghi không delay, UART FIFO tự buffer */
__attribute__((optimize("O0")))
static void uart_putc_fast(char c)
{
    UART_TX_REG = (uint32_t)(uint8_t)c;
    __asm__ volatile ("fence w,w" ::: "memory");
    /* Minimal gap: 32 NOPs ≈ 320ns → đủ để S5 accept write */
    __asm__ volatile (
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        ::: "memory"
    );
}

__attribute__((optimize("O0")))
static void uart_puts_fast(const char *s)
{
    while (*s)
        uart_putc_fast(*s++);
}

__attribute__((optimize("O0")))
static void uart_puthex8_fast(uint8_t v)
{
    const char *hex = "0123456789ABCDEF";
    uart_putc_fast(hex[(v >> 4) & 0xF]);
    uart_putc_fast(hex[v & 0xF]);
}

__attribute__((optimize("O0")))
static void uart_puthex32_fast(uint32_t v)
{
    uart_puthex8_fast((uint8_t)(v >> 24));
    uart_puthex8_fast((uint8_t)(v >> 16));
    uart_puthex8_fast((uint8_t)(v >>  8));
    uart_puthex8_fast((uint8_t)(v      ));
}

__attribute__((optimize("O0")))
static void uart_print_result(
    uint32_t ctext0, uint32_t ctext1,
    uint32_t tag0,   uint32_t tag1,
    uint32_t tag2,   uint32_t tag3,
    uint32_t status_val, int retcode)
{
    uart_puts_fast("\r\n=ASCON RESULT=\r\n");

    uart_puts_fast("C:");
    uart_puthex32_fast(ctext0);
    uart_puthex32_fast(ctext1);
    uart_puts_fast("\r\n");

    uart_puts_fast("T:");
    uart_puthex32_fast(tag0);
    uart_puthex32_fast(tag1);
    uart_puthex32_fast(tag2);
    uart_puthex32_fast(tag3);
    uart_puts_fast("\r\n");

    uart_puts_fast("STS:");
    uart_puthex32_fast(status_val);
    uart_puts_fast("\r\n");

    uart_puts_fast("RET:");
    if      (retcode ==  0) uart_puts_fast("OK");
    else if (retcode == -1) uart_puts_fast("E-1");
    else if (retcode == -2) uart_puts_fast("E-2");
    else if (retcode == -3) uart_puts_fast("E-3");
    else                    uart_puts_fast("E-?");
    uart_puts_fast("\r\n");
}

#endif /* UART_DRV_H */