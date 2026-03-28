	.file	"example.c"
	.option nopic
	.option norelax
	.attribute arch, "rv32i2p1_m2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
# GNU C17 (13.2.0-11ubuntu1+12) version 13.2.0 (riscv64-unknown-elf)
#	compiled by GNU C version 13.2.0, GMP version 6.3.0, MPFR version 4.2.1, MPC version 1.3.1, isl version isl-0.26-GMP

# GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
# options passed: -mabi=ilp32 -mno-relax -misa-spec=20191213 -march=rv32im -O0
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32	#,,
	sw	s0,28(sp)	#,
	addi	s0,sp,32	#,,
# example.c:222:     int a = 10;
	li	a5,10		# tmp136,
	sw	a5,-20(s0)	# tmp136, a
# example.c:223:     int b = 20;
	li	a5,20		# tmp137,
	sw	a5,-24(s0)	# tmp137, b
# example.c:224:     int c = a + b;  // c = 30
	lw	a4,-20(s0)		# tmp139, a
	lw	a5,-24(s0)		# tmp140, b
	add	a5,a4,a5	# tmp140, tmp138, tmp139
	sw	a5,-28(s0)	# tmp138, c
# example.c:225:     return c;
	lw	a5,-28(s0)		# _4, c
# example.c:226: }
	mv	a0,a5	#, <retval>
	lw	s0,28(sp)		#,
	addi	sp,sp,32	#,,
	jr	ra		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
