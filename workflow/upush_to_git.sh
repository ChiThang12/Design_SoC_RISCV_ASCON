#!/usr/bin/env bash
# ============================================
# push_to_git.sh
# Usage:
#   ./push_to_git.sh "commit message"
# ============================================

if [[ -z "$1" ]]; then
    echo "[ERROR] Missing commit message!"
    echo 'Usage: ./push_to_git.sh "commit message"'
    exit 1
fi

MSG="$1"

echo "============================================"
echo "Git add + commit"
echo "Message: \"$MSG\""
echo "============================================"

git add .
git commit -m "$MSG" || exit 1

echo "--------------------------------------------"
echo "Commit done successfully."
echo "============================================"
