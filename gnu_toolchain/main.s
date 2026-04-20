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
# main.c:59: {
	li	a4,268435456		# ivtmp.13,
	addi	a4,a4,544	#, ivtmp.13, ivtmp.13
# main.c:69:     for (i = 0u; i < (uint32_t)DMEM_MULTI_BLOCK_COUNT; i++) {
	li	a5,0		# i,
# main.c:70:         pt[i * 2u]      = (uint32_t)(0xA0000000u | i);
	li	a0,-1610612736		# tmp148,
# main.c:71:         pt[i * 2u + 1u] = (uint32_t)(0xB0000000u | i);
	li	a1,-1342177280		# tmp149,
# main.c:69:     for (i = 0u; i < (uint32_t)DMEM_MULTI_BLOCK_COUNT; i++) {
	li	a2,16		# tmp150,
.L2:
# main.c:70:         pt[i * 2u]      = (uint32_t)(0xA0000000u | i);
	or	a3,a5,a0	# tmp148, _3, i
# main.c:70:         pt[i * 2u]      = (uint32_t)(0xA0000000u | i);
	sw	a3,0(a4)	# _3, *_2
# main.c:71:         pt[i * 2u + 1u] = (uint32_t)(0xB0000000u | i);
	or	a3,a5,a1	# tmp149, _6, i
# main.c:71:         pt[i * 2u + 1u] = (uint32_t)(0xB0000000u | i);
	sw	a3,4(a4)	# _6, *_5
# main.c:69:     for (i = 0u; i < (uint32_t)DMEM_MULTI_BLOCK_COUNT; i++) {
	addi	a5,a5,1	#, i, i
# main.c:69:     for (i = 0u; i < (uint32_t)DMEM_MULTI_BLOCK_COUNT; i++) {
	addi	a4,a4,8	#, ivtmp.13, ivtmp.13
	bne	a5,a2,.L2	#, i, tmp150,
# main.c:75:     ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);
	li	a4,2		# tmp151,
 #APP
# 75 "main.c" 1
	lui  t0, 0x20000
sw   a4, 32(t0)	# tmp151,
fence w, w

# 0 "" 2
# main.c:78:     ASCON_WRITE(ASCON_OFS_MODE, ASCON_MODE_128_ENC);
 #NO_APP
	li	a5,0		# tmp152,
 #APP
# 78 "main.c" 1
	lui  t0, 0x20000
sw   a5, 0(t0)	# tmp152,
fence w, w

# 0 "" 2
# main.c:81:     ASCON_WRITE(ASCON_OFS_KEY_0, MY_KEY_0);
 #NO_APP
	li	a5,-559038464		# tmp153,
	addi	a5,a5,-273	#, tmp153, tmp153
 #APP
# 81 "main.c" 1
	lui  t0, 0x20000
sw   a5, 16(t0)	# tmp153,
fence w, w

# 0 "" 2
# main.c:82:     ASCON_WRITE(ASCON_OFS_KEY_1, MY_KEY_1);
 #NO_APP
	li	a5,-889274368		# tmp155,
	addi	a5,a5,-1346	#, tmp155, tmp155
 #APP
# 82 "main.c" 1
	lui  t0, 0x20000
sw   a5, 20(t0)	# tmp155,
fence w, w

# 0 "" 2
# main.c:83:     ASCON_WRITE(ASCON_OFS_KEY_2, MY_KEY_2);
 #NO_APP
	li	a5,19087360		# tmp157,
	addi	a5,a5,1383	#, tmp157, tmp157
 #APP
# 83 "main.c" 1
	lui  t0, 0x20000
sw   a5, 24(t0)	# tmp157,
fence w, w

# 0 "" 2
# main.c:84:     ASCON_WRITE(ASCON_OFS_KEY_3, MY_KEY_3);
 #NO_APP
	li	a5,-1985228800		# tmp159,
	addi	a5,a5,-529	#, tmp159, tmp159
 #APP
# 84 "main.c" 1
	lui  t0, 0x20000
sw   a5, 28(t0)	# tmp159,
fence w, w

# 0 "" 2
# main.c:87:     ASCON_WRITE(ASCON_OFS_NONCE_0, MY_NONCE_0);
 #NO_APP
	li	a5,286330880		# tmp161,
	addi	a5,a5,273	#, tmp161, tmp161
 #APP
# 87 "main.c" 1
	lui  t0, 0x20000
sw   a5, 36(t0)	# tmp161,
fence w, w

# 0 "" 2
# main.c:88:     ASCON_WRITE(ASCON_OFS_NONCE_1, MY_NONCE_1);
 #NO_APP
	li	a5,572661760		# tmp163,
	addi	a5,a5,546	#, tmp163, tmp163
 #APP
# 88 "main.c" 1
	lui  t0, 0x20000
sw   a5, 40(t0)	# tmp163,
fence w, w

# 0 "" 2
# main.c:89:     ASCON_WRITE(ASCON_OFS_NONCE_2, MY_NONCE_2);
 #NO_APP
	li	a5,858992640		# tmp165,
	addi	a5,a5,819	#, tmp165, tmp165
 #APP
# 89 "main.c" 1
	lui  t0, 0x20000
sw   a5, 44(t0)	# tmp165,
fence w, w

# 0 "" 2
# main.c:90:     ASCON_WRITE(ASCON_OFS_NONCE_3, MY_NONCE_3);
 #NO_APP
	li	a5,1145323520		# tmp167,
	addi	a5,a5,1092	#, tmp167, tmp167
 #APP
# 90 "main.c" 1
	lui  t0, 0x20000
sw   a5, 48(t0)	# tmp167,
fence w, w

# 0 "" 2
# main.c:93:     ASCON_WRITE(ASCON_OFS_DMA_SRC,   PT_MULTI_BASE);           /* 0x10000220 */
 #NO_APP
	li	a5,268435456		# tmp169,
	addi	a5,a5,544	#, tmp169, tmp169
 #APP
# 93 "main.c" 1
	lui  t0, 0x20000
sw   a5, 256(t0)	# tmp169,
fence w, w

# 0 "" 2
# main.c:94:     ASCON_WRITE(ASCON_OFS_DMA_DST,   CT_MULTI_BASE);           /* 0x100002A0 */
 #NO_APP
	li	a5,268435456		# tmp171,
	addi	a5,a5,672	#, tmp171, tmp171
 #APP
# 94 "main.c" 1
	lui  t0, 0x20000
sw   a5, 260(t0)	# tmp171,
fence w, w

# 0 "" 2
# main.c:95:     ASCON_WRITE(ASCON_OFS_DMA_LEN,   DMEM_MULTI_PT_LEN);       /* 128 bytes  */
 #NO_APP
	li	a5,128		# tmp173,
 #APP
# 95 "main.c" 1
	lui  t0, 0x20000
sw   a5, 264(t0)	# tmp173,
fence w, w

# 0 "" 2
# main.c:96:     ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);                       /* [OPT-2] ARLEN=7: 8 beats per burst */
 #NO_APP
	li	a5,7		# tmp174,
 #APP
# 96 "main.c" 1
	lui  t0, 0x20000
sw   a5, 276(t0)	# tmp174,
fence w, w

# 0 "" 2
# main.c:97:     ASCON_WRITE(ASCON_OFS_DATA_LEN,  8u);                       /* 8 bytes per block */
 #NO_APP
	li	a5,8		# tmp175,
 #APP
# 97 "main.c" 1
	lui  t0, 0x20000
sw   a5, 60(t0)	# tmp175,
fence w, w

# 0 "" 2
# main.c:101:     ASCON_WRITE(ASCON_OFS_IRQ_EN, 0x02u);
# 101 "main.c" 1
	lui  t0, 0x20000
sw   a4, 12(t0)	# tmp151,
fence w, w

# 0 "" 2
# main.c:106:     __asm__ volatile ("fence rw, rw" ::: "memory");
# 106 "main.c" 1
	fence rw, rw
# 0 "" 2
# main.c:111:     ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);
 #NO_APP
	li	a5,5		# tmp177,
 #APP
# 111 "main.c" 1
	lui  t0, 0x20000
sw   a5, 32(t0)	# tmp177,
fence w, w

# 0 "" 2
 #NO_APP
	li	a5,4194304		# tmp147,
	addi	a5,a5,-1	#, ivtmp_52, tmp147
.L4:
# main.c:126:         __asm__ volatile ("nop; nop; nop; nop; nop; nop; nop; nop" ::: "memory");
 #APP
# 126 "main.c" 1
	nop; nop; nop; nop; nop; nop; nop; nop
# 0 "" 2
# main.c:127:         ASCON_READ(ASCON_OFS_STATUS, status);
# 127 "main.c" 1
	lui  t0, 0x20000
lw   a4, 4(t0)	# status,

# 0 "" 2
# main.c:128:         if (--timeout == 0u) {
 #NO_APP
	addi	a5,a5,-1	#, ivtmp_52, ivtmp_52
	beq	a5,zero,.L6	#, ivtmp_52,,
# main.c:132:     } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)));
	andi	a3,a4,56	#, tmp179, status
# main.c:132:     } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)));
	beq	a3,zero,.L4	#, tmp179,,
# main.c:134:     if (status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) {
	andi	a3,a4,48	#, retcode, status
# main.c:134:     if (status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) {
	bne	a3,zero,.L7	#, retcode,,
# main.c:140:     __asm__ volatile ("fence r, r" ::: "memory");
 #APP
# 140 "main.c" 1
	fence r, r
# 0 "" 2
 #NO_APP
.L3:
# main.c:146:     DMEM->STATUS  = status;
	li	a5,268435456		# tmp180,
	sw	a4,532(a5)	# status, MEM[(struct DmemLayout_t *)268435904B].STATUS
# main.c:147:     DMEM->RETCODE = retcode;
	sw	a3,536(a5)	# retcode, MEM[(struct DmemLayout_t *)268435904B].RETCODE
.L5:
# main.c:150:     while (1) __asm__ volatile ("nop");
 #APP
# 150 "main.c" 1
	nop
# 0 "" 2
 #NO_APP
	j	.L5		#
.L6:
# main.c:129:             retcode = (uint32_t)(-2);
	li	a3,-2		# retcode,
	j	.L3		#
.L7:
# main.c:135:         retcode = (uint32_t)(-1);
	li	a3,-1		# retcode,
	j	.L3		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
