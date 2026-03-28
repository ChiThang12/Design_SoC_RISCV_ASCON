/*
 * ascon_store.c
 *
 * Lưu (STORE) các bit input của ASCON IP vào DMEM.
 *
 * Luồng thực hiện:
 *   1. SOFT_RST ASCON core
 *   2. Ghi KEY, NONCE, PTEXT vào ASCON IP + STORE bản sao vào DMEM
 *   3. Ghi MODE (mã hóa)
 *   4. Kích hoạt CTRL.START = 1
 *   5. Polling chờ STATUS.DONE = 1
 *   6. Đọc CTEXT + TAG từ ASCON IP, STORE vào DMEM
 *   7. SOFT_RST lại ASCON core
 *
 * Compile:
 *   ./compile_c_to_hex.sh -i ascon_store.c -o ascon_store.hex -v -k
 *
 * Memory Map (spec 03 + 04):
 *   S1 DMEM  : 0x1000_0000  64KB  (RAM — stack, data)
 *   S2 ASCON : 0x2000_0000   4KB  (AXI4 Lite slave)
 */

// #include <stdint.h>

// /* ============================================================
//  * ASCON Register Map (spec 05 — Section 4)
//  * Base: 0x2000_0000
//  * ============================================================ */
// #define ASCON_BASE  0x20000000UL
// #define REG(off)    (*((volatile uint32_t *)(ASCON_BASE + (off))))

// /* Control / Status */
// #define ASCON_CTRL      REG(0x00)   /* R/W  — bit[0]=START, bit[1]=SOFT_RST */
// #define ASCON_STATUS    REG(0x04)   /* RO   — bit[0]=BUSY,  bit[1]=DONE     */
// #define ASCON_MODE      REG(0x08)   /* R/W  — bit[0]: 0=encrypt, 1=decrypt  */

// /* Key (128-bit, WO) */
// #define ASCON_KEY0      REG(0x10)   /* bits [127:96] */
// #define ASCON_KEY1      REG(0x14)   /* bits [95:64]  */
// #define ASCON_KEY2      REG(0x18)   /* bits [63:32]  */
// #define ASCON_KEY3      REG(0x1C)   /* bits [31:0]   */

// /* Nonce (128-bit, WO) */
// #define ASCON_NONCE0    REG(0x20)   /* bits [127:96] */
// #define ASCON_NONCE1    REG(0x24)   /* bits [95:64]  */
// #define ASCON_NONCE2    REG(0x28)   /* bits [63:32]  */
// #define ASCON_NONCE3    REG(0x2C)   /* bits [31:0]   */

// /* Plaintext (64-bit, WO) */
// #define ASCON_PTEXT0    REG(0x30)   /* bits [63:32]  */
// #define ASCON_PTEXT1    REG(0x34)   /* bits [31:0]   */

// /* Ciphertext output (64-bit, RO) */
// #define ASCON_CTEXT0    REG(0x40)   /* bits [63:32]  */
// #define ASCON_CTEXT1    REG(0x44)   /* bits [31:0]   */

// /* Auth Tag output (128-bit, RO) */
// #define ASCON_TAG0      REG(0x48)   /* bits [127:96] */
// #define ASCON_TAG1      REG(0x4C)   /* bits [95:64]  */
// #define ASCON_TAG2      REG(0x50)   /* bits [63:32]  */
// #define ASCON_TAG3      REG(0x54)   /* bits [31:0]   */

// /* Status bit masks */
// #define STATUS_BUSY     (1u << 0)
// #define STATUS_DONE     (1u << 1)

// /* CTRL bit masks */
// #define CTRL_START      (1u << 0)
// #define CTRL_SOFT_RST   (1u << 1)

// /* MODE values */
// #define MODE_ENCRYPT    0u
// #define MODE_DECRYPT    1u

// /* ============================================================
//  * DMEM layout — vùng lưu snapshot input + output ASCON
//  * Base: 0x1000_0000
//  *
//  * Offset  Size   Nội dung
//  * 0x00    16B    key[0..3]    — input đã ghi vào ASCON
//  * 0x10    16B    nonce[0..3]  — input đã ghi vào ASCON
//  * 0x20     8B    ptext[0..1]  — input đã ghi vào ASCON
//  * 0x28     8B    ctext[0..1]  — output đọc từ ASCON
//  * 0x30    16B    tag[0..3]    — output đọc từ ASCON
//  * ============================================================ */
// #define DMEM_BASE   0x10000000UL
// #define DMEM(off)   (*((volatile uint32_t *)(DMEM_BASE + (off))))

// #define DMEM_KEY0       DMEM(0x00)
// #define DMEM_KEY1       DMEM(0x04)
// #define DMEM_KEY2       DMEM(0x08)
// #define DMEM_KEY3       DMEM(0x0C)

// #define DMEM_NONCE0     DMEM(0x10)
// #define DMEM_NONCE1     DMEM(0x14)
// #define DMEM_NONCE2     DMEM(0x18)
// #define DMEM_NONCE3     DMEM(0x1C)

// #define DMEM_PTEXT0     DMEM(0x20)
// #define DMEM_PTEXT1     DMEM(0x24)

// #define DMEM_CTEXT0     DMEM(0x28)
// #define DMEM_CTEXT1     DMEM(0x2C)

// #define DMEM_TAG0       DMEM(0x30)
// #define DMEM_TAG1       DMEM(0x34)
// #define DMEM_TAG2       DMEM(0x38)
// #define DMEM_TAG3       DMEM(0x3C)

// /* ============================================================
//  * Test vector
//  * Thay bằng giá trị thật khi tích hợp vào hệ thống.
//  * ============================================================ */
// static const uint32_t TEST_KEY[4] = {
//     0x00112233u,    /* key[127:96] */
//     0x44556677u,    /* key[95:64]  */
//     0x8899AABBu,    /* key[63:32]  */
//     0xCCDDEEFFu     /* key[31:0]   */
// };

// static const uint32_t TEST_NONCE[4] = {
//     0xDEADBEEFu,    /* nonce[127:96] */
//     0xCAFEBABEu,    /* nonce[95:64]  */
//     0x01234567u,    /* nonce[63:32]  */
//     0x89ABCDEFu     /* nonce[31:0]   */
// };

// static const uint32_t TEST_PTEXT[2] = {
//     0x48656C6Cu,    /* ptext[63:32]  = "Hell" */
//     0x6F210000u     /* ptext[31:0]   = "o!.." */
// };

// /* ============================================================
//  * store_ascon_inputs_to_dmem
//  *
//  * Ghi KEY, NONCE, PTEXT vào ASCON IP registers (WO).
//  * Đồng thời STORE bản sao vào DMEM để kiểm tra/debug.
//  * ============================================================ */
// static void store_ascon_inputs_to_dmem(void)
// {
//     /* Bước 1: Reset core trước khi nạp input mới */
//     ASCON_CTRL = CTRL_SOFT_RST;

//     /* --- KEY --- */
//     DMEM_KEY0 = TEST_KEY[0];   ASCON_KEY0 = TEST_KEY[0];
//     DMEM_KEY1 = TEST_KEY[1];   ASCON_KEY1 = TEST_KEY[1];
//     DMEM_KEY2 = TEST_KEY[2];   ASCON_KEY2 = TEST_KEY[2];
//     DMEM_KEY3 = TEST_KEY[3];   ASCON_KEY3 = TEST_KEY[3];

//     /* --- NONCE --- */
//     DMEM_NONCE0 = TEST_NONCE[0];   ASCON_NONCE0 = TEST_NONCE[0];
//     DMEM_NONCE1 = TEST_NONCE[1];   ASCON_NONCE1 = TEST_NONCE[1];
//     DMEM_NONCE2 = TEST_NONCE[2];   ASCON_NONCE2 = TEST_NONCE[2];
//     DMEM_NONCE3 = TEST_NONCE[3];   ASCON_NONCE3 = TEST_NONCE[3];

//     /* --- PLAINTEXT --- */
//     DMEM_PTEXT0 = TEST_PTEXT[0];   ASCON_PTEXT0 = TEST_PTEXT[0];
//     DMEM_PTEXT1 = TEST_PTEXT[1];   ASCON_PTEXT1 = TEST_PTEXT[1];

//     /* Bước 3: MODE = encrypt */
//     ASCON_MODE = MODE_ENCRYPT;
// }

// /* ============================================================
//  * run_ascon_and_store_output
//  *
//  * Kích hoạt ASCON, chờ DONE, đọc CTEXT + TAG, STORE vào DMEM.
//  * ============================================================ */
// static void run_ascon_and_store_output(void)
// {
//     /* Bước 4: Kích hoạt START */
//     ASCON_CTRL = CTRL_START;

//     /* Bước 5: Polling STATUS.DONE (~30 cycles theo spec Section 3) */
//     while (!(ASCON_STATUS & STATUS_DONE)) {
//         /* busy-wait */
//     }

//     /* Bước 6: Đọc CTEXT (RO) → STORE vào DMEM */
//     DMEM_CTEXT0 = ASCON_CTEXT0;
//     DMEM_CTEXT1 = ASCON_CTEXT1;

//     /* Bước 6: Đọc TAG (RO) → STORE vào DMEM */
//     DMEM_TAG0 = ASCON_TAG0;
//     DMEM_TAG1 = ASCON_TAG1;
//     DMEM_TAG2 = ASCON_TAG2;
//     DMEM_TAG3 = ASCON_TAG3;

//     /* Bước 7: SOFT_RST để sẵn sàng cho lần kế tiếp */
//     ASCON_CTRL = CTRL_SOFT_RST;
// }

// /* ============================================================
//  * main
//  * ============================================================ */
// int main(void)
// {
//     /* Ghi KEY + NONCE + PTEXT vào ASCON IP và lưu bản sao vào DMEM */
//     store_ascon_inputs_to_dmem();

//     /* Chạy ASCON, đọc CTEXT + TAG, lưu vào DMEM */
//     run_ascon_and_store_output();

//     /*
//      * Snapshot DMEM sau khi chạy xong:
//      *
//      *   Addr            Content         Size
//      *   0x1000_0000     KEY[0..3]       16 bytes  (input)
//      *   0x1000_0010     NONCE[0..3]     16 bytes  (input)
//      *   0x1000_0020     PTEXT[0..1]      8 bytes  (input)
//      *   0x1000_0028     CTEXT[0..1]      8 bytes  (output)
//      *   0x1000_0030     TAG[0..3]       16 bytes  (output)
//      */

//     /* Halt */
//     while (1) { /* spin */ }

//     return 0;
// }

int main(void) {
    int a = 10;
    int b = 20;
    int c = a + b;  // c = 30
    return c;
}