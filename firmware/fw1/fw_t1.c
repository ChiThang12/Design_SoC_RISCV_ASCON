/*
 * fw_t1.c — Tầng 1: Crossbar Route + DMA_LEN Verification
 *
 * Mục tiêu:
 *   - Xác nhận crossbar route đúng S2 (ASCON_BASE = 0x20000000)
 *   - Xác nhận ASCON slave nhận write không có DECERR
 *   - Xác nhận DMA_LEN register được latch đúng giá trị 24
 *
 * KHÔNG kick DMA hay CORE — chỉ verify register write path.
 *
 * KHÔNG include dmem_layout.h / ascon_stream.h:
 *   Linker thực tế (linker_minimal.ld):
 *     DMEM_DATA = 2KB (0x10000000..0x100007FF)
 *     __stack_top = 0x10002000
 *   dmem_layout.h có DMEM_BASE=0x100001C0 và g_stream (436B) → .bss vượt
 *   quá 2KB limit → linker ASSERT fail hoặc crt0 corrupt.
 *   T1 chỉ cần ascon_regs.h + uart_drv.h.
 *
 * DMA addresses (hardcode):
 *   DMA_SRC = 0x10000100  (trong DMEM_DATA, align 16)
 *   DMA_DST = 0x10000110
 *   DMA_LEN = 24          (OUTPUT: 8B ctext + 16B tag)
 *
 * Compile:
 *   ./compile_c_to_hex.sh -i fw_t1.c -o t1.hex -O 0
 */

#include <stdint.h>
#include "ascon_regs.h"
#include "uart_drv.h"

/*
 * DMA constants — hardcode, không phụ thuộc dmem_layout.h.
 *
 * DMA_LEN phải là OUTPUT length (24), KHÔNG phải INPUT length (4).
 * RTL ascon_dma FSM dùng reg_dma_len để copy
 *   (ctext 8B + tag 16B) = 24B về DMEM[DMA_DST].
 */
#define T1_DMA_SRC_ADDR   0x10000100UL   /* DMEM plaintext buffer  */
#define T1_DMA_DST_ADDR   0x10000110UL   /* DMEM ctext+tag output  */
#define T1_DMA_OUTPUT_LEN 24u            /* 8B ctext + 16B tag     */

/* ─────────────────────────────────────────────────────────────────────────────
 * trap_handler — BẮT BUỘC, linker error nếu thiếu.
 * T1 không dùng IRQ → stub.
 * ─────────────────────────────────────────────────────────────────────────────
 */
__attribute__((interrupt("machine"), aligned(4)))
void trap_handler(void)
{
    for (;;) {}
}

/* ─────────────────────────────────────────────────────────────────────────────
 * main
 * ─────────────────────────────────────────────────────────────────────────────
 */
int main(void)
{
    /* [1] UART ─────────────────────────────────────────────────────────── */
    uart_init();
    uart_puts_fast("T1:START\r\n");

    /* [2] SOFT_RST — clear sticky status, reg_dma_en trước mọi thứ ─────── */
    ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
    __asm__ volatile ("fence" ::: "memory");

    /* [3] IRQ_EN = 0 — disable IRQ trong lúc config ──────────────────────  */
    ASCON_WRITE(ASCON->IRQ_EN, 0u);
    __asm__ volatile ("fence" ::: "memory");

    /* [4] MODE ─────────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON->MODE, MODE_ENCRYPT);
    __asm__ volatile ("fence" ::: "memory");

    /* [5] KEY_0..3 ─────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON->KEY_0, 0x00112233u);
    ASCON_WRITE(ASCON->KEY_1, 0x44556677u);
    ASCON_WRITE(ASCON->KEY_2, 0x8899AABBu);
    ASCON_WRITE(ASCON->KEY_3, 0xCCDDEEFFu);
    __asm__ volatile ("fence" ::: "memory");

    /* [6] NONCE_0..3 ───────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON->NONCE_0, 0xDEADBEEFu);
    ASCON_WRITE(ASCON->NONCE_1, 0xCAFEBABEu);
    ASCON_WRITE(ASCON->NONCE_2, 0x01234567u);
    ASCON_WRITE(ASCON->NONCE_3, 0x89ABCDEFu);
    __asm__ volatile ("fence" ::: "memory");

    /* [7] PTEXT_0 = "Hell" ─────────────────────────────────────────────── */
    ASCON_WRITE(ASCON->PTEXT_0, 0x48656C6Cu);
    __asm__ volatile ("fence" ::: "memory");

    /* [8] DATA_LEN = 4 (INPUT byte count của plaintext block) ─────────── */
    ASCON_WRITE(ASCON->DATA_LEN, (uint32_t)(4u & DATA_LEN_MASK));
    __asm__ volatile ("fence" ::: "memory");

    /* [9] DMA_SRC ──────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON->DMA_SRC, (uint32_t)T1_DMA_SRC_ADDR);
    __asm__ volatile ("fence" ::: "memory");

    /* [10] DMA_DST ─────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON->DMA_DST, (uint32_t)T1_DMA_DST_ADDR);
    __asm__ volatile ("fence" ::: "memory");

    /* [11] DMA_LEN = 24 (OUTPUT length — điểm mấu chốt FIX-1) ─────────── */
    ASCON_WRITE(ASCON->DMA_LEN, (uint32_t)T1_DMA_OUTPUT_LEN);
    __asm__ volatile ("fence" ::: "memory");

    uart_puts_fast("T1:REGS_WRITTEN\r\n");

    /* [12] Fence cuối ──────────────────────────────────────────────────── */
    __asm__ volatile ("fence" ::: "memory");

    /* [13] Đọc STATUS, check error bits [5:4] = STATUS_ANY_ERROR = 0x30 ── */
    uint32_t st = ascon_read_status();

    uart_puts_fast("T1:ST=");
    uart_puthex32_fast(st);
    uart_puts_fast("\r\n");

    if (st & STATUS_ANY_ERROR) {
        uart_puts_fast("T1:FAIL:ERR\r\n");
        for (;;) {}
        return 1;
    }

    /* [14] PASS ────────────────────────────────────────────────────────── */
    uart_puts_fast("T1:OK\r\n");

    /* [15] Loop ────────────────────────────────────────────────────────── */
    for (;;) {}

    return 0;
}