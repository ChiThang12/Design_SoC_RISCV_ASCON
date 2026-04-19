	.file	"main.c"
	.option nopic
	.option norelax
	.attribute arch, "rv32i2p1_m2p0_zicsr2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
# GNU C17 (13.2.0-11ubuntu1+12) version 13.2.0 (riscv64-unknown-elf)
#	compiled by GNU C version 13.2.0, GMP version 6.3.0, MPFR version 4.2.1, MPC version 1.3.1, isl version isl-0.26-GMP

# GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
# options passed: -mabi=ilp32 -mno-relax -misa-spec=20191213 -march=rv32im_zicsr -O1 -ffreestanding
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
# main.c:64:     DMEM->PTEXT_0 = MY_PTEXT_0;
	li	a5,268435456		# tmp140,
	addi	a5,a5,448	#, tmp140, tmp140
	li	a3,-559038464		# tmp142,
	addi	a3,a3,-273	#, tmp142, tmp142
	sw	a3,0(a5)	# tmp142, MEM[(struct DmemLayout_t *)268435904B].PTEXT_0
# main.c:65:     DMEM->PTEXT_1 = MY_PTEXT_1;
	li	a4,19087360		# tmp146,
	addi	a4,a4,1383	#, tmp146, tmp146
	sw	a4,4(a5)	# tmp146, MEM[(struct DmemLayout_t *)268435904B].PTEXT_1
# main.c:68:     ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);
	li	a2,2		# tmp148,
 #APP
# 68 "main.c" 1
	lui  t0, 0x20000
sw   a2, 32(t0)	# tmp148,
fence w, w

# 0 "" 2
# main.c:71:     ASCON_WRITE(ASCON_OFS_MODE, ASCON_MODE_128_ENC);
 #NO_APP
	li	a2,0		# tmp149,
 #APP
# 71 "main.c" 1
	lui  t0, 0x20000
sw   a2, 0(t0)	# tmp149,
fence w, w

# 0 "" 2
# main.c:74:     ASCON_WRITE(ASCON_OFS_KEY_0, MY_KEY_0);
# 74 "main.c" 1
	lui  t0, 0x20000
sw   a3, 16(t0)	# tmp142,
fence w, w

# 0 "" 2
# main.c:75:     ASCON_WRITE(ASCON_OFS_KEY_1, MY_KEY_1);
 #NO_APP
	li	a3,-889274368		# tmp152,
	addi	a3,a3,-1346	#, tmp152, tmp152
 #APP
# 75 "main.c" 1
	lui  t0, 0x20000
sw   a3, 20(t0)	# tmp152,
fence w, w

# 0 "" 2
# main.c:76:     ASCON_WRITE(ASCON_OFS_KEY_2, MY_KEY_2);
# 76 "main.c" 1
	lui  t0, 0x20000
sw   a4, 24(t0)	# tmp146,
fence w, w

# 0 "" 2
# main.c:77:     ASCON_WRITE(ASCON_OFS_KEY_3, MY_KEY_3);
 #NO_APP
	li	a4,-1985228800		# tmp156,
	addi	a4,a4,-529	#, tmp156, tmp156
 #APP
# 77 "main.c" 1
	lui  t0, 0x20000
sw   a4, 28(t0)	# tmp156,
fence w, w

# 0 "" 2
# main.c:80:     ASCON_WRITE(ASCON_OFS_NONCE_0, MY_NONCE_0);
 #NO_APP
	li	a4,286330880		# tmp158,
	addi	a4,a4,273	#, tmp158, tmp158
 #APP
# 80 "main.c" 1
	lui  t0, 0x20000
sw   a4, 36(t0)	# tmp158,
fence w, w

# 0 "" 2
# main.c:81:     ASCON_WRITE(ASCON_OFS_NONCE_1, MY_NONCE_1);
 #NO_APP
	li	a4,572661760		# tmp160,
	addi	a4,a4,546	#, tmp160, tmp160
 #APP
# 81 "main.c" 1
	lui  t0, 0x20000
sw   a4, 40(t0)	# tmp160,
fence w, w

# 0 "" 2
# main.c:82:     ASCON_WRITE(ASCON_OFS_NONCE_2, MY_NONCE_2);
 #NO_APP
	li	a4,858992640		# tmp162,
	addi	a4,a4,819	#, tmp162, tmp162
 #APP
# 82 "main.c" 1
	lui  t0, 0x20000
sw   a4, 44(t0)	# tmp162,
fence w, w

# 0 "" 2
# main.c:83:     ASCON_WRITE(ASCON_OFS_NONCE_3, MY_NONCE_3);
 #NO_APP
	li	a4,1145323520		# tmp164,
	addi	a4,a4,1092	#, tmp164, tmp164
 #APP
# 83 "main.c" 1
	lui  t0, 0x20000
sw   a4, 48(t0)	# tmp164,
fence w, w

# 0 "" 2
# main.c:86:     ASCON_WRITE(ASCON_OFS_DMA_SRC,   DMEM_DMA_SRC_ADDR);     /* PTEXT_0 addr      */
# 86 "main.c" 1
	lui  t0, 0x20000
sw   a5, 256(t0)	# tmp140,
fence w, w

# 0 "" 2
# main.c:87:     ASCON_WRITE(ASCON_OFS_DMA_DST,   DMEM_DMA_OUTPUT_ADDR);  /* CTEXT_0 addr      */
 #NO_APP
	li	a5,268435456		# tmp168,
	addi	a5,a5,464	#, tmp168, tmp168
 #APP
# 87 "main.c" 1
	lui  t0, 0x20000
sw   a5, 260(t0)	# tmp168,
fence w, w

# 0 "" 2
# main.c:88:     ASCON_WRITE(ASCON_OFS_DMA_LEN,   DMEM_DMA_INPUT_LEN);    /* 8 bytes (2 words) */
 #NO_APP
	li	a5,8		# tmp170,
 #APP
# 88 "main.c" 1
	lui  t0, 0x20000
sw   a5, 264(t0)	# tmp170,
fence w, w

# 0 "" 2
# main.c:89:     ASCON_WRITE(ASCON_OFS_DMA_BURST, 0u);                     /* ARLEN=0: 1 beat   */
# 89 "main.c" 1
	lui  t0, 0x20000
sw   a2, 276(t0)	# tmp149,
fence w, w

# 0 "" 2
# main.c:90:     ASCON_WRITE(ASCON_OFS_DATA_LEN,  DMEM_DMA_INPUT_LEN);
# 90 "main.c" 1
	lui  t0, 0x20000
sw   a5, 60(t0)	# tmp170,
fence w, w

# 0 "" 2
# main.c:95:     __asm__ volatile ("fence rw, rw" ::: "memory");
# 95 "main.c" 1
	fence rw, rw
# 0 "" 2
# main.c:100:     ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);
 #NO_APP
	li	a5,5		# tmp173,
 #APP
# 100 "main.c" 1
	lui  t0, 0x20000
sw   a5, 32(t0)	# tmp173,
fence w, w

# 0 "" 2
 #NO_APP
	li	a5,1048576		# tmp139,
	addi	a5,a5,-1	#, ivtmp_40, tmp139
.L3:
# main.c:108:         ASCON_READ(ASCON_OFS_STATUS, status);
 #APP
# 108 "main.c" 1
	lui  t0, 0x20000
lw   a4, 4(t0)	# status,

# 0 "" 2
# main.c:109:         if (--timeout == 0u) {
 #NO_APP
	addi	a5,a5,-1	#, ivtmp_40, ivtmp_40
	beq	a5,zero,.L5	#, ivtmp_40,,
# main.c:113:     } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)));
	andi	a3,a4,56	#, tmp175, status
# main.c:113:     } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)));
	beq	a3,zero,.L3	#, tmp175,,
# main.c:115:     if (status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) {
	andi	a3,a4,48	#, retcode, status
# main.c:115:     if (status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) {
	bne	a3,zero,.L6	#, retcode,,
# main.c:121:     __asm__ volatile ("fence r, r" ::: "memory");
 #APP
# 121 "main.c" 1
	fence r, r
# 0 "" 2
 #NO_APP
.L2:
# main.c:127:     DMEM->STATUS  = status;
	li	a5,268435456		# tmp176,
	sw	a4,532(a5)	# status, MEM[(struct DmemLayout_t *)268435904B].STATUS
# main.c:128:     DMEM->RETCODE = retcode;
	sw	a3,536(a5)	# retcode, MEM[(struct DmemLayout_t *)268435904B].RETCODE
.L4:
# main.c:131:     while (1) __asm__ volatile ("nop");
 #APP
# 131 "main.c" 1
	nop
# 0 "" 2
 #NO_APP
	j	.L4		#
.L5:
# main.c:110:             retcode = (uint32_t)(-2);
	li	a3,-2		# retcode,
	j	.L2		#
.L6:
# main.c:116:         retcode = (uint32_t)(-1);
	li	a3,-1		# retcode,
	j	.L2		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
