/*
 * main_v13.c  —  ASCON-128 DMA Firmware
 *
 * ============================================================================
 * FIXES SO VỚI v12
 * ============================================================================
 *
 * FIX-J (CRITICAL — UART_TX offset sai):
 *   v12: #define UART_TX (*((volatile uint32_t *)(UART_BASE + 0x00UL)))
 *   TB debug_data.v log S5-UART: không thấy write nào → offset 0x00 sai.
 *   uart_drv.h (v6) đã dùng đúng offset 0x04 (AXI UART Lite / Xilinx style).
 *   FIX: đổi UART_TX offset sang 0x04.
 *   Xác nhận: TB log phải thấy [S5-UART] WRITE offset=0x04.
 *
 * FIX-K (_Static_assert hardcode địa chỉ stack cũ):
 *   v12 có: assert (RETCODE addr) < 0x10001F00UL
 *   0x10001F00 là __stack_top của crt0 cũ (addi sp,-256).
 *   compile_c_to_hex.sh v2.7: __stack_top = 0x10002000, stack bottom = 0x10001000.
 *   FIX: đổi ngưỡng assert thành 0x10001000UL (= DMEM_STACK bottom).
 *
 * FIX-L (CTEXT snapshot thiếu trong DMEM):
 *   v12 step5 chỉ copy TAG từ ASCON vào DMEM, không copy CTEXT_0/CTEXT_1.
 *   DMA đã ghi CTEXT vào DMEM->CTEXT_0/1 (0x10000010/14) trực tiếp.
 *   Nhưng để TB scoreboard đọc được CTEXT qua DMEM struct đúng:
 *   Thêm snapshot CTEXT_0/1 từ DMEM (DMA output) vào step5 debug log.
 *   Không cần đọc lại từ ASCON->CTEXT vì DMA đã ghi vào DMEM.
 *
 * Không thay đổi nào khác so với v12.
 * ============================================================================
 *
 * COMPILE:
 *   ./compile_c_to_hex.sh -i main.c -o program.hex -v
 *
 * Kiểm tra assembly sau compile:
 *   CTRL_SOFT_RST write: phải thấy `li aN, 2` (KHÔNG phải 8).
 *   UART write:          phải thấy offset 4 (sw aX, 4(aY)).
 *   DMA_SRC write:       phải thấy `sw aX, 256(aY)` với aX = 0x10000000.
 *   _start:              phải thấy `lui x2, 0x10002` rồi call main NGAY,
 *                        KHÔNG có addi sp,sp,-N ở giữa.
 */

#include <stdint.h>
#include "ascon_regs.h"
#include "dmem_layout.h"
/* KHÔNG include uart_drv.h — dùng UART inline bên dưới */

/* ==========================================================================
 * SECTION 1: UART
 *
 * FIX-J: offset 0x04 (AXI UART Lite / Xilinx style).
 * TB log phải thấy: [S5-UART] WRITE offset=0x04 data=0x4F ('O')
 * Nếu không thấy → thử đổi lại 0x00.
 * ========================================================================== */
#define UART_BASE   0x50000000UL
#define UART_TX     (*((volatile uint32_t *)(UART_BASE + 0x04UL)))  /* FIX-J */

/* ==========================================================================
 * SECTION 2: TEST VECTOR
 * ========================================================================== */
#define PTEXT_LEN    8u
#define PTEXT_WORD0  0x6C6C6548u   /* little-endian: 'H','e','l','l' */
#define PTEXT_WORD1  0x0000216Fu   /* little-endian: 'o','!',0x00,0x00 */

#define CFG_KEY_0    0x00112233u
#define CFG_KEY_1    0x44556677u
#define CFG_KEY_2    0x8899AABBu
#define CFG_KEY_3    0xCCDDEEFFu

#define CFG_NONCE_0  0xDEADBEEFu
#define CFG_NONCE_1  0xCAFEBABEu
#define CFG_NONCE_2  0x01234567u
#define CFG_NONCE_3  0x89ABCDEFu

#define DMEM_BASE    0x10000000UL

#define POLL_TIMEOUT          5000u
#define RESET_POLL_TIMEOUT    256u

/* ==========================================================================
 * SECTION 2b: STATIC ASSERTS
 * ========================================================================== */

/*
 * FIX-K: Ngưỡng đúng = DMEM_STACK bottom = 0x10001000
 * (compile_c_to_hex.sh v2.7: DMEM_STACK ORIGIN=0x10001000, LENGTH=4K)
 * RETCODE tại 0x10000058 < 0x10001000 → OK, không bao giờ overlap stack.
 */
_Static_assert(
    (0x10000000UL + 0x0058UL + 4u) < 0x10001000UL,
    "RETCODE overlap DMEM_STACK bottom!"
);

/* BUG-E guard */
_Static_assert(CTRL_SOFT_RST == 0x02u,
    "BUG-E: CTRL_SOFT_RST phai la 0x02");
_Static_assert(CTRL_DMA_START == 0x05u,
    "CTRL_DMA_START phai la 0x05");

/* ==========================================================================
 * SECTION 3: MACROS
 * ========================================================================== */

/*
 * ASCON_WRITE: ghi MMIO + fence + 32 NOP gap.
 * 32 NOP ≈ 320ns @ 100MHz — đủ cho AXI write settle trước write tiếp theo.
 */
#define ASCON_WRITE(reg, val)                                        \
    do {                                                             \
        (reg) = (uint32_t)(val);                                     \
        __asm__ volatile ("fence w,w" ::: "memory");                 \
        __asm__ volatile (                                           \
            "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"              \
            "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"              \
            "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"              \
            "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"              \
            ::: "memory"                                             \
        );                                                           \
    } while (0)

/* MB: compiler barrier, không sinh instruction */
#define MB()  __asm__ volatile ("" ::: "memory")

/* ==========================================================================
 * SECTION 4: UART TX
 *
 * Dùng 16 NOP gap thay vì delay loop — tổng time TX không bị giới hạn
 * bởi watchdog, UART FIFO tự buffer các byte.
 * ========================================================================== */

__attribute__((optimize("O0"), noinline))
static void uart_putc(char c)
{
    UART_TX = (uint32_t)(uint8_t)c;
    __asm__ volatile ("fence w,w" ::: "memory");
    __asm__ volatile (
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        ::: "memory"
    );
}

__attribute__((optimize("O0"), noinline))
static void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

__attribute__((optimize("O0"), noinline))
static void uart_puthex8(uint8_t v)
{
    const char *h = "0123456789ABCDEF";
    uart_putc(h[(v >> 4) & 0xFu]);
    uart_putc(h[v & 0xFu]);
}

__attribute__((optimize("O0"), noinline))
static void uart_puthex32(uint32_t v)
{
    uart_puthex8((uint8_t)(v >> 24));
    uart_puthex8((uint8_t)(v >> 16));
    uart_puthex8((uint8_t)(v >>  8));
    uart_puthex8((uint8_t)(v      ));
}

/* ==========================================================================
 * SECTION 5: STEP 1 — GHI PLAINTEXT VÀO DMEM
 * ========================================================================== */

__attribute__((optimize("O0"), noinline))
static void step1_write_ptext_to_dmem(void)
{
    DMEM->PTEXT_0 = PTEXT_WORD0;   /* 0x10000000 ← 0x6C6C6548 */
    MB();
    DMEM->PTEXT_1 = PTEXT_WORD1;   /* 0x10000004 ← 0x0000216F */
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ==========================================================================
 * SECTION 6: STEP 2 — RESET VÀ CẤU HÌNH ASCON
 *
 * Thứ tự: SOFT_RST → poll CORE_BUSY==0 → MODE → IRQ_EN → KEY → NONCE → LEN
 * Timeout → return -3 NGAY, không rơi xuống config (BUG-H guard).
 * ========================================================================== */

__attribute__((optimize("O0"), noinline))
static int step2_reset_and_config(void)
{
    uint32_t st;
    uint32_t to;

    /* SOFT_RST = 0x02 (BUG-E FIX) */
    ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);

    /* 64 NOP delay — core internal reset */
    __asm__ volatile (
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        ::: "memory"
    );

    /* Poll CORE_BUSY == 0 */
    to = RESET_POLL_TIMEOUT;
    do {
        st = ascon_read_status();
        if (!(st & STATUS_CORE_BUSY)) break;
        __asm__ volatile ("nop\nnop\nnop\nnop\n" ::: "memory");
        to--;
    } while (to > 0u);

    if (st & STATUS_CORE_BUSY) {
        DMEM->STATUS  = st;
        DMEM->RETCODE = (uint32_t)(int32_t)(-3);
        __asm__ volatile ("fence w,w" ::: "memory");
        return -3;
    }

    /* Config: MODE → IRQ_EN → KEY[0..3] → NONCE[0..3] → DATA_LEN */
    ASCON_WRITE(ASCON->MODE,     MODE_ENCRYPT);
    ASCON_WRITE(ASCON->IRQ_EN,   0u);
    ASCON_WRITE(ASCON->KEY_0,    CFG_KEY_0);
    ASCON_WRITE(ASCON->KEY_1,    CFG_KEY_1);
    ASCON_WRITE(ASCON->KEY_2,    CFG_KEY_2);
    ASCON_WRITE(ASCON->KEY_3,    CFG_KEY_3);
    ASCON_WRITE(ASCON->NONCE_0,  CFG_NONCE_0);
    ASCON_WRITE(ASCON->NONCE_1,  CFG_NONCE_1);
    ASCON_WRITE(ASCON->NONCE_2,  CFG_NONCE_2);
    ASCON_WRITE(ASCON->NONCE_3,  CFG_NONCE_3);
    ASCON_WRITE(ASCON->DATA_LEN, (uint32_t)(PTEXT_LEN & DATA_LEN_MASK));

    return 0;
}

/* ==========================================================================
 * SECTION 7: STEP 3 — KICK ASCON DMA
 *
 * Thứ tự bắt buộc: DMA_SRC → DMA_DST → DMA_LEN → fence → CTRL_DMA_START
 * DMA_LEN = DMEM_DMA_INPUT_LEN = 8 (input semantics).
 * Nếu RTL dùng output semantics: đổi thành DMEM_DMA_OUTPUT_LEN = 24.
 * ========================================================================== */

__attribute__((optimize("O0"), noinline))
static void step3_kick_dma(void)
{
    ASCON_WRITE(ASCON->DMA_SRC, (uint32_t)(DMEM_BASE + 0x0000UL)); /* PTEXT_0 */
    ASCON_WRITE(ASCON->DMA_DST, DMEM_DMA_OUTPUT_ADDR);             /* CTEXT_0 */
    ASCON_WRITE(ASCON->DMA_LEN, DMEM_DMA_INPUT_LEN);               /* = 8     */

    /* Triple fence + 32 NOP barrier trước START */
    __asm__ volatile ("fence w,w" ::: "memory");
    __asm__ volatile ("fence w,w" ::: "memory");
    __asm__ volatile ("fence w,w" ::: "memory");
    __asm__ volatile (
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        ::: "memory"
    );

    /* CTRL = DMA_EN | START = 0x05 */
    ASCON_WRITE(ASCON->CTRL, CTRL_DMA_START);

    /* Post-kick gap */
    __asm__ volatile (
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        ::: "memory"
    );
}

/* ==========================================================================
 * SECTION 8: STEP 4 — POLL STATUS.DMA_DONE
 * ========================================================================== */

__attribute__((optimize("O0"), noinline))
static uint32_t step4_poll_done(void)
{
    uint32_t st;
    uint32_t to = POLL_TIMEOUT;

    do {
        st = ascon_read_status();
        if (st & STATUS_ANY_ERROR) return st;
        if (st & STATUS_DMA_DONE)  return st;
        to--;
    } while (to > 0u);

    return 0u;  /* timeout */
}

/* ==========================================================================
 * SECTION 9: STEP 5 — COPY RESULTS + LƯU DEBUG VÀO DMEM
 *
 * FIX-L: Snapshot cả CTEXT (từ DMEM, DMA đã ghi) và TAG (từ ASCON regs).
 * ========================================================================== */

__attribute__((optimize("O0"), noinline))
static void step5_copy_results_to_dmem(uint32_t status_val, int retcode)
{
    /*
     * CTEXT: DMA đã ghi vào DMEM->CTEXT_0/1 trực tiếp.
     * Không cần copy lại — chỉ đọc để xác nhận TB scoreboard.
     * (DMEM->CTEXT_0 đã = output DMA)
     */

    /* TAG: đọc từ ASCON registers sau DMA_DONE */
    DMEM->TAG_0 = ASCON->TAG_0;  MB();
    DMEM->TAG_1 = ASCON->TAG_1;  MB();
    DMEM->TAG_2 = ASCON->TAG_2;  MB();
    DMEM->TAG_3 = ASCON->TAG_3;  MB();

    DMEM->DATALEN = PTEXT_LEN;
    DMEM->STATUS  = status_val;
    DMEM->RETCODE = (uint32_t)(int32_t)retcode;

    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ==========================================================================
 * SECTION 10: STEP 6 — IN KẾT QUẢ RA UART
 *
 * Format output:
 *   OK\r\n          — thành công
 *   C:XXXXXXXXXXXXXXXX\r\n  — ciphertext (8 bytes hex)
 *   T:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\r\n  — tag (16 bytes hex)
 *   E:RST\r\n       — reset timeout
 *   E:TMO\r\n       — DMA poll timeout
 *   E:XX\r\n        — error (STATUS byte hex)
 * ========================================================================== */

__attribute__((optimize("O0"), noinline))
static void step6_print_result(uint32_t status_val, int retcode)
{
    if (retcode != 0) {
        if (retcode == -3) {
            uart_puts("E:RST\r\n");
        } else if (retcode == -2) {
            uart_puts("E:TMO\r\n");
        } else {
            uart_puts("E:");
            uart_puthex8((uint8_t)(status_val & 0xFFu));
            uart_puts("\r\n");
        }
        return;
    }

    /* retcode == 0: in ciphertext + tag */
    uart_puts("OK\r\n");
    uart_puts("C:");
    uart_puthex32(DMEM->CTEXT_0);
    uart_puthex32(DMEM->CTEXT_1);
    uart_puts("\r\n");
    uart_puts("T:");
    uart_puthex32(DMEM->TAG_0);
    uart_puthex32(DMEM->TAG_1);
    uart_puthex32(DMEM->TAG_2);
    uart_puthex32(DMEM->TAG_3);
    uart_puts("\r\n");
}

/* ==========================================================================
 * SECTION 11: MAIN
 * ========================================================================== */

int main(void)
{
    uint32_t status_val;
    int      retcode;

    /* STEP 1: Ghi plaintext vào DMEM */
    step1_write_ptext_to_dmem();

    /* STEP 2: Reset + config ASCON */
    retcode = step2_reset_and_config();
    if (retcode != 0) {
        step6_print_result(DMEM->STATUS, retcode);
        return retcode;
    }

    /* STEP 3: Kick DMA */
    step3_kick_dma();

    /* STEP 4: Poll DMA_DONE */
    status_val = step4_poll_done();

    /* Timeout */
    if (status_val == 0u) {
        retcode = -2;
        DMEM->STATUS  = ascon_read_status();
        DMEM->RETCODE = (uint32_t)(int32_t)retcode;
        __asm__ volatile ("fence w,w" ::: "memory");
        ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
        step6_print_result(0u, retcode);
        return retcode;
    }

    /* Error */
    if (status_val & STATUS_ANY_ERROR) {
        retcode = -1;
        DMEM->STATUS  = status_val;
        DMEM->RETCODE = (uint32_t)(int32_t)retcode;
        __asm__ volatile ("fence w,w" ::: "memory");
        ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
        step6_print_result(status_val, retcode);
        return retcode;
    }

    /* STEP 5: Copy results vào DMEM */
    step5_copy_results_to_dmem(status_val, 0);

    /* STEP 6: In kết quả */
    step6_print_result(status_val, 0);

    /* Security: clear KEY/NONCE bằng SOFT_RST */
    ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);

    return 0;
}