#!/usr/bin/env bash
# select-context.sh
# Reads JS script from stdin. Outputs additionalContext string for Claude.
# Total output stays under 9500 chars.
set -euo pipefail

SCRIPT=$(cat)
DIR="${CLAUDE_PROJECT_DIR}"
BUDGET=9500
TRUNCATE="${DIR}/.claude/hooks/lib/truncate-to-budget.sh"

# ── Signal detection ────────────────────────────────────────────
is_discovery=false
is_frame=false
is_component=false
is_token=false
is_vector=false
is_file=false

printf '%s' "$SCRIPT" | grep -qF -e "getLocalVariableCollectionsAsync" \
  -e "getLocalTextStylesAsync" -e "search_design_system" && is_discovery=true || true

printf '%s' "$SCRIPT" | grep -qF -e "createFrame" -e "insertChild" \
  -e "appendChild" && is_frame=true || true

printf '%s' "$SCRIPT" | grep -qF -e "createComponent" \
  -e "detachInstance" && is_component=true || true

printf '%s' "$SCRIPT" | grep -qF -e "setSharedPluginData" \
  -e "setPluginData" && is_token=true || true

printf '%s' "$SCRIPT" | grep -qF -e "createVector" -e "createRectangle" \
  -e "createEllipse" -e "createPolygon" -e "createStar" -e "createLine" \
  -e "createBooleanOperation" -e "createImage" && is_vector=true || true

printf '%s' "$SCRIPT" | grep -qF -e "createPage" \
  -e "deleteNode" && is_file=true || true

# ── Build file list ─────────────────────────────────────────────
FILES=()
# figma-code.md always first (universal constraints)
FILES+=("${DIR}/figma-code.md")

$is_discovery && FILES+=("${DIR}/figma-read.md")
$is_frame     && FILES+=("${DIR}/figma-frames.md")
$is_component && FILES+=("${DIR}/figma-components.md")
$is_token     && FILES+=("${DIR}/figma-tokens.md")
$is_vector    && FILES+=("${DIR}/figma-vectors.md")
$is_file      && FILES+=("${DIR}/figma-files.md")

# ── Allocate budget equally across files ────────────────────────
FILE_COUNT=${#FILES[@]}
# Reserve ~250 chars per file for header + separator + truncation-note overhead
# (the truncation note includes the absolute file path, so can be long)
OVERHEAD_PER_FILE=250
PER_FILE=$(( (BUDGET / FILE_COUNT) - OVERHEAD_PER_FILE ))

# ── Build output ────────────────────────────────────────────────
OUTPUT=""
NL=$'\n'
for F in "${FILES[@]}"; do
  CHUNK=$(bash "$TRUNCATE" "$F" "$PER_FILE")
  HEADER=$(basename "$F" .md | tr '[:lower:]-' '[:upper:]_')
  OUTPUT+="${HEADER}:${NL}${CHUNK}${NL}${NL}---${NL}${NL}"
done

printf '%s' "$OUTPUT"
