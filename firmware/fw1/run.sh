#!/usr/bin/env bash
# [FIX] #!/bin/bash → #!/usr/bin/env bash (portable, khớp với compile_c_to_hex.sh)
 
echo "========================================="
echo "    RISC-V C -> HEX -> MO PHONG"
echo "========================================="
echo
 
# ── Đường dẫn cố định ────────────────────────────────────────
HEX_OUT="program.hex"
HEX_DEST="cpu/memory_axi4full/program.hex"
INST_MEM="cpu/memory_axi4full/inst_mem.v"
TB_TOP="run_soc_ascon.v"
WRUN=".\workflow\wrun_verilog.bat"
 
# ============================================================
# BƯỚC 0: Patch inst_mem.v — đảm bảo array đúng 2048 words (8KB)
#
# IMEM_SIZE = 8192 bytes = 2048 words (32-bit)
#   → reg [31:0] mem [0:2047]
#
# Các bản cũ có thể còn [0:1023] (4KB) hoặc [0:4095] (16KB sai).
# Script này chuẩn hóa về [0:2047].
# ============================================================
echo "[0/3] Kiem tra inst_mem.v..."
 
if [ -f "$INST_MEM" ]; then
    PATCHED=0
 
    if grep -qE "\[0:1023\]" "$INST_MEM"; then
        echo "  [FIX] Patch inst_mem: [0:1023] -> [0:2047] (4KB -> 8KB)"
        sed -i 's/\[0:1023\]/[0:2047]/g' "$INST_MEM"
        PATCHED=1
    fi
 
    if grep -qE "\[0:4095\]" "$INST_MEM"; then
        echo "  [FIX] Patch inst_mem: [0:4095] -> [0:2047] (16KB -> 8KB)"
        sed -i 's/\[0:4095\]/[0:2047]/g' "$INST_MEM"
        PATCHED=1
    fi
 
    if [ $PATCHED -eq 0 ]; then
        if grep -qE "\[0:2047\]" "$INST_MEM"; then
            echo "  [OK] inst_mem.v da dung [0:2047] (8KB) — khong can patch"
        else
            echo "  [WARN] Khong tim thay pattern [0:N] quen biet trong inst_mem.v"
            echo "         Kiem tra thu cong: grep -n 'reg.*mem' $INST_MEM"
        fi
    else
        echo "  [OK] inst_mem.v da duoc patch ve [0:2047]"
    fi
else
    echo "  [WARN] Khong tim thay $INST_MEM — bo qua patch"
fi
echo
 
# ============================================================
# BƯỚC 1: Compile fw_t1.c -> program.hex
# ============================================================
echo "[1/3] Dang bien dich fw_t1.c -> $HEX_OUT ..."
 
./compile_c_to_hex.sh -i fw_t1.c -o "$HEX_OUT" -k -O 0
 
if [ $? -ne 0 ]; then
    echo
    echo "[LOI] Bien dich that bai! Kiem tra code C hoac script."
    exit 1
fi
 
echo "[OK] Bien dich thanh cong!"
echo