#!/usr/bin/env bash
# ============================================
# run_verilog.sh
# Usage:
#   ./run_verilog.sh alu.v
#   ./run_verilog.sh -g2012 alu.v
#   ./run_verilog.sh -l mylog alu.v        # custom log name → log/mylog.log
#   ./run_verilog.sh -g2005 -l test alu.v  # combine std + log name
# ============================================

STD=""
SRC=""
LOG_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -g2001|-g2005|-g2012)
            STD="$1"; shift ;;
        -l)
            LOG_NAME="$2"; shift 2 ;;
        *)
            SRC="$1"; shift ;;
    esac
done

if [[ -z "$SRC" ]]; then
    echo "[ERROR] Missing verilog file!"
    echo "Usage:"
    echo "  ./run_verilog.sh alu.v"
    echo "  ./run_verilog.sh -g2012 alu.v"
    echo "  ./run_verilog.sh -l <logname> alu.v"
    exit 1
fi

NAME=$(basename "$SRC" .v)
[[ -z "$LOG_NAME" ]] && LOG_NAME="$NAME"

# 👉 Tạo thư mục log nếu chưa tồn tại
LOG_DIR="log"
mkdir -p "$LOG_DIR"

LOG="${LOG_DIR}/${LOG_NAME}.log"

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