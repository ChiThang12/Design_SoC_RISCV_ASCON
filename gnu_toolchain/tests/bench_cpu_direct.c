/* bench_cpu_direct.c — CPU Integer Performance Benchmark
 *
 * Build:
 *   cd gnu_toolchain
 *   ./compile_c_to_hex.sh -i tests/bench_cpu_direct.c \
 *                          -o tests/bench_cpu_direct.hex -O 1 -c
 *
 * Simulate:
 *   ~/workflow/urun_verilog.sh run_bench_cpu.v
 *   rtk read run_bench_cpu.log
 *
 * 4 workloads — mỗi cái đo từ SOC_CTRL hardware counters:
 *   cyc = SOC_CYCLE_CNT delta   (free-running, không phụ thuộc mcycle CSR)
 *   ins = SOC_INSTR_LO  delta   (minstret approx: regwrite_wb only)
 *   stl = SOC_STALL_CNT delta   (pipeline stall cycles)
 *
 *   W1 ALU chain  : 8000 iter add/xor/shift  → forwarding efficiency + IPC
 *   W2 MUL chain  : 4000 iter mul-acc         → 2-stage hardware MUL throughput
 *   W3 BHT branch : 8000 iter TNTN pattern    → BHT prediction rate
 *   W4 Memory     : 128-word array write+read → DCache cold miss → hot hit
 *
 * UART output (TB parses "[BENCH-DONE]" để stop simulation):
 *   [CPU-BENCH]
 *   sysid=A5C00001
 *   W1 alu cyc=XXXXXXXX ins=XXXXXXXX stl=XXXXXXXX
 *   W2 mul cyc=XXXXXXXX ins=XXXXXXXX stl=XXXXXXXX
 *   W3 bht cyc=XXXXXXXX ins=XXXXXXXX stl=XXXXXXXX
 *   W4 mem cyc=XXXXXXXX ins=XXXXXXXX ih=XXXXXXXX im=XXXXXXXX dh=XXXXXXXX dm=XXXXXXXX
 *   [BENCH-DONE]
 */
#include <stdint.h>
#include "uart.h"
#include "soc_ctrl.h"

/* ── Workload sizes ─────────────────────────────────────────────────────────── */
#define W1_N  8000u   /* ALU chain iterations   (~6 ops/iter → ~48k instructions) */
#define W2_N  4000u   /* MUL iterations          (~3 ops/iter → ~12k instructions) */
#define W3_N  8000u   /* branch iterations       (~3 ops/iter → ~24k instructions) */
#define W4_N  128u    /* array length (uint32_t) → 512 B, fits in 8KB DCache      */

/* ── Memory benchmark array (placed in .bss → DMEM starting at 0x10000000) ── */
static uint32_t bench_arr[W4_N];

/* ── Volatile sink: forces GCC to materialize computation result ─────────────
 * Prevents dead-code elimination at -O1. Write at end of each workload.      */
static volatile uint32_t v_sink;

/* ── Counter snapshot ───────────────────────────────────────────────────────
 * Reads 7 counters cùng lúc. Pass NULL cho ih/im/dh/dm nếu không cần.
 * fence trước/sau để tránh reorder với workload code.                        */
static void snap(uint32_t *cyc, uint32_t *ins, uint32_t *stl,
                 uint32_t *ih,  uint32_t *im,
                 uint32_t *dh,  uint32_t *dm)
{
    __asm__ volatile ("fence rw,rw" ::: "memory");
    *cyc = SOC_CYCLE_CNT;
    *ins = SOC_INSTR_LO;
    *stl = SOC_STALL_CNT;
    if (ih) *ih = SOC_ICACHE_HITS;
    if (im) *im = SOC_ICACHE_MISS;
    if (dh) *dh = SOC_DCACHE_HITS;
    if (dm) *dm = SOC_DCACHE_MISS;
    __asm__ volatile ("fence rw,rw" ::: "memory");
}

int main(void)
{
    uint32_t c0, c1, n0, n1, s0, s1;
    uint32_t ih0, im0, dh0, dm0;
    uint32_t ih1, im1, dh1, dm1;
    uint32_t i;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);
    uart_puts("[CPU-BENCH]\r\n");

    /* Verify SoC identity — xác nhận boot OK */
    uart_puts("sysid=");
    uart_puthex32(soc_ctrl_sysid());
    uart_puts("\r\n");

    /* ═══════════════════════════════════════════════════════════════════════
     * W1 — ALU chain: add / xor / shift
     * Chain a→b→c→a đảm bảo mỗi lệnh phụ thuộc lệnh trước (RAW hazard).
     * Forwarding tốt → không stall. Forwarding kém → nhiều stall.
     * ~6 phép/iter × 8000 iter ≈ 48000 lệnh. Baseline IPC measurement.
     * ═══════════════════════════════════════════════════════════════════════ */
    {
        uint32_t a = 1u, b = 3u, c = 7u;
        snap(&c0, &n0, &s0, 0, 0, 0, 0);
        for (i = 0u; i < W1_N; i++) {
            a = (a ^ (a >> 3)) + b;
            b = (b + c)        ^ (b << 5);
            c = (c + 0x1Fu)    + (a ^ c);
        }
        snap(&c1, &n1, &s1, 0, 0, 0, 0);
        v_sink = a ^ b ^ c;

        uart_puts("W1 alu cyc="); uart_puthex32(c1 - c0);
        uart_puts(" ins=");       uart_puthex32(n1 - n0);
        uart_puts(" stl=");       uart_puthex32(s1 - s0);
        uart_puts("\r\n");
    }

    /* ═══════════════════════════════════════════════════════════════════════
     * W2 — MUL chain: multiply + accumulate
     * Mỗi iter: 1 MUL (2-stage pipelined) + 2 ALU.
     * MUL result (2 cycles) → immediate use trong ADD → 1 stall nếu không có
     * interlock hiding. Nếu MUL được pipelined đúng: CPI ≈ 1.5–2.0.
     * k thay đổi mỗi iter → không folded bởi GCC -O1.
     * ═══════════════════════════════════════════════════════════════════════ */
    {
        uint32_t acc = 0u, k = 0x12345678u;
        snap(&c0, &n0, &s0, 0, 0, 0, 0);
        for (i = 0u; i < W2_N; i++) {
            acc += (i * k) ^ (i + 1u);
            k    = k ^ (k >> 7) ^ (acc << 3);
        }
        snap(&c1, &n1, &s1, 0, 0, 0, 0);
        v_sink = acc ^ k;

        uart_puts("W2 mul cyc="); uart_puthex32(c1 - c0);
        uart_puts(" ins=");       uart_puthex32(n1 - n0);
        uart_puts(" stl=");       uart_puthex32(s1 - s0);
        uart_puts("\r\n");
    }

    /* ═══════════════════════════════════════════════════════════════════════
     * W3 — Branch: alternating TAKEN / NOT-TAKEN (TNTN... pattern)
     * Pattern i&1: 0,1,0,1,... → hardest case cho BHT.
     *   1-bit predictor (strongish): mispredicts 100%
     *   2-bit saturating: mispredicts 50% (oscillates weakly-taken ↔ weakly-not)
     *   BHT với global history ≥ 1 bit: có thể học TNTN → đạt ~100%
     * Loop-back branch (i < W3_N) luôn TAKEN → BHT learns quickly.
     * ═══════════════════════════════════════════════════════════════════════ */
    {
        uint32_t s_even = 0u, s_odd = 0u;
        snap(&c0, &n0, &s0, 0, 0, 0, 0);
        for (i = 0u; i < W3_N; i++) {
            if (i & 1u) s_odd  = s_odd  + i + 3u;
            else        s_even = s_even + i * 2u + 1u;
        }
        snap(&c1, &n1, &s1, 0, 0, 0, 0);
        v_sink = s_even ^ s_odd;

        uart_puts("W3 bht cyc="); uart_puthex32(c1 - c0);
        uart_puts(" ins=");       uart_puthex32(n1 - n0);
        uart_puts(" stl=");       uart_puthex32(s1 - s0);
        uart_puts("\r\n");
    }

    /* ═══════════════════════════════════════════════════════════════════════
     * W4 — Memory: sequential write pass → sequential read-accumulate pass
     *
     * Array: 128 × 4B = 512B.
     * DCache: 8KB, 16B/line → 512B / 16B = 32 lines cần load (cold miss).
     * Write pass: 32 DCache cold misses (line fill) + 128 hits sau fill.
     * Read pass: 128 DCache hits (tất cả line đã warm).
     *
     * ih/im/dh/dm = delta so với trước W4 → phản ánh đúng W4 access pattern.
     * ═══════════════════════════════════════════════════════════════════════ */
    {
        uint32_t sum = 0u;

        snap(&c0, &n0, &s0, &ih0, &im0, &dh0, &dm0);

        /* Write pass — cold DCache line fill */
        for (i = 0u; i < W4_N; i++) bench_arr[i] = i * 0x12345u;

        /* Read+sum pass — DCache warm, all hits */
        for (i = 0u; i < W4_N; i++) sum += bench_arr[i] ^ (i << 3);

        snap(&c1, &n1, &s1, &ih1, &im1, &dh1, &dm1);
        v_sink = sum;

        uart_puts("W4 mem cyc="); uart_puthex32(c1 - c0);
        uart_puts(" ins=");       uart_puthex32(n1 - n0);
        uart_puts(" ih=");        uart_puthex32(ih1 - ih0);
        uart_puts(" im=");        uart_puthex32(im1 - im0);
        uart_puts(" dh=");        uart_puthex32(dh1 - dh0);
        uart_puts(" dm=");        uart_puthex32(dm1 - dm0);
        uart_puts("\r\n");
    }

    uart_puts("[BENCH-DONE]\r\n");
    while (1) __asm__ volatile ("nop");
    return 0;
}
