	.file	"main.c"
	.option nopic
	.option norelax
	.attribute arch, "rv32i2p1_m2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
# GNU C17 (13.2.0-11ubuntu1+12) version 13.2.0 (riscv64-unknown-elf)
#	compiled by GNU C version 13.2.0, GMP version 6.3.0, MPFR version 4.2.1, MPC version 1.3.1, isl version isl-0.26-GMP

# GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
# options passed: -mabi=ilp32 -mno-relax -misa-spec=20191213 -march=rv32im -O0 -ffreestanding
	.text
	.align	2
	.type	ascon_read_status, @function
ascon_read_status:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
# ascon_regs.h:147:     uint32_t s = ASCON->STATUS;
	li	a5,536870912		# _1,
# ascon_regs.h:147:     uint32_t s = ASCON->STATUS;
	lw	a5,60(a5)		# tmp137, _1->STATUS
	sw	a5,-20(s0)	# tmp137, s
# ascon_regs.h:148:     __asm__ volatile ("" ::: "memory");
# ascon_regs.h:149:     return s;
	lw	a5,-20(s0)		# _5, s
# ascon_regs.h:150: }
	mv	a0,a5	#, <retval>
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	ascon_read_status, .-ascon_read_status
	.align	2
	.type	uart_putc, @function
uart_putc:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
	mv	a5,a0	# tmp136, c
	sb	a5,-17(s0)	# tmp137, c
# main.c:133:     UART_TX = (uint32_t)(uint8_t)c;
	li	a5,1342177280		# tmp138,
	addi	a5,a5,4	#, _1, tmp138
# main.c:133:     UART_TX = (uint32_t)(uint8_t)c;
	lbu	a4,-17(s0)	# _2, c
# main.c:133:     UART_TX = (uint32_t)(uint8_t)c;
	sw	a4,0(a5)	# _2, *_1
# main.c:134:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 134 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:135:     __asm__ volatile (
# 135 "main.c" 1
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
# main.c:140: }
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
# main.c:145:     while (*s)
	j	.L5		#
.L6:
# main.c:146:         uart_putc(*s++);
	lw	a5,-20(s0)		# s.0_1, s
	addi	a4,a5,1	#, tmp137, s.0_1
	sw	a4,-20(s0)	# tmp137, s
# main.c:146:         uart_putc(*s++);
	lbu	a5,0(a5)	# _2, *s.0_1
	mv	a0,a5	#, _2
	call	uart_putc		#
.L5:
# main.c:145:     while (*s)
	lw	a5,-20(s0)		# tmp138, s
	lbu	a5,0(a5)	# _3, *s_4
	bne	a5,zero,.L6	#, _3,,
# main.c:147: }
	nop	
	nop	
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_puts, .-uart_puts
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
# main.c:152:     const char *h = "0123456789ABCDEF";
	lui	a5,%hi(.LC0)	# tmp146,
	addi	a5,a5,%lo(.LC0)	# tmp145, tmp146,
	sw	a5,-20(s0)	# tmp145, h
# main.c:153:     uart_putc(h[(v >> 4) & 0xFu]);
	lbu	a5,-33(s0)	# tmp147, v
	srli	a5,a5,4	#, tmp148, tmp147
	andi	a5,a5,0xff	# _1, tmp148
	andi	a5,a5,15	#, _3, _2
# main.c:153:     uart_putc(h[(v >> 4) & 0xFu]);
	lw	a4,-20(s0)		# tmp149, h
	add	a5,a4,a5	# _3, _4, tmp149
# main.c:153:     uart_putc(h[(v >> 4) & 0xFu]);
	lbu	a5,0(a5)	# _5, *_4
	mv	a0,a5	#, _5
	call	uart_putc		#
# main.c:154:     uart_putc(h[v & 0xFu]);
	lbu	a5,-33(s0)	# _6, v
	andi	a5,a5,15	#, _7, _6
# main.c:154:     uart_putc(h[v & 0xFu]);
	lw	a4,-20(s0)		# tmp150, h
	add	a5,a4,a5	# _7, _8, tmp150
# main.c:154:     uart_putc(h[v & 0xFu]);
	lbu	a5,0(a5)	# _9, *_8
	mv	a0,a5	#, _9
	call	uart_putc		#
# main.c:155: }
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
# main.c:160:     uart_puthex8((uint8_t)(v >> 24));
	lw	a5,-20(s0)		# tmp141, v
	srli	a5,a5,24	#, _1, tmp141
# main.c:160:     uart_puthex8((uint8_t)(v >> 24));
	andi	a5,a5,0xff	# _2, _1
	mv	a0,a5	#, _2
	call	uart_puthex8		#
# main.c:161:     uart_puthex8((uint8_t)(v >> 16));
	lw	a5,-20(s0)		# tmp142, v
	srli	a5,a5,16	#, _3, tmp142
# main.c:161:     uart_puthex8((uint8_t)(v >> 16));
	andi	a5,a5,0xff	# _4, _3
	mv	a0,a5	#, _4
	call	uart_puthex8		#
# main.c:162:     uart_puthex8((uint8_t)(v >>  8));
	lw	a5,-20(s0)		# tmp143, v
	srli	a5,a5,8	#, _5, tmp143
# main.c:162:     uart_puthex8((uint8_t)(v >>  8));
	andi	a5,a5,0xff	# _6, _5
	mv	a0,a5	#, _6
	call	uart_puthex8		#
# main.c:163:     uart_puthex8((uint8_t)(v      ));
	lw	a5,-20(s0)		# tmp144, v
	andi	a5,a5,0xff	# _7, tmp144
	mv	a0,a5	#, _7
	call	uart_puthex8		#
# main.c:164: }
	nop	
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_puthex32, .-uart_puthex32
	.align	2
	.type	step1_write_ptext_to_dmem, @function
step1_write_ptext_to_dmem:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# main.c:173:     DMEM->PTEXT_0 = PTEXT_WORD0;   /* 0x10000000 ← 0x6C6C6548 */
	li	a5,268435456		# _1,
# main.c:173:     DMEM->PTEXT_0 = PTEXT_WORD0;   /* 0x10000000 ← 0x6C6C6548 */
	li	a4,1819041792		# tmp137,
	addi	a4,a4,1352	#, tmp136, tmp137
	sw	a4,0(a5)	# tmp136, _1->PTEXT_0
# main.c:174:     MB();
# main.c:175:     DMEM->PTEXT_1 = PTEXT_WORD1;   /* 0x10000004 ← 0x0000216F */
	li	a5,268435456		# _2,
# main.c:175:     DMEM->PTEXT_1 = PTEXT_WORD1;   /* 0x10000004 ← 0x0000216F */
	li	a4,8192		# tmp139,
	addi	a4,a4,367	#, tmp138, tmp139
	sw	a4,4(a5)	# tmp138, _2->PTEXT_1
# main.c:176:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 176 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:177: }
 #NO_APP
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	step1_write_ptext_to_dmem, .-step1_write_ptext_to_dmem
	.align	2
	.type	step2_reset_and_config, @function
step2_reset_and_config:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
# main.c:193:     ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
	li	a5,536870912		# _1,
	li	a4,2		# tmp152,
	sw	a4,0(a5)	# tmp152, _1->CTRL
 #APP
# 193 "main.c" 1
	fence w,w
# 0 "" 2
# 193 "main.c" 1
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
# main.c:196:     __asm__ volatile (
# 196 "main.c" 1
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
# main.c:209:     to = RESET_POLL_TIMEOUT;
 #NO_APP
	li	a5,256		# tmp153,
	sw	a5,-20(s0)	# tmp153, to
.L13:
# main.c:211:         st = ascon_read_status();
	call	ascon_read_status		#
	sw	a0,-24(s0)	#, st
# main.c:212:         if (!(st & STATUS_CORE_BUSY)) break;
	lw	a5,-24(s0)		# tmp154, st
	andi	a5,a5,1	#, _2, tmp154
# main.c:212:         if (!(st & STATUS_CORE_BUSY)) break;
	beq	a5,zero,.L16	#, _2,,
# main.c:213:         __asm__ volatile ("nop\nnop\nnop\nnop\n" ::: "memory");
 #APP
# 213 "main.c" 1
	nop
nop
nop
nop

# 0 "" 2
# main.c:214:         to--;
 #NO_APP
	lw	a5,-20(s0)		# tmp156, to
	addi	a5,a5,-1	#, tmp155, tmp156
	sw	a5,-20(s0)	# tmp155, to
# main.c:215:     } while (to > 0u);
	lw	a5,-20(s0)		# tmp157, to
	bne	a5,zero,.L13	#, tmp157,,
	j	.L12		#
.L16:
# main.c:212:         if (!(st & STATUS_CORE_BUSY)) break;
	nop	
.L12:
# main.c:217:     if (st & STATUS_CORE_BUSY) {
	lw	a5,-24(s0)		# tmp158, st
	andi	a5,a5,1	#, _3, tmp158
# main.c:217:     if (st & STATUS_CORE_BUSY) {
	beq	a5,zero,.L14	#, _3,,
# main.c:218:         DMEM->STATUS  = st;
	li	a5,268435456		# _4,
# main.c:218:         DMEM->STATUS  = st;
	lw	a4,-24(s0)		# tmp159, st
	sw	a4,84(a5)	# tmp159, _4->STATUS
# main.c:219:         DMEM->RETCODE = (uint32_t)(int32_t)(-3);
	li	a5,268435456		# _5,
# main.c:219:         DMEM->RETCODE = (uint32_t)(int32_t)(-3);
	li	a4,-3		# tmp160,
	sw	a4,88(a5)	# tmp160, _5->RETCODE
# main.c:220:         __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 220 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:221:         return -3;
 #NO_APP
	li	a5,-3		# _18,
	j	.L15		#
.L14:
# main.c:225:     ASCON_WRITE(ASCON->MODE,     MODE_ENCRYPT);
	li	a5,536870912		# _6,
	li	a4,1		# tmp161,
	sw	a4,4(a5)	# tmp161, _6->MODE
 #APP
# 225 "main.c" 1
	fence w,w
# 0 "" 2
# 225 "main.c" 1
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
# main.c:226:     ASCON_WRITE(ASCON->IRQ_EN,   0u);
 #NO_APP
	li	a5,536870912		# _7,
	sw	zero,8(a5)	#, _7->IRQ_EN
 #APP
# 226 "main.c" 1
	fence w,w
# 0 "" 2
# 226 "main.c" 1
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
# main.c:227:     ASCON_WRITE(ASCON->KEY_0,    CFG_KEY_0);
 #NO_APP
	li	a5,536870912		# _8,
	li	a4,1122304		# tmp163,
	addi	a4,a4,563	#, tmp162, tmp163
	sw	a4,16(a5)	# tmp162, _8->KEY_0
 #APP
# 227 "main.c" 1
	fence w,w
# 0 "" 2
# 227 "main.c" 1
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
# main.c:228:     ASCON_WRITE(ASCON->KEY_1,    CFG_KEY_1);
 #NO_APP
	li	a5,536870912		# _9,
	li	a4,1146445824		# tmp165,
	addi	a4,a4,1655	#, tmp164, tmp165
	sw	a4,20(a5)	# tmp164, _9->KEY_1
 #APP
# 228 "main.c" 1
	fence w,w
# 0 "" 2
# 228 "main.c" 1
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
# main.c:229:     ASCON_WRITE(ASCON->KEY_2,    CFG_KEY_2);
 #NO_APP
	li	a5,536870912		# _10,
	li	a4,-2003193856		# tmp167,
	addi	a4,a4,-1349	#, tmp166, tmp167
	sw	a4,24(a5)	# tmp166, _10->KEY_2
 #APP
# 229 "main.c" 1
	fence w,w
# 0 "" 2
# 229 "main.c" 1
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
# main.c:230:     ASCON_WRITE(ASCON->KEY_3,    CFG_KEY_3);
 #NO_APP
	li	a5,536870912		# _11,
	li	a4,-857870336		# tmp169,
	addi	a4,a4,-257	#, tmp168, tmp169
	sw	a4,28(a5)	# tmp168, _11->KEY_3
 #APP
# 230 "main.c" 1
	fence w,w
# 0 "" 2
# 230 "main.c" 1
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
# main.c:231:     ASCON_WRITE(ASCON->NONCE_0,  CFG_NONCE_0);
 #NO_APP
	li	a5,536870912		# _12,
	li	a4,-559038464		# tmp171,
	addi	a4,a4,-273	#, tmp170, tmp171
	sw	a4,32(a5)	# tmp170, _12->NONCE_0
 #APP
# 231 "main.c" 1
	fence w,w
# 0 "" 2
# 231 "main.c" 1
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
# main.c:232:     ASCON_WRITE(ASCON->NONCE_1,  CFG_NONCE_1);
 #NO_APP
	li	a5,536870912		# _13,
	li	a4,-889274368		# tmp173,
	addi	a4,a4,-1346	#, tmp172, tmp173
	sw	a4,36(a5)	# tmp172, _13->NONCE_1
 #APP
# 232 "main.c" 1
	fence w,w
# 0 "" 2
# 232 "main.c" 1
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
# main.c:233:     ASCON_WRITE(ASCON->NONCE_2,  CFG_NONCE_2);
 #NO_APP
	li	a5,536870912		# _14,
	li	a4,19087360		# tmp175,
	addi	a4,a4,1383	#, tmp174, tmp175
	sw	a4,40(a5)	# tmp174, _14->NONCE_2
 #APP
# 233 "main.c" 1
	fence w,w
# 0 "" 2
# 233 "main.c" 1
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
# main.c:234:     ASCON_WRITE(ASCON->NONCE_3,  CFG_NONCE_3);
 #NO_APP
	li	a5,536870912		# _15,
	li	a4,-1985228800		# tmp177,
	addi	a4,a4,-529	#, tmp176, tmp177
	sw	a4,44(a5)	# tmp176, _15->NONCE_3
 #APP
# 234 "main.c" 1
	fence w,w
# 0 "" 2
# 234 "main.c" 1
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
# main.c:235:     ASCON_WRITE(ASCON->DATA_LEN, (uint32_t)(PTEXT_LEN & DATA_LEN_MASK));
 #NO_APP
	li	a5,536870912		# _16,
	li	a4,8		# tmp178,
	sw	a4,48(a5)	# tmp178, _16->DATA_LEN
 #APP
# 235 "main.c" 1
	fence w,w
# 0 "" 2
# 235 "main.c" 1
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
# main.c:237:     return 0;
 #NO_APP
	li	a5,0		# _18,
.L15:
# main.c:238: }
	mv	a0,a5	#, <retval>
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	step2_reset_and_config, .-step2_reset_and_config
	.align	2
	.type	step3_kick_dma, @function
step3_kick_dma:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# main.c:251:     ASCON_WRITE(ASCON->DMA_SRC, (uint32_t)(DMEM_BASE + 0x0000UL)); /* PTEXT_0 */
	li	a5,536870912		# _1,
	li	a4,268435456		# tmp138,
	sw	a4,256(a5)	# tmp138, _1->DMA_SRC
 #APP
# 251 "main.c" 1
	fence w,w
# 0 "" 2
# 251 "main.c" 1
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
# main.c:252:     ASCON_WRITE(ASCON->DMA_DST, DMEM_DMA_OUTPUT_ADDR);             /* CTEXT_0 */
 #NO_APP
	li	a5,536870912		# _2,
	li	a4,268435456		# tmp140,
	addi	a4,a4,16	#, tmp139, tmp140
	sw	a4,260(a5)	# tmp139, _2->DMA_DST
 #APP
# 252 "main.c" 1
	fence w,w
# 0 "" 2
# 252 "main.c" 1
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
# main.c:253:     ASCON_WRITE(ASCON->DMA_LEN, DMEM_DMA_INPUT_LEN);               /* = 8     */
 #NO_APP
	li	a5,536870912		# _3,
	li	a4,8		# tmp141,
	sw	a4,264(a5)	# tmp141, _3->DMA_LEN
 #APP
# 253 "main.c" 1
	fence w,w
# 0 "" 2
# 253 "main.c" 1
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
# main.c:256:     __asm__ volatile ("fence w,w" ::: "memory");
# 256 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:257:     __asm__ volatile ("fence w,w" ::: "memory");
# 257 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:258:     __asm__ volatile ("fence w,w" ::: "memory");
# 258 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:259:     __asm__ volatile (
# 259 "main.c" 1
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
# main.c:268:     ASCON_WRITE(ASCON->CTRL, CTRL_DMA_START);
 #NO_APP
	li	a5,536870912		# _4,
	li	a4,5		# tmp142,
	sw	a4,0(a5)	# tmp142, _4->CTRL
 #APP
# 268 "main.c" 1
	fence w,w
# 0 "" 2
# 268 "main.c" 1
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
# main.c:271:     __asm__ volatile (
# 271 "main.c" 1
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
# main.c:276: }
 #NO_APP
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	step3_kick_dma, .-step3_kick_dma
	.align	2
	.type	step4_poll_done, @function
step4_poll_done:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
# main.c:286:     uint32_t to = POLL_TIMEOUT;
	li	a5,4096		# tmp139,
	addi	a5,a5,904	#, tmp138, tmp139
	sw	a5,-20(s0)	# tmp138, to
.L22:
# main.c:289:         st = ascon_read_status();
	call	ascon_read_status		#
	sw	a0,-24(s0)	#, st
# main.c:290:         if (st & STATUS_ANY_ERROR) return st;
	lw	a5,-24(s0)		# tmp140, st
	andi	a5,a5,4	#, _1, tmp140
# main.c:290:         if (st & STATUS_ANY_ERROR) return st;
	beq	a5,zero,.L19	#, _1,,
# main.c:290:         if (st & STATUS_ANY_ERROR) return st;
	lw	a5,-24(s0)		# _4, st
# main.c:290:         if (st & STATUS_ANY_ERROR) return st;
	j	.L20		#
.L19:
# main.c:291:         if (st & STATUS_DMA_DONE)  return st;
	lw	a5,-24(s0)		# tmp141, st
	andi	a5,a5,2	#, _2, tmp141
# main.c:291:         if (st & STATUS_DMA_DONE)  return st;
	beq	a5,zero,.L21	#, _2,,
# main.c:291:         if (st & STATUS_DMA_DONE)  return st;
	lw	a5,-24(s0)		# _4, st
# main.c:291:         if (st & STATUS_DMA_DONE)  return st;
	j	.L20		#
.L21:
# main.c:292:         to--;
	lw	a5,-20(s0)		# tmp143, to
	addi	a5,a5,-1	#, tmp142, tmp143
	sw	a5,-20(s0)	# tmp142, to
# main.c:293:     } while (to > 0u);
	lw	a5,-20(s0)		# tmp144, to
	bne	a5,zero,.L22	#, tmp144,,
# main.c:295:     return 0u;  /* timeout */
	li	a5,0		# _4,
.L20:
# main.c:296: }
	mv	a0,a5	#, <retval>
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	step4_poll_done, .-step4_poll_done
	.align	2
	.type	step5_copy_results_to_dmem, @function
step5_copy_results_to_dmem:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# status_val, status_val
	sw	a1,-24(s0)	# retcode, retcode
# main.c:314:     DMEM->TAG_0 = ASCON->TAG_0;  MB();
	li	a4,536870912		# _1,
# main.c:314:     DMEM->TAG_0 = ASCON->TAG_0;  MB();
	li	a5,268435456		# _2,
# main.c:314:     DMEM->TAG_0 = ASCON->TAG_0;  MB();
	lw	a4,64(a4)		# _3, _1->TAG_0
# main.c:314:     DMEM->TAG_0 = ASCON->TAG_0;  MB();
	sw	a4,24(a5)	# _3, _2->TAG_0
# main.c:314:     DMEM->TAG_0 = ASCON->TAG_0;  MB();
# main.c:315:     DMEM->TAG_1 = ASCON->TAG_1;  MB();
	li	a4,536870912		# _4,
# main.c:315:     DMEM->TAG_1 = ASCON->TAG_1;  MB();
	li	a5,268435456		# _5,
# main.c:315:     DMEM->TAG_1 = ASCON->TAG_1;  MB();
	lw	a4,68(a4)		# _6, _4->TAG_1
# main.c:315:     DMEM->TAG_1 = ASCON->TAG_1;  MB();
	sw	a4,28(a5)	# _6, _5->TAG_1
# main.c:315:     DMEM->TAG_1 = ASCON->TAG_1;  MB();
# main.c:316:     DMEM->TAG_2 = ASCON->TAG_2;  MB();
	li	a4,536870912		# _7,
# main.c:316:     DMEM->TAG_2 = ASCON->TAG_2;  MB();
	li	a5,268435456		# _8,
# main.c:316:     DMEM->TAG_2 = ASCON->TAG_2;  MB();
	lw	a4,72(a4)		# _9, _7->TAG_2
# main.c:316:     DMEM->TAG_2 = ASCON->TAG_2;  MB();
	sw	a4,32(a5)	# _9, _8->TAG_2
# main.c:316:     DMEM->TAG_2 = ASCON->TAG_2;  MB();
# main.c:317:     DMEM->TAG_3 = ASCON->TAG_3;  MB();
	li	a4,536870912		# _10,
# main.c:317:     DMEM->TAG_3 = ASCON->TAG_3;  MB();
	li	a5,268435456		# _11,
# main.c:317:     DMEM->TAG_3 = ASCON->TAG_3;  MB();
	lw	a4,76(a4)		# _12, _10->TAG_3
# main.c:317:     DMEM->TAG_3 = ASCON->TAG_3;  MB();
	sw	a4,36(a5)	# _12, _11->TAG_3
# main.c:317:     DMEM->TAG_3 = ASCON->TAG_3;  MB();
# main.c:319:     DMEM->DATALEN = PTEXT_LEN;
	li	a5,268435456		# _13,
# main.c:319:     DMEM->DATALEN = PTEXT_LEN;
	li	a4,8		# tmp150,
	sw	a4,80(a5)	# tmp150, _13->DATALEN
# main.c:320:     DMEM->STATUS  = status_val;
	li	a5,268435456		# _14,
# main.c:320:     DMEM->STATUS  = status_val;
	lw	a4,-20(s0)		# tmp151, status_val
	sw	a4,84(a5)	# tmp151, _14->STATUS
# main.c:321:     DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	li	a5,268435456		# _15,
# main.c:321:     DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	lw	a4,-24(s0)		# retcode.1_16, retcode
# main.c:321:     DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	sw	a4,88(a5)	# retcode.1_16, _15->RETCODE
# main.c:323:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 323 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:324: }
 #NO_APP
	nop	
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	step5_copy_results_to_dmem, .-step5_copy_results_to_dmem
	.section	.rodata
	.align	2
.LC1:
	.string	"E:RST\r\n"
	.align	2
.LC2:
	.string	"E:TMO\r\n"
	.align	2
.LC3:
	.string	"E:"
	.align	2
.LC4:
	.string	"\r\n"
	.align	2
.LC5:
	.string	"OK\r\n"
	.align	2
.LC6:
	.string	"C:"
	.align	2
.LC7:
	.string	"T:"
	.text
	.align	2
	.type	step6_print_result, @function
step6_print_result:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# status_val, status_val
	sw	a1,-24(s0)	# retcode, retcode
# main.c:341:     if (retcode != 0) {
	lw	a5,-24(s0)		# tmp147, retcode
	beq	a5,zero,.L25	#, tmp147,,
# main.c:342:         if (retcode == -3) {
	lw	a4,-24(s0)		# tmp148, retcode
	li	a5,-3		# tmp149,
	bne	a4,a5,.L26	#, tmp148, tmp149,
# main.c:343:             uart_puts("E:RST\r\n");
	lui	a5,%hi(.LC1)	# tmp150,
	addi	a0,a5,%lo(.LC1)	#, tmp150,
	call	uart_puts		#
# main.c:351:         return;
	j	.L24		#
.L26:
# main.c:344:         } else if (retcode == -2) {
	lw	a4,-24(s0)		# tmp151, retcode
	li	a5,-2		# tmp152,
	bne	a4,a5,.L28	#, tmp151, tmp152,
# main.c:345:             uart_puts("E:TMO\r\n");
	lui	a5,%hi(.LC2)	# tmp153,
	addi	a0,a5,%lo(.LC2)	#, tmp153,
	call	uart_puts		#
# main.c:351:         return;
	j	.L24		#
.L28:
# main.c:347:             uart_puts("E:");
	lui	a5,%hi(.LC3)	# tmp154,
	addi	a0,a5,%lo(.LC3)	#, tmp154,
	call	uart_puts		#
# main.c:348:             uart_puthex8((uint8_t)(status_val & 0xFFu));
	lw	a5,-20(s0)		# tmp155, status_val
	andi	a5,a5,0xff	# _1, tmp155
	mv	a0,a5	#, _1
	call	uart_puthex8		#
# main.c:349:             uart_puts("\r\n");
	lui	a5,%hi(.LC4)	# tmp156,
	addi	a0,a5,%lo(.LC4)	#, tmp156,
	call	uart_puts		#
# main.c:351:         return;
	j	.L24		#
.L25:
# main.c:355:     uart_puts("OK\r\n");
	lui	a5,%hi(.LC5)	# tmp157,
	addi	a0,a5,%lo(.LC5)	#, tmp157,
	call	uart_puts		#
# main.c:356:     uart_puts("C:");
	lui	a5,%hi(.LC6)	# tmp158,
	addi	a0,a5,%lo(.LC6)	#, tmp158,
	call	uart_puts		#
# main.c:357:     uart_puthex32(DMEM->CTEXT_0);
	li	a5,268435456		# _2,
	lw	a5,16(a5)		# _3, _2->CTEXT_0
# main.c:357:     uart_puthex32(DMEM->CTEXT_0);
	mv	a0,a5	#, _3
	call	uart_puthex32		#
# main.c:358:     uart_puthex32(DMEM->CTEXT_1);
	li	a5,268435456		# _4,
	lw	a5,20(a5)		# _5, _4->CTEXT_1
# main.c:358:     uart_puthex32(DMEM->CTEXT_1);
	mv	a0,a5	#, _5
	call	uart_puthex32		#
# main.c:359:     uart_puts("\r\n");
	lui	a5,%hi(.LC4)	# tmp159,
	addi	a0,a5,%lo(.LC4)	#, tmp159,
	call	uart_puts		#
# main.c:360:     uart_puts("T:");
	lui	a5,%hi(.LC7)	# tmp160,
	addi	a0,a5,%lo(.LC7)	#, tmp160,
	call	uart_puts		#
# main.c:361:     uart_puthex32(DMEM->TAG_0);
	li	a5,268435456		# _6,
	lw	a5,24(a5)		# _7, _6->TAG_0
# main.c:361:     uart_puthex32(DMEM->TAG_0);
	mv	a0,a5	#, _7
	call	uart_puthex32		#
# main.c:362:     uart_puthex32(DMEM->TAG_1);
	li	a5,268435456		# _8,
	lw	a5,28(a5)		# _9, _8->TAG_1
# main.c:362:     uart_puthex32(DMEM->TAG_1);
	mv	a0,a5	#, _9
	call	uart_puthex32		#
# main.c:363:     uart_puthex32(DMEM->TAG_2);
	li	a5,268435456		# _10,
	lw	a5,32(a5)		# _11, _10->TAG_2
# main.c:363:     uart_puthex32(DMEM->TAG_2);
	mv	a0,a5	#, _11
	call	uart_puthex32		#
# main.c:364:     uart_puthex32(DMEM->TAG_3);
	li	a5,268435456		# _12,
	lw	a5,36(a5)		# _13, _12->TAG_3
# main.c:364:     uart_puthex32(DMEM->TAG_3);
	mv	a0,a5	#, _13
	call	uart_puthex32		#
# main.c:365:     uart_puts("\r\n");
	lui	a5,%hi(.LC4)	# tmp161,
	addi	a0,a5,%lo(.LC4)	#, tmp161,
	call	uart_puts		#
.L24:
# main.c:366: }
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	step6_print_result, .-step6_print_result
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	sw	s1,20(sp)	#,
	addi	s0,sp,32	#,,
# main.c:378:     step1_write_ptext_to_dmem();
	call	step1_write_ptext_to_dmem		#
# main.c:381:     retcode = step2_reset_and_config();
	call	step2_reset_and_config		#
	sw	a0,-20(s0)	#, retcode
# main.c:382:     if (retcode != 0) {
	lw	a5,-20(s0)		# tmp149, retcode
	beq	a5,zero,.L31	#, tmp149,,
# main.c:383:         step6_print_result(DMEM->STATUS, retcode);
	li	a5,268435456		# _1,
	lw	a5,84(a5)		# _2, _1->STATUS
# main.c:383:         step6_print_result(DMEM->STATUS, retcode);
	lw	a1,-20(s0)		#, retcode
	mv	a0,a5	#, _2
	call	step6_print_result		#
# main.c:384:         return retcode;
	lw	a5,-20(s0)		# _14, retcode
	j	.L32		#
.L31:
# main.c:388:     step3_kick_dma();
	call	step3_kick_dma		#
# main.c:391:     status_val = step4_poll_done();
	call	step4_poll_done		#
	sw	a0,-24(s0)	#, status_val
# main.c:394:     if (status_val == 0u) {
	lw	a5,-24(s0)		# tmp150, status_val
	bne	a5,zero,.L33	#, tmp150,,
# main.c:395:         retcode = -2;
	li	a5,-2		# tmp151,
	sw	a5,-20(s0)	# tmp151, retcode
# main.c:396:         DMEM->STATUS  = ascon_read_status();
	li	s1,268435456		# _3,
# main.c:396:         DMEM->STATUS  = ascon_read_status();
	call	ascon_read_status		#
	mv	a5,a0	# _4,
# main.c:396:         DMEM->STATUS  = ascon_read_status();
	sw	a5,84(s1)	# _4, _3->STATUS
# main.c:397:         DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	li	a5,268435456		# _5,
# main.c:397:         DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	lw	a4,-20(s0)		# retcode.2_6, retcode
# main.c:397:         DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	sw	a4,88(a5)	# retcode.2_6, _5->RETCODE
# main.c:398:         __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 398 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:399:         ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
 #NO_APP
	li	a5,536870912		# _7,
	li	a4,2		# tmp152,
	sw	a4,0(a5)	# tmp152, _7->CTRL
 #APP
# 399 "main.c" 1
	fence w,w
# 0 "" 2
# 399 "main.c" 1
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
# main.c:400:         step6_print_result(0u, retcode);
 #NO_APP
	lw	a1,-20(s0)		#, retcode
	li	a0,0		#,
	call	step6_print_result		#
# main.c:401:         return retcode;
	lw	a5,-20(s0)		# _14, retcode
	j	.L32		#
.L33:
# main.c:405:     if (status_val & STATUS_ANY_ERROR) {
	lw	a5,-24(s0)		# tmp153, status_val
	andi	a5,a5,4	#, _8, tmp153
# main.c:405:     if (status_val & STATUS_ANY_ERROR) {
	beq	a5,zero,.L34	#, _8,,
# main.c:406:         retcode = -1;
	li	a5,-1		# tmp154,
	sw	a5,-20(s0)	# tmp154, retcode
# main.c:407:         DMEM->STATUS  = status_val;
	li	a5,268435456		# _9,
# main.c:407:         DMEM->STATUS  = status_val;
	lw	a4,-24(s0)		# tmp155, status_val
	sw	a4,84(a5)	# tmp155, _9->STATUS
# main.c:408:         DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	li	a5,268435456		# _10,
# main.c:408:         DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	lw	a4,-20(s0)		# retcode.3_11, retcode
# main.c:408:         DMEM->RETCODE = (uint32_t)(int32_t)retcode;
	sw	a4,88(a5)	# retcode.3_11, _10->RETCODE
# main.c:409:         __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 409 "main.c" 1
	fence w,w
# 0 "" 2
# main.c:410:         ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
 #NO_APP
	li	a5,536870912		# _12,
	li	a4,2		# tmp156,
	sw	a4,0(a5)	# tmp156, _12->CTRL
 #APP
# 410 "main.c" 1
	fence w,w
# 0 "" 2
# 410 "main.c" 1
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
# main.c:411:         step6_print_result(status_val, retcode);
 #NO_APP
	lw	a1,-20(s0)		#, retcode
	lw	a0,-24(s0)		#, status_val
	call	step6_print_result		#
# main.c:412:         return retcode;
	lw	a5,-20(s0)		# _14, retcode
	j	.L32		#
.L34:
# main.c:416:     step5_copy_results_to_dmem(status_val, 0);
	li	a1,0		#,
	lw	a0,-24(s0)		#, status_val
	call	step5_copy_results_to_dmem		#
# main.c:419:     step6_print_result(status_val, 0);
	li	a1,0		#,
	lw	a0,-24(s0)		#, status_val
	call	step6_print_result		#
# main.c:422:     ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
	li	a5,536870912		# _13,
	li	a4,2		# tmp157,
	sw	a4,0(a5)	# tmp157, _13->CTRL
 #APP
# 422 "main.c" 1
	fence w,w
# 0 "" 2
# 422 "main.c" 1
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
# main.c:424:     return 0;
 #NO_APP
	li	a5,0		# _14,
.L32:
# main.c:425: }
	mv	a0,a5	#, <retval>
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	lw	s1,20(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
