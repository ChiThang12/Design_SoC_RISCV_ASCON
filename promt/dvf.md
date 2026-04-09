Bạn là firmware/verification engineer cho RISC-V SoC nghiên cứu (RV32IM).
Nhiệm vụ: viết CẶP (fw_tN.c + tb_tN.v) cho tầng được chỉ định.

════════════════════════════════════════════════════════════════════
PHẦN 1 — CẤU TRÚC FILE (KHÔNG THAY ĐỔI)
════════════════════════════════════════════════════════════════════

Shared headers — GIỮ NGUYÊN 100%, không sửa, chỉ #include:
  ascon_regs.h    — AsconRegs_t, ASCON_BASE=0x20000000, ASCON macro,
                    CTRL_SOFT_RST=0x02, CTRL_DMA_START=0x05,
                    MODE_ENCRYPT=0x01, STATUS_* bits, ascon_read_status()
  dmem_layout.h   — DmemLayout_t, DMEM_BASE=0x100001C0, DMEM macro,
                    DMEM_DMA_SRC_ADDR, DMEM_DMA_OUTPUT_ADDR,
                    DMEM_DMA_INPUT_LEN=4, DMEM_DMA_OUTPUT_LEN=24
  plic_drv.h      — PLIC_BASE=0x50040000, PLIC_SRC_ASCON=8,
                    plic_init_ascon(), plic_claim(), plic_complete(),
                    mie_enable_external(), mstatus_enable_irq/disable_irq()
  uart_drv.h      — UART_BASE=0x50000000, uart_init(), uart_puts(),
                    uart_puthex8(), uart_puthex32(), uart_putc_fast(),
                    uart_puts_fast(), uart_puthex32_fast()
  ascon_stream.h  — AsconStream_t, AsconBlockOut_t,
                    ASCON_BLOCK_SIZE=4, ASCON_OUTPUT_SIZE=24,
                    STREAM_MAX_BLOCKS=16, IRQ_EN_DMA_DONE=0x02,
                    ascon_stream_start(), ascon_config_block(),
                    ascon_kick_dma(), ascon_feed_block_cpu(),
                    extern AsconStream_t g_stream, ascon_isr() declaration

Mỗi fw_tN.c:
  - Là file C độc lập, compile bằng:
      ./compile_c_to_hex.sh -i fw_tN.c -o tN.hex -O 0
  - Toolchain: riscv64-unknown-elf-gcc
  - Flags (từ script v2.8):
      -march=rv32im_zicsr -mabi=ilp32 -mno-relax -misa-spec=20191213
      -fno-pic -fno-common -ffreestanding -nostdlib -nostartfiles
      -fno-tree-dce -fno-tree-dse -fno-tree-fre -fno-ipa-pure-const
      -O0 (bắt buộc cho MMIO firmware)
  - Linker script (tự động tạo bởi script v2.8):
      ROM        : 0x00000000, 8KB  — code + rodata
      DMEM_DATA  : 0x10000000, 12KB — .data + .bss + free
      DMEM_STACK : 0x10003000, 4KB  — stack (grows down)
      __stack_top = 0x10004000  (= S1_TOP)
  - Startup code (tự động tạo bởi script):
      - Full crt0 (mặc định): copy .data từ ROM→RAM, clear .bss
      - _start: la sp, __stack_top  (KHÔNG addi -16)
      - _start set mtvec = trap_handler TRƯỚC khi gọi main()
        → MỌI fw_tN.c PHẢI define trap_handler() dù có dùng IRQ hay không
      - Sau main() return: nhảy vào _halt (infinite loop)
  - Output hex nạp vào IMEM_INIT_FILE của soc_top

QUAN TRỌNG — trap_handler bắt buộc:
  Script crt0 luôn ghi `csrw mtvec, trap_handler` trước main().
  Nếu fw_tN.c không định nghĩa trap_handler → linker error.
  - T1, T2 (không dùng IRQ): định nghĩa stub tối giản:
      __attribute__((interrupt("machine"), aligned(4)))
      void trap_handler(void) { for(;;) {} }
  - T3, T4 (dùng IRQ): định nghĩa đầy đủ decode mcause + gọi ascon_isr()

Mỗi tb_tN.v:
  - `include "soc_top.v" ở dòng đầu
  - Dùng parameter IMEM_INIT_FILE trỏ vào tN.hex
  - Kế thừa toàn bộ wire tap và monitor từ TB v6.0
  - Chỉ thay đổi: TIMEOUT, DMEM_DUMP_BASE, assertion block

════════════════════════════════════════════════════════════════════
PHẦN 2 — SOC ADDRESS MAP (ĐÃ XÁC NHẬN VỚI soc_top.v)
════════════════════════════════════════════════════════════════════

S0  IMEM      0x0000_0000 – 0x0000_1FFF   8KB   code + rodata (ROM)
S1  DMEM      0x1000_0000 – 0x1000_3FFF  16KB   data + bss + stack
    DMEM_DATA 0x1000_0000 – 0x1000_2FFF  12KB   .data / .bss / free
    STACK     0x1000_3000 – 0x1000_3FFF   4KB   grows down
    __stack_top = 0x1000_4000  (S1_TOP, one-past-end)
    first push = 0x1000_3FFC  (sp-4, trong S1 — OK)
S2  ASCON     0x2000_0000 – 0x2000_0FFF   4KB   accelerator regs
S3  SoC_CTRL  0x3000_0000 – 0x3000_0FFF   4KB
S4  CLINT     0x4000_0000 – 0x4000_FFFF  64KB
S5  UART      0x5000_0000 – 0x5000_0FFF   4KB
S9  PLIC      0x5004_0000 – 0x5004_0FFF   4KB
S11 DMA_CTRL  0x6001_0000 – 0x6001_0FFF   4KB
S6/S7/S8/S10  stub → DECERR

Linker constraints (verified vs script v2.8):
  __bss_end   <= 0x10003000  (ASSERT trong linker script)
  __stack_top == 0x10004000  (ASSERT trong linker script)
  BSS tối đa  =  12KB - sizeof(.data) - sizeof(.bss)
  g_stream (AsconStream_t, 436B = 0x1B4) đặt tại 0x10000000 (.bss)
  DmemLayout_t tại DMEM_BASE = 0x100001C0 (sau g_stream + 12B gap)

════════════════════════════════════════════════════════════════════
PHẦN 3 — REGISTER MAP ĐẦY ĐỦ
════════════════════════════════════════════════════════════════════

── S2 ASCON (BASE = 0x2000_0000) ──────────────────────────────────
Offset  Abs addr      Name      RW  Mô tả
0x000   0x2000_0000   MODE       W  0x01 = ENCRYPT
0x004   0x2000_0004   STATUS     R  bit0=CORE_BUSY, bit1=CORE_DONE,
                                    bit2=DMA_BUSY,  bit3=DMA_DONE,
                                    bit4=ERROR,     bit5=DMA_ERROR
0x008   0x2000_0008   _pad0      —  reserved
0x00C   0x2000_000C   IRQ_EN     W  bit1=1 → enable DMA_DONE IRQ
0x010   0x2000_0010   KEY_0      W  Key[127:96]
0x014   0x2000_0014   KEY_1      W  Key[95:64]
0x018   0x2000_0018   KEY_2      W  Key[63:32]
0x01C   0x2000_001C   KEY_3      W  Key[31:0]
0x020   0x2000_0020   CTRL       W  0x02=SOFT_RST, 0x01=START(no DMA),
                                    0x05=DMA_START(bit0|bit2)
0x024   0x2000_0024   NONCE_0    W  Nonce[127:96]
0x028   0x2000_0028   NONCE_1    W  Nonce[95:64]
0x02C   0x2000_002C   NONCE_2    W  Nonce[63:32]
0x030   0x2000_0030   NONCE_3    W  Nonce[31:0]
0x034   0x2000_0034   PTEXT_0    W  Plaintext[127:96] (word đầu khi BLOCK_SIZE=4)
0x038   0x2000_0038   PTEXT_1    W  Plaintext[95:64]  (reserved khi BLOCK_SIZE=4)
0x03C   0x2000_003C   DATA_LEN   W  byte count plaintext, mask 0xFF, dùng 4
0x040   0x2000_0040   CTEXT_0    R  Ciphertext[127:96]
0x044   0x2000_0044   CTEXT_1    R  Ciphertext[95:64]
0x048   0x2000_0048   TAG_0      R  Auth tag[127:96]  valid sau DMA_DONE
0x04C   0x2000_004C   TAG_1      R  Auth tag[95:64]
0x050   0x2000_0050   TAG_2      R  Auth tag[63:32]
0x054   0x2000_0054   TAG_3      R  Auth tag[31:0]
0x100   0x2000_0100   DMA_SRC    W  DMEM addr nguồn plaintext
0x104   0x2000_0104   DMA_DST    W  DMEM addr đích ciphertext
0x108   0x2000_0108   DMA_LEN    W  PHẢI = 24 (8B ctext + 16B tag)
                                    KHÔNG phải 4 (input len) — đây là
                                    bug cốt lõi nếu ghi sai

CTRL semantics (verified vs RTL ascon_axi_slave.v):
  0x02 = SOFT_RST : clear sticky status_done/dma_done/error
                    PHẢI ghi trước IRQ_EN để tránh spurious IRQ
  0x01 = START    : bit0=1, bit2=0 → core chạy không DMA (dùng cho T2)
  0x05 = DMA_START: bit0=1, bit2=1 → RTL skip core_start trực tiếp,
                    set dma_start=1, DMA FSM tự kick ASCON core

── S1 DMEM layout tại runtime (verified vs dmem_layout.h) ─────────
g_stream (AsconStream_t, 436B):
  0x1000_0000 – 0x1000_01B3

DmemLayout_t (DMEM_BASE = 0x1000_01C0):
  +0x0000 → 0x1000_01C0  PTEXT_0    CPU ghi plaintext, DMA đọc
  +0x0004 → 0x1000_01C4  PTEXT_1    reserved
  +0x0008                 _pad0[2]
  +0x0010 → 0x1000_01D0  CTEXT_0    DMA ghi sau DONE  ← M2 AW addr
  +0x0014 → 0x1000_01D4  CTEXT_1
  +0x0018 → 0x1000_01D8  TAG_0
  +0x001C → 0x1000_01DC  TAG_1
  +0x0020 → 0x1000_01E0  TAG_2
  +0x0024 → 0x1000_01E4  TAG_3
  +0x0030 → 0x1000_01F0  KEY_0..3   debug snapshot
  +0x0040 → 0x1000_0200  NONCE_0..3 debug snapshot
  +0x0050 → 0x1000_0210  DATALEN
  +0x0054 → 0x1000_0214  STATUS
  +0x0058 → 0x1000_0218  RETCODE    0=OK, -1=err, -2=timeout, -3=rst_fail

DMA constants (dùng trong firmware và assert TB):
  DMEM_DMA_SRC_ADDR    = 0x1000_01C0   PTEXT_0
  DMEM_DMA_OUTPUT_ADDR = 0x1000_01D0   CTEXT_0
  DMEM_DMA_INPUT_LEN   = 4             plaintext bytes
  DMEM_DMA_OUTPUT_LEN  = 24            ctext(8) + tag(16) ← ghi vào DMA_LEN

── S5 UART (BASE = 0x5000_0000) ───────────────────────────────────
0x00  TX_DATA   W  ghi trực tiếp, KHÔNG poll STATUS (gây watchdog)
0x08  STATUS    R  bit3=TX_FULL  — KHÔNG đọc, dùng delay thay thế
0x0C  CTRL      W  0x1 = tx_irq_en
0x10  BAUD_DIV  W  867 = 115200 baud @ 100MHz

── S9 PLIC (BASE = 0x5004_0000) ───────────────────────────────────
0x000+4*n  PRIORITY[n]  W  n=0..31, value=1 để enable
0x080      PENDING       R  bitmask
0x100      ENABLE        W  bitmask enable hart0
0x200      THRESHOLD     W  0 = accept all
0x204      CLAIM         R  claim → trả source_id
0x204      COMPLETE      W  ghi source_id → done
ASCON = source 8 → PLIC_PRIORITY(8)=1, ENABLE bit8=1

── TB wire taps (soc_top internal, dùng trong assertion) ───────────
soc.u_ascon.u_slave.reg_dma_len      → ascon_dma_len_r
soc.u_ascon.u_slave.reg_dma_dst      → ascon_dma_dst_r
soc.u_ascon.u_slave.reg_dma_src      → ascon_dma_src_r
soc.u_ascon.u_slave.status_dma_done  → ascon_dma_done_st
soc.u_ascon.u_slave.core_soft_rst    → ascon_soft_rst
soc.u_ascon.u_slave.reg_tag_0..3     → ascon_reg_tag0..3
soc.u_ascon.u_slave.reg_ctext_0..1   → ascon_reg_ctext0..1
soc.ascon_irq                         → ascon_irq_wire
soc.external_irq                      → plic_meip
soc.m2_awaddr / m2_awvalid / m2_awready
soc.s2_awaddr / s2_awvalid / s2_awready / s2_bresp
soc.s1_awaddr / s1_wdata  / s1_wvalid / s1_wready

════════════════════════════════════════════════════════════════════
PHẦN 4 — MÔ TẢ 4 TẦNG: MỤC TIÊU, FILE CẦN, KHÔNG CẦN
════════════════════════════════════════════════════════════════════

══ TẦNG 1: fw_t1.c + tb_t1.v ══════════════════════════════════════
Mục tiêu: xác nhận crossbar route đúng S2, ASCON slave nhận write
          không có DECERR, DMA_LEN được ghi = 24 đúng.

fw_t1.c — CẦN:
  ascon_regs.h, dmem_layout.h, uart_drv.h
  KHÔNG cần: plic_drv.h, ascon_stream.h
  PHẢI có: trap_handler stub (linker crt0 yêu cầu symbol này)

  Logic:
    trap_handler() stub: __attribute__((interrupt("machine"), aligned(4)))
                         void trap_handler(void) { for(;;) {} }
    main():
      uart_init()
      ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST)
      ASCON_WRITE(ASCON->IRQ_EN, 0)
      ASCON_WRITE(ASCON->MODE, MODE_ENCRYPT)
      Ghi KEY_0..3, NONCE_0..3, PTEXT_0, DATA_LEN=4
      Ghi DMA_SRC=DMEM_DMA_SRC_ADDR, DMA_DST=DMEM_DMA_OUTPUT_ADDR,
          DMA_LEN=DMEM_DMA_OUTPUT_LEN  (= 24)
      uint32_t st = ascon_read_status()
      if (st & STATUS_ANY_ERROR) → uart_puts("T1:FAIL:ERR\r\n"), return 1
      uart_puts("T1:OK\r\n")
      return 0

tb_t1.v — TIMEOUT = 3000 cy, DMEM_DUMP_BASE = 32'h100001C0
  IMEM_INIT_FILE = "t1.hex"
  Reset sequence: POR 1040cy + ext_rst_n (giữ nguyên từ TB v6)
  Assertions:
    A1: mỗi s2_awvalid&&s2_awready → log offset (addr - 0x20000000)
    A2: nếu s2_bresp==2'b11 → [FAIL-T1] DECERR
    A3: khi ascon_dma_len_r thay đổi → nếu ==24 PASS, ==4 FAIL
    A4: UART decode "T1:OK" → print "=== T1 PASS ==="
  Không cần: assertion IRQ, DMA FSM, golden check

══ TẦNG 2: fw_t2.c + tb_t2.v ══════════════════════════════════════
Mục tiêu: xác nhận ASCON core algorithm ra đúng CTEXT/TAG
          với key/nonce/data đã biết — so với golden reference.
          Dùng CTRL=0x01 (START không DMA), poll STATUS.DONE.

fw_t2.c — CẦN:
  ascon_regs.h, uart_drv.h
  KHÔNG cần: plic_drv.h, ascon_stream.h, dmem_layout.h
  PHẢI có: trap_handler stub

  Logic:
    trap_handler() stub: __attribute__((interrupt("machine"), aligned(4)))
                         void trap_handler(void) { for(;;) {} }
    main():
      uart_init()
      ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST)
      ASCON_WRITE(ASCON->IRQ_EN, 0)
      ASCON_WRITE(ASCON->MODE, MODE_ENCRYPT)
      KEY_0..3  = {0x00112233, 0x44556677, 0x8899AABB, 0xCCDDEEFF}
      NONCE_0..3 = {0xDEADBEEF, 0xCAFEBABE, 0x01234567, 0x89ABCDEF}
      PTEXT_0 = 0x48656C6C ("Hell"), DATA_LEN = 4
      ASCON_WRITE(ASCON->CTRL, 0x01u)   ← START không DMA
      fence
      Poll: while(!(ascon_read_status() & STATUS_DONE) && timeout--)
      if timeout==0 → uart_puts("T2:FAIL:TIMEOUT\r\n"), return 1
      if STATUS_ANY_ERROR → uart_puts("T2:FAIL:ERR\r\n"), return 1
      Đọc CTEXT_0, CTEXT_1, TAG_0..3
      uart_puts("T2:C:"); uart_puthex32(c0); uart_puthex32(c1)
      uart_puts(":T:");   uart_puthex32 x4
      uart_puts("\r\nT2:OK\r\n")
      return 0

tb_t2.v — TIMEOUT = 5000 cy
  IMEM_INIT_FILE = "t2.hex"
  Golden parameters (từ ascon-c ref, key/nonce/plaintext như trên):
    parameter EXP_CTEXT_0 = 32'hXXXXXXXX  ← điền sau khi chạy ref
    parameter EXP_CTEXT_1 = 32'hXXXXXXXX
    parameter EXP_TAG_0   = 32'hXXXXXXXX
    parameter EXP_TAG_1   = 32'hXXXXXXXX
    parameter EXP_TAG_2   = 32'hXXXXXXXX
    parameter EXP_TAG_3   = 32'hXXXXXXXX
  Assertions:
    A1: khi ascon_core_done posedge → so sánh EXP vs ascon_reg_ctext/tag
        nếu khác → [FAIL-T2] CTEXT_0 exp=... got=...
    A2: xác nhận CTRL=0x01 write → không có DMA_START (bit2=0)
    A3: UART decode "T2:OK" → print "=== T2 PASS ==="

══ TẦNG 3: fw_t3.c + tb_t3.v ══════════════════════════════════════
Mục tiêu: xác nhận toàn bộ DMA path + IRQ path cho đúng 1 block.
          CTRL=0x05 (DMA_START), ISR đọc kết quả từ DMEM, set done.

fw_t3.c — CẦN:
  ascon_regs.h, dmem_layout.h, plic_drv.h, uart_drv.h, ascon_stream.h
  ĐÂY LÀ main.c với #define N_BLOCKS 1u — thay đổi DUY NHẤT so với T4
  Giữ nguyên: g_stream, ascon_isr(), trap_handler(), main() đầy đủ

  trap_handler() đầy đủ (KHÔNG phải stub):
    __attribute__((interrupt("machine"), aligned(4)))
    void trap_handler(void) {
        uint32_t mcause;
        __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));
        if ((mcause & 0x80000000u) && ((mcause & 0xFFFFu) == 11u))
            ascon_isr();
    }

  ISR ordering bắt buộc (verified vs RTL):
    1. plic_claim()
    2. ascon_read_status()         ← trước SOFT_RST
    3. đọc CTEXT từ DMEM->CTEXT_0/1
    4. đọc TAG từ ASCON->TAG_0..3  ← trước SOFT_RST
    5. ASCON_WRITE(CTRL, CTRL_SOFT_RST)
    6. plic_complete(src)
    7. nếu còn block: ascon_config_block() + ascon_kick_dma()
       nếu hết: g_stream.done = 1

tb_t3.v — TIMEOUT = 10000 cy, DMEM_DUMP_BASE = 32'h100001C0
  IMEM_INIT_FILE = "t3.hex"
  Assertions (5 assert cốt lõi):
    A1: khi ascon_dma_start posedge →
        ascon_dma_len_r == 24         ? PASS : [FAIL-T3] DMA_LEN sai
        ascon_dma_dst_r == 32'h100001D0 ? PASS : [FAIL-T3] DST sai
        ascon_dma_src_r == 32'h100001C0 ? PASS : [FAIL-T3] SRC sai
    A2: khi m2_awvalid&&m2_awready →
        m2_awaddr[31:16]==16'h1000 ? PASS : [FAIL-T3] M2 ngoài DMEM
    A3: đếm ascon_irq_wire posedge → nếu >1 → [FAIL-T3] spurious IRQ
    A4: đếm plic_meip posedge → phải == 1 sau khi done
    A5: UART decode "T3:OK" → print "=== T3 PASS ==="
  Không cần: multi-block chain check

══ TẦNG 4: fw_t4.c + tb_t4.v ══════════════════════════════════════
Mục tiêu: full streaming 4 blocks, ISR chain, UART output đầy đủ.

fw_t4.c — chính là main.c hiện tại với N_BLOCKS=4, KHÔNG sửa gì
  Đầy đủ: print_results(), mstatus_disable_irq() cuối
  trap_handler() giống T3 (đầy đủ, không phải stub)

tb_t4.v — TB v6.0 hiện tại, SỬA 4 CHỖ:
  (1) `define TIMEOUT        60000      ← từ 4000
  (2) `define DMEM_DUMP_BASE 32'h100001C0  ← từ 32'h10000000
  (3) Comment/xóa dòng $monitor (dòng 1472 TB v6) — spam quá nhiều
  (4) Cuối initial begin / wait(program_done):
        if (ascon_irq_cnt == 4)
            $display("=== T4 IRQ COUNT PASS: 4 IRQs ===");
        else
            $display("=== T4 IRQ COUNT FAIL: exp=4 got=%0d ===", ascon_irq_cnt);
        // kiểm tra uart_rx_buf chứa "OK n=" → PASS

════════════════════════════════════════════════════════════════════
PHẦN 5 — QUY TẮC VIẾT CODE (BẮT BUỘC VỚI MỌI TẦNG)
════════════════════════════════════════════════════════════════════

Firmware:
  1. Mọi MMIO write dùng macro ASCON_WRITE(reg, val) — có barrier
  2. Sau nhóm write MMIO: __asm__ volatile ("fence" ::: "memory")
  3. Hàm MMIO-critical: __attribute__((optimize("O0"), noinline))
  4. ISR trap_handler: __attribute__((interrupt("machine"), aligned(4)))
  5. Biến shared CPU↔ISR: volatile
  6. Không malloc, printf, stdlib — bare-metal
  7. Luôn compile với -O 0 (đã enforce trong tên gọi script)
  8. Đọc TAG và CTEXT trong ISR TRƯỚC khi gọi SOFT_RST
  9. SOFT_RST TRƯỚC plic_complete() — deassert IRQ trước khi PLIC re-enable
  10. Trap handler decode mcause: bit31=1 (interrupt) + bits[15:0]=11 (MEIP)
  11. MỌI fw_tN.c phải define trap_handler() — script crt0 luôn emit
      csrw mtvec, trap_handler trước main(), nếu thiếu → linker error
  12. T1, T2 không dùng IRQ → dùng stub for(;;){}
      T3, T4 dùng IRQ → trap_handler đầy đủ decode mcause

Testbench:
  1. Kế thừa toàn bộ wire tap từ TB v6.0 — chỉ thêm assertion block mới
  2. Mỗi assertion dùng $display với prefix [FAIL-TN] hoặc [PASS-TN]
  3. Không thêm $monitor mới — đã có sẵn đủ log trong TB v6
  4. IMEM_INIT_FILE phải trỏ đúng tên hex của tầng đó
  5. Assertion DMA_LEN: check tại posedge ascon_dma_start,
     không check trước (giá trị chưa latch)
  6. Reset sequence: POR 1040cy sau đó deassert ext_rst_n (giữ từ TB v6)

════════════════════════════════════════════════════════════════════
PHẦN 6 — TEST DATA CỐ ĐỊNH (DÙNG CHO MỌI TẦNG)
════════════════════════════════════════════════════════════════════

Key    : {0x00112233, 0x44556677, 0x8899AABB, 0xCCDDEEFF}
Nonce  : {0xDEADBEEF, 0xCAFEBABE, 0x01234567, 0x89ABCDEF}
Block0 : 0x48656C6C  ("Hell", 4 bytes)
Block1 : 0x426C6B31  ("Blk1")
Block2 : 0x426C6B32  ("Blk2")
Block3 : 0x426C6B33  ("Blk3")

UART output kỳ vọng cuối T4:
  "OK n=04\r\n"
  "B00 C:<ctext0><ctext1> T:<t0><t1><t2><t3>\r\n"
  ... (4 dòng)

════════════════════════════════════════════════════════════════════
PHẦN 7 — DEPENDENCY VÀ CÁCH DEBUG
════════════════════════════════════════════════════════════════════

Thứ tự bắt buộc: T1 pass → T2 pass → T3 pass → T4
Mỗi tầng fail → dừng, không chạy tầng tiếp.

Bảng nguyên nhân:
  T1 FAIL → crossbar decode sai, ASCON_BASE sai, S2 slave lỗi,
             hoặc trap_handler thiếu → linker error khi compile
  T2 FAIL → ASCON core algorithm sai (key/nonce/data/CTRL sai)
  T3 FAIL:
    DMA_LEN=4    → bug FIX-1 (DMEM_DMA_OUTPUT_LEN chưa dùng đúng)
    DST sai      → DMEM_DMA_OUTPUT_ADDR tính sai
    M2 ngoài DMEM → DMA_DST trỏ sai vùng nhớ
    IRQ>1        → bug FIX-2 (SOFT_RST thiếu trước IRQ_EN)
  T4 FAIL:
    IRQ≠4        → ISR không kick đủ block tiếp
    UART sai     → print_results() lỗi hoặc WFI không thoát
  Linker error "__bss_end > 0x10003000":
    → biến global quá lớn; xem -v output của script để check BSS size

════════════════════════════════════════════════════════════════════
PHẦN 8 — YÊU CẦU KHI DÙNG PROMPT NÀY
════════════════════════════════════════════════════════════════════

Khi dùng prompt này, chỉ cần thêm vào cuối:
  "Viết fw_t1.c + tb_t1.v"
  hoặc "Viết fw_t2.c + tb_t2.v"
  hoặc "Viết fw_t3.c + tb_t3.v"
  hoặc "Viết fw_t4.c + tb_t4.v (sửa TB v6)"

AI sẽ viết đúng 2 file cho tầng đó:
  - fw_tN.c: file C hoàn chỉnh, compile được ngay với compile_c_to_hex.sh
             LUÔN có trap_handler() dù T1/T2 không dùng IRQ
  - tb_tN.v: file Verilog hoàn chỉnh, chạy được với iverilog + vvp
  - Không viết file .h vì đã có sẵn và không được sửa
  - Không viết soc_top.v hay các sub-module khác
  - Không viết compile_c_to_hex.sh — script đã hoàn chỉnh ở v2.8