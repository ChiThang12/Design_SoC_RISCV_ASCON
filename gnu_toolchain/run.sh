#!/usr/bin/env bash
echo "========================================="
echo "    RISC-V C -> HEX -> MO PHONG"
echo "========================================="
echo
HEX_OUT="program.hex"
INST_MEM="cpu/memory_axi4full/inst_mem.v"

echo "[0/3] Kiem tra inst_mem.v..."
if [ -f "$INST_MEM" ]; then
    if grep -qE "\[0:1023\]" "$INST_MEM"; then
        sed -i 's/\[0:1023\]/[0:2047]/g' "$INST_MEM"
        echo "  [FIX] Patched -> [0:2047]"
    elif grep -qE "\[0:2047\]" "$INST_MEM"; then
        echo "  [OK] [0:2047]"
    fi
else
    echo "  [WARN] Khong tim thay $INST_MEM"
fi
echo

echo "[1/3] Dang bien dich..."
./compile_c_to_hex.sh -i main.c -o "$HEX_OUT" -k -O 1 -c

if [ $? -ne 0 ]; then
    echo "[LOI] Bien dich that bai!"
    exit 1
fi
echo "[OK] Bien dich thanh cong!"
echo