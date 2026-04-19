#!/usr/bin/env bash
# ============================================
# run_verilog.sh
# Usage:
#   ./run_verilog.sh alu.v
#   ./run_verilog.sh -g2012 alu.v
# ============================================

STD=""
SRC=""

if [[ "$1" == "-g2001" || "$1" == "-g2005" || "$1" == "-g2012" ]]; then
    STD="$1"
    SRC="$2"
else
    SRC="$1"
fi

if [[ -z "$SRC" ]]; then
    echo "[ERROR] Missing verilog file!"
    echo "Usage:"
    echo "  ./run_verilog.sh alu.v"
    echo "  ./run_verilog.sh -g2012 alu.v"
    exit 1
fi

NAME=$(basename "$SRC" .v)
LOG="${NAME}.log"

echo "============================================"
echo "Source   : $SRC"
if [[ -z "$STD" ]]; then
    echo "Standard : default"
else
    echo "Standard : $STD"
fi
echo "Output   : $NAME.vvp"
echo "Log file : $LOG"
echo "============================================"

iverilog $STD -o "$NAME.vvp" "$SRC" || exit 1

echo "--------------------------------------------"
echo "Running simulation..."
echo "--------------------------------------------"

# Ghi cả stdout + stderr vào log
vvp "$NAME.vvp" > "$LOG" 2>&1

echo "--------------------------------------------"
echo "Done. Log saved to $LOG"
echo "============================================"