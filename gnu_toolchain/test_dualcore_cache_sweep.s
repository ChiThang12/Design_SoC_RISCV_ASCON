	.file	"test_dualcore_cache_sweep.c"
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
	.type	dualcore_fail_stop, @function
dualcore_fail_stop:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# tests_dualcore/dualcore_common.h:21:     DMEM32(RESULT_ADDR) = RESULT_FAIL;
	li	a5,268435456		# tmp135,
	addi	a5,a5,16	#, _1, tmp135
# tests_dualcore/dualcore_common.h:21:     DMEM32(RESULT_ADDR) = RESULT_FAIL;
	li	a4,-559087616		# tmp137,
	addi	a4,a4,1	#, tmp136, tmp137
	sw	a4,0(a5)	# tmp136, *_1
# tests_dualcore/dualcore_common.h:22:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 22 "tests_dualcore/dualcore_common.h" 1
	fence w,w
# 0 "" 2
 #NO_APP
.L2:
# tests_dualcore/dualcore_common.h:24:         __asm__ volatile ("nop");
 #APP
# 24 "tests_dualcore/dualcore_common.h" 1
	nop
# 0 "" 2
# tests_dualcore/dualcore_common.h:24:         __asm__ volatile ("nop");
 #NO_APP
	j	.L2		#
	.size	dualcore_fail_stop, .-dualcore_fail_stop
	.align	2
	.type	dualcore_publish_start, @function
dualcore_publish_start:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# sig0, sig0
	sw	a1,-24(s0)	# sig1, sig1
# tests_dualcore/dualcore_common.h:30:     DMEM32(SHARED_SIG0_ADDR) = sig0;
	li	a5,268435456		# _1,
# tests_dualcore/dualcore_common.h:30:     DMEM32(SHARED_SIG0_ADDR) = sig0;
	lw	a4,-20(s0)		# tmp141, sig0
	sw	a4,0(a5)	# tmp141, *_1
# tests_dualcore/dualcore_common.h:31:     DMEM32(SHARED_SIG1_ADDR) = sig1;
	li	a5,268435456		# tmp142,
	addi	a5,a5,4	#, _2, tmp142
# tests_dualcore/dualcore_common.h:31:     DMEM32(SHARED_SIG1_ADDR) = sig1;
	lw	a4,-24(s0)		# tmp143, sig1
	sw	a4,0(a5)	# tmp143, *_2
# tests_dualcore/dualcore_common.h:32:     DMEM32(SHARED_COUNT_ADDR) = 0u;
	li	a5,268435456		# tmp144,
	addi	a5,a5,8	#, _3, tmp144
# tests_dualcore/dualcore_common.h:32:     DMEM32(SHARED_COUNT_ADDR) = 0u;
	sw	zero,0(a5)	#, *_3
# tests_dualcore/dualcore_common.h:33:     DMEM32(HEARTBEAT_ADDR) = 0u;
	li	a5,268435456		# tmp145,
	addi	a5,a5,12	#, _4, tmp145
# tests_dualcore/dualcore_common.h:33:     DMEM32(HEARTBEAT_ADDR) = 0u;
	sw	zero,0(a5)	#, *_4
# tests_dualcore/dualcore_common.h:34:     DMEM32(RESULT_ADDR) = RESULT_RUNNING;
	li	a5,268435456		# tmp146,
	addi	a5,a5,16	#, _5, tmp146
# tests_dualcore/dualcore_common.h:34:     DMEM32(RESULT_ADDR) = RESULT_RUNNING;
	li	a4,-889323520		# tmp148,
	addi	a4,a4,1	#, tmp147, tmp148
	sw	a4,0(a5)	# tmp147, *_5
# tests_dualcore/dualcore_common.h:35:     DMEM32(AUX0_ADDR) = 0u;
	li	a5,268435456		# tmp149,
	addi	a5,a5,20	#, _6, tmp149
# tests_dualcore/dualcore_common.h:35:     DMEM32(AUX0_ADDR) = 0u;
	sw	zero,0(a5)	#, *_6
# tests_dualcore/dualcore_common.h:36:     DMEM32(AUX1_ADDR) = 0u;
	li	a5,268435456		# tmp150,
	addi	a5,a5,24	#, _7, tmp150
# tests_dualcore/dualcore_common.h:36:     DMEM32(AUX1_ADDR) = 0u;
	sw	zero,0(a5)	#, *_7
# tests_dualcore/dualcore_common.h:37:     __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 37 "tests_dualcore/dualcore_common.h" 1
	fence w,w
# 0 "" 2
# tests_dualcore/dualcore_common.h:38: }
 #NO_APP
	nop	
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	dualcore_publish_start, .-dualcore_publish_start
	.align	2
	.type	dualcore_check_signatures, @function
dualcore_check_signatures:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# sig0, sig0
	sw	a1,-24(s0)	# sig1, sig1
# tests_dualcore/dualcore_common.h:42:     if (DMEM32(SHARED_SIG0_ADDR) != sig0) {
	li	a5,268435456		# _1,
	lw	a5,0(a5)		# _2, *_1
# tests_dualcore/dualcore_common.h:42:     if (DMEM32(SHARED_SIG0_ADDR) != sig0) {
	lw	a4,-20(s0)		# tmp138, sig0
	beq	a4,a5,.L5	#, tmp138, _2,
# tests_dualcore/dualcore_common.h:43:         dualcore_fail_stop();
	call	dualcore_fail_stop		#
.L5:
# tests_dualcore/dualcore_common.h:45:     if (DMEM32(SHARED_SIG1_ADDR) != sig1) {
	li	a5,268435456		# tmp139,
	addi	a5,a5,4	#, _3, tmp139
	lw	a5,0(a5)		# _4, *_3
# tests_dualcore/dualcore_common.h:45:     if (DMEM32(SHARED_SIG1_ADDR) != sig1) {
	lw	a4,-24(s0)		# tmp140, sig1
	beq	a4,a5,.L7	#, tmp140, _4,
# tests_dualcore/dualcore_common.h:46:         dualcore_fail_stop();
	call	dualcore_fail_stop		#
.L7:
# tests_dualcore/dualcore_common.h:48: }
	nop	
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	dualcore_check_signatures, .-dualcore_check_signatures
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-48	#,,
	sw	ra,44(sp)	#,
	sw	s0,40(sp)	#,
	addi	s0,sp,48	#,,
# tests_dualcore/test_dualcore_cache_sweep.c:15:     dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);
	li	a5,610840576		# tmp154,
	addi	a1,a5,-800	#,, tmp154
	li	a5,-892469248		# tmp155,
	addi	a0,a5,1	#,, tmp155
	call	dualcore_publish_start		#
# tests_dualcore/test_dualcore_cache_sweep.c:17:     for (round = 0; round < 24u; round++) {
	sw	zero,-20(s0)	#, round
# tests_dualcore/test_dualcore_cache_sweep.c:17:     for (round = 0; round < 24u; round++) {
	j	.L9		#
.L14:
# tests_dualcore/test_dualcore_cache_sweep.c:19:         uint32_t sum = 0u;
	sw	zero,-28(s0)	#, sum
# tests_dualcore/test_dualcore_cache_sweep.c:21:         for (i = 0; i < BUF_WORDS; i++) {
	sw	zero,-24(s0)	#, i
# tests_dualcore/test_dualcore_cache_sweep.c:21:         for (i = 0; i < BUF_WORDS; i++) {
	j	.L10		#
.L11:
# tests_dualcore/test_dualcore_cache_sweep.c:22:             uint32_t value = (round << 16) ^ (i * 0x01010101u) ^ 0x55AA00FFu;
	lw	a5,-20(s0)		# tmp156, round
	slli	a3,a5,16	#, _1, tmp156
# tests_dualcore/test_dualcore_cache_sweep.c:22:             uint32_t value = (round << 16) ^ (i * 0x01010101u) ^ 0x55AA00FFu;
	lw	a4,-24(s0)		# tmp157, i
	mv	a5,a4	# tmp158, tmp157
	slli	a5,a5,8	#, tmp159, tmp158
	add	a5,a5,a4	# tmp157, tmp158, tmp158
	slli	a4,a5,16	#, tmp160, tmp158
	add	a5,a5,a4	# tmp160, _2, tmp158
# tests_dualcore/test_dualcore_cache_sweep.c:22:             uint32_t value = (round << 16) ^ (i * 0x01010101u) ^ 0x55AA00FFu;
	xor	a4,a3,a5	# _2, _3, _1
# tests_dualcore/test_dualcore_cache_sweep.c:22:             uint32_t value = (round << 16) ^ (i * 0x01010101u) ^ 0x55AA00FFu;
	li	a5,1437204480		# tmp163,
	addi	a5,a5,255	#, tmp162, tmp163
	xor	a5,a4,a5	# tmp162, tmp161, _3
	sw	a5,-40(s0)	# tmp161, value
# tests_dualcore/test_dualcore_cache_sweep.c:23:             DMEM32(BUF_BASE + (i << 2)) = value;
	lw	a5,-24(s0)		# tmp164, i
	slli	a4,a5,2	#, _4, tmp164
	li	a5,268435456		# tmp166,
	addi	a5,a5,64	#, tmp165, tmp166
	add	a5,a4,a5	# tmp165, _5, _4
	mv	a4,a5	# _6, _5
# tests_dualcore/test_dualcore_cache_sweep.c:23:             DMEM32(BUF_BASE + (i << 2)) = value;
	lw	a5,-40(s0)		# tmp167, value
	sw	a5,0(a4)	# tmp167, *_6
# tests_dualcore/test_dualcore_cache_sweep.c:24:             sum ^= value;
	lw	a4,-28(s0)		# tmp169, sum
	lw	a5,-40(s0)		# tmp170, value
	xor	a5,a4,a5	# tmp170, tmp168, tmp169
	sw	a5,-28(s0)	# tmp168, sum
# tests_dualcore/test_dualcore_cache_sweep.c:21:         for (i = 0; i < BUF_WORDS; i++) {
	lw	a5,-24(s0)		# tmp172, i
	addi	a5,a5,1	#, tmp171, tmp172
	sw	a5,-24(s0)	# tmp171, i
.L10:
# tests_dualcore/test_dualcore_cache_sweep.c:21:         for (i = 0; i < BUF_WORDS; i++) {
	lw	a4,-24(s0)		# tmp173, i
	li	a5,31		# tmp174,
	bleu	a4,a5,.L11	#, tmp173, tmp174,
# tests_dualcore/test_dualcore_cache_sweep.c:27:         for (i = 0; i < BUF_WORDS; i++) {
	sw	zero,-24(s0)	#, i
# tests_dualcore/test_dualcore_cache_sweep.c:27:         for (i = 0; i < BUF_WORDS; i++) {
	j	.L12		#
.L13:
# tests_dualcore/test_dualcore_cache_sweep.c:28:             uint32_t value = DMEM32(BUF_BASE + (i << 2));
	lw	a5,-24(s0)		# tmp175, i
	slli	a4,a5,2	#, _7, tmp175
	li	a5,268435456		# tmp177,
	addi	a5,a5,64	#, tmp176, tmp177
	add	a5,a4,a5	# tmp176, _8, _7
# tests_dualcore/test_dualcore_cache_sweep.c:28:             uint32_t value = DMEM32(BUF_BASE + (i << 2));
	lw	a5,0(a5)		# tmp178, *_9
	sw	a5,-36(s0)	# tmp178, value
# tests_dualcore/test_dualcore_cache_sweep.c:29:             sum ^= value;
	lw	a4,-28(s0)		# tmp180, sum
	lw	a5,-36(s0)		# tmp181, value
	xor	a5,a4,a5	# tmp181, tmp179, tmp180
	sw	a5,-28(s0)	# tmp179, sum
# tests_dualcore/test_dualcore_cache_sweep.c:27:         for (i = 0; i < BUF_WORDS; i++) {
	lw	a5,-24(s0)		# tmp183, i
	addi	a5,a5,1	#, tmp182, tmp183
	sw	a5,-24(s0)	# tmp182, i
.L12:
# tests_dualcore/test_dualcore_cache_sweep.c:27:         for (i = 0; i < BUF_WORDS; i++) {
	lw	a4,-24(s0)		# tmp184, i
	li	a5,31		# tmp185,
	bleu	a4,a5,.L13	#, tmp184, tmp185,
# tests_dualcore/test_dualcore_cache_sweep.c:32:         DMEM32(OUT_SUM_ADDR) = sum;
	li	a5,268435456		# tmp186,
	addi	a5,a5,20	#, _10, tmp186
# tests_dualcore/test_dualcore_cache_sweep.c:32:         DMEM32(OUT_SUM_ADDR) = sum;
	lw	a4,-28(s0)		# tmp187, sum
	sw	a4,0(a5)	# tmp187, *_10
# tests_dualcore/test_dualcore_cache_sweep.c:33:         DMEM32(OUT_LAST_ADDR) = round;
	li	a5,268435456		# tmp188,
	addi	a5,a5,24	#, _11, tmp188
# tests_dualcore/test_dualcore_cache_sweep.c:33:         DMEM32(OUT_LAST_ADDR) = round;
	lw	a4,-20(s0)		# tmp189, round
	sw	a4,0(a5)	# tmp189, *_11
# tests_dualcore/test_dualcore_cache_sweep.c:34:         DMEM32(SHARED_COUNT_ADDR) = round + 1u;
	li	a5,268435456		# tmp190,
	addi	a5,a5,8	#, _12, tmp190
# tests_dualcore/test_dualcore_cache_sweep.c:34:         DMEM32(SHARED_COUNT_ADDR) = round + 1u;
	lw	a4,-20(s0)		# tmp191, round
	addi	a4,a4,1	#, _13, tmp191
# tests_dualcore/test_dualcore_cache_sweep.c:34:         DMEM32(SHARED_COUNT_ADDR) = round + 1u;
	sw	a4,0(a5)	# _13, *_12
# tests_dualcore/test_dualcore_cache_sweep.c:35:         DMEM32(HEARTBEAT_ADDR) = round + 1u;
	li	a5,268435456		# tmp192,
	addi	a5,a5,12	#, _14, tmp192
# tests_dualcore/test_dualcore_cache_sweep.c:35:         DMEM32(HEARTBEAT_ADDR) = round + 1u;
	lw	a4,-20(s0)		# tmp193, round
	addi	a4,a4,1	#, _15, tmp193
# tests_dualcore/test_dualcore_cache_sweep.c:35:         DMEM32(HEARTBEAT_ADDR) = round + 1u;
	sw	a4,0(a5)	# _15, *_14
# tests_dualcore/test_dualcore_cache_sweep.c:37:         dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
	li	a5,610840576		# tmp194,
	addi	a1,a5,-800	#,, tmp194
	li	a5,-892469248		# tmp195,
	addi	a0,a5,1	#,, tmp195
	call	dualcore_check_signatures		#
# tests_dualcore/test_dualcore_cache_sweep.c:38:         __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 38 "tests_dualcore/test_dualcore_cache_sweep.c" 1
	fence w,w
# 0 "" 2
# tests_dualcore/test_dualcore_cache_sweep.c:17:     for (round = 0; round < 24u; round++) {
 #NO_APP
	lw	a5,-20(s0)		# tmp197, round
	addi	a5,a5,1	#, tmp196, tmp197
	sw	a5,-20(s0)	# tmp196, round
.L9:
# tests_dualcore/test_dualcore_cache_sweep.c:17:     for (round = 0; round < 24u; round++) {
	lw	a4,-20(s0)		# tmp198, round
	li	a5,23		# tmp199,
	bleu	a4,a5,.L14	#, tmp198, tmp199,
.L16:
# tests_dualcore/test_dualcore_cache_sweep.c:42:         uint32_t beat = DMEM32(HEARTBEAT_ADDR) + 1u;
	li	a5,268435456		# tmp200,
	addi	a5,a5,12	#, _16, tmp200
	lw	a5,0(a5)		# _17, *_16
# tests_dualcore/test_dualcore_cache_sweep.c:42:         uint32_t beat = DMEM32(HEARTBEAT_ADDR) + 1u;
	addi	a5,a5,1	#, tmp201, _17
	sw	a5,-32(s0)	# tmp201, beat
# tests_dualcore/test_dualcore_cache_sweep.c:43:         DMEM32(HEARTBEAT_ADDR) = beat;
	li	a5,268435456		# tmp202,
	addi	a5,a5,12	#, _18, tmp202
# tests_dualcore/test_dualcore_cache_sweep.c:43:         DMEM32(HEARTBEAT_ADDR) = beat;
	lw	a4,-32(s0)		# tmp203, beat
	sw	a4,0(a5)	# tmp203, *_18
# tests_dualcore/test_dualcore_cache_sweep.c:44:         dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
	li	a5,610840576		# tmp204,
	addi	a1,a5,-800	#,, tmp204
	li	a5,-892469248		# tmp205,
	addi	a0,a5,1	#,, tmp205
	call	dualcore_check_signatures		#
# tests_dualcore/test_dualcore_cache_sweep.c:45:         if ((beat & 15u) == 0u) {
	lw	a5,-32(s0)		# tmp206, beat
	andi	a5,a5,15	#, _19, tmp206
# tests_dualcore/test_dualcore_cache_sweep.c:45:         if ((beat & 15u) == 0u) {
	bne	a5,zero,.L16	#, _19,,
# tests_dualcore/test_dualcore_cache_sweep.c:46:             __asm__ volatile ("fence w,w" ::: "memory");
 #APP
# 46 "tests_dualcore/test_dualcore_cache_sweep.c" 1
	fence w,w
# 0 "" 2
# tests_dualcore/test_dualcore_cache_sweep.c:41:     while (1) {
 #NO_APP
	j	.L16		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
