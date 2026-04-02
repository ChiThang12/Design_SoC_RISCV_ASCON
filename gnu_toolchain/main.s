	.file	"main.c"
	.option nopic
	.option norelax
	.attribute arch, "rv32i2p1_m2p0_zicsr2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
# GNU C17 (13.2.0-11ubuntu1+12) version 13.2.0 (riscv64-unknown-elf)
#	compiled by GNU C version 13.2.0, GMP version 6.3.0, MPFR version 4.2.1, MPC version 1.3.1, isl version isl-0.26-GMP

# GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
# options passed: -mabi=ilp32 -mno-relax -misa-spec=20191213 -march=rv32im_zicsr -O0 -ffreestanding
	.text
	.align	2
	.type	ascon_read_status, @function
ascon_read_status:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
# ascon_regs.h:161:     uint32_t s = ASCON->STATUS;
	li	a5,536870912		# _1,
# ascon_regs.h:161:     uint32_t s = ASCON->STATUS;
	lw	a5,4(a5)		# tmp137, _1->STATUS
	sw	a5,-20(s0)	# tmp137, s
# ascon_regs.h:162:     __asm__ volatile ("" ::: "memory");
# ascon_regs.h:163:     return s;
	lw	a5,-20(s0)		# _5, s
# ascon_regs.h:164: }
	mv	a0,a5	#, <retval>
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	ascon_read_status, .-ascon_read_status
	.align	2
	.type	plic_init_ascon, @function
plic_init_ascon:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# plic_drv.h:35:     PLIC_PRIORITY(PLIC_SRC_ASCON) = 1u;
	li	a5,1342439424		# tmp137,
	addi	a5,a5,32	#, _1, tmp137
# plic_drv.h:35:     PLIC_PRIORITY(PLIC_SRC_ASCON) = 1u;
	li	a4,1		# tmp138,
	sw	a4,0(a5)	# tmp138, *_1
# plic_drv.h:38:     PLIC_ENABLE = (1u << PLIC_SRC_ASCON);
	li	a5,1342439424		# tmp139,
	addi	a5,a5,256	#, _2, tmp139
# plic_drv.h:38:     PLIC_ENABLE = (1u << PLIC_SRC_ASCON);
	li	a4,256		# tmp140,
	sw	a4,0(a5)	# tmp140, *_2
# plic_drv.h:41:     PLIC_THRESHOLD = 0u;
	li	a5,1342439424		# tmp141,
	addi	a5,a5,512	#, _3, tmp141
# plic_drv.h:41:     PLIC_THRESHOLD = 0u;
	sw	zero,0(a5)	#, *_3
# plic_drv.h:43:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 43 "plic_drv.h" 1
	fence w,w
# 0 "" 2
# plic_drv.h:44: }
 #NO_APP
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	plic_init_ascon, .-plic_init_ascon
	.align	2
	.type	plic_claim, @function
plic_claim:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# plic_drv.h:49:     return PLIC_CLAIM;
	li	a5,1342439424		# tmp137,
	addi	a5,a5,516	#, _1, tmp137
	lw	a5,0(a5)		# _3, *_1
# plic_drv.h:50: }
	mv	a0,a5	#, <retval>
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	plic_claim, .-plic_claim
	.align	2
	.type	plic_complete, @function
plic_complete:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# source_id, source_id
# plic_drv.h:55:     PLIC_COMPLETE = source_id;
	li	a5,1342439424		# tmp135,
	addi	a5,a5,516	#, _1, tmp135
# plic_drv.h:55:     PLIC_COMPLETE = source_id;
	lw	a4,-20(s0)		# tmp136, source_id
	sw	a4,0(a5)	# tmp136, *_1
# plic_drv.h:56:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 56 "plic_drv.h" 1
	fence w,w
# 0 "" 2
# plic_drv.h:57: }
 #NO_APP
	nop	
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	plic_complete, .-plic_complete
	.align	2
	.type	mie_enable_external, @function
mie_enable_external:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# plic_drv.h:63:     __asm__ volatile (
 #APP
# 63 "plic_drv.h" 1
	li   t0, 0x800
csrs mie, t0

# 0 "" 2
# plic_drv.h:68: }
 #NO_APP
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	mie_enable_external, .-mie_enable_external
	.align	2
	.type	mstatus_enable_irq, @function
mstatus_enable_irq:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# plic_drv.h:73:     __asm__ volatile (
 #APP
# 73 "plic_drv.h" 1
	li   t0, 0x8
csrs mstatus, t0

# 0 "" 2
# plic_drv.h:78: }
 #NO_APP
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	mstatus_enable_irq, .-mstatus_enable_irq
	.align	2
	.type	mstatus_disable_irq, @function
mstatus_disable_irq:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# plic_drv.h:82:     __asm__ volatile (
 #APP
# 82 "plic_drv.h" 1
	li   t0, 0x8
csrc mstatus, t0

# 0 "" 2
# plic_drv.h:87: }
 #NO_APP
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	mstatus_disable_irq, .-mstatus_disable_irq
	.align	2
	.type	ascon_feed_block_cpu, @function
ascon_feed_block_cpu:
	addi	sp,sp,-48	#,,
	sw	s0,44(sp)	#,
	addi	s0,sp,48	#,,
	sw	a0,-36(s0)	# block_idx, block_idx
# ascon_stream.h:75:     const uint8_t *src = g_stream.ptext + block_idx * ASCON_BLOCK_SIZE;
	lui	a5,%hi(g_stream)	# tmp138,
	addi	a5,a5,%lo(g_stream)	# tmp139, tmp138,
	lw	a4,0(a5)		# _1, g_stream.ptext
# ascon_stream.h:75:     const uint8_t *src = g_stream.ptext + block_idx * ASCON_BLOCK_SIZE;
	lw	a5,-36(s0)		# tmp140, block_idx
	slli	a5,a5,2	#, _2, tmp140
# ascon_stream.h:75:     const uint8_t *src = g_stream.ptext + block_idx * ASCON_BLOCK_SIZE;
	add	a5,a4,a5	# _2, tmp141, _1
	sw	a5,-20(s0)	# tmp141, src
# ascon_stream.h:79:     __builtin_memcpy(&w0, src, 4);
	addi	a5,s0,-24	#, tmp142,
	lw	a4,-20(s0)		# tmp143, src
	lbu	a3,0(a4)	# tmp145, MEM <char[1:4]> [(void *)src_7]
	mv	a1,a3	# tmp144, tmp145
	lbu	a3,1(a4)	# tmp147, MEM <char[1:4]> [(void *)src_7]
	mv	a2,a3	# tmp146, tmp147
	lbu	a3,2(a4)	# tmp149, MEM <char[1:4]> [(void *)src_7]
	lbu	a4,3(a4)	# tmp151, MEM <char[1:4]> [(void *)src_7]
	sb	a1,0(a5)	# tmp144, MEM <char[1:4]> [(void *)&w0]
	sb	a2,1(a5)	# tmp146, MEM <char[1:4]> [(void *)&w0]
	sb	a3,2(a5)	# tmp148, MEM <char[1:4]> [(void *)&w0]
	sb	a4,3(a5)	# tmp150, MEM <char[1:4]> [(void *)&w0]
# ascon_stream.h:81:     DMEM->PTEXT_0 = w0;
	li	a5,268435456		# tmp152,
	addi	a5,a5,448	#, _3, tmp152
# ascon_stream.h:81:     DMEM->PTEXT_0 = w0;
	lw	a4,-24(s0)		# w0.0_4, w0
	sw	a4,0(a5)	# w0.0_4, _3->PTEXT_0
# ascon_stream.h:87:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 87 "ascon_stream.h" 1
	fence	
# 0 "" 2
# ascon_stream.h:88: }
 #NO_APP
	nop	
	lw	s0,44(sp)		#,
	addi	sp,sp,48	#,,
	jr	ra		#
	.size	ascon_feed_block_cpu, .-ascon_feed_block_cpu
	.align	2
	.type	ascon_config_block, @function
ascon_config_block:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# ascon_stream.h:96:     ASCON_WRITE(ASCON->MODE,    MODE_ENCRYPT);
	li	a5,536870912		# _1,
	li	a4,1		# tmp155,
	sw	a4,0(a5)	# tmp155, _1->MODE
# ascon_stream.h:97:     ASCON_WRITE(ASCON->IRQ_EN,  IRQ_EN_DMA_DONE);  /* FIXED: Struct updated to match RTL */
	li	a5,536870912		# _2,
	li	a4,2		# tmp156,
	sw	a4,12(a5)	# tmp156, _2->IRQ_EN
# ascon_stream.h:98:     ASCON_WRITE(ASCON->KEY_0,   g_stream.key[0]);
	li	a5,536870912		# _3,
	lui	a4,%hi(g_stream)	# tmp157,
	addi	a4,a4,%lo(g_stream)	# tmp158, tmp157,
	lw	a4,8(a4)		# _4, g_stream.key[0]
	sw	a4,16(a5)	# _4, _3->KEY_0
# ascon_stream.h:99:     ASCON_WRITE(ASCON->KEY_1,   g_stream.key[1]);
	li	a5,536870912		# _5,
	lui	a4,%hi(g_stream)	# tmp159,
	addi	a4,a4,%lo(g_stream)	# tmp160, tmp159,
	lw	a4,12(a4)		# _6, g_stream.key[1]
	sw	a4,20(a5)	# _6, _5->KEY_1
# ascon_stream.h:100:     ASCON_WRITE(ASCON->KEY_2,   g_stream.key[2]);
	li	a5,536870912		# _7,
	lui	a4,%hi(g_stream)	# tmp161,
	addi	a4,a4,%lo(g_stream)	# tmp162, tmp161,
	lw	a4,16(a4)		# _8, g_stream.key[2]
	sw	a4,24(a5)	# _8, _7->KEY_2
# ascon_stream.h:101:     ASCON_WRITE(ASCON->KEY_3,   g_stream.key[3]);
	li	a5,536870912		# _9,
	lui	a4,%hi(g_stream)	# tmp163,
	addi	a4,a4,%lo(g_stream)	# tmp164, tmp163,
	lw	a4,20(a4)		# _10, g_stream.key[3]
	sw	a4,28(a5)	# _10, _9->KEY_3
# ascon_stream.h:102:     ASCON_WRITE(ASCON->NONCE_0, g_stream.nonce[0]);
	li	a5,536870912		# _11,
	lui	a4,%hi(g_stream)	# tmp165,
	addi	a4,a4,%lo(g_stream)	# tmp166, tmp165,
	lw	a4,24(a4)		# _12, g_stream.nonce[0]
	sw	a4,36(a5)	# _12, _11->NONCE_0
# ascon_stream.h:103:     ASCON_WRITE(ASCON->NONCE_1, g_stream.nonce[1]);
	li	a5,536870912		# _13,
	lui	a4,%hi(g_stream)	# tmp167,
	addi	a4,a4,%lo(g_stream)	# tmp168, tmp167,
	lw	a4,28(a4)		# _14, g_stream.nonce[1]
	sw	a4,40(a5)	# _14, _13->NONCE_1
# ascon_stream.h:104:     ASCON_WRITE(ASCON->NONCE_2, g_stream.nonce[2]);
	li	a5,536870912		# _15,
	lui	a4,%hi(g_stream)	# tmp169,
	addi	a4,a4,%lo(g_stream)	# tmp170, tmp169,
	lw	a4,32(a4)		# _16, g_stream.nonce[2]
	sw	a4,44(a5)	# _16, _15->NONCE_2
# ascon_stream.h:105:     ASCON_WRITE(ASCON->NONCE_3, g_stream.nonce[3]);
	li	a5,536870912		# _17,
	lui	a4,%hi(g_stream)	# tmp171,
	addi	a4,a4,%lo(g_stream)	# tmp172, tmp171,
	lw	a4,36(a4)		# _18, g_stream.nonce[3]
	sw	a4,48(a5)	# _18, _17->NONCE_3
# ascon_stream.h:106:     ASCON_WRITE(ASCON->DATA_LEN, (uint32_t)(ASCON_BLOCK_SIZE & DATA_LEN_MASK));
	li	a5,536870912		# _19,
	li	a4,4		# tmp173,
	sw	a4,60(a5)	# tmp173, _19->DATA_LEN
# ascon_stream.h:108:     return 0;
	li	a5,0		# _43,
# ascon_stream.h:109: }
	mv	a0,a5	#, <retval>
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	ascon_config_block, .-ascon_config_block
	.align	2
	.type	ascon_kick_dma, @function
ascon_kick_dma:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# ascon_stream.h:116:     ASCON_WRITE(ASCON->DMA_SRC, DMEM_DMA_SRC_ADDR);     /* PTEXT_0 */
	li	a5,536870912		# _1,
	li	a4,268435456		# tmp139,
	addi	a4,a4,448	#, tmp138, tmp139
	sw	a4,256(a5)	# tmp138, _1->DMA_SRC
# ascon_stream.h:117:     ASCON_WRITE(ASCON->DMA_DST, DMEM_DMA_OUTPUT_ADDR);  /* CTEXT_0 */
	li	a5,536870912		# _2,
	li	a4,268435456		# tmp141,
	addi	a4,a4,464	#, tmp140, tmp141
	sw	a4,260(a5)	# tmp140, _2->DMA_DST
# ascon_stream.h:118:     ASCON_WRITE(ASCON->DMA_LEN, DMEM_DMA_INPUT_LEN);    /* 8 bytes */
	li	a5,536870912		# _3,
	li	a4,4		# tmp142,
	sw	a4,264(a5)	# tmp142, _3->DMA_LEN
# ascon_stream.h:121:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 121 "ascon_stream.h" 1
	fence w,w
# 0 "" 2
# ascon_stream.h:122:     __asm__ volatile ("fence w,w" ::: "memory");
# 122 "ascon_stream.h" 1
	fence w,w
# 0 "" 2
# ascon_stream.h:123:     __asm__ volatile ("fence w,w" ::: "memory");
# 123 "ascon_stream.h" 1
	fence w,w
# 0 "" 2
# ascon_stream.h:124:     __asm__ volatile (
# 124 "ascon_stream.h" 1
	nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# ascon_stream.h:131:     __asm__ volatile ("fence" ::: "memory");
# 131 "ascon_stream.h" 1
	fence	
# 0 "" 2
# ascon_stream.h:133:     ASCON_WRITE(ASCON->CTRL, CTRL_DMA_START);
 #NO_APP
	li	a5,536870912		# _4,
	li	a4,5		# tmp143,
	sw	a4,32(a5)	# tmp143, _4->CTRL
# ascon_stream.h:134: }
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	ascon_kick_dma, .-ascon_kick_dma
	.align	2
	.type	ascon_stream_start, @function
ascon_stream_start:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
# ascon_stream.h:145:     g_stream.cur_block = 0u;
	lui	a5,%hi(g_stream)	# tmp136,
	addi	a5,a5,%lo(g_stream)	# tmp137, tmp136,
	sw	zero,424(a5)	#, g_stream.cur_block
# ascon_stream.h:146:     g_stream.done      = 0u;
	lui	a5,%hi(g_stream)	# tmp138,
	addi	a5,a5,%lo(g_stream)	# tmp139, tmp138,
	sw	zero,428(a5)	#, g_stream.done
# ascon_stream.h:147:     g_stream.error     = 0u;
	lui	a5,%hi(g_stream)	# tmp140,
	addi	a5,a5,%lo(g_stream)	# tmp141, tmp140,
	sw	zero,432(a5)	#, g_stream.error
# ascon_stream.h:149:     ascon_feed_block_cpu(0u);
	li	a0,0		#,
	call	ascon_feed_block_cpu		#
# ascon_stream.h:151:     int r = ascon_config_block();
	call	ascon_config_block		#
	sw	a0,-20(s0)	#, r
# ascon_stream.h:152:     if (r != 0) {
	lw	a5,-20(s0)		# tmp142, r
	beq	a5,zero,.L15	#, tmp142,,
# ascon_stream.h:153:         g_stream.error = (uint32_t)(uint32_t)(-3);
	lui	a5,%hi(g_stream)	# tmp143,
	addi	a5,a5,%lo(g_stream)	# tmp144, tmp143,
	li	a4,-3		# tmp145,
	sw	a4,432(a5)	# tmp145, g_stream.error
# ascon_stream.h:154:         g_stream.done  = 1u;
	lui	a5,%hi(g_stream)	# tmp146,
	addi	a5,a5,%lo(g_stream)	# tmp147, tmp146,
	li	a4,1		# tmp148,
	sw	a4,428(a5)	# tmp148, g_stream.done
# ascon_stream.h:155:         return r;
	lw	a5,-20(s0)		# _1, r
	j	.L16		#
.L15:
# ascon_stream.h:158:     ascon_kick_dma();
	call	ascon_kick_dma		#
# ascon_stream.h:159:     return 0;
	li	a5,0		# _1,
.L16:
# ascon_stream.h:160: }
	mv	a0,a5	#, <retval>
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	ascon_stream_start, .-ascon_stream_start
	.align	2
	.type	uart_putc, @function
uart_putc:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
	mv	a5,a0	# tmp136, c
	sb	a5,-17(s0)	# tmp137, c
# main.c:36:     UART_TX = (uint32_t)(uint8_t)c;
	li	a5,1342177280		# _1,
# main.c:36:     UART_TX = (uint32_t)(uint8_t)c;
	lbu	a4,-17(s0)	# _2, c
# main.c:36:     UART_TX = (uint32_t)(uint8_t)c;
	sw	a4,0(a5)	# _2, *_1
# main.c:37:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 37 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:38:     __asm__ volatile (
# 38 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:43: }
 #NO_APP
	nop	
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_putc, .-uart_putc
	.align	2
	.type	uart_puts, @function
uart_puts:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# s, s
# main.c:46: static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
	j	.L19		#
.L20:
# main.c:46: static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
	lw	a5,-20(s0)		# s.1_1, s
	addi	a4,a5,1	#, tmp137, s.1_1
	sw	a4,-20(s0)	# tmp137, s
# main.c:46: static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
	lbu	a5,0(a5)	# _2, *s.1_1
	mv	a0,a5	#, _2
	call	uart_putc		#
.L19:
# main.c:46: static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
	lw	a5,-20(s0)		# tmp138, s
	lbu	a5,0(a5)	# _3, *s_4
	bne	a5,zero,.L20	#, _3,,
# main.c:46: static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
	nop	
	nop	
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_puts, .-uart_puts
	.align	2
	.type	uart_init, @function
uart_init:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# main.c:52:     *((volatile uint32_t *)(UART_BASE + 0x10)) = 867u;
	li	a5,1342177280		# tmp136,
	addi	a5,a5,16	#, _1, tmp136
# main.c:52:     *((volatile uint32_t *)(UART_BASE + 0x10)) = 867u;
	li	a4,867		# tmp137,
	sw	a4,0(a5)	# tmp137, *_1
# main.c:53:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 53 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:56:     *((volatile uint32_t *)(UART_BASE + 0x0C)) = 0x1;
 #NO_APP
	li	a5,1342177280		# tmp138,
	addi	a5,a5,12	#, _2, tmp138
# main.c:56:     *((volatile uint32_t *)(UART_BASE + 0x0C)) = 0x1;
	li	a4,1		# tmp139,
	sw	a4,0(a5)	# tmp139, *_2
# main.c:57:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 57 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:58: }
 #NO_APP
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	uart_init, .-uart_init
	.section	.rodata
	.align	2
.LC0:
	.string	"0123456789ABCDEF"
	.text
	.align	2
	.type	uart_puthex8, @function
uart_puthex8:
	addi	sp,sp,-48	#,,
	sw	ra,44(sp)	#,
	sw	s0,40(sp)	#,
	addi	s0,sp,48	#,,
	mv	a5,a0	# tmp143, v
	sb	a5,-33(s0)	# tmp144, v
# main.c:63:     const char *h = "0123456789ABCDEF";
	lui	a5,%hi(.LC0)	# tmp146,
	addi	a5,a5,%lo(.LC0)	# tmp145, tmp146,
	sw	a5,-20(s0)	# tmp145, h
# main.c:64:     uart_putc(h[(v >> 4) & 0xFu]);
	lbu	a5,-33(s0)	# tmp147, v
	srli	a5,a5,4	#, tmp148, tmp147
	andi	a5,a5,0xff	# _1, tmp148
	andi	a5,a5,15	#, _3, _2
# main.c:64:     uart_putc(h[(v >> 4) & 0xFu]);
	lw	a4,-20(s0)		# tmp149, h
	add	a5,a4,a5	# _3, _4, tmp149
# main.c:64:     uart_putc(h[(v >> 4) & 0xFu]);
	lbu	a5,0(a5)	# _5, *_4
	mv	a0,a5	#, _5
	call	uart_putc		#
# main.c:65:     uart_putc(h[v & 0xFu]);
	lbu	a5,-33(s0)	# _6, v
	andi	a5,a5,15	#, _7, _6
# main.c:65:     uart_putc(h[v & 0xFu]);
	lw	a4,-20(s0)		# tmp150, h
	add	a5,a4,a5	# _7, _8, tmp150
# main.c:65:     uart_putc(h[v & 0xFu]);
	lbu	a5,0(a5)	# _9, *_8
	mv	a0,a5	#, _9
	call	uart_putc		#
# main.c:66: }
	nop	
	lw	ra,44(sp)		#,
	lw	s0,40(sp)		#,
	addi	sp,sp,48	#,,
	jr	ra		#
	.size	uart_puthex8, .-uart_puthex8
	.align	2
	.type	uart_puthex32, @function
uart_puthex32:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# v, v
# main.c:71:     uart_puthex8((uint8_t)(v >> 24));
	lw	a5,-20(s0)		# tmp141, v
	srli	a5,a5,24	#, _1, tmp141
# main.c:71:     uart_puthex8((uint8_t)(v >> 24));
	andi	a5,a5,0xff	# _2, _1
	mv	a0,a5	#, _2
	call	uart_puthex8		#
# main.c:72:     uart_puthex8((uint8_t)(v >> 16));
	lw	a5,-20(s0)		# tmp142, v
	srli	a5,a5,16	#, _3, tmp142
# main.c:72:     uart_puthex8((uint8_t)(v >> 16));
	andi	a5,a5,0xff	# _4, _3
	mv	a0,a5	#, _4
	call	uart_puthex8		#
# main.c:73:     uart_puthex8((uint8_t)(v >>  8));
	lw	a5,-20(s0)		# tmp143, v
	srli	a5,a5,8	#, _5, tmp143
# main.c:73:     uart_puthex8((uint8_t)(v >>  8));
	andi	a5,a5,0xff	# _6, _5
	mv	a0,a5	#, _6
	call	uart_puthex8		#
# main.c:74:     uart_puthex8((uint8_t)(v      ));
	lw	a5,-20(s0)		# tmp144, v
	andi	a5,a5,0xff	# _7, tmp144
	mv	a0,a5	#, _7
	call	uart_puthex8		#
# main.c:75: }
	nop	
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_puthex32, .-uart_puthex32
	.section	.rodata
	.align	2
	.type	g_plaintext, @object
	.size	g_plaintext, 16
g_plaintext:
	.ascii	"HellBlk1Blk2Blk3"
	.align	2
	.type	g_key, @object
	.size	g_key, 16
g_key:
	.word	1122867
	.word	1146447479
	.word	-2003195205
	.word	-857870593
	.align	2
	.type	g_nonce, @object
	.size	g_nonce, 16
g_nonce:
	.word	-559038737
	.word	-889275714
	.word	19088743
	.word	-1985229329
	.globl	g_stream
	.bss
	.align	2
	.type	g_stream, @object
	.size	g_stream, 436
g_stream:
	.zero	436
	.text
	.align	2
	.globl	ascon_isr
	.type	ascon_isr, @function
ascon_isr:
	addi	sp,sp,-48	#,,
	sw	ra,44(sp)	#,
	sw	s0,40(sp)	#,
	addi	s0,sp,48	#,,
# main.c:129:     uint32_t src = plic_claim();
	call	plic_claim		#
	sw	a0,-20(s0)	#, src
# main.c:132:     if (src != PLIC_SRC_ASCON) {
	lw	a4,-20(s0)		# tmp151, src
	li	a5,8		# tmp152,
	beq	a4,a5,.L25	#, tmp151, tmp152,
# main.c:133:         if (src != 0u) plic_complete(src);
	lw	a5,-20(s0)		# tmp153, src
	beq	a5,zero,.L32	#, tmp153,,
# main.c:133:         if (src != 0u) plic_complete(src);
	lw	a0,-20(s0)		#, src
	call	plic_complete		#
# main.c:134:         return;
	j	.L32		#
.L25:
# main.c:138:     uint32_t st = ascon_read_status();
	call	ascon_read_status		#
	sw	a0,-24(s0)	#, st
# main.c:141:     if (st & STATUS_ANY_ERROR) {
	lw	a5,-24(s0)		# tmp154, st
	andi	a5,a5,48	#, _1, tmp154
# main.c:141:     if (st & STATUS_ANY_ERROR) {
	beq	a5,zero,.L28	#, _1,,
# main.c:142:         g_stream.error = st;
	lui	a5,%hi(g_stream)	# tmp155,
	addi	a5,a5,%lo(g_stream)	# tmp156, tmp155,
	lw	a4,-24(s0)		# tmp157, st
	sw	a4,432(a5)	# tmp157, g_stream.error
# main.c:143:         ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
	li	a5,536870912		# _2,
	li	a4,2		# tmp158,
	sw	a4,32(a5)	# tmp158, _2->CTRL
# main.c:144:         plic_complete(src);
	lw	a0,-20(s0)		#, src
	call	plic_complete		#
# main.c:145:         g_stream.done = 1u;
	lui	a5,%hi(g_stream)	# tmp159,
	addi	a5,a5,%lo(g_stream)	# tmp160, tmp159,
	li	a4,1		# tmp161,
	sw	a4,428(a5)	# tmp161, g_stream.done
# main.c:146:         return;
	j	.L24		#
.L28:
# main.c:150:     uint32_t blk = g_stream.cur_block;
	lui	a5,%hi(g_stream)	# tmp162,
	addi	a5,a5,%lo(g_stream)	# tmp163, tmp162,
	lw	a5,424(a5)		# tmp164, g_stream.cur_block
	sw	a5,-28(s0)	# tmp164, blk
# main.c:151:     if (blk < STREAM_MAX_BLOCKS) {
	lw	a4,-28(s0)		# tmp165, blk
	li	a5,15		# tmp166,
	bgtu	a4,a5,.L29	#, tmp165, tmp166,
# main.c:152:         AsconBlockOut_t *out = &g_stream.out[blk];
	lw	a4,-28(s0)		# tmp167, blk
	mv	a5,a4	# tmp168, tmp167
	slli	a5,a5,1	#, tmp169, tmp168
	add	a5,a5,a4	# tmp167, tmp168, tmp168
	slli	a5,a5,3	#, tmp170, tmp168
	addi	a4,a5,32	#, tmp171, tmp168
	lui	a5,%hi(g_stream)	# tmp174,
	addi	a5,a5,%lo(g_stream)	# tmp173, tmp174,
	add	a5,a4,a5	# tmp173, tmp172, tmp171
	addi	a5,a5,8	#, tmp175, tmp172
	sw	a5,-32(s0)	# tmp175, out
# main.c:158:         out->ctext[0] = DMEM->CTEXT_0;
	li	a5,268435456		# tmp176,
	addi	a5,a5,448	#, _3, tmp176
	lw	a4,16(a5)		# _4, _3->CTEXT_0
# main.c:158:         out->ctext[0] = DMEM->CTEXT_0;
	lw	a5,-32(s0)		# tmp177, out
	sw	a4,0(a5)	# _4, out_27->ctext[0]
# main.c:159:         __asm__ volatile ("" ::: "memory");
# main.c:160:         out->ctext[1] = DMEM->CTEXT_1;
	li	a5,268435456		# tmp178,
	addi	a5,a5,448	#, _5, tmp178
	lw	a4,20(a5)		# _6, _5->CTEXT_1
# main.c:160:         out->ctext[1] = DMEM->CTEXT_1;
	lw	a5,-32(s0)		# tmp179, out
	sw	a4,4(a5)	# _6, out_27->ctext[1]
# main.c:161:         __asm__ volatile ("" ::: "memory");
# main.c:167:         out->tag[0] = ASCON->TAG_0;
	li	a5,536870912		# _7,
	lw	a4,72(a5)		# _8, _7->TAG_0
# main.c:167:         out->tag[0] = ASCON->TAG_0;
	lw	a5,-32(s0)		# tmp180, out
	sw	a4,8(a5)	# _8, out_27->tag[0]
# main.c:168:         __asm__ volatile ("" ::: "memory");
# main.c:169:         out->tag[1] = ASCON->TAG_1;
	li	a5,536870912		# _9,
	lw	a4,76(a5)		# _10, _9->TAG_1
# main.c:169:         out->tag[1] = ASCON->TAG_1;
	lw	a5,-32(s0)		# tmp181, out
	sw	a4,12(a5)	# _10, out_27->tag[1]
# main.c:170:         __asm__ volatile ("" ::: "memory");
# main.c:171:         out->tag[2] = ASCON->TAG_2;
	li	a5,536870912		# _11,
	lw	a4,80(a5)		# _12, _11->TAG_2
# main.c:171:         out->tag[2] = ASCON->TAG_2;
	lw	a5,-32(s0)		# tmp182, out
	sw	a4,16(a5)	# _12, out_27->tag[2]
# main.c:172:         __asm__ volatile ("" ::: "memory");
# main.c:173:         out->tag[3] = ASCON->TAG_3;
	li	a5,536870912		# _13,
	lw	a4,84(a5)		# _14, _13->TAG_3
# main.c:173:         out->tag[3] = ASCON->TAG_3;
	lw	a5,-32(s0)		# tmp183, out
	sw	a4,20(a5)	# _14, out_27->tag[3]
# main.c:174:         __asm__ volatile ("" ::: "memory");
.L29:
# main.c:178:     ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
	li	a5,536870912		# _15,
	li	a4,2		# tmp184,
	sw	a4,32(a5)	# tmp184, _15->CTRL
# main.c:181:     plic_complete(src);
	lw	a0,-20(s0)		#, src
	call	plic_complete		#
# main.c:184:     uint32_t next = blk + 1u;
	lw	a5,-28(s0)		# tmp186, blk
	addi	a5,a5,1	#, tmp185, tmp186
	sw	a5,-36(s0)	# tmp185, next
# main.c:185:     g_stream.cur_block = next;
	lui	a5,%hi(g_stream)	# tmp187,
	addi	a5,a5,%lo(g_stream)	# tmp188, tmp187,
	lw	a4,-36(s0)		# tmp189, next
	sw	a4,424(a5)	# tmp189, g_stream.cur_block
# main.c:187:     if (next < g_stream.n_blocks) {
	lui	a5,%hi(g_stream)	# tmp190,
	addi	a5,a5,%lo(g_stream)	# tmp191, tmp190,
	lw	a5,4(a5)		# _16, g_stream.n_blocks
# main.c:187:     if (next < g_stream.n_blocks) {
	lw	a4,-36(s0)		# tmp192, next
	bgeu	a4,a5,.L30	#, tmp192, _16,
# main.c:192:         ascon_feed_block_cpu(next);
	lw	a0,-36(s0)		#, next
	call	ascon_feed_block_cpu		#
# main.c:194:         int r = ascon_config_block();
	call	ascon_config_block		#
	sw	a0,-40(s0)	#, r
# main.c:195:         if (r != 0) {
	lw	a5,-40(s0)		# tmp193, r
	beq	a5,zero,.L31	#, tmp193,,
# main.c:196:             g_stream.error = (uint32_t)(int32_t)r;
	lw	a4,-40(s0)		# r.2_17, r
# main.c:196:             g_stream.error = (uint32_t)(int32_t)r;
	lui	a5,%hi(g_stream)	# tmp194,
	addi	a5,a5,%lo(g_stream)	# tmp195, tmp194,
	sw	a4,432(a5)	# r.2_17, g_stream.error
# main.c:197:             g_stream.done  = 1u;
	lui	a5,%hi(g_stream)	# tmp196,
	addi	a5,a5,%lo(g_stream)	# tmp197, tmp196,
	li	a4,1		# tmp198,
	sw	a4,428(a5)	# tmp198, g_stream.done
# main.c:198:             return;
	j	.L24		#
.L31:
# main.c:201:         ascon_kick_dma();
	call	ascon_kick_dma		#
	j	.L24		#
.L30:
# main.c:206:         g_stream.done = 1u;
	lui	a5,%hi(g_stream)	# tmp199,
	addi	a5,a5,%lo(g_stream)	# tmp200, tmp199,
	li	a4,1		# tmp201,
	sw	a4,428(a5)	# tmp201, g_stream.done
	j	.L24		#
.L32:
# main.c:134:         return;
	nop	
.L24:
# main.c:208: }
	lw	ra,44(sp)		#,
	lw	s0,40(sp)		#,
	addi	sp,sp,48	#,,
	jr	ra		#
	.size	ascon_isr, .-ascon_isr
	.align	2
	.globl	trap_handler
	.type	trap_handler, @function
trap_handler:
	addi	sp,sp,-96	#,,
	sw	ra,92(sp)	#,
	sw	t0,88(sp)	#,
	sw	t1,84(sp)	#,
	sw	t2,80(sp)	#,
	sw	s0,76(sp)	#,
	sw	a0,72(sp)	#,
	sw	a1,68(sp)	#,
	sw	a2,64(sp)	#,
	sw	a3,60(sp)	#,
	sw	a4,56(sp)	#,
	sw	a5,52(sp)	#,
	sw	a6,48(sp)	#,
	sw	a7,44(sp)	#,
	sw	t3,40(sp)	#,
	sw	t4,36(sp)	#,
	sw	t5,32(sp)	#,
	sw	t6,28(sp)	#,
	addi	s0,sp,96	#,,
# main.c:223:     __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));
 #APP
# 223 "main.c" 1
	csrr a5, mcause	# mcause
# 0 "" 2
 #NO_APP
	sw	a5,-84(s0)	# mcause, mcause
# main.c:226:     if ((mcause & 0x80000000u) && ((mcause & 0xFFFFu) == 11u)) {
	lw	a5,-84(s0)		# mcause.3_1, mcause
# main.c:226:     if ((mcause & 0x80000000u) && ((mcause & 0xFFFFu) == 11u)) {
	bge	a5,zero,.L35	#, mcause.3_1,,
# main.c:226:     if ((mcause & 0x80000000u) && ((mcause & 0xFFFFu) == 11u)) {
	lw	a4,-84(s0)		# tmp137, mcause
	li	a5,65536		# tmp139,
	addi	a5,a5,-1	#, tmp138, tmp139
	and	a4,a4,a5	# tmp138, _2, tmp137
# main.c:226:     if ((mcause & 0x80000000u) && ((mcause & 0xFFFFu) == 11u)) {
	li	a5,11		# tmp140,
	bne	a4,a5,.L35	#, _2, tmp140,
# main.c:227:         ascon_isr();
	call	ascon_isr		#
.L35:
# main.c:230: }
	nop	
	lw	ra,92(sp)		#,
	lw	t0,88(sp)		#,
	lw	t1,84(sp)		#,
	lw	t2,80(sp)		#,
	lw	s0,76(sp)		#,
	lw	a0,72(sp)		#,
	lw	a1,68(sp)		#,
	lw	a2,64(sp)		#,
	lw	a3,60(sp)		#,
	lw	a4,56(sp)		#,
	lw	a5,52(sp)		#,
	lw	a6,48(sp)		#,
	lw	a7,44(sp)		#,
	lw	t3,40(sp)		#,
	lw	t4,36(sp)		#,
	lw	t5,32(sp)		#,
	lw	t6,28(sp)		#,
	addi	sp,sp,96	#,,
	mret	
	.size	trap_handler, .-trap_handler
	.section	.rodata
	.align	2
.LC1:
	.string	"E:STS="
	.align	2
.LC2:
	.string	"\r\n"
	.align	2
.LC3:
	.string	"OK n="
	.align	2
.LC4:
	.string	"B"
	.align	2
.LC5:
	.string	" C:"
	.align	2
.LC6:
	.string	" T:"
	.text
	.align	2
	.type	print_results, @function
print_results:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
# main.c:237:     if (g_stream.error != 0u) {
	lui	a5,%hi(g_stream)	# tmp146,
	addi	a5,a5,%lo(g_stream)	# tmp147, tmp146,
	lw	a5,432(a5)		# _1, g_stream.error
# main.c:237:     if (g_stream.error != 0u) {
	beq	a5,zero,.L37	#, _1,,
# main.c:238:         uart_puts("E:STS=");
	lui	a5,%hi(.LC1)	# tmp148,
	addi	a0,a5,%lo(.LC1)	#, tmp148,
	call	uart_puts		#
# main.c:239:         uart_puthex32(g_stream.error);
	lui	a5,%hi(g_stream)	# tmp149,
	addi	a5,a5,%lo(g_stream)	# tmp150, tmp149,
	lw	a5,432(a5)		# _2, g_stream.error
# main.c:239:         uart_puthex32(g_stream.error);
	mv	a0,a5	#, _2
	call	uart_puthex32		#
# main.c:240:         uart_puts("\r\n");
	lui	a5,%hi(.LC2)	# tmp151,
	addi	a0,a5,%lo(.LC2)	#, tmp151,
	call	uart_puts		#
# main.c:241:         return;
	j	.L36		#
.L37:
# main.c:244:     uart_puts("OK n=");
	lui	a5,%hi(.LC3)	# tmp152,
	addi	a0,a5,%lo(.LC3)	#, tmp152,
	call	uart_puts		#
# main.c:245:     uart_puthex8((uint8_t)g_stream.n_blocks);
	lui	a5,%hi(g_stream)	# tmp153,
	addi	a5,a5,%lo(g_stream)	# tmp154, tmp153,
	lw	a5,4(a5)		# _3, g_stream.n_blocks
# main.c:245:     uart_puthex8((uint8_t)g_stream.n_blocks);
	andi	a5,a5,0xff	# _4, _3
	mv	a0,a5	#, _4
	call	uart_puthex8		#
# main.c:246:     uart_puts("\r\n");
	lui	a5,%hi(.LC2)	# tmp155,
	addi	a0,a5,%lo(.LC2)	#, tmp155,
	call	uart_puts		#
# main.c:248:     for (uint32_t i = 0u; i < g_stream.n_blocks; i++) {
	sw	zero,-20(s0)	#, i
# main.c:248:     for (uint32_t i = 0u; i < g_stream.n_blocks; i++) {
	j	.L39		#
.L40:
# main.c:249:         uart_puts("B");
	lui	a5,%hi(.LC4)	# tmp156,
	addi	a0,a5,%lo(.LC4)	#, tmp156,
	call	uart_puts		#
# main.c:250:         uart_puthex8((uint8_t)i);
	lw	a5,-20(s0)		# tmp157, i
	andi	a5,a5,0xff	# _5, tmp157
	mv	a0,a5	#, _5
	call	uart_puthex8		#
# main.c:251:         uart_puts(" C:");
	lui	a5,%hi(.LC5)	# tmp158,
	addi	a0,a5,%lo(.LC5)	#, tmp158,
	call	uart_puts		#
# main.c:252:         uart_puthex32(g_stream.out[i].ctext[0]);
	lui	a5,%hi(g_stream)	# tmp159,
	addi	a3,a5,%lo(g_stream)	# tmp160, tmp159,
	lw	a4,-20(s0)		# tmp161, i
	mv	a5,a4	# tmp163, tmp161
	slli	a5,a5,1	#, tmp164, tmp163
	add	a5,a5,a4	# tmp161, tmp163, tmp163
	slli	a5,a5,3	#, tmp165, tmp163
	add	a5,a3,a5	# tmp163, tmp162, tmp160
	lw	a5,40(a5)		# _6, g_stream.out[i_13].ctext[0]
	mv	a0,a5	#, _6
	call	uart_puthex32		#
# main.c:253:         uart_puthex32(g_stream.out[i].ctext[1]);
	lui	a5,%hi(g_stream)	# tmp166,
	addi	a3,a5,%lo(g_stream)	# tmp167, tmp166,
	lw	a4,-20(s0)		# tmp168, i
	mv	a5,a4	# tmp170, tmp168
	slli	a5,a5,1	#, tmp171, tmp170
	add	a5,a5,a4	# tmp168, tmp170, tmp170
	slli	a5,a5,3	#, tmp172, tmp170
	add	a5,a3,a5	# tmp170, tmp169, tmp167
	lw	a5,44(a5)		# _7, g_stream.out[i_13].ctext[1]
	mv	a0,a5	#, _7
	call	uart_puthex32		#
# main.c:254:         uart_puts(" T:");
	lui	a5,%hi(.LC6)	# tmp173,
	addi	a0,a5,%lo(.LC6)	#, tmp173,
	call	uart_puts		#
# main.c:255:         uart_puthex32(g_stream.out[i].tag[0]);
	lui	a5,%hi(g_stream)	# tmp174,
	addi	a3,a5,%lo(g_stream)	# tmp175, tmp174,
	lw	a4,-20(s0)		# tmp176, i
	mv	a5,a4	# tmp178, tmp176
	slli	a5,a5,1	#, tmp179, tmp178
	add	a5,a5,a4	# tmp176, tmp178, tmp178
	slli	a5,a5,3	#, tmp180, tmp178
	add	a5,a3,a5	# tmp178, tmp177, tmp175
	lw	a5,48(a5)		# _8, g_stream.out[i_13].tag[0]
	mv	a0,a5	#, _8
	call	uart_puthex32		#
# main.c:256:         uart_puthex32(g_stream.out[i].tag[1]);
	lui	a5,%hi(g_stream)	# tmp181,
	addi	a3,a5,%lo(g_stream)	# tmp182, tmp181,
	lw	a4,-20(s0)		# tmp183, i
	mv	a5,a4	# tmp185, tmp183
	slli	a5,a5,1	#, tmp186, tmp185
	add	a5,a5,a4	# tmp183, tmp185, tmp185
	slli	a5,a5,3	#, tmp187, tmp185
	add	a5,a3,a5	# tmp185, tmp184, tmp182
	lw	a5,52(a5)		# _9, g_stream.out[i_13].tag[1]
	mv	a0,a5	#, _9
	call	uart_puthex32		#
# main.c:257:         uart_puthex32(g_stream.out[i].tag[2]);
	lui	a5,%hi(g_stream)	# tmp188,
	addi	a3,a5,%lo(g_stream)	# tmp189, tmp188,
	lw	a4,-20(s0)		# tmp190, i
	mv	a5,a4	# tmp192, tmp190
	slli	a5,a5,1	#, tmp193, tmp192
	add	a5,a5,a4	# tmp190, tmp192, tmp192
	slli	a5,a5,3	#, tmp194, tmp192
	add	a5,a3,a5	# tmp192, tmp191, tmp189
	lw	a5,56(a5)		# _10, g_stream.out[i_13].tag[2]
	mv	a0,a5	#, _10
	call	uart_puthex32		#
# main.c:258:         uart_puthex32(g_stream.out[i].tag[3]);
	lui	a5,%hi(g_stream)	# tmp195,
	addi	a3,a5,%lo(g_stream)	# tmp196, tmp195,
	lw	a4,-20(s0)		# tmp197, i
	mv	a5,a4	# tmp199, tmp197
	slli	a5,a5,1	#, tmp200, tmp199
	add	a5,a5,a4	# tmp197, tmp199, tmp199
	slli	a5,a5,3	#, tmp201, tmp199
	add	a5,a3,a5	# tmp199, tmp198, tmp196
	lw	a5,60(a5)		# _11, g_stream.out[i_13].tag[3]
	mv	a0,a5	#, _11
	call	uart_puthex32		#
# main.c:259:         uart_puts("\r\n");
	lui	a5,%hi(.LC2)	# tmp202,
	addi	a0,a5,%lo(.LC2)	#, tmp202,
	call	uart_puts		#
# main.c:248:     for (uint32_t i = 0u; i < g_stream.n_blocks; i++) {
	lw	a5,-20(s0)		# tmp204, i
	addi	a5,a5,1	#, tmp203, tmp204
	sw	a5,-20(s0)	# tmp203, i
.L39:
# main.c:248:     for (uint32_t i = 0u; i < g_stream.n_blocks; i++) {
	lui	a5,%hi(g_stream)	# tmp205,
	addi	a5,a5,%lo(g_stream)	# tmp206, tmp205,
	lw	a5,4(a5)		# _12, g_stream.n_blocks
# main.c:248:     for (uint32_t i = 0u; i < g_stream.n_blocks; i++) {
	lw	a4,-20(s0)		# tmp207, i
	bltu	a4,a5,.L40	#, tmp207, _12,
.L36:
# main.c:261: }
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	print_results, .-print_results
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
# main.c:277:     __asm__ volatile (
 #APP
# 277 "main.c" 1
	la   t0, trap_handler
csrw mtvec, t0

# 0 "" 2
# main.c:285:     plic_init_ascon();
 #NO_APP
	call	plic_init_ascon		#
# main.c:289:     mie_enable_external();
	call	mie_enable_external		#
# main.c:290:     mstatus_enable_irq();
	call	mstatus_enable_irq		#
# main.c:294:     g_stream.ptext    = g_plaintext;
	lui	a5,%hi(g_stream)	# tmp146,
	addi	a5,a5,%lo(g_stream)	# tmp147, tmp146,
	lui	a4,%hi(g_plaintext)	# tmp149,
	addi	a4,a4,%lo(g_plaintext)	# tmp148, tmp149,
	sw	a4,0(a5)	# tmp148, g_stream.ptext
# main.c:295:     g_stream.n_blocks = N_BLOCKS;
	lui	a5,%hi(g_stream)	# tmp150,
	addi	a5,a5,%lo(g_stream)	# tmp151, tmp150,
	li	a4,4		# tmp152,
	sw	a4,4(a5)	# tmp152, g_stream.n_blocks
# main.c:296:     g_stream.key[0]   = g_key[0];
	li	a5,1122304		# tmp153,
	addi	a4,a5,563	#, _1, tmp153
# main.c:296:     g_stream.key[0]   = g_key[0];
	lui	a5,%hi(g_stream)	# tmp154,
	addi	a5,a5,%lo(g_stream)	# tmp155, tmp154,
	sw	a4,8(a5)	# _1, g_stream.key[0]
# main.c:297:     g_stream.key[1]   = g_key[1];
	li	a5,1146445824		# tmp156,
	addi	a4,a5,1655	#, _2, tmp156
# main.c:297:     g_stream.key[1]   = g_key[1];
	lui	a5,%hi(g_stream)	# tmp157,
	addi	a5,a5,%lo(g_stream)	# tmp158, tmp157,
	sw	a4,12(a5)	# _2, g_stream.key[1]
# main.c:298:     g_stream.key[2]   = g_key[2];
	li	a5,-2003193856		# tmp159,
	addi	a4,a5,-1349	#, _3, tmp159
# main.c:298:     g_stream.key[2]   = g_key[2];
	lui	a5,%hi(g_stream)	# tmp160,
	addi	a5,a5,%lo(g_stream)	# tmp161, tmp160,
	sw	a4,16(a5)	# _3, g_stream.key[2]
# main.c:299:     g_stream.key[3]   = g_key[3];
	li	a5,-857870336		# tmp162,
	addi	a4,a5,-257	#, _4, tmp162
# main.c:299:     g_stream.key[3]   = g_key[3];
	lui	a5,%hi(g_stream)	# tmp163,
	addi	a5,a5,%lo(g_stream)	# tmp164, tmp163,
	sw	a4,20(a5)	# _4, g_stream.key[3]
# main.c:300:     g_stream.nonce[0] = g_nonce[0];
	li	a5,-559038464		# tmp165,
	addi	a4,a5,-273	#, _5, tmp165
# main.c:300:     g_stream.nonce[0] = g_nonce[0];
	lui	a5,%hi(g_stream)	# tmp166,
	addi	a5,a5,%lo(g_stream)	# tmp167, tmp166,
	sw	a4,24(a5)	# _5, g_stream.nonce[0]
# main.c:301:     g_stream.nonce[1] = g_nonce[1];
	li	a5,-889274368		# tmp168,
	addi	a4,a5,-1346	#, _6, tmp168
# main.c:301:     g_stream.nonce[1] = g_nonce[1];
	lui	a5,%hi(g_stream)	# tmp169,
	addi	a5,a5,%lo(g_stream)	# tmp170, tmp169,
	sw	a4,28(a5)	# _6, g_stream.nonce[1]
# main.c:302:     g_stream.nonce[2] = g_nonce[2];
	li	a5,19087360		# tmp171,
	addi	a4,a5,1383	#, _7, tmp171
# main.c:302:     g_stream.nonce[2] = g_nonce[2];
	lui	a5,%hi(g_stream)	# tmp172,
	addi	a5,a5,%lo(g_stream)	# tmp173, tmp172,
	sw	a4,32(a5)	# _7, g_stream.nonce[2]
# main.c:303:     g_stream.nonce[3] = g_nonce[3];
	li	a5,-1985228800		# tmp174,
	addi	a4,a5,-529	#, _8, tmp174
# main.c:303:     g_stream.nonce[3] = g_nonce[3];
	lui	a5,%hi(g_stream)	# tmp175,
	addi	a5,a5,%lo(g_stream)	# tmp176, tmp175,
	sw	a4,36(a5)	# _8, g_stream.nonce[3]
# main.c:307:     int r = ascon_stream_start();
	call	ascon_stream_start		#
	sw	a0,-20(s0)	#, r
# main.c:308:     if (r != 0) {
	lw	a5,-20(s0)		# tmp177, r
	beq	a5,zero,.L44	#, tmp177,,
# main.c:310:         return r;
	lw	a5,-20(s0)		# _11, r
	j	.L43		#
.L45:
# main.c:333:         __asm__ volatile ("wfi");
 #APP
# 333 "main.c" 1
	wfi
# 0 "" 2
 #NO_APP
.L44:
# main.c:332:     while (!g_stream.done) {
	lui	a5,%hi(g_stream)	# tmp178,
	addi	a5,a5,%lo(g_stream)	# tmp179, tmp178,
	lw	a5,428(a5)		# _9, g_stream.done
# main.c:332:     while (!g_stream.done) {
	beq	a5,zero,.L45	#, _9,,
# main.c:345:     mstatus_disable_irq();
	call	mstatus_disable_irq		#
# main.c:346:     ASCON_WRITE(ASCON->IRQ_EN, 0u);
	li	a5,536870912		# _10,
	sw	zero,12(a5)	#, _10->IRQ_EN
# main.c:348:     return 0;
	li	a5,0		# _11,
.L43:
# main.c:349: }
	mv	a0,a5	#, <retval>
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
