/* test_dma_uart.c — CPU Compute → DMEM → DMA mem-to-mem → DMEM → UART
 *
 * Flow:
 *   1. CPU tính toán message "HELLO DMA-SOC!\r\n" bằng phép tính ASCII
 *      → ghi vào src_buf trong DMEM
 *   2. fence rw,rw: drain store buffer trước khi DMA đọc
 *   3. DMA CH0 (mode=00 mem-to-mem): src_buf → dst_buf
 *      [NOTE] periph mode (01/10) không dùng được vì dma_periph_req=4'b0
 *             trong soc_top.v — DMA sẽ kẹt S_P_WAIT mãi nếu dùng mode đó.
 *   4. fence r,r: invalidate sau khi DMA ghi xong
 *   5. CPU đọc từ dst_buf → gửi từng byte qua UART
 *
 * Build:
 *   ./compile_c_to_hex.sh -i tests/test_dma_uart.c -o tests/test_dma_uart.hex -O 1 -c
 */
#include <stdint.h>
#include "uart.h"
#include "dma.h"
#include "dmem_layout.h"

/*
 * Vùng DMEM tự do: CT_MULTI_BASE (0x100002A0) + 144B = 0x10000330.
 * Đặt hai buffer 16-byte tại đây, đều trước guard zone (0x10000800).
 */
#define SRC_BUF_BASE  0x10000330UL   /* CPU-computed message: 16 bytes */
#define DST_BUF_BASE  0x10000340UL   /* DMA output buffer  : 16 bytes */
#define MSG_LEN       16u            /* bội số 4 → word-aligned cho DMA */

static int run_dma_uart_test(void)
{
    volatile uint8_t *src = (volatile uint8_t *)SRC_BUF_BASE;
    volatile uint8_t *dst = (volatile uint8_t *)DST_BUF_BASE;
    uint32_t st;
    int i;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);
    uart_puts("[INFO] CPU compute -> DMEM -> DMA -> UART\r\n");

    /* 1. CPU compute: xây dựng "HELLO DMA-SOC!\r\n" qua phép tính ASCII
     *    Dùng arithmetic thay vì string literal để thể hiện CPU đang tính toán.
     */
    {
        uint8_t A = (uint8_t)'A';
        src[0]  = A + 7u;   /* 'H' = 72 */
        src[1]  = A + 4u;   /* 'E' = 69 */
        src[2]  = A + 11u;  /* 'L' = 76 */
        src[3]  = A + 11u;  /* 'L' = 76 */
        src[4]  = A + 14u;  /* 'O' = 79 */
        src[5]  = (uint8_t)' ';
        src[6]  = A + 3u;   /* 'D' = 68 */
        src[7]  = A + 12u;  /* 'M' = 77 */
        src[8]  = A + 0u;   /* 'A' = 65 */
        src[9]  = (uint8_t)'-';
        src[10] = A + 18u;  /* 'S' = 83 */
        src[11] = A + 14u;  /* 'O' = 79 */
        src[12] = A + 2u;   /* 'C' = 67 */
        src[13] = (uint8_t)'!';
        src[14] = (uint8_t)'\r';
        src[15] = (uint8_t)'\n';
    }

    /* 2. Fence: CPU store buffer phải flush xuống DMEM trước khi DMA đọc */
    __asm__ volatile ("fence rw,rw" ::: "memory");

    /* 3. DMA CH0: mem-to-mem copy src_buf → dst_buf */
    dma_clear_all_status();
    dma_ch0_setup((uint32_t)SRC_BUF_BASE, (uint32_t)DST_BUF_BASE, MSG_LEN);
    dma_ch0_start();

    st = dma_wait(0u);
    if (st & DMA_ST_ERROR(0u)) {
        uart_puts("[FAIL] DMA error st=0x");
        uart_puthex32(st);
        uart_puts("\r\n");
        DMEM->RETCODE = (uint32_t)(-1);
        return -1;
    }

    /* 4. Fence: DMA write phải visible trước khi CPU đọc */
    __asm__ volatile ("fence r,r" ::: "memory");

    /* 5. CPU đọc từ dst_buf (DMA output) và gửi qua UART */
    uart_puts("[MSG] ");
    for (i = 0; i < (int)MSG_LEN; i++) {
        uint8_t c = dst[i];
        if (c == 0u) break;
        uart_putc((char)c);
    }

    uart_puts("[PASS] dma_uart\r\n");
    DMEM->RETCODE = 0u;
    return 0;
}

#ifndef INTEGRATION_BUILD
int main(void)
{
    int r = run_dma_uart_test();
    if (r != 0) {
        DMEM->RETCODE = (uint32_t)(-1);
    }
    while (1) __asm__ volatile ("nop");
    return 0;
}
#endif
