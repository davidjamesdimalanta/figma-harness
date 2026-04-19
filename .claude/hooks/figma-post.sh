#!/usr/bin/env bash
set -euo pipefail

# figma-post.sh — PostToolUse hook for mcp__figma__use_figma
# Updates shared state with a fileKey found in tool_response when none is stored yet.

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

# If state file doesn't exist, pre-hook handles creation — nothing to do here.
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# If fileKey is already stored, nothing to update.
CURRENT_FK="$(jq -r '.fileKey // ""' "$STATE_FILE")"
if [[ -n "$CURRENT_FK" && "$CURRENT_FK" != "null" ]]; then
  exit 0
fi

# Read stdin JSON
INPUT="$(cat)"

# Try to extract fileKey from tool_response (must be at least 10 alphanumeric chars).
RESPONSE_FK="$(printf '%s' "$INPUT" | jq -r '.tool_response.fileKey // ""')"

if [[ ${#RESPONSE_FK} -ge 10 ]] && printf '%s' "$RESPONSE_FK" | grep -qE '^[A-Za-z0-9]+$'; then
  NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  STATE="$(jq --arg fk "$RESPONSE_FK" --arg ts "$NOW" \
    '.fileKey = $fk | .lastUpdated = $ts' "$STATE_FILE")"
  TMP="$(mktemp "${STATE_FILE}.XXXXXX")"
  printf '%s\n' "$STATE" > "$TMP"
  mv "$TMP" "$STATE_FILE"
fi

exit 0
