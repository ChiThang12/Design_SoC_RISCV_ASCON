# Instructions from program.hex
10010137    # lui x2, 0x10010
00c000ef    # jal x1, 12 (0xc)
00050513    # addi x10, x0, 5
ffdff06f    # jal x0, -4 (loop back)
ff010113    # addi x2, x2, -16
00812623    # sw x8, 12(x2)
01010413    # addi x8, x2, 16
02a00793    # addi x15, x0, 42
00078513    # addi x10, x15, 0
00c12403    # lw x8, 12(x2)
01010113    # addi x2, x2, 16
00008067    # jalr x0, 0(x1)
