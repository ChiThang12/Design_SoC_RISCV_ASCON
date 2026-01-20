#!/bin/bash

echo "========================================="
echo "    RISC-V C -> HEX -> MO PHONG"
echo "========================================="
echo

echo "[1/2] Dang bien dich example.c -> program.hex..."
./compile_c_to_hex.sh -i example.c -o program.hex
if [ $? -ne 0 ]; then
    echo
    echo "[LOI] Bien dich that bai! Kiem tra code C hoac script."
    read -p "Nhan Enter de thoat..."
    exit 1
fi
echo "[OK] Bien dich thanh cong!"
echo

echo "[2/2] Dang chay mo phong voi vvp..."
vvp run_program.vvp
echo
echo "========================================="
echo "           HOAN TAT!"
echo "========================================="
read -p "Nhan Enter de thoat..."
