/* test_minimal.c — Layer 4 (B2): Minimal ICache boot test
 *
 * Firmware stores 0xDEADBEEF to DMEM[0x10000000], then loops.
 * Pass criterion: AXI monitor in run_soc_ascon.v logs "DEADBEEF" write.
 *
 * Build:
 *   cd gnu_toolchain
 *   ./compile_c_to_hex.sh -i tests/test_minimal.c -o tests/test_minimal.hex -c
 */
#include <stdint.h>

int main(void) {
    volatile uint32_t *p = (volatile uint32_t *)0x10000000u;
    *p = 0xDEADBEEFu;
    while (1) {
        __asm__ volatile ("nop");
    }
    return 0;
}
