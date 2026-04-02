/*
 * main_stream.c — Interrupt-driven ASCON-128 Streaming Firmware
 *
 * Flow:
 *   1. CPU init PLIC + enable M-mode IRQ
 *   2. CPU ghi block 0 → kick DMA → làm việc khác
 *   3. ASCON xong → IRQ → ascon_isr():
 *        - lấy kết quả block N
 *        - nếu còn block N+1: kick tiếp
 *        - nếu hết: g_stream.done = 1
 *   4. CPU poll g_stream.done (hoặc WFI) rồi in kết quả
 *
 * Upgrade path:
 *   Khi có SoC DMA: thay ascon_feed_block_cpu() bằng hàm SoC DMA,
 *   phần còn lại (ISR, PLIC, ASCON config) giữ nguyên.
 *
 * Compile:
 *   ./compile_c_to_hex.sh -i main_stream.c -o program.hex -O 0
 */

#include <stdint.h>
#include "ascon_regs.h"
#include "dmem_layout.h"
#include "plic_drv.h"
#include "ascon_stream.h"

/* ============================================================
 * SECTION 1: UART (inline, no poll)
 * ============================================================ */
#define UART_BASE   0x50000000UL
#define UART_TX     (*((volatile uint32_t *)(UART_BASE + 0x00UL)))

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
static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

__attribute__((optimize("O0"), noinline))
static void uart_init(void)
{
    /* Set baud rate for 115200 @ 100MHz = 867 */
    *((volatile uint32_t *)(UART_BASE + 0x10)) = 867u;
    __asm__ volatile ("fence w,w" ::: "memory");
    
    /* Enable TX (bit 0 = tx_irq_en) */
    *((volatile uint32_t *)(UART_BASE + 0x0C)) = 0x1;
    __asm__ volatile ("fence w,w" ::: "memory");
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

/* ============================================================
 * SECTION 2: TEST DATA
 *
 * 4 blocks × 8 bytes = 32 bytes plaintext.
 * Layout: ptext[block*8 .. block*8+7]
 * Dùng chung key/nonce cho tất cả blocks (demo).
 * Production: nên increment nonce mỗi block.
 * ============================================================ */
#define N_BLOCKS  4u

static const uint8_t g_plaintext[N_BLOCKS * ASCON_BLOCK_SIZE] = {
    /* Block 0: "Hello!  " */
    0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0x00, 0x00,
    /* Block 1: "Block01 " */
    0x42, 0x6C, 0x6F, 0x63, 0x6B, 0x30, 0x31, 0x20,
    /* Block 2: "Block02 " */
    0x42, 0x6C, 0x6F, 0x63, 0x6B, 0x30, 0x32, 0x20,
    /* Block 3: "Block03 " */
    0x42, 0x6C, 0x6F, 0x63, 0x6B, 0x30, 0x33, 0x20,
};

static const uint32_t g_key[4] = {
    0x00112233u, 0x44556677u, 0x8899AABBu, 0xCCDDEEFFu
};

static const uint32_t g_nonce[4] = {
    0xDEADBEEFu, 0xCAFEBABEu, 0x01234567u, 0x89ABCDEFu
};

/* ============================================================
 * SECTION 3: STREAM CONTEXT (global singleton)
 * ============================================================ */
AsconStream_t g_stream;

/* ============================================================
 * SECTION 4: ISR IMPLEMENTATION
 *
 * Được gọi từ trap_handler() khi PLIC source 8 (ASCON) pending.
 *
 * CRITICAL ordering:
 *   a) PLIC claim TRƯỚC khi đọc ASCON registers
 *      → nếu claim sau, PLIC có thể re-assert trước khi ta complete
 *   b) PLIC complete SAU khi xử lý xong
 *      → complete trước làm PLIC accept IRQ mới trong khi ta chưa xong
 *   c) SOFT_RST để clear key/nonce trong ASCON registers (security)
 *   d) Nếu còn block tiếp: kick TRƯỚC khi return từ ISR
 *      → tối thiểu latency giữa các blocks
 * ============================================================ */
__attribute__((optimize("O0"), noinline))
void ascon_isr(void)
{
    /* a) PLIC claim — lấy source ID */
    uint32_t src = plic_claim();

    /* Spurious IRQ guard */
    if (src != PLIC_SRC_ASCON) {
        if (src != 0u) plic_complete(src);
        return;
    }

    /* Đọc STATUS */
    uint32_t st = ascon_read_status();

    /* Lỗi: ghi nhận và abort */
    if (st & STATUS_ANY_ERROR) {
        g_stream.error = st;
        ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
        plic_complete(src);
        g_stream.done = 1u;
        return;
    }

    /* Lấy kết quả block hiện tại */
    uint32_t blk = g_stream.cur_block;
    if (blk < STREAM_MAX_BLOCKS) {
        AsconBlockOut_t *out = &g_stream.out[blk];

        /*
         * ctext: DMA đã ghi vào DMEM->CTEXT_0/1.
         * Đọc từ DMEM (không phải ASCON regs) vì DMA write vào SRAM.
         */
        out->ctext[0] = DMEM->CTEXT_0;
        __asm__ volatile ("" ::: "memory");
        out->ctext[1] = DMEM->CTEXT_1;
        __asm__ volatile ("" ::: "memory");

        /*
         * tag: đọc từ ASCON registers TAG_0..3
         * (valid sau DMA_DONE, trước SOFT_RST)
         */
        out->tag[0] = ASCON->TAG_0;
        __asm__ volatile ("" ::: "memory");
        out->tag[1] = ASCON->TAG_1;
        __asm__ volatile ("" ::: "memory");
        out->tag[2] = ASCON->TAG_2;
        __asm__ volatile ("" ::: "memory");
        out->tag[3] = ASCON->TAG_3;
        __asm__ volatile ("" ::: "memory");
    }

    /* Security: clear key/nonce bằng SOFT_RST */
    ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);

    /* b) PLIC complete — báo đã xử lý xong IRQ này */
    plic_complete(src);

    /* Advance block index */
    uint32_t next = blk + 1u;
    g_stream.cur_block = next;

    if (next < g_stream.n_blocks) {
        /*
         * Còn block tiếp: feed + config + kick ngay trong ISR.
         * CPU tiếp tục làm việc khác sau khi ISR return.
         */
        ascon_feed_block_cpu(next);

        int r = ascon_config_block();
        if (r != 0) {
            g_stream.error = (uint32_t)(int32_t)r;
            g_stream.done  = 1u;
            return;
        }

        ascon_kick_dma();
        /* ISR return: CPU tiếp tục, ASCON chạy ngầm */

    } else {
        /* Tất cả blocks xong */
        g_stream.done = 1u;
    }
}

/* ============================================================
 * SECTION 5: TRAP HANDLER
 *
 * RISC-V M-mode trap entry point.
 * Đăng ký bằng cách ghi địa chỉ vào mtvec (direct mode).
 *
 * mcause bit[31]=1 → interrupt
 * mcause[3:0]=11   → machine external interrupt (MEIP)
 * ============================================================ */
__attribute__((interrupt("machine"), aligned(4)))
void trap_handler(void)
{
    uint32_t mcause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));

    /* Interrupt bit set + MEIP (cause=11) */
    if ((mcause & 0x80000000u) && ((mcause & 0xFFFFu) == 11u)) {
        ascon_isr();
    }
    /* Các exception khác: ignore hoặc xử lý tại đây */
}

/* ============================================================
 * SECTION 6: PRINT RESULTS
 * ============================================================ */
static void print_results(void)
{
    if (g_stream.error != 0u) {
        uart_puts("E:STS=");
        uart_puthex32(g_stream.error);
        uart_puts("\r\n");
        return;
    }

    uart_puts("OK n=");
    uart_puthex8((uint8_t)g_stream.n_blocks);
    uart_puts("\r\n");

    for (uint32_t i = 0u; i < g_stream.n_blocks; i++) {
        uart_puts("B");
        uart_puthex8((uint8_t)i);
        uart_puts(" C:");
        uart_puthex32(g_stream.out[i].ctext[0]);
        uart_puthex32(g_stream.out[i].ctext[1]);
        uart_puts(" T:");
        uart_puthex32(g_stream.out[i].tag[0]);
        uart_puthex32(g_stream.out[i].tag[1]);
        uart_puthex32(g_stream.out[i].tag[2]);
        uart_puthex32(g_stream.out[i].tag[3]);
        uart_puts("\r\n");
    }
}

/* ============================================================
 * SECTION 7: MAIN
 * ============================================================ */
int main(void)
{
    /* ── Init UART ─────────────────────────────────────────── */
    // uart_init();
    
    /* ── Setup trap vector ─────────────────────────────────── */
    // uart_puts("MAIN: Start\n");
    /*
     * Ghi địa chỉ trap_handler vào mtvec (direct mode, bit[1:0]=0).
     * Sử dụng assembly để load địa chỉ tuyệt đối.
     */
    __asm__ volatile (
        "la   t0, trap_handler\n"
        "csrw mtvec, t0\n"
        ::: "t0", "memory"
    );
    // uart_puts("MAIN: mtvec set\n");

    /* ── Init PLIC ─────────────────────────────────────────── */
    plic_init_ascon();
    // uart_puts("MAIN: PLIC init\n");

    /* ── Enable M-mode interrupts ──────────────────────────── */
    mie_enable_external();
    mstatus_enable_irq();
    // uart_puts("MAIN: IRQs enabled\n");

    /* ── Chuẩn bị stream context ───────────────────────────── */
    g_stream.ptext    = g_plaintext;
    g_stream.n_blocks = N_BLOCKS;
    g_stream.key[0]   = g_key[0];
    g_stream.key[1]   = g_key[1];
    g_stream.key[2]   = g_key[2];
    g_stream.key[3]   = g_key[3];
    g_stream.nonce[0] = g_nonce[0];
    g_stream.nonce[1] = g_nonce[1];
    g_stream.nonce[2] = g_nonce[2];
    g_stream.nonce[3] = g_nonce[3];
    // uart_puts("MAIN: Stream context set\n");

    /* ── Kick block 0 ──────────────────────────────────────── */
    int r = ascon_stream_start();
    if (r != 0) {
        // uart_puts("E:RST\r\n");
        return r;
    }
    // uart_puts("MAIN: Stream started\n");

    /*
     * ── CPU làm việc khác trong khi ASCON chạy ─────────────
     *
     * Đây là phần CPU "other work". Trong demo: chỉ in thông báo.
     * Production: xử lý dữ liệu, giao tiếp UART/SPI, v.v.
     *
     * KHÔNG được động vào DMEM PTEXT/CTEXT vùng đang dùng
     * cho đến khi g_stream.done = 1.
     */
    // uart_puts("CPU: working...\r\n");

    /*
     * Vòng lặp chờ: dùng WFI để CPU vào low-power khi idle.
     * ISR tự kick block tiếp, main chỉ chờ done flag.
     *
     * Thay "while (!g_stream.done)" bằng logic khác nếu muốn
     * CPU làm việc thực sự thay vì WFI.
     */
    while (!g_stream.done) {
        __asm__ volatile ("wfi");
        /*
         * Sau WFI, CPU wake do IRQ → trap_handler → ascon_isr()
         * → nếu xong: g_stream.done = 1, vòng lặp thoát.
         *    nếu còn block: kick tiếp trong ISR, WFI lại.
         */
    }

    /* ── In kết quả ────────────────────────────────────────── */
    // print_results();

    /* ── Disable IRQ sau khi xong ──────────────────────────── */
    mstatus_disable_irq();
    ASCON_WRITE(ASCON->IRQ_EN, 0u);

    return 0;
}