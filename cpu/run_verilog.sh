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

echo "============================================"
echo "Source   : $SRC"
if [[ -z "$STD" ]]; then
    echo "Standard : default"
else
    echo "Standard : $STD"
fi
echo "Output   : $NAME.vvp"
echo "============================================"

iverilog $STD -o "$NAME.vvp" "$SRC" || exit 1

echo "--------------------------------------------"
echo "Running simulation..."
echo "--------------------------------------------"
vvp "$NAME.vvp"

echo "--------------------------------------------"
echo "Done."
echo "============================================"
