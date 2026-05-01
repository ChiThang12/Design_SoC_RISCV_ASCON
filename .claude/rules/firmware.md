# Firmware Rules — Design_SoC_RISCV_ASCON

## 1. Tổng quan Firmware Stack

Firmware nằm trong `gnu_toolchain/`, viết bằng C (bare-metal) cho RISC-V RV32IM.
Không có OS, không có libc — chỉ có inline assembly MMIO access.

### 1.1. Cấu trúc thư mục
```
gnu_toolchain/
├── main.c                     ← Firmware chính (v10.0, DMA 16-block)
├── example.c                  ← Legacy example (commented out)
├── compile_c_to_hex.sh        ← ★ Build script chính (v2.7)
├── build_all.sh               ← Build tất cả tests
├── build.sh / run.sh          ← Script phụ
├── linker_minimal.ld          ← Linker script (auto-generated bởi compile_c_to_hex.sh)
├── startup_generated.s        ← CRT0 (auto-generated bởi compile_c_to_hex.sh)
├── program.hex                ← Output hex (load vào IMEM qua boot_ctrl)
│
├── ascon.h                    ← ASCON accelerator driver (inline asm MMIO)
├── dma.h                      ← General-purpose DMA driver (inline asm MMIO)
├── dmem_layout.h              ← DMEM memory layout struct + addresses
├── uart.h                     ← UART TX/RX driver (inline asm)
├── plic_drv.h                 ← PLIC interrupt controller driver
│
├── include/                   ← ★ Canonical header set (dùng bởi tests/)
│   ├── memory_map.h           ← Tập trung tất cả base address
│   ├── ascon.h                ← Bản mới nhất (symlink/copy)
│   ├── dma.h                  ← Bản mới nhất
│   ├── dmem_layout.h
│   ├── uart.h                 ← Bản mở rộng (có UART_DIV constants)
│   ├── plic.h                 ← PLIC driver (khác plic_drv.h — dùng cho tests)
│   ├── irq.h                  ← RISC-V M-mode interrupt helpers
│   ├── clint.h                ← CLINT timer driver
│   ├── gpio.h                 ← GPIO driver
│   ├── timer.h                ← Timer/WDT driver
│   └── soc_ctrl.h             ← SoC control (SYS_ID, cache stats, cycle cnt)
│
├── tests/                     ← ★ Test suite + benchmarks
│   ├── test_uart.c            ← UART loopback test
│   ├── test_gpio.c            ← GPIO read/write test
│   ├── test_timer.c           ← Timer countdown test
│   ├── test_clint.c           ← CLINT mtime/mtimecmp test
│   ├── test_plic.c            ← PLIC interrupt routing test
│   ├── test_ascon.c           ← ASCON 16-block DMA encrypt test
│   ├── test_integration.c     ← Unity build: chạy tất cả 6 test
│   ├── bench_cpu_direct.c     ← Benchmark: CPU-direct mode (N=1,4,16)
│   ├── bench_dma_poll.c       ← Benchmark: DMA mode + busy-wait poll
│   └── bench_dma_irq.c        ← Benchmark: DMA mode + WFI interrupt
│
└── demo/                      ← Demo files (subset)
    ├── main.c, ascon.h, dma.h, dmem_layout.h, plic_drv.h
    └── compile_c_to_hex.sh, program.hex
```

### 1.2. Include Path
```
Tests dùng headers từ include/:
  #include "uart.h"        → include/uart.h
  #include "ascon.h"       → include/ascon.h
  #include "dmem_layout.h" → include/dmem_layout.h

Firmware gốc (main.c) dùng:
  #include "include/ascon.h"
  #include "include/dmem_layout.h"
```

## 2. Toolchain & Build

### 2.1. Compiler
- **Toolchain**: `riscv64-unknown-elf-gcc` (cross-compile RV32)
- **ISA**: `-march=rv32im_zicsr -mabi=ilp32`
- **Chuẩn**: Freestanding (`-ffreestanding -nostdlib -nostartfiles`)
- **Optimization**: Mặc định `-O0`, benchmark dùng `-O1`

### 2.2. Build command
```bash
cd gnu_toolchain

# Build firmware chính → program.hex
./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c

# Build một test
./compile_c_to_hex.sh -i tests/test_ascon.c -o tests/test_ascon.hex -O 1 -c

# Build tất cả tests
./build_all.sh
```

### 2.3. Flags quan trọng
| Flag | Ý nghĩa |
|------|---------|
| `-c` | Bare-metal startup (không clear .bss, không copy .data) |
| `-k` | Giữ lại file tạm (`.elf`, `.dump`, `.map`, `.s`) |
| `-O 0` | KHÔNG optimize — an toàn nhất cho MMIO firmware |
| `-O 1` | Optimize nhẹ — dùng cho benchmark (timing-sensitive) |
| `-n` | Không pad NOP vào hex file |
| `-v` | Verbose: in section layout, symbol table |

### 2.4. Cảnh báo Optimization
> **QUAN TRỌNG**: `-O2` và `-O3` có thể khiến GCC fold/reorder MMIO writes!
> Inline assembly với `"memory"` clobber + `fence` tránh được phần lớn, nhưng
> vẫn nên dùng `-O0` hoặc `-O1` cho firmware MMIO.

### 2.5. Output Files
```
Sau build:
  program.hex       ← Load vào IMEM (2048 words = 8KB, padded NOP)
  main.elf          ← ELF để debug (symbol table)
  main.dump         ← Disassembly (objdump -d)
  main.map          ← Linker map (section addresses, symbols)
  main.s            ← GCC generated assembly
```

## 3. Memory Map (Firmware View)

### 3.1. Address Spaces
```
0x0000_0000 – 0x0000_1FFF   IMEM (ROM, 8KB)  — .text + .rodata
0x1000_0000 – 0x1000_07FF   DMEM_DATA (2KB)  — .data + .bss
0x1000_0800 – 0x1000_0FFF   GUARD ZONE (2KB) — unmapped (linker-enforced)
0x1000_1000 – 0x1000_1FFF   DMEM_STACK (4KB) — stack (grows down)

0x2000_0000   ASCON   (S2)  — ascon.h
0x3000_0000   SoC Ctrl(S3)  — soc_ctrl.h
0x4000_0000   CLINT   (S4)  — clint.h
0x5000_0000   UART    (S5)  — uart.h
0x5001_0000   GPIO    (S6)  — gpio.h
0x5002_0000   SPI     (S7)  — stub (DECERR)
0x5003_0000   Timer   (S8)  — timer.h
0x5004_0000   PLIC    (S9)  — plic.h
0x6000_0000   OTP     (S10) — stub (DECERR)
0x6001_0000   DMA     (S11) — dma.h
```

### 3.2. DMEM Layout (chi tiết)
```
0x10000000 – 0x100001B3   g_stream (.bss, AsconStream_t, 436B)
0x100001B4 – 0x100001BF   alignment gap (12B)
0x100001C0 – 0x1000021B   DmemLayout_t (92B) — DMEM base pointer
0x1000021C – 0x1000021F   gap
0x10000220 – 0x1000029F   PT_MULTI_BASE  — plaintext buffer (16 blocks × 8B = 128B)
0x100002A0 – 0x1000032F   CT_MULTI_BASE  — ciphertext+tag buffer (128B + 16B = 144B)
0x10000330 – 0x100007FF   free
0x10000800 – 0x10000FFF   GUARD ZONE
0x10001000 – 0x10001FEF   stack area
0x10001FF0                __stack_top (sp vào main = 0x10001FF0)
```

### 3.3. Stack Convention
- `__stack_top = 0x10001FF0` (resolved bởi linker)
- `_start` load `sp = __stack_top`, KHÔNG trừ 16 (FIX-STACK v2.7)
- `main()` tự push frame: `sp - 32 = 0x10001FD0`, `sw ra, 28(sp) = 0x10001FEC`
- First push phải < `0x10001FFF` (DMEM upper bound)

## 4. MMIO Access Pattern

### 4.1. Inline Assembly MMIO (Preferred)
Tất cả peripheral drivers dùng inline assembly để đảm bảo:
- Compiler KHÔNG reorder/duplicate MMIO writes
- Offset được mã hóa trực tiếp vào lệnh (`"i"` constraint)
- `fence w,w` sau write đảm bảo ordering đến hardware

```c
/* Pattern chuẩn cho ASCON/DMA: */
#define PERIPH_WRITE(offset, val) do {               \
    __asm__ volatile (                                \
        "lui  t0, " PERIPH_BASE_HI "\n"              \
        "sw   %0, %1(t0)\n"                          \
        "fence w, w\n"                                \
        :: "r" ((uint32_t)(val)), "i" (offset)        \
        : "t0", "memory"                              \
    );                                                \
} while(0)

#define PERIPH_READ(offset, val) do {                \
    __asm__ volatile (                                \
        "lui  t0, " PERIPH_BASE_HI "\n"              \
        "lw   %0, %1(t0)\n"                          \
        : "=r" (val)                                  \
        : "i" (offset)                                \
        : "t0", "memory"                              \
    );                                                \
} while(0)
```

### 4.2. Volatile Pointer MMIO (Alternative — dùng cho soc_ctrl, plic...)
```c
/* Khi offset là compile-time constant: */
#define MMIO_REG(base, offset)  (*((volatile uint32_t *)((base) + (offset))))

/* Ví dụ: */
#define SOC_SYS_ID  MMIO_REG(SOC_CTRL_BASE, 0x000)
uint32_t id = SOC_SYS_ID;  // đọc
SOC_SYS_CTRL = 1u;         // ghi
```

### 4.3. Dynamic Offset MMIO (dùng khi offset là runtime variable)
```c
/* DMA channel index là biến → dùng pointer arithmetic: */
#define DMA_WRITE_DYN(base_reg, dyn_offset, val) do {   \
    volatile uint32_t *_p = (volatile uint32_t *)        \
        (0x60010000u + (uint32_t)(dyn_offset));          \
    *_p = (uint32_t)(val);                               \
    __asm__ volatile ("fence w, w" ::: "memory");        \
} while(0)
```

## 5. Driver APIs

### 5.1. ASCON (ascon.h)
```c
/* Setup */
ascon_soft_reset();
ascon_set_mode(ASCON_MODE_128_ENC);   // 0x0=128-enc, 0x1=128a-enc, 0x2=128-dec, 0x3=128a-dec
ascon_set_key(k0, k1, k2, k3);       // 128-bit, big-endian word order
ascon_set_nonce(n0, n1, n2, n3);
ascon_set_ad(a0, a1, a2, a3, ad_len); // Optional: associated data (max 16B)
ascon_clear_ad();                      // Clear AD for sessions without AD

/* CPU-Direct mode (single block, max 64-bit plaintext) */
ascon_set_ptext(p0, p1, byte_len);
ascon_core_start();                    // CTRL = 0x1
ascon_wait_core_done();
ascon_get_ctext(&c0, &c1);
ascon_get_tag(&t0, &t1, &t2, &t3);

/* DMA mode (multi-block streaming) */
ascon_dma_config(src_addr, dst_addr, byte_len);
ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);  // ARLEN=7 (8 beats)
ASCON_WRITE(ASCON_OFS_DATA_LEN, 8u);   // 8 bytes per block
__asm__ volatile ("fence rw,rw" ::: "memory");
ascon_dma_start();                      // CTRL = 0x5 (DMA_EN | CORE_START)
uint32_t st = ascon_wait_dma_done();
```

### 5.2. CTRL Register — Gotcha quan trọng nhất
```c
/* !! CRITICAL !! DMA cần CẢ bit[0] (CORE_START) VÀ bit[2] (DMA_EN): */
ASCON_CTRL_DMA_START = 0x5   // = bit0 | bit2

/* Sai: chỉ ghi DMA_EN (0x4) → CORE không chạy → CORE_DONE timeout */
/* Đúng: ghi 0x5 = DMA_EN | CORE_START */
```

### 5.3. DMA General-Purpose (dma.h)
```c
/* Đơn giản nhất: */
int ret = dma_memcpy(ch, src, dst, len);  // blocking, return 0=OK, -1=error

/* Manual: */
dma_ch0_setup(src, dst, len);
dma_ch0_start();                  // CH_CTRL = EN | START | MODE_MEM
uint32_t st = dma_wait(0);       // poll DONE | ERROR
dma_clear_done(0);

/* Runtime channel: */
dma_ch_setup(ch, src, dst, len);
dma_ch_start(ch);

/* 2 channel song song: */
dma_ch0_start(); dma_ch1_start();
dma_wait_all(0x3);                // chờ cả CH0 và CH1
```

### 5.4. Interrupt (irq.h + plic.h)
```c
/* Setup PLIC + CPU: */
plic_set_threshold(0u);
plic_set_priority(PLIC_SRC_ASCON, 1u);   // src 8 = ASCON
plic_enable(PLIC_SRC_ASCON);
irq_set_mtvec(my_isr);
irq_enable_external();                    // mie.MEIE = bit 11
irq_enable_global();                      // mstatus.MIE = bit 3

/* ISR: */
__attribute__((interrupt("machine"))) void my_isr(void) {
    uint32_t src = plic_claim();
    // handle...
    plic_complete(src);
}
```

## 6. Fence Usage — Khi nào cần Memory Barrier

| Tình huống | Fence | Lý do |
|-----------|-------|-------|
| Trước DMA start | `fence rw,rw` | Drain store buffer: CPU writes to DMEM phải visible trước khi DMA reads |
| Sau DMA done | `fence r,r` | Invalidate: CPU reads DMEM phải thấy data mới từ DMA write |
| Sau MMIO write | `fence w,w` | Ordering: MMIO writes phải đến hardware theo thứ tự |
| Trước ISR return | `fence w,w` | Ordering: PLIC complete write phải commit trước mret |

## 7. Startup Flow (Boot Sequence)

```
1. boot_ctrl copy program.hex → IMEM (S0)
2. Release cpu_rst_n
3. CPU fetch _start từ 0x00000000
4. _start:
   a. la sp, __stack_top          (= 0x10001FF0)
   b. la t0, trap_handler → csrw mtvec
   c. [Full CRT0] copy .data ROM→DMEM, clear .bss
   d. call main
5. main() → configure peripherals → run workload → halt loop
```

## 8. Quy tắc viết Firmware

### 8.1. MMIO Safety
- **LUÔN** dùng inline assembly hoặc `volatile` pointer cho MMIO access
- **KHÔNG** dùng biến thường để cache MMIO address — compiler sẽ optimize away
- Mỗi MMIO write phải có `fence w,w` hoặc `"memory"` clobber
- Poll loop phải có `"memory"` clobber trong `__asm__` block

### 8.2. Firmware ↔ RTL Consistency
- Register offset trong firmware header **PHẢI khớp** với `ascon_axi_slave.v` localparams
- Khi thêm/đổi register RTL → update header file tương ứng NGAY
- Status bit position phải match giữa firmware `#define` và RTL `status_word` concatenation
- CTRL bit semantic (1-cycle pulse vs level) phải match RTL `always @(posedge clk)` block

### 8.3. Khi sửa RTL cần sửa Firmware
| Thay đổi RTL | File firmware cần update |
|-------------|------------------------|
| Thêm/đổi register offset | `ascon.h`, `dma.h`, `include/*.h` |
| Đổi status bit layout | `ascon.h` (ASCON_ST_* defines) |
| Đổi CTRL bit semantic | `ascon.h` (ASCON_CTRL_* defines) |
| Đổi memory map / base address | `include/memory_map.h`, `dmem_layout.h` |
| Đổi DMEM size | `linker_minimal.ld`, `compile_c_to_hex.sh` |
| Đổi FIFO depth / burst len | `main.c` DMA_BURST config |
| Thêm peripheral mới | Tạo `include/<periph>.h`, update `memory_map.h` |
| Đổi IRQ source routing | `plic.h` / `plic_drv.h` (PLIC_SRC_* defines) |
| Đổi clock frequency | `uart.h` (UART_DIV_* defines) |

### 8.4. Struct Layout Safety
- `dmem_layout.h` dùng `_Static_assert` để verify offset tại compile-time
- Khi thêm field vào `DmemLayout_t`, PHẢI thêm `_Static_assert` tương ứng
- DMA buffer addresses phải word-aligned (LSB 2 bits = 00)
- DMA buffer regions KHÔNG được overlap `DmemLayout_t` hoặc stack

### 8.5. Test Pattern
```c
/* Mỗi test module export 1 hàm: */
static int run_xxx_test(void) { ... return 0; /* 0=PASS, -1=FAIL */ }

/* Standalone: */
#ifndef INTEGRATION_BUILD
int main(void) {
    int r = run_xxx_test();
    if (r == 0) uart_puts("[PASS] xxx\r\n");
    else        uart_puts("[FAIL] xxx\r\n");
    while (1) __asm__ volatile ("nop");
}
#endif

/* Integration: test_integration.c include tất cả với #define INTEGRATION_BUILD */
```

## 9. Performance Benchmark Suite

### 9.1. Benchmark Programs
| File | Mode | Đo gì |
|------|------|-------|
| `bench_cpu_direct.c` | CPU-Direct | mcycle CSR cho N=1,4,16 single-block AEAD |
| `bench_dma_poll.c` | DMA + Poll | PERF_TOTAL (hw counter) cho N=1,4,16 multi-block |
| `bench_dma_irq.c` | DMA + WFI | PERF_TOTAL + IRQ wakeup latency |

### 9.2. Performance Counters (Hardware)
```c
/* Đọc từ ASCON registers (read-only, auto-reset khi soft_rst): */
ASCON_READ(ASCON_OFS_PERF_TOTAL, total);  // cycles DMA_BUSY=1
ASCON_READ(ASCON_OFS_PERF_CORE,  core);   // subset: cycles CORE_BUSY=1

/* CPU cycle counter: */
uint32_t t0, t1;
__asm__ volatile ("csrr %0, mcycle" : "=r"(t0));
// ... workload ...
__asm__ volatile ("csrr %0, mcycle" : "=r"(t1));
uint32_t elapsed = t1 - t0;
```

### 9.3. Key Metrics
```
T_overhead     = cycles(N=1)
T_per_block    = (cycles(N=16) - cycles(N=1)) / 15
Throughput     = N_blocks × 64 bits / T_total / f_clk
CORE_util      = PERF_CORE / PERF_TOTAL × 100%
```

## 10. Debug Tips

### 10.1. Post-simulation Inspection
```c
/* Firmware ghi kết quả vào DMEM để TB kiểm tra: */
DMEM->STATUS  = status;
DMEM->RETCODE = retcode;   // 0=OK, -1=error, -2=timeout

/* Trong gtkwave: xem DMEM address 0x10000218 (RETCODE offset) */
```

### 10.2. UART Debug Output
```c
uart_init(UART_DIV_115200_100MHZ, 0u, 0u);
uart_puts("[PASS] ascon\r\n");
uart_puthex32(value);   // print 32-bit hex
uart_puthex8(byte);     // print 8-bit hex
```

### 10.3. Common Firmware Bugs
| Triệu chứng | Nguyên nhân | Fix |
|-------------|-------------|-----|
| PC jump to 0xffffff00 | Stack overflow (sp > DMEM_STACK) | Check linker __stack_top, giảm local vars |
| CORE_DONE timeout | CTRL chỉ ghi DMA_EN (0x4) thiếu CORE_START | Dùng ASCON_CTRL_DMA_START (0x5) |
| DMA reads stale data | Thiếu `fence rw,rw` trước dma_start | Thêm fence |
| CPU reads old ctext | Thiếu `fence r,r` sau dma_done | Thêm fence |
| Key/Nonce sai | GCC INCR burst ghi tất cả vào KEY_0 | RTL đã fix (wr_addr_lat += 4) |
| Infinite poll loop | Status bit position sai giữa FW và RTL | Verify ASCON_ST_* vs status_word |