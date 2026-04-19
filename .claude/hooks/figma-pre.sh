#!/usr/bin/env bash
set -euo pipefail

# figma-pre.sh — PreToolUse hook for mcp__figma__use_figma
# Enforces discovery-before-write discipline per figma-harness spec.

if [[ -z "${CLAUDE_PROJECT_DIR:-}" ]]; then
  printf '[figma-harness] CLAUDE_PROJECT_DIR is not set; hook is a no-op.\n' >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  printf '[figma-harness] jq is required but not found in PATH.\n' >&2
  exit 0
fi

STATE_FILE="${CLAUDE_PROJECT_DIR}/.claude/figma-harness-state.json"
mkdir -p "$(dirname "$STATE_FILE")"

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
IS_DISCOVERY=false
if printf '%s' "$CODE" | grep -qF \
  -e "getLocalVariableCollectionsAsync" \
  -e "getLocalTextStylesAsync" \
  -e "search_design_system"; then
  IS_DISCOVERY=true
fi

if [[ "$IS_DISCOVERY" == "true" ]]; then
  STATE="$(printf '%s' "$STATE" | jq --arg ts "$NOW" '.discoveryRan = true | .lastUpdated = $ts')"
  TMP="$(mktemp "${STATE_FILE}.XXXXXX")"
  printf '%s\n' "$STATE" > "$TMP"
  mv "$TMP" "$STATE_FILE"
  # Fall through to context injection at the bottom.
fi

# ── Write detection ──────────────────────────────────────────────────────────
IS_WRITE=false
if [[ "$IS_DISCOVERY" != "true" ]] && printf '%s' "$CODE" | grep -qF \
  -e "appendChild" \
  -e "createFrame" \
  -e "createComponent" \
  -e "setSharedPluginData" \
  -e "setPluginData" \
  -e "insertChild" \
  -e "createVector" \
  -e "createText" \
  -e "createRectangle" \
  -e "createEllipse" \
  -e "createPolygon" \
  -e "createStar" \
  -e "createLine" \
  -e "createBooleanOperation" \
  -e "createImage" \
  -e "createPage" \
  -e "deleteNode" \
  -e "detachInstance"; then
  IS_WRITE=true
fi

if [[ "$IS_WRITE" == "true" ]]; then
  DISCOVERY_RAN="$(printf '%s' "$STATE" | jq -r '.discoveryRan // false')"
  if [[ "$DISCOVERY_RAN" != "true" ]]; then
    # Persist state before blocking
    STATE="$(printf '%s' "$STATE" | jq --arg ts "$NOW" '.lastUpdated = $ts')"
    TMP="$(mktemp "${STATE_FILE}.XXXXXX")"
    printf '%s\n' "$STATE" > "$TMP"
    mv "$TMP" "$STATE_FILE"
    printf '[figma-harness] Discovery has not run this session.\nPaste scripts/discovery-audit.js into use_figma before writing.\n' >&2
    exit 2
  fi
fi

# ── Persist updated state ───────────────────────────────────────────────────
STATE="$(printf '%s' "$STATE" | jq --arg ts "$NOW" '.lastUpdated = $ts')"
TMP="$(mktemp "${STATE_FILE}.XXXXXX")"
printf '%s\n' "$STATE" > "$TMP"
mv "$TMP" "$STATE_FILE"

# ── Inject capability context ───────────────────────────────────────────────
CONTEXT=$(printf '%s' "$CODE" | \
  CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" \
  bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/lib/select-context.sh")

# Emit JSON output with additionalContext
jq -n \
  --arg ctx "$CONTEXT" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      additionalContext: $ctx
    }
  }'

exit 0
