	.file	"fw_t1.c"
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
	.type	uart_init, @function
uart_init:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# uart_drv.h:52:     UART_BAUD = UART_BAUD_115200;
	li	a5,1342177280		# tmp136,
	addi	a5,a5,16	#, _1, tmp136
# uart_drv.h:52:     UART_BAUD = UART_BAUD_115200;
	li	a4,867		# tmp137,
	sw	a4,0(a5)	# tmp137, *_1
# uart_drv.h:53:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 53 "uart_drv.h" 1
	fence w,w
# 0 "" 2
# uart_drv.h:56:     UART_CTRL = 0x1;  /* tx_irq_en = 1 */
 #NO_APP
	li	a5,1342177280		# tmp138,
	addi	a5,a5,12	#, _2, tmp138
# uart_drv.h:56:     UART_CTRL = 0x1;  /* tx_irq_en = 1 */
	li	a4,1		# tmp139,
	sw	a4,0(a5)	# tmp139, *_2
# uart_drv.h:57:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 57 "uart_drv.h" 1
	fence w,w
# 0 "" 2
# uart_drv.h:58: }
 #NO_APP
	nop	
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	uart_init, .-uart_init
	.align	2
	.type	uart_putc, @function
uart_putc:
	addi	sp,sp,-48	#,,
	sw	s0,44(sp)	#,
	addi	s0,sp,48	#,,
	mv	a5,a0	# tmp139, c
	sb	a5,-33(s0)	# tmp140, c
# uart_drv.h:66:     volatile uint32_t delay = UART_TX_DELAY_CYCLES;
	li	a5,8192		# tmp142,
	addi	a5,a5,608	#, tmp141, tmp142
	sw	a5,-20(s0)	# tmp141, delay
# uart_drv.h:68:     UART_TX_REG = (uint32_t)(uint8_t)c;
	li	a5,1342177280		# _1,
# uart_drv.h:68:     UART_TX_REG = (uint32_t)(uint8_t)c;
	lbu	a4,-33(s0)	# _2, c
# uart_drv.h:68:     UART_TX_REG = (uint32_t)(uint8_t)c;
	sw	a4,0(a5)	# _2, *_1
# uart_drv.h:69:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 69 "uart_drv.h" 1
	fence w,w
# 0 "" 2
# uart_drv.h:71:     while (delay > 0u)
 #NO_APP
	j	.L5		#
.L6:
# uart_drv.h:72:         delay--;
	lw	a5,-20(s0)		# delay.0_3, delay
	addi	a5,a5,-1	#, _4, delay.0_3
	sw	a5,-20(s0)	# _4, delay
.L5:
# uart_drv.h:71:     while (delay > 0u)
	lw	a5,-20(s0)		# delay.1_5, delay
	bne	a5,zero,.L6	#, delay.1_5,,
# uart_drv.h:73: }
	nop	
	nop	
	lw	s0,44(sp)		#,
	addi	sp,sp,48	#,,
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
# uart_drv.h:81:     while (*s)
	j	.L8		#
.L9:
# uart_drv.h:82:         uart_putc(*s++);
	lw	a5,-20(s0)		# s.2_1, s
	addi	a4,a5,1	#, tmp137, s.2_1
	sw	a4,-20(s0)	# tmp137, s
# uart_drv.h:82:         uart_putc(*s++);
	lbu	a5,0(a5)	# _2, *s.2_1
	mv	a0,a5	#, _2
	call	uart_putc		#
.L8:
# uart_drv.h:81:     while (*s)
	lw	a5,-20(s0)		# tmp138, s
	lbu	a5,0(a5)	# _3, *s_4
	bne	a5,zero,.L9	#, _3,,
# uart_drv.h:83: }
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
# uart_drv.h:91:     const char *hex = "0123456789ABCDEF";
	lui	a5,%hi(.LC0)	# tmp146,
	addi	a5,a5,%lo(.LC0)	# tmp145, tmp146,
	sw	a5,-20(s0)	# tmp145, hex
# uart_drv.h:92:     uart_putc(hex[(v >> 4) & 0xF]);
	lbu	a5,-33(s0)	# tmp147, v
	srli	a5,a5,4	#, tmp148, tmp147
	andi	a5,a5,0xff	# _1, tmp148
	andi	a5,a5,15	#, _3, _2
# uart_drv.h:92:     uart_putc(hex[(v >> 4) & 0xF]);
	lw	a4,-20(s0)		# tmp149, hex
	add	a5,a4,a5	# _3, _4, tmp149
# uart_drv.h:92:     uart_putc(hex[(v >> 4) & 0xF]);
	lbu	a5,0(a5)	# _5, *_4
	mv	a0,a5	#, _5
	call	uart_putc		#
# uart_drv.h:93:     uart_putc(hex[v & 0xF]);
	lbu	a5,-33(s0)	# _6, v
	andi	a5,a5,15	#, _7, _6
# uart_drv.h:93:     uart_putc(hex[v & 0xF]);
	lw	a4,-20(s0)		# tmp150, hex
	add	a5,a4,a5	# _7, _8, tmp150
# uart_drv.h:93:     uart_putc(hex[v & 0xF]);
	lbu	a5,0(a5)	# _9, *_8
	mv	a0,a5	#, _9
	call	uart_putc		#
# uart_drv.h:94: }
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
# uart_drv.h:102:     uart_puthex8((uint8_t)(v >> 24));
	lw	a5,-20(s0)		# tmp141, v
	srli	a5,a5,24	#, _1, tmp141
# uart_drv.h:102:     uart_puthex8((uint8_t)(v >> 24));
	andi	a5,a5,0xff	# _2, _1
	mv	a0,a5	#, _2
	call	uart_puthex8		#
# uart_drv.h:103:     uart_puthex8((uint8_t)(v >> 16));
	lw	a5,-20(s0)		# tmp142, v
	srli	a5,a5,16	#, _3, tmp142
# uart_drv.h:103:     uart_puthex8((uint8_t)(v >> 16));
	andi	a5,a5,0xff	# _4, _3
	mv	a0,a5	#, _4
	call	uart_puthex8		#
# uart_drv.h:104:     uart_puthex8((uint8_t)(v >>  8));
	lw	a5,-20(s0)		# tmp143, v
	srli	a5,a5,8	#, _5, tmp143
# uart_drv.h:104:     uart_puthex8((uint8_t)(v >>  8));
	andi	a5,a5,0xff	# _6, _5
	mv	a0,a5	#, _6
	call	uart_puthex8		#
# uart_drv.h:105:     uart_puthex8((uint8_t)(v      ));
	lw	a5,-20(s0)		# tmp144, v
	andi	a5,a5,0xff	# _7, tmp144
	mv	a0,a5	#, _7
	call	uart_puthex8		#
# uart_drv.h:106: }
	nop	
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_puthex32, .-uart_puthex32
	.align	2
	.type	uart_putc_fast, @function
uart_putc_fast:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
	mv	a5,a0	# tmp136, c
	sb	a5,-17(s0)	# tmp137, c
# uart_drv.h:129:     UART_TX_REG = (uint32_t)(uint8_t)c;
	li	a5,1342177280		# _1,
# uart_drv.h:129:     UART_TX_REG = (uint32_t)(uint8_t)c;
	lbu	a4,-17(s0)	# _2, c
# uart_drv.h:129:     UART_TX_REG = (uint32_t)(uint8_t)c;
	sw	a4,0(a5)	# _2, *_1
# uart_drv.h:130:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 130 "uart_drv.h" 1
	fence w,w
# 0 "" 2
# uart_drv.h:132:     __asm__ volatile (
# 132 "uart_drv.h" 1
	nop
nop
nop
nop
nop
nop
nop
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
# uart_drv.h:137: }
 #NO_APP
	nop	
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_putc_fast, .-uart_putc_fast
	.align	2
	.type	uart_puts_fast, @function
uart_puts_fast:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# s, s
# uart_drv.h:142:     while (*s)
	j	.L14		#
.L15:
# uart_drv.h:143:         uart_putc_fast(*s++);
	lw	a5,-20(s0)		# s.3_1, s
	addi	a4,a5,1	#, tmp137, s.3_1
	sw	a4,-20(s0)	# tmp137, s
# uart_drv.h:143:         uart_putc_fast(*s++);
	lbu	a5,0(a5)	# _2, *s.3_1
	mv	a0,a5	#, _2
	call	uart_putc_fast		#
.L14:
# uart_drv.h:142:     while (*s)
	lw	a5,-20(s0)		# tmp138, s
	lbu	a5,0(a5)	# _3, *s_4
	bne	a5,zero,.L15	#, _3,,
# uart_drv.h:144: }
	nop	
	nop	
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_puts_fast, .-uart_puts_fast
	.align	2
	.type	uart_puthex8_fast, @function
uart_puthex8_fast:
	addi	sp,sp,-48	#,,
	sw	ra,44(sp)	#,
	sw	s0,40(sp)	#,
	addi	s0,sp,48	#,,
	mv	a5,a0	# tmp143, v
	sb	a5,-33(s0)	# tmp144, v
# uart_drv.h:149:     const char *hex = "0123456789ABCDEF";
	lui	a5,%hi(.LC0)	# tmp146,
	addi	a5,a5,%lo(.LC0)	# tmp145, tmp146,
	sw	a5,-20(s0)	# tmp145, hex
# uart_drv.h:150:     uart_putc_fast(hex[(v >> 4) & 0xF]);
	lbu	a5,-33(s0)	# tmp147, v
	srli	a5,a5,4	#, tmp148, tmp147
	andi	a5,a5,0xff	# _1, tmp148
	andi	a5,a5,15	#, _3, _2
# uart_drv.h:150:     uart_putc_fast(hex[(v >> 4) & 0xF]);
	lw	a4,-20(s0)		# tmp149, hex
	add	a5,a4,a5	# _3, _4, tmp149
# uart_drv.h:150:     uart_putc_fast(hex[(v >> 4) & 0xF]);
	lbu	a5,0(a5)	# _5, *_4
	mv	a0,a5	#, _5
	call	uart_putc_fast		#
# uart_drv.h:151:     uart_putc_fast(hex[v & 0xF]);
	lbu	a5,-33(s0)	# _6, v
	andi	a5,a5,15	#, _7, _6
# uart_drv.h:151:     uart_putc_fast(hex[v & 0xF]);
	lw	a4,-20(s0)		# tmp150, hex
	add	a5,a4,a5	# _7, _8, tmp150
# uart_drv.h:151:     uart_putc_fast(hex[v & 0xF]);
	lbu	a5,0(a5)	# _9, *_8
	mv	a0,a5	#, _9
	call	uart_putc_fast		#
# uart_drv.h:152: }
	nop	
	lw	ra,44(sp)		#,
	lw	s0,40(sp)		#,
	addi	sp,sp,48	#,,
	jr	ra		#
	.size	uart_puthex8_fast, .-uart_puthex8_fast
	.align	2
	.type	uart_puthex32_fast, @function
uart_puthex32_fast:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# v, v
# uart_drv.h:157:     uart_puthex8_fast((uint8_t)(v >> 24));
	lw	a5,-20(s0)		# tmp141, v
	srli	a5,a5,24	#, _1, tmp141
# uart_drv.h:157:     uart_puthex8_fast((uint8_t)(v >> 24));
	andi	a5,a5,0xff	# _2, _1
	mv	a0,a5	#, _2
	call	uart_puthex8_fast		#
# uart_drv.h:158:     uart_puthex8_fast((uint8_t)(v >> 16));
	lw	a5,-20(s0)		# tmp142, v
	srli	a5,a5,16	#, _3, tmp142
# uart_drv.h:158:     uart_puthex8_fast((uint8_t)(v >> 16));
	andi	a5,a5,0xff	# _4, _3
	mv	a0,a5	#, _4
	call	uart_puthex8_fast		#
# uart_drv.h:159:     uart_puthex8_fast((uint8_t)(v >>  8));
	lw	a5,-20(s0)		# tmp143, v
	srli	a5,a5,8	#, _5, tmp143
# uart_drv.h:159:     uart_puthex8_fast((uint8_t)(v >>  8));
	andi	a5,a5,0xff	# _6, _5
	mv	a0,a5	#, _6
	call	uart_puthex8_fast		#
# uart_drv.h:160:     uart_puthex8_fast((uint8_t)(v      ));
	lw	a5,-20(s0)		# tmp144, v
	andi	a5,a5,0xff	# _7, tmp144
	mv	a0,a5	#, _7
	call	uart_puthex8_fast		#
# uart_drv.h:161: }
	nop	
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	uart_puthex32_fast, .-uart_puthex32_fast
	.section	.rodata
	.align	2
.LC1:
	.string	"\r\n=ASCON RESULT=\r\n"
	.align	2
.LC2:
	.string	"C:"
	.align	2
.LC3:
	.string	"\r\n"
	.align	2
.LC4:
	.string	"T:"
	.align	2
.LC5:
	.string	"STS:"
	.align	2
.LC6:
	.string	"RET:"
	.align	2
.LC7:
	.string	"OK"
	.align	2
.LC8:
	.string	"E-1"
	.align	2
.LC9:
	.string	"E-2"
	.align	2
.LC10:
	.string	"E-3"
	.align	2
.LC11:
	.string	"E-?"
	.text
	.align	2
	.type	uart_print_result, @function
uart_print_result:
	addi	sp,sp,-48	#,,
	sw	ra,44(sp)	#,
	sw	s0,40(sp)	#,
	addi	s0,sp,48	#,,
	sw	a0,-20(s0)	# ctext0, ctext0
	sw	a1,-24(s0)	# ctext1, ctext1
	sw	a2,-28(s0)	# tag0, tag0
	sw	a3,-32(s0)	# tag1, tag1
	sw	a4,-36(s0)	# tag2, tag2
	sw	a5,-40(s0)	# tag3, tag3
	sw	a6,-44(s0)	# status_val, status_val
	sw	a7,-48(s0)	# retcode, retcode
# uart_drv.h:170:     uart_puts_fast("\r\n=ASCON RESULT=\r\n");
	lui	a5,%hi(.LC1)	# tmp134,
	addi	a0,a5,%lo(.LC1)	#, tmp134,
	call	uart_puts_fast		#
# uart_drv.h:172:     uart_puts_fast("C:");
	lui	a5,%hi(.LC2)	# tmp135,
	addi	a0,a5,%lo(.LC2)	#, tmp135,
	call	uart_puts_fast		#
# uart_drv.h:173:     uart_puthex32_fast(ctext0);
	lw	a0,-20(s0)		#, ctext0
	call	uart_puthex32_fast		#
# uart_drv.h:174:     uart_puthex32_fast(ctext1);
	lw	a0,-24(s0)		#, ctext1
	call	uart_puthex32_fast		#
# uart_drv.h:175:     uart_puts_fast("\r\n");
	lui	a5,%hi(.LC3)	# tmp136,
	addi	a0,a5,%lo(.LC3)	#, tmp136,
	call	uart_puts_fast		#
# uart_drv.h:177:     uart_puts_fast("T:");
	lui	a5,%hi(.LC4)	# tmp137,
	addi	a0,a5,%lo(.LC4)	#, tmp137,
	call	uart_puts_fast		#
# uart_drv.h:178:     uart_puthex32_fast(tag0);
	lw	a0,-28(s0)		#, tag0
	call	uart_puthex32_fast		#
# uart_drv.h:179:     uart_puthex32_fast(tag1);
	lw	a0,-32(s0)		#, tag1
	call	uart_puthex32_fast		#
# uart_drv.h:180:     uart_puthex32_fast(tag2);
	lw	a0,-36(s0)		#, tag2
	call	uart_puthex32_fast		#
# uart_drv.h:181:     uart_puthex32_fast(tag3);
	lw	a0,-40(s0)		#, tag3
	call	uart_puthex32_fast		#
# uart_drv.h:182:     uart_puts_fast("\r\n");
	lui	a5,%hi(.LC3)	# tmp138,
	addi	a0,a5,%lo(.LC3)	#, tmp138,
	call	uart_puts_fast		#
# uart_drv.h:184:     uart_puts_fast("STS:");
	lui	a5,%hi(.LC5)	# tmp139,
	addi	a0,a5,%lo(.LC5)	#, tmp139,
	call	uart_puts_fast		#
# uart_drv.h:185:     uart_puthex32_fast(status_val);
	lw	a0,-44(s0)		#, status_val
	call	uart_puthex32_fast		#
# uart_drv.h:186:     uart_puts_fast("\r\n");
	lui	a5,%hi(.LC3)	# tmp140,
	addi	a0,a5,%lo(.LC3)	#, tmp140,
	call	uart_puts_fast		#
# uart_drv.h:188:     uart_puts_fast("RET:");
	lui	a5,%hi(.LC6)	# tmp141,
	addi	a0,a5,%lo(.LC6)	#, tmp141,
	call	uart_puts_fast		#
# uart_drv.h:189:     if      (retcode ==  0) uart_puts_fast("OK");
	lw	a5,-48(s0)		# tmp142, retcode
	bne	a5,zero,.L19	#, tmp142,,
# uart_drv.h:189:     if      (retcode ==  0) uart_puts_fast("OK");
	lui	a5,%hi(.LC7)	# tmp143,
	addi	a0,a5,%lo(.LC7)	#, tmp143,
	call	uart_puts_fast		#
	j	.L20		#
.L19:
# uart_drv.h:190:     else if (retcode == -1) uart_puts_fast("E-1");
	lw	a4,-48(s0)		# tmp144, retcode
	li	a5,-1		# tmp145,
	bne	a4,a5,.L21	#, tmp144, tmp145,
# uart_drv.h:190:     else if (retcode == -1) uart_puts_fast("E-1");
	lui	a5,%hi(.LC8)	# tmp146,
	addi	a0,a5,%lo(.LC8)	#, tmp146,
	call	uart_puts_fast		#
	j	.L20		#
.L21:
# uart_drv.h:191:     else if (retcode == -2) uart_puts_fast("E-2");
	lw	a4,-48(s0)		# tmp147, retcode
	li	a5,-2		# tmp148,
	bne	a4,a5,.L22	#, tmp147, tmp148,
# uart_drv.h:191:     else if (retcode == -2) uart_puts_fast("E-2");
	lui	a5,%hi(.LC9)	# tmp149,
	addi	a0,a5,%lo(.LC9)	#, tmp149,
	call	uart_puts_fast		#
	j	.L20		#
.L22:
# uart_drv.h:192:     else if (retcode == -3) uart_puts_fast("E-3");
	lw	a4,-48(s0)		# tmp150, retcode
	li	a5,-3		# tmp151,
	bne	a4,a5,.L23	#, tmp150, tmp151,
# uart_drv.h:192:     else if (retcode == -3) uart_puts_fast("E-3");
	lui	a5,%hi(.LC10)	# tmp152,
	addi	a0,a5,%lo(.LC10)	#, tmp152,
	call	uart_puts_fast		#
	j	.L20		#
.L23:
# uart_drv.h:193:     else                    uart_puts_fast("E-?");
	lui	a5,%hi(.LC11)	# tmp153,
	addi	a0,a5,%lo(.LC11)	#, tmp153,
	call	uart_puts_fast		#
.L20:
# uart_drv.h:194:     uart_puts_fast("\r\n");
	lui	a5,%hi(.LC3)	# tmp154,
	addi	a0,a5,%lo(.LC3)	#, tmp154,
	call	uart_puts_fast		#
# uart_drv.h:195: }
	nop	
	lw	ra,44(sp)		#,
	lw	s0,40(sp)		#,
	addi	sp,sp,48	#,,
	jr	ra		#
	.size	uart_print_result, .-uart_print_result
	.align	2
	.globl	trap_handler
	.type	trap_handler, @function
trap_handler:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
.L25:
# fw_t1.c:51:     for (;;) {}
	j	.L25		#
	.size	trap_handler, .-trap_handler
	.section	.rodata
	.align	2
.LC12:
	.string	"T1:START\r\n"
	.align	2
.LC13:
	.string	"T1:REGS_WRITTEN\r\n"
	.align	2
.LC14:
	.string	"T1:ST="
	.align	2
.LC15:
	.string	"T1:FAIL:ERR\r\n"
	.align	2
.LC16:
	.string	"T1:OK\r\n"
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
# fw_t1.c:61:     uart_init();
	call	uart_init		#
# fw_t1.c:62:     uart_puts_fast("T1:START\r\n");
	lui	a5,%hi(.LC12)	# tmp152,
	addi	a0,a5,%lo(.LC12)	#, tmp152,
	call	uart_puts_fast		#
# fw_t1.c:65:     ASCON_WRITE(ASCON->CTRL, CTRL_SOFT_RST);
	li	a5,536870912		# _1,
	li	a4,2		# tmp153,
	sw	a4,32(a5)	# tmp153, _1->CTRL
# fw_t1.c:66:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 66 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:69:     ASCON_WRITE(ASCON->IRQ_EN, 0u);
 #NO_APP
	li	a5,536870912		# _2,
	sw	zero,12(a5)	#, _2->IRQ_EN
# fw_t1.c:70:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 70 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:73:     ASCON_WRITE(ASCON->MODE, MODE_ENCRYPT);
 #NO_APP
	li	a5,536870912		# _3,
	li	a4,1		# tmp154,
	sw	a4,0(a5)	# tmp154, _3->MODE
# fw_t1.c:74:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 74 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:77:     ASCON_WRITE(ASCON->KEY_0, 0x00112233u);
 #NO_APP
	li	a5,536870912		# _4,
	li	a4,1122304		# tmp156,
	addi	a4,a4,563	#, tmp155, tmp156
	sw	a4,16(a5)	# tmp155, _4->KEY_0
# fw_t1.c:78:     ASCON_WRITE(ASCON->KEY_1, 0x44556677u);
	li	a5,536870912		# _5,
	li	a4,1146445824		# tmp158,
	addi	a4,a4,1655	#, tmp157, tmp158
	sw	a4,20(a5)	# tmp157, _5->KEY_1
# fw_t1.c:79:     ASCON_WRITE(ASCON->KEY_2, 0x8899AABBu);
	li	a5,536870912		# _6,
	li	a4,-2003193856		# tmp160,
	addi	a4,a4,-1349	#, tmp159, tmp160
	sw	a4,24(a5)	# tmp159, _6->KEY_2
# fw_t1.c:80:     ASCON_WRITE(ASCON->KEY_3, 0xCCDDEEFFu);
	li	a5,536870912		# _7,
	li	a4,-857870336		# tmp162,
	addi	a4,a4,-257	#, tmp161, tmp162
	sw	a4,28(a5)	# tmp161, _7->KEY_3
# fw_t1.c:81:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 81 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:84:     ASCON_WRITE(ASCON->NONCE_0, 0xDEADBEEFu);
 #NO_APP
	li	a5,536870912		# _8,
	li	a4,-559038464		# tmp164,
	addi	a4,a4,-273	#, tmp163, tmp164
	sw	a4,36(a5)	# tmp163, _8->NONCE_0
# fw_t1.c:85:     ASCON_WRITE(ASCON->NONCE_1, 0xCAFEBABEu);
	li	a5,536870912		# _9,
	li	a4,-889274368		# tmp166,
	addi	a4,a4,-1346	#, tmp165, tmp166
	sw	a4,40(a5)	# tmp165, _9->NONCE_1
# fw_t1.c:86:     ASCON_WRITE(ASCON->NONCE_2, 0x01234567u);
	li	a5,536870912		# _10,
	li	a4,19087360		# tmp168,
	addi	a4,a4,1383	#, tmp167, tmp168
	sw	a4,44(a5)	# tmp167, _10->NONCE_2
# fw_t1.c:87:     ASCON_WRITE(ASCON->NONCE_3, 0x89ABCDEFu);
	li	a5,536870912		# _11,
	li	a4,-1985228800		# tmp170,
	addi	a4,a4,-529	#, tmp169, tmp170
	sw	a4,48(a5)	# tmp169, _11->NONCE_3
# fw_t1.c:88:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 88 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:91:     ASCON_WRITE(ASCON->PTEXT_0, 0x48656C6Cu);
 #NO_APP
	li	a5,536870912		# _12,
	li	a4,1214607360		# tmp172,
	addi	a4,a4,-916	#, tmp171, tmp172
	sw	a4,52(a5)	# tmp171, _12->PTEXT_0
# fw_t1.c:92:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 92 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:95:     ASCON_WRITE(ASCON->DATA_LEN, (uint32_t)(4u & DATA_LEN_MASK));
 #NO_APP
	li	a5,536870912		# _13,
	li	a4,4		# tmp173,
	sw	a4,60(a5)	# tmp173, _13->DATA_LEN
# fw_t1.c:96:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 96 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:99:     ASCON_WRITE(ASCON->DMA_SRC, (uint32_t)T1_DMA_SRC_ADDR);
 #NO_APP
	li	a5,536870912		# _14,
	li	a4,268435456		# tmp175,
	addi	a4,a4,256	#, tmp174, tmp175
	sw	a4,256(a5)	# tmp174, _14->DMA_SRC
# fw_t1.c:100:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 100 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:103:     ASCON_WRITE(ASCON->DMA_DST, (uint32_t)T1_DMA_DST_ADDR);
 #NO_APP
	li	a5,536870912		# _15,
	li	a4,268435456		# tmp177,
	addi	a4,a4,272	#, tmp176, tmp177
	sw	a4,260(a5)	# tmp176, _15->DMA_DST
# fw_t1.c:104:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 104 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:107:     ASCON_WRITE(ASCON->DMA_LEN, (uint32_t)T1_DMA_OUTPUT_LEN);
 #NO_APP
	li	a5,536870912		# _16,
	li	a4,24		# tmp178,
	sw	a4,264(a5)	# tmp178, _16->DMA_LEN
# fw_t1.c:108:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 108 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:110:     uart_puts_fast("T1:REGS_WRITTEN\r\n");
 #NO_APP
	lui	a5,%hi(.LC13)	# tmp179,
	addi	a0,a5,%lo(.LC13)	#, tmp179,
	call	uart_puts_fast		#
# fw_t1.c:113:     __asm__ volatile ("fence" ::: "memory");
 #APP
# 113 "fw_t1.c" 1
	fence	
# 0 "" 2
# fw_t1.c:116:     uint32_t st = ascon_read_status();
 #NO_APP
	call	ascon_read_status		#
	sw	a0,-20(s0)	#, st
# fw_t1.c:118:     uart_puts_fast("T1:ST=");
	lui	a5,%hi(.LC14)	# tmp180,
	addi	a0,a5,%lo(.LC14)	#, tmp180,
	call	uart_puts_fast		#
# fw_t1.c:119:     uart_puthex32_fast(st);
	lw	a0,-20(s0)		#, st
	call	uart_puthex32_fast		#
# fw_t1.c:120:     uart_puts_fast("\r\n");
	lui	a5,%hi(.LC3)	# tmp181,
	addi	a0,a5,%lo(.LC3)	#, tmp181,
	call	uart_puts_fast		#
# fw_t1.c:122:     if (st & STATUS_ANY_ERROR) {
	lw	a5,-20(s0)		# tmp182, st
	andi	a5,a5,48	#, _17, tmp182
# fw_t1.c:122:     if (st & STATUS_ANY_ERROR) {
	beq	a5,zero,.L27	#, _17,,
# fw_t1.c:123:         uart_puts_fast("T1:FAIL:ERR\r\n");
	lui	a5,%hi(.LC15)	# tmp183,
	addi	a0,a5,%lo(.LC15)	#, tmp183,
	call	uart_puts_fast		#
.L28:
# fw_t1.c:124:         for (;;) {}
	j	.L28		#
.L27:
# fw_t1.c:129:     uart_puts_fast("T1:OK\r\n");
	lui	a5,%hi(.LC16)	# tmp184,
	addi	a0,a5,%lo(.LC16)	#, tmp184,
	call	uart_puts_fast		#
.L29:
# fw_t1.c:132:     for (;;) {}
	j	.L29		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
