#!/bin/bash

# Stop nếu có lỗi
set -e

# Compile C → ELF (bare metal, không runtime, không stack)
riscv64-unknown-elf-gcc \
    -O0 \
    -nostdlib -nostartfiles \
    -march=rv32im -mabi=ilp32 \
    -Ttext=0x0 \
    -o test.elf test.c

# Xuất file .hex (Verilog hex format)
riscv64-unknown-elf-objcopy -O verilog test.elf test.hex

echo "Build done! Tạo xong test.elf và test.hex"

