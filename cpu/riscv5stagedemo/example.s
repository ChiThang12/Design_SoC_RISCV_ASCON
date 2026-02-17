	.file	"example.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
# GNU C17 (13.2.0-11ubuntu1+12) version 13.2.0 (riscv64-unknown-elf)
#	compiled by GNU C version 13.2.0, GMP version 6.3.0, MPFR version 4.2.1, MPC version 1.3.1, isl version isl-0.26-GMP

# GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
# options passed: -mabi=ilp32 -misa-spec=20191213 -march=rv32im
	.text
	.globl	global_array
	.bss
	.align	2
	.type	global_array, @object
	.size	global_array, 64
global_array:
	.zero	64
	.globl	result
	.section	.sbss,"aw",@nobits
	.align	2
	.type	result, @object
	.size	result, 4
result:
	.zero	4
	.text
	.align	2
	.globl	test_alu
	.type	test_alu, @function
test_alu:
	addi	sp,sp,-48	#,,
	sw	s0,44(sp)	#,
	addi	s0,sp,48	#,,
	sw	a0,-36(s0)	# a, a
	sw	a1,-40(s0)	# b, b
# example.c:12:     int r = 0;
	sw	zero,-20(s0)	#, r
# example.c:14:     r += a + b;        // ADD
	lw	a4,-36(s0)		# tmp147, a
	lw	a5,-40(s0)		# tmp148, b
	add	a5,a4,a5	# tmp148, _1, tmp147
# example.c:14:     r += a + b;        // ADD
	lw	a4,-20(s0)		# tmp150, r
	add	a5,a4,a5	# _1, tmp149, tmp150
	sw	a5,-20(s0)	# tmp149, r
# example.c:15:     r += a - b;        // SUB
	lw	a4,-36(s0)		# tmp151, a
	lw	a5,-40(s0)		# tmp152, b
	sub	a5,a4,a5	# _2, tmp151, tmp152
# example.c:15:     r += a - b;        // SUB
	lw	a4,-20(s0)		# tmp154, r
	add	a5,a4,a5	# _2, tmp153, tmp154
	sw	a5,-20(s0)	# tmp153, r
# example.c:16:     r += a & b;        // AND
	lw	a4,-36(s0)		# tmp155, a
	lw	a5,-40(s0)		# tmp156, b
	and	a5,a4,a5	# tmp156, _3, tmp155
# example.c:16:     r += a & b;        // AND
	lw	a4,-20(s0)		# tmp158, r
	add	a5,a4,a5	# _3, tmp157, tmp158
	sw	a5,-20(s0)	# tmp157, r
# example.c:17:     r += a | b;        // OR
	lw	a4,-36(s0)		# tmp159, a
	lw	a5,-40(s0)		# tmp160, b
	or	a5,a4,a5	# tmp160, _4, tmp159
# example.c:17:     r += a | b;        // OR
	lw	a4,-20(s0)		# tmp162, r
	add	a5,a4,a5	# _4, tmp161, tmp162
	sw	a5,-20(s0)	# tmp161, r
# example.c:18:     r += a ^ b;        // XOR
	lw	a4,-36(s0)		# tmp163, a
	lw	a5,-40(s0)		# tmp164, b
	xor	a5,a4,a5	# tmp164, _5, tmp163
# example.c:18:     r += a ^ b;        // XOR
	lw	a4,-20(s0)		# tmp166, r
	add	a5,a4,a5	# _5, tmp165, tmp166
	sw	a5,-20(s0)	# tmp165, r
# example.c:19:     r += a << 2;       // SLL
	lw	a5,-36(s0)		# tmp167, a
	slli	a5,a5,2	#, _6, tmp167
# example.c:19:     r += a << 2;       // SLL
	lw	a4,-20(s0)		# tmp169, r
	add	a5,a4,a5	# _6, tmp168, tmp169
	sw	a5,-20(s0)	# tmp168, r
# example.c:20:     r += a >> 1;       // SRL (logical if unsigned)
	lw	a5,-36(s0)		# tmp170, a
	srai	a5,a5,1	#, _7, tmp170
# example.c:20:     r += a >> 1;       // SRL (logical if unsigned)
	lw	a4,-20(s0)		# tmp172, r
	add	a5,a4,a5	# _7, tmp171, tmp172
	sw	a5,-20(s0)	# tmp171, r
# example.c:21:     r += (a < b);      // SLT
	lw	a4,-36(s0)		# tmp174, a
	lw	a5,-40(s0)		# tmp175, b
	slt	a5,a4,a5	# tmp175, tmp176, tmp174
	andi	a5,a5,0xff	# _8, tmp173
	mv	a4,a5	# _9, _8
# example.c:21:     r += (a < b);      // SLT
	lw	a5,-20(s0)		# tmp178, r
	add	a5,a5,a4	# _9, tmp177, tmp178
	sw	a5,-20(s0)	# tmp177, r
# example.c:22:     r += (a != b);     // compare
	lw	a4,-36(s0)		# tmp180, a
	lw	a5,-40(s0)		# tmp181, b
	sub	a5,a4,a5	# tmp183, tmp180, tmp181
	snez	a5,a5	# tmp182, tmp183
	andi	a5,a5,0xff	# _10, tmp179
	mv	a4,a5	# _11, _10
# example.c:22:     r += (a != b);     // compare
	lw	a5,-20(s0)		# tmp185, r
	add	a5,a5,a4	# _11, tmp184, tmp185
	sw	a5,-20(s0)	# tmp184, r
# example.c:24:     return r;
	lw	a5,-20(s0)		# _24, r
# example.c:25: }
	mv	a0,a5	#, <retval>
	lw	s0,44(sp)		#,
	addi	sp,sp,48	#,,
	jr	ra		#
	.size	test_alu, .-test_alu
	.align	2
	.globl	test_memory
	.type	test_memory, @function
test_memory:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
# example.c:31:     for (int i = 0; i < 16; i++) {
	sw	zero,-20(s0)	#, i
# example.c:31:     for (int i = 0; i < 16; i++) {
	j	.L4		#
.L5:
# example.c:32:         global_array[i] = i * 3;
	lw	a4,-20(s0)		# tmp138, i
	mv	a5,a4	# tmp139, tmp138
	slli	a5,a5,1	#, tmp140, tmp139
	add	a4,a5,a4	# tmp138, _1, tmp139
# example.c:32:         global_array[i] = i * 3;
	lui	a5,%hi(global_array)	# tmp141,
	addi	a3,a5,%lo(global_array)	# tmp142, tmp141,
	lw	a5,-20(s0)		# tmp143, i
	slli	a5,a5,2	#, tmp144, tmp143
	add	a5,a3,a5	# tmp144, tmp145, tmp142
	sw	a4,0(a5)	# _1, global_array[i_2]
# example.c:31:     for (int i = 0; i < 16; i++) {
	lw	a5,-20(s0)		# tmp147, i
	addi	a5,a5,1	#, tmp146, tmp147
	sw	a5,-20(s0)	# tmp146, i
.L4:
# example.c:31:     for (int i = 0; i < 16; i++) {
	lw	a4,-20(s0)		# tmp148, i
	li	a5,15		# tmp149,
	ble	a4,a5,.L5	#, tmp148, tmp149,
# example.c:35:     int sum = 0;
	sw	zero,-24(s0)	#, sum
# example.c:36:     for (int i = 0; i < 16; i++) {
	sw	zero,-28(s0)	#, i
# example.c:36:     for (int i = 0; i < 16; i++) {
	j	.L6		#
.L7:
# example.c:37:         sum += global_array[i];
	lui	a5,%hi(global_array)	# tmp150,
	addi	a4,a5,%lo(global_array)	# tmp151, tmp150,
	lw	a5,-28(s0)		# tmp152, i
	slli	a5,a5,2	#, tmp153, tmp152
	add	a5,a4,a5	# tmp153, tmp154, tmp151
	lw	a5,0(a5)		# _11, global_array[i_4]
# example.c:37:         sum += global_array[i];
	lw	a4,-24(s0)		# tmp156, sum
	add	a5,a4,a5	# _11, tmp155, tmp156
	sw	a5,-24(s0)	# tmp155, sum
# example.c:36:     for (int i = 0; i < 16; i++) {
	lw	a5,-28(s0)		# tmp158, i
	addi	a5,a5,1	#, tmp157, tmp158
	sw	a5,-28(s0)	# tmp157, i
.L6:
# example.c:36:     for (int i = 0; i < 16; i++) {
	lw	a4,-28(s0)		# tmp159, i
	li	a5,15		# tmp160,
	ble	a4,a5,.L7	#, tmp159, tmp160,
# example.c:40:     return sum;
	lw	a5,-24(s0)		# _10, sum
# example.c:41: }
	mv	a0,a5	#, <retval>
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	test_memory, .-test_memory
	.align	2
	.globl	test_branch
	.type	test_branch, @function
test_branch:
	addi	sp,sp,-48	#,,
	sw	s0,44(sp)	#,
	addi	s0,sp,48	#,,
	sw	a0,-36(s0)	# x, x
# example.c:47:     int r = 0;
	sw	zero,-20(s0)	#, r
# example.c:49:     if (x == 10) {
	lw	a4,-36(s0)		# tmp136, x
	li	a5,10		# tmp137,
	bne	a4,a5,.L10	#, tmp136, tmp137,
# example.c:50:         r = 100;
	li	a5,100		# tmp138,
	sw	a5,-20(s0)	# tmp138, r
	j	.L11		#
.L10:
# example.c:52:         r = 50;
	li	a5,50		# tmp139,
	sw	a5,-20(s0)	# tmp139, r
.L11:
# example.c:55:     if (x < 5) {
	lw	a4,-36(s0)		# tmp140, x
	li	a5,4		# tmp141,
	bgt	a4,a5,.L12	#, tmp140, tmp141,
# example.c:56:         r += 1;
	lw	a5,-20(s0)		# tmp143, r
	addi	a5,a5,1	#, tmp142, tmp143
	sw	a5,-20(s0)	# tmp142, r
	j	.L13		#
.L12:
# example.c:58:         r += 2;
	lw	a5,-20(s0)		# tmp145, r
	addi	a5,a5,2	#, tmp144, tmp145
	sw	a5,-20(s0)	# tmp144, r
.L13:
# example.c:61:     return r;
	lw	a5,-20(s0)		# _9, r
# example.c:62: }
	mv	a0,a5	#, <retval>
	lw	s0,44(sp)		#,
	addi	sp,sp,48	#,,
	jr	ra		#
	.size	test_branch, .-test_branch
	.align	2
	.globl	test_loop
	.type	test_loop, @function
test_loop:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
# example.c:68:     int acc = 0;
	sw	zero,-20(s0)	#, acc
# example.c:70:     for (int i = 0; i < 20; i++) {
	sw	zero,-24(s0)	#, i
# example.c:70:     for (int i = 0; i < 20; i++) {
	j	.L16		#
.L17:
# example.c:71:         acc += i;       // RAW hazard
	lw	a4,-20(s0)		# tmp137, acc
	lw	a5,-24(s0)		# tmp138, i
	add	a5,a4,a5	# tmp138, tmp136, tmp137
	sw	a5,-20(s0)	# tmp136, acc
# example.c:70:     for (int i = 0; i < 20; i++) {
	lw	a5,-24(s0)		# tmp140, i
	addi	a5,a5,1	#, tmp139, tmp140
	sw	a5,-24(s0)	# tmp139, i
.L16:
# example.c:70:     for (int i = 0; i < 20; i++) {
	lw	a4,-24(s0)		# tmp141, i
	li	a5,19		# tmp142,
	ble	a4,a5,.L17	#, tmp141, tmp142,
# example.c:74:     return acc;
	lw	a5,-20(s0)		# _5, acc
# example.c:75: }
	mv	a0,a5	#, <retval>
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	test_loop, .-test_loop
	.align	2
	.globl	factorial
	.type	factorial, @function
factorial:
	addi	sp,sp,-32	#,,
	sw	ra,28(sp)	#,
	sw	s0,24(sp)	#,
	addi	s0,sp,32	#,,
	sw	a0,-20(s0)	# n, n
# example.c:81:     if (n <= 1)
	lw	a4,-20(s0)		# tmp138, n
	li	a5,1		# tmp139,
	bgt	a4,a5,.L20	#, tmp138, tmp139,
# example.c:82:         return 1;
	li	a5,1		# _3,
	j	.L21		#
.L20:
# example.c:84:     return n * factorial(n - 1);
	lw	a5,-20(s0)		# tmp140, n
	addi	a5,a5,-1	#, _1, tmp140
	mv	a0,a5	#, _1
	call	factorial		#
	mv	a4,a0	# _2,
# example.c:84:     return n * factorial(n - 1);
	lw	a5,-20(s0)		# tmp141, n
	mul	a5,a4,a5	# _3, _2, tmp141
.L21:
# example.c:85: }
	mv	a0,a5	#, <retval>
	lw	ra,28(sp)		#,
	lw	s0,24(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	factorial, .-factorial
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-48	#,,
	sw	ra,44(sp)	#,
	sw	s0,40(sp)	#,
	addi	s0,sp,48	#,,
# example.c:92:     int a = 15;
	li	a5,15		# tmp139,
	sw	a5,-20(s0)	# tmp139, a
# example.c:93:     int b = 7;
	li	a5,7		# tmp140,
	sw	a5,-24(s0)	# tmp140, b
# example.c:95:     int alu_res   = test_alu(a, b);
	lw	a1,-24(s0)		#, b
	lw	a0,-20(s0)		#, a
	call	test_alu		#
	sw	a0,-28(s0)	#, alu_res
# example.c:96:     int mem_res   = test_memory();
	call	test_memory		#
	sw	a0,-32(s0)	#, mem_res
# example.c:97:     int br_res    = test_branch(10);
	li	a0,10		#,
	call	test_branch		#
	sw	a0,-36(s0)	#, br_res
# example.c:98:     int loop_res  = test_loop();
	call	test_loop		#
	sw	a0,-40(s0)	#, loop_res
# example.c:99:     int fact_res  = factorial(5);
	li	a0,5		#,
	call	factorial		#
	sw	a0,-44(s0)	#, fact_res
# example.c:101:     result = alu_res + mem_res + br_res + loop_res + fact_res;
	lw	a4,-28(s0)		# tmp141, alu_res
	lw	a5,-32(s0)		# tmp142, mem_res
	add	a4,a4,a5	# tmp142, _1, tmp141
# example.c:101:     result = alu_res + mem_res + br_res + loop_res + fact_res;
	lw	a5,-36(s0)		# tmp143, br_res
	add	a4,a4,a5	# tmp143, _2, _1
# example.c:101:     result = alu_res + mem_res + br_res + loop_res + fact_res;
	lw	a5,-40(s0)		# tmp144, loop_res
	add	a4,a4,a5	# tmp144, _3, _2
# example.c:101:     result = alu_res + mem_res + br_res + loop_res + fact_res;
	lw	a5,-44(s0)		# tmp145, fact_res
	add	a4,a4,a5	# tmp145, _4, _3
# example.c:101:     result = alu_res + mem_res + br_res + loop_res + fact_res;
	lui	a5,%hi(result)	# tmp146,
	sw	a4,%lo(result)(a5)	# _4, result
.L23:
# example.c:104:     while (1);
	j	.L23		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
