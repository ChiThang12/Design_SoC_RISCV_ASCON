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
# main.c:92:     SW_SINGLE(DMEM_BASE + offsetof(DmemLayout_t, PTEXT_0), MY_PTEXT);
	li	a5,268435456		# tmp147,
	addi	a5,a5,448	#, tmp147, tmp147
	li	a4,-559038464		# tmp149,
	addi	a4,a4,-273	#, tmp149, tmp149
 #APP
# 92 "main.c" 1
	sw   a4, 0(a5)	# tmp149, tmp147
fence w, w

# 0 "" 2
# 92 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:97:     ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);
 #NO_APP
	li	a3,2		# tmp151,
 #APP
# 97 "main.c" 1
	lui  t0, 0x20000
sw   a3, 32(t0)	# tmp151,
fence w, w

# 0 "" 2
# main.c:98:     NOP_BARRIER();
# 98 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:99:     NOP_BARRIER();
# 99 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:102:     ASCON_WRITE(ASCON_OFS_MODE, ASCON_MODE_128_ENC);
 #NO_APP
	li	a3,0		# tmp152,
 #APP
# 102 "main.c" 1
	lui  t0, 0x20000
sw   a3, 0(t0)	# tmp152,
fence w, w

# 0 "" 2
# main.c:103:     NOP_BARRIER();
# 103 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:111:     ASCON_WRITE(ASCON_OFS_KEY_0, MY_KEY_0);
# 111 "main.c" 1
	lui  t0, 0x20000
sw   a4, 16(t0)	# tmp149,
fence w, w

# 0 "" 2
# main.c:112:     NOP_BARRIER();
# 112 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:113:     ASCON_WRITE(ASCON_OFS_KEY_1, MY_KEY_1);
 #NO_APP
	li	a4,-889274368		# tmp155,
	addi	a4,a4,-1346	#, tmp155, tmp155
 #APP
# 113 "main.c" 1
	lui  t0, 0x20000
sw   a4, 20(t0)	# tmp155,
fence w, w

# 0 "" 2
# main.c:114:     NOP_BARRIER();
# 114 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:115:     ASCON_WRITE(ASCON_OFS_KEY_2, MY_KEY_2);
 #NO_APP
	li	a4,19087360		# tmp157,
	addi	a4,a4,1383	#, tmp157, tmp157
 #APP
# 115 "main.c" 1
	lui  t0, 0x20000
sw   a4, 24(t0)	# tmp157,
fence w, w

# 0 "" 2
# main.c:116:     NOP_BARRIER();
# 116 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:117:     ASCON_WRITE(ASCON_OFS_KEY_3, MY_KEY_3);
 #NO_APP
	li	a4,-1985228800		# tmp159,
	addi	a4,a4,-529	#, tmp159, tmp159
 #APP
# 117 "main.c" 1
	lui  t0, 0x20000
sw   a4, 28(t0)	# tmp159,
fence w, w

# 0 "" 2
# main.c:118:     NOP_BARRIER();
# 118 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:126:     ASCON_WRITE(ASCON_OFS_NONCE_0, MY_NONCE_0);
 #NO_APP
	li	a4,286330880		# tmp161,
	addi	a4,a4,273	#, tmp161, tmp161
 #APP
# 126 "main.c" 1
	lui  t0, 0x20000
sw   a4, 36(t0)	# tmp161,
fence w, w

# 0 "" 2
# main.c:127:     NOP_BARRIER();
# 127 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:128:     ASCON_WRITE(ASCON_OFS_NONCE_1, MY_NONCE_1);
 #NO_APP
	li	a4,572661760		# tmp163,
	addi	a4,a4,546	#, tmp163, tmp163
 #APP
# 128 "main.c" 1
	lui  t0, 0x20000
sw   a4, 40(t0)	# tmp163,
fence w, w

# 0 "" 2
# main.c:129:     NOP_BARRIER();
# 129 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:130:     ASCON_WRITE(ASCON_OFS_NONCE_2, MY_NONCE_2);
 #NO_APP
	li	a4,858992640		# tmp165,
	addi	a4,a4,819	#, tmp165, tmp165
 #APP
# 130 "main.c" 1
	lui  t0, 0x20000
sw   a4, 44(t0)	# tmp165,
fence w, w

# 0 "" 2
# main.c:131:     NOP_BARRIER();
# 131 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:132:     ASCON_WRITE(ASCON_OFS_NONCE_3, MY_NONCE_3);
 #NO_APP
	li	a4,1145323520		# tmp167,
	addi	a4,a4,1092	#, tmp167, tmp167
 #APP
# 132 "main.c" 1
	lui  t0, 0x20000
sw   a4, 48(t0)	# tmp167,
fence w, w

# 0 "" 2
# main.c:133:     NOP_BARRIER();
# 133 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:140:     ASCON_WRITE(ASCON_OFS_DMA_SRC, DMEM_DMA_SRC_ADDR);
# 140 "main.c" 1
	lui  t0, 0x20000
sw   a5, 256(t0)	# tmp147,
fence w, w

# 0 "" 2
# main.c:141:     NOP_BARRIER();
# 141 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:142:     ASCON_WRITE(ASCON_OFS_DMA_DST, DMEM_DMA_OUTPUT_ADDR);
 #NO_APP
	li	a5,268435456		# tmp171,
	addi	a5,a5,464	#, tmp171, tmp171
 #APP
# 142 "main.c" 1
	lui  t0, 0x20000
sw   a5, 260(t0)	# tmp171,
fence w, w

# 0 "" 2
# main.c:143:     NOP_BARRIER();
# 143 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:144:     ASCON_WRITE(ASCON_OFS_DMA_LEN, DMEM_DMA_INPUT_LEN);
 #NO_APP
	li	a5,4		# tmp173,
 #APP
# 144 "main.c" 1
	lui  t0, 0x20000
sw   a5, 264(t0)	# tmp173,
fence w, w

# 0 "" 2
# main.c:145:     NOP_BARRIER();
# 145 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:148:     __asm__ volatile ("fence rw, rw" ::: "memory");
# 148 "main.c" 1
	fence rw, rw
# 0 "" 2
# main.c:160:     ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);   /* 0x5 = bit0|bit2 */
 #NO_APP
	li	a5,5		# tmp174,
 #APP
# 160 "main.c" 1
	lui  t0, 0x20000
sw   a5, 32(t0)	# tmp174,
fence w, w

# 0 "" 2
# main.c:161:     NOP_BARRIER();
# 161 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
 #NO_APP
	li	a5,1048576		# tmp145,
	addi	a5,a5,-1	#, ivtmp_72, tmp145
.L3:
# main.c:168:         NOP_BARRIER();
 #APP
# 168 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:169:         ASCON_READ(ASCON_OFS_STATUS, status);
# 169 "main.c" 1
	lui  t0, 0x20000
lw   a4, 4(t0)	# status,

# 0 "" 2
 #NO_APP
	mv	a2,a4	# status, status
# main.c:170:         if (--timeout == 0u) {
	addi	a5,a5,-1	#, ivtmp_72, ivtmp_72
	beq	a5,zero,.L6	#, ivtmp_72,,
# main.c:174:     } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR)));
	andi	a3,a4,40	#, tmp176, status
# main.c:174:     } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR)));
	beq	a3,zero,.L3	#, tmp176,,
# main.c:176:     if (status & ASCON_ST_DMA_ERR) {
	andi	a4,a4,32	#, tmp177, status
# main.c:177:         retcode = (uint32_t)(-1);
	li	a5,-1		# retcode,
# main.c:176:     if (status & ASCON_ST_DMA_ERR) {
	bne	a4,zero,.L2	#, tmp177,,
	li	a4,1048576		# tmp146,
	addi	a4,a4,-1	#, ivtmp_70, tmp146
.L4:
# main.c:189:         NOP_BARRIER();
 #APP
# 189 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:190:         ASCON_READ(ASCON_OFS_STATUS, status);
# 190 "main.c" 1
	lui  t0, 0x20000
lw   a5, 4(t0)	# status,

# 0 "" 2
 #NO_APP
	mv	a2,a5	# status, status
# main.c:191:         if (--timeout == 0u) {
	addi	a4,a4,-1	#, ivtmp_70, ivtmp_70
	beq	a4,zero,.L8	#, ivtmp_70,,
# main.c:195:     } while (!(status & ASCON_ST_CORE_DONE));
	andi	a3,a5,2	#, tmp179, status
# main.c:195:     } while (!(status & ASCON_ST_CORE_DONE));
	beq	a3,zero,.L4	#, tmp179,,
# main.c:197:     if (status & ASCON_ST_CORE_ERR) {
	slli	a5,a5,27	#, tmp181, status
	srai	a5,a5,31	#, retcode, tmp181
.L2:
# main.c:206:     SW_SINGLE(DMEM_BASE + offsetof(DmemLayout_t, STATUS),  status);
	li	a4,268435456		# tmp182,
	addi	a4,a4,532	#, tmp182, tmp182
 #APP
# 206 "main.c" 1
	sw   a2, 0(a4)	# status, tmp182
fence w, w

# 0 "" 2
# 206 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
# main.c:207:     SW_SINGLE(DMEM_BASE + offsetof(DmemLayout_t, RETCODE), retcode);
 #NO_APP
	li	a4,268435456		# tmp184,
	addi	a4,a4,536	#, tmp184, tmp184
 #APP
# 207 "main.c" 1
	sw   a5, 0(a4)	# retcode, tmp184
fence w, w

# 0 "" 2
# 207 "main.c" 1
	nop
nop
nop
nop
nop
nop
nop
nop

# 0 "" 2
 #NO_APP
.L5:
# main.c:210:     while (1) __asm__ volatile ("nop");
 #APP
# 210 "main.c" 1
	nop
# 0 "" 2
 #NO_APP
	j	.L5		#
.L6:
# main.c:171:             retcode = (uint32_t)(-2);
	li	a5,-2		# retcode,
	j	.L2		#
.L8:
# main.c:192:             retcode = (uint32_t)(-2);
	li	a5,-2		# retcode,
	j	.L2		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
