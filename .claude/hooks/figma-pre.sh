#!/usr/bin/env bash
set -euo pipefail

# figma-pre.sh — PreToolUse hook for mcp__figma__use_figma
# Enforces discovery-before-write discipline per figma-harness spec.

STATE_FILE="${CLAUDE_PROJECT_DIR}/.claude/figma-harness-state.json"

# Read stdin JSON
INPUT="$(cat)"

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
CODE="$(printf '%s' "$INPUT" | jq -r '.tool_input.code // ""')"
FILE_KEY="$(printf '%s' "$INPUT" | jq -r '.tool_input.fileKey // ""')"

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ── Load or initialise state ─────────────────────────────────────────────────
if [[ -f "$STATE_FILE" ]]; then
  STATE_SESSION="$(jq -r '.sessionId // ""' "$STATE_FILE")"

  if [[ "$STATE_SESSION" != "$SESSION_ID" ]]; then
    # New session — reset discoveryRan
    STATE="$(jq -n \
      --arg sid "$SESSION_ID" \
      --arg fk  "" \
      --arg ts  "$NOW" \
      '{sessionId:$sid, fileKey:$fk, discoveryRan:false, lastUpdated:$ts}')"
  else
    STATE="$(cat "$STATE_FILE")"
  fi
else
  STATE="$(jq -n \
    --arg sid "$SESSION_ID" \
    --arg fk  "" \
    --arg ts  "$NOW" \
    '{sessionId:$sid, fileKey:$fk, discoveryRan:false, lastUpdated:$ts}')"
fi

# ── Update fileKey if provided and not yet set ───────────────────────────────
if [[ -n "$FILE_KEY" ]]; then
  CURRENT_FK="$(printf '%s' "$STATE" | jq -r '.fileKey // ""')"
  if [[ -z "$CURRENT_FK" || "$CURRENT_FK" == "null" ]]; then
    STATE="$(printf '%s' "$STATE" | jq --arg fk "$FILE_KEY" '.fileKey = $fk')"
  fi
fi

# ── Discovery detection ──────────────────────────────────────────────────────
DISCOVERY_PATTERNS=(
  "getLocalVariableCollectionsAsync"
  "getLocalTextStylesAsync"
  "search_design_system"
)

IS_DISCOVERY=false
for pat in "${DISCOVERY_PATTERNS[@]}"; do
  if printf '%s' "$CODE" | grep -qF "$pat"; then
    IS_DISCOVERY=true
    break
  fi
done

if [[ "$IS_DISCOVERY" == "true" ]]; then
  STATE="$(printf '%s' "$STATE" | jq --arg ts "$NOW" '.discoveryRan = true | .lastUpdated = $ts')"
  printf '%s\n' "$STATE" > "$STATE_FILE"
  exit 0
fi

# ── Write detection ──────────────────────────────────────────────────────────
WRITE_PATTERNS=(
  "appendChild"
  "createFrame"
  "createComponent"
  "setSharedPluginData"
  "setPluginData"
  "insertChild"
  "createVector"
  "createText"
  "createRectangle"
  "createEllipse"
  "createPolygon"
  "createStar"
  "createLine"
  "createBooleanOperation"
  "createImage"
  "createPage"
  "deleteNode"
  "detachInstance"
)

IS_WRITE=false
for pat in "${WRITE_PATTERNS[@]}"; do
  if printf '%s' "$CODE" | grep -qF "$pat"; then
    IS_WRITE=true
    break
  fi
done

if [[ "$IS_WRITE" == "true" ]]; then
  DISCOVERY_RAN="$(printf '%s' "$STATE" | jq -r '.discoveryRan // false')"
  if [[ "$DISCOVERY_RAN" != "true" ]]; then
    # Persist state before blocking
    STATE="$(printf '%s' "$STATE" | jq --arg ts "$NOW" '.lastUpdated = $ts')"
    printf '%s\n' "$STATE" > "$STATE_FILE"
    printf '[figma-harness] Discovery has not run this session.\nPaste scripts/discovery-audit.js into use_figma before writing.\n' >&2
    exit 2
  fi
fi

# ── Persist updated state and allow ─────────────────────────────────────────
STATE="$(printf '%s' "$STATE" | jq --arg ts "$NOW" '.lastUpdated = $ts')"
printf '%s\n' "$STATE" > "$STATE_FILE"
exit 0
