#!/usr/bin/env bash
# truncate-to-budget.sh <file_path> <budget_chars>
# Outputs file content truncated to budget_chars.
# If truncated, appends a note with the full file path.
set -euo pipefail

FILE="$1"
BUDGET="$2"

if [[ ! -f "$FILE" ]]; then
  echo "[figma-harness] capability file not found: $FILE" >&2
  exit 0
fi

CONTENT=$(cat "$FILE")
LEN=${#CONTENT}

if (( LEN <= BUDGET )); then
  printf '%s' "$CONTENT"
else
  printf '%s' "${CONTENT:0:$BUDGET}"
  printf '\n…[truncated — full file at %s]' "$FILE"
fi
