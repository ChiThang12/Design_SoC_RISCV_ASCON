	.file	"simple_test.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
# GNU C17 (13.2.0-11ubuntu1+12) version 13.2.0 (riscv64-unknown-elf)
#	compiled by GNU C version 13.2.0, GMP version 6.3.0, MPFR version 4.2.1, MPC version 1.3.1, isl version isl-0.26-GMP

# GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
# options passed: -mabi=ilp32 -misa-spec=20191213 -march=rv32im
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16	#,,
	sw	s0,12(sp)	#,
	addi	s0,sp,16	#,,
# simple_test.c:3:     return 42;
	li	a5,42		# _1,
# simple_test.c:4: }
	mv	a0,a5	#, <retval>
	lw	s0,12(sp)		#,
	addi	sp,sp,16	#,,
	jr	ra		#
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
