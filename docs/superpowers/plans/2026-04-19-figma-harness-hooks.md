# Figma Harness Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire three Claude Code hooks that enforce the figma-harness orchestration at the tool layer — blocking writes before discovery, and capturing novel observations after each successful `use_figma` call.

**Architecture:** A `PreToolUse` command hook gates write calls by checking a shared state file; a `PostToolUse` command hook updates that state; a `PostToolUse` agent hook runs a prompt to extract and persist novel observations to `design-skills/<fileKey>/observations.md`.

**Tech Stack:** Bash, `jq` (macOS built-in via Homebrew), Claude Code hooks system (settings.json)

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `.claude/hooks/figma-pre.sh` | PreToolUse gate: classify read/write, check discovery state, block or allow |
| Create | `.claude/hooks/figma-post.sh` | PostToolUse state update: extract file key from response, update state file |
| Create | `.claude/settings.json` | Wire all three hooks with matchers and agent prompt |
| Gitignore | `.gitignore` | Exclude `.claude/figma-harness-state.json` from version control |

Runtime state file (not committed): `.claude/figma-harness-state.json`

---

## Task 1: Verify `use_figma` tool input schema

Before writing the hook, confirm which JSON field holds the JS script in `tool_input`. This determines the `jq` path used in every hook.

**Files:**
- Read: `~/.claude/settings.json` (global MCP config, to find figma server registration)
- Research: run a dummy `use_figma` call and capture hook stdin

- [ ] **Step 1: Check the Figma MCP tool schema**

```bash
# Find the figma MCP server binary or config
cat ~/.claude/settings.json | jq '.mcpServers'
```

Look for the figma server entry. The tool input field name is either `code`, `script`, or `javascript`.

- [ ] **Step 2: Confirm with a test hook**

Add a temporary debug hook to `.claude/settings.json` that dumps stdin to a file:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__figma__use_figma",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'cat > /tmp/figma-hook-debug.json'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Trigger a `use_figma` call in a Figma session**

Ask Claude to run any trivial `use_figma` call (e.g., `return figma.currentPage.name`), then:

```bash
cat /tmp/figma-hook-debug.json | jq '.tool_input | keys'
```

Expected output — one of:
- `["code"]`
- `["script"]`
- `["javascript"]`

Record the field name. Use it in all subsequent hook scripts as `$SCRIPT_FIELD`.

- [ ] **Step 4: Remove the debug hook**

Delete the temporary hook from `.claude/settings.json` before proceeding.

- [ ] **Step 5: Commit finding as a code comment**

```bash
# No file to commit yet — note the field name for Tasks 2 and 3
# e.g., field name is "code" → jq path is .tool_input.code
```

---

## Task 2: Create `figma-pre.sh` (PreToolUse gate)

**Files:**
- Create: `.claude/hooks/figma-pre.sh`

- [ ] **Step 1: Create the hooks directory**

```bash
mkdir -p "/path/to/figma-harness/.claude/hooks"
```

- [ ] **Step 2: Write the hook script**

Replace `CODE_FIELD` with the field name confirmed in Task 1 (e.g., `code`).

```bash
#!/usr/bin/env bash
# figma-pre.sh — PreToolUse gate for use_figma
# Blocks write calls until discovery has run this session.

set -euo pipefail

STATE_FILE="${CLAUDE_PROJECT_DIR}/.claude/figma-harness-state.json"
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
SCRIPT=$(echo "$INPUT" | jq -r '.tool_input.CODE_FIELD // ""')

# ── File key extraction ──────────────────────────────────────────
FILE_KEY=$(echo "$SCRIPT" | grep -oE 'figma\.com/(design|file)/[A-Za-z0-9]+' | head -1 | grep -oE '[A-Za-z0-9]+$' || true)

# ── Load or reset state ──────────────────────────────────────────
if [[ -f "$STATE_FILE" ]]; then
  STORED_SESSION=$(jq -r '.sessionId // ""' "$STATE_FILE")
  if [[ "$STORED_SESSION" != "$SESSION_ID" ]]; then
    # Stale state from a previous session — reset
    echo "{}" > "$STATE_FILE"
  fi
else
  echo "{}" > "$STATE_FILE"
fi

DISCOVERY_RAN=$(jq -r '.discoveryRan // false' "$STATE_FILE")
STORED_KEY=$(jq -r '.fileKey // ""' "$STATE_FILE")

# ── Update file key if newly found ───────────────────────────────
if [[ -n "$FILE_KEY" && "$STORED_KEY" != "$FILE_KEY" ]]; then
  jq --arg k "$FILE_KEY" --arg s "$SESSION_ID" \
    '.fileKey = $k | .sessionId = $s | .lastUpdated = now | todate' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

# ── Discovery detection ──────────────────────────────────────────
DISCOVERY_SIGNALS="getLocalVariableCollectionsAsync|getLocalTextStylesAsync|search_design_system"
if echo "$SCRIPT" | grep -qE "$DISCOVERY_SIGNALS"; then
  jq --arg s "$SESSION_ID" \
    '.discoveryRan = true | .sessionId = $s | .lastUpdated = now | todate' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  exit 0
fi

# ── Write detection ──────────────────────────────────────────────
WRITE_SIGNALS="appendChild|createFrame|createComponent|setSharedPluginData|setPluginData|insertChild|createVector|createText|createRectangle|createEllipse|createPolygon|createStar|createLine|createBooleanOperation|createImage|createPage|deleteNode|detachInstance"
if echo "$SCRIPT" | grep -qE "$WRITE_SIGNALS"; then
  if [[ "$DISCOVERY_RAN" != "true" ]]; then
    echo "[figma-harness] Discovery has not run this session." >&2
    echo "Paste scripts/discovery-audit.js into use_figma before writing." >&2
    exit 2
  fi
fi

exit 0
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x ".claude/hooks/figma-pre.sh"
```

- [ ] **Step 4: Smoke test — discovery not yet run**

Create a test input file:

```bash
cat > /tmp/test-pre-write.json << 'EOF'
{
  "session_id": "test-session-001",
  "hook_event_name": "PreToolUse",
  "tool_name": "mcp__figma__use_figma",
  "tool_input": {
    "code": "const frame = figma.createFrame(); frame.name = 'Test';"
  }
}
EOF
```

Run:
```bash
echo "$(cat /tmp/test-pre-write.json)" | bash .claude/hooks/figma-pre.sh
echo "Exit: $?"
```

Expected: exit code 2, stderr contains `[figma-harness] Discovery has not run this session.`

- [ ] **Step 5: Smoke test — discovery already ran**

First seed the state:
```bash
cat > .claude/figma-harness-state.json << 'EOF'
{"sessionId":"test-session-001","discoveryRan":true,"fileKey":"","lastUpdated":"2026-04-19T00:00:00Z"}
EOF
```

Run the same write input again:
```bash
echo "$(cat /tmp/test-pre-write.json)" | bash .claude/hooks/figma-pre.sh
echo "Exit: $?"
```

Expected: exit code 0 (allowed through).

- [ ] **Step 6: Smoke test — discovery call passes through**

```bash
cat > /tmp/test-pre-discovery.json << 'EOF'
{
  "session_id": "test-session-002",
  "hook_event_name": "PreToolUse",
  "tool_name": "mcp__figma__use_figma",
  "tool_input": {
    "code": "const cols = await figma.variables.getLocalVariableCollectionsAsync(); return JSON.stringify(cols);"
  }
}
EOF

rm -f .claude/figma-harness-state.json
echo "$(cat /tmp/test-pre-discovery.json)" | bash .claude/hooks/figma-pre.sh
echo "Exit: $?"
cat .claude/figma-harness-state.json | jq '.discoveryRan'
```

Expected: exit 0, `discoveryRan` is `true` in state file.

- [ ] **Step 7: Commit**

```bash
git add .claude/hooks/figma-pre.sh
git commit -m "feat: add PreToolUse gate hook for use_figma write calls"
```

---

## Task 3: Create `figma-post.sh` (PostToolUse state update)

**Files:**
- Create: `.claude/hooks/figma-post.sh`

- [ ] **Step 1: Write the hook script**

```bash
#!/usr/bin/env bash
# figma-post.sh — PostToolUse state update for use_figma
# Extracts file key from tool response if not yet in state.

set -euo pipefail

STATE_FILE="${CLAUDE_PROJECT_DIR}/.claude/figma-harness-state.json"
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // "" | tostring')

# Only proceed if state file exists
[[ -f "$STATE_FILE" ]] || exit 0

STORED_KEY=$(jq -r '.fileKey // ""' "$STATE_FILE")

# If file key already set, nothing to do
[[ -n "$STORED_KEY" ]] && exit 0

# Try to extract a file key from the response
# Figma node IDs contain colons (e.g. "21:173") — not useful for file key
# Look for a fileKey field explicitly in the response JSON
FILE_KEY=$(echo "$RESPONSE" | grep -oE '"fileKey"\s*:\s*"([A-Za-z0-9]+)"' | grep -oE '[A-Za-z0-9]{10,}' | head -1 || true)

if [[ -n "$FILE_KEY" ]]; then
  jq --arg k "$FILE_KEY" --arg s "$SESSION_ID" \
    '.fileKey = $k | .sessionId = $s | .lastUpdated = now | todate' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

exit 0
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x ".claude/hooks/figma-post.sh"
```

- [ ] **Step 3: Smoke test**

```bash
cat > /tmp/test-post.json << 'EOF'
{
  "session_id": "test-session-003",
  "hook_event_name": "PostToolUse",
  "tool_name": "mcp__figma__use_figma",
  "tool_input": { "code": "return figma.currentPage.name;" },
  "tool_response": { "fileKey": "ABC123XYZ99", "result": "Page 1" }
}
EOF

echo '{"sessionId":"test-session-003","discoveryRan":true,"fileKey":"","lastUpdated":"2026-04-19T00:00:00Z"}' > .claude/figma-harness-state.json
echo "$(cat /tmp/test-post.json)" | bash .claude/hooks/figma-post.sh
cat .claude/figma-harness-state.json | jq '.fileKey'
```

Expected: `"ABC123XYZ99"`

- [ ] **Step 4: Commit**

```bash
git add .claude/hooks/figma-post.sh
git commit -m "feat: add PostToolUse state-update hook for use_figma"
```

---

## Task 4: Wire hooks and agent capture in `settings.json`

**Files:**
- Create: `.claude/settings.json`

- [ ] **Step 1: Create settings.json with all three hooks**

Replace `CODE_FIELD` with the field name from Task 1, and `PROJECT_ROOT` with the absolute path to the figma-harness repo.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__figma__use_figma",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/figma-pre.sh",
            "timeout": 10,
            "statusMessage": "Figma harness: checking discovery gate..."
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__figma__use_figma",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/figma-post.sh",
            "timeout": 5
          },
          {
            "type": "agent",
            "prompt": "You are a Figma design knowledge extractor.\n\nYou have just received a use_figma API response. Decide if it contains a novel, file-specific observation worth persisting to the design-skills knowledge base.\n\n\"Novel\" means: a token name, component key, node ID, mode name, or structural pattern not likely to be obvious from the Figma API docs alone — something specific to THIS file that would help future sessions avoid re-discovery.\n\nFirst, read $CLAUDE_PROJECT_DIR/.claude/figma-harness-state.json to get the fileKey. If fileKey is empty or the file doesn't exist, exit silently.\n\nIf the response contains something novel:\n- Append a single markdown bullet to $CLAUDE_PROJECT_DIR/design-skills/{fileKey}/observations.md (create file if missing, create directory if missing)\n- Format: `- YYYY-MM-DD: [observation]. Node/query: [id or search string].`\n\nIf not novel, do nothing.\n\nDo not explain your reasoning. Either write the bullet or exit silently.",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON syntax**

```bash
jq . .claude/settings.json
```

Expected: JSON pretty-printed with no errors.

- [ ] **Step 3: Verify hook file paths are correct**

```bash
ls -la .claude/hooks/figma-pre.sh .claude/hooks/figma-post.sh
```

Expected: both files exist and are executable (`-rwxr-xr-x`).

- [ ] **Step 4: Commit**

```bash
git add .claude/settings.json
git commit -m "feat: wire figma-harness hooks in settings.json"
```

---

## Task 5: Add gitignore entry for state file

**Files:**
- Modify: `.gitignore` (create if missing)

- [ ] **Step 1: Add state file to gitignore**

```bash
echo '.claude/figma-harness-state.json' >> .gitignore
```

- [ ] **Step 2: Verify it's excluded**

```bash
git check-ignore -v .claude/figma-harness-state.json
```

Expected output: `.gitignore:N:.claude/figma-harness-state.json`

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore figma-harness runtime state file"
```

---

## Task 6: End-to-end integration test

This task has no code to write — it verifies the full hook chain works in a live Claude Code session with the Figma MCP connected.

- [ ] **Step 1: Open a Claude Code session in the figma-harness project**

```bash
cd /path/to/figma-harness
claude
```

- [ ] **Step 2: Attempt a write call before discovery — expect block**

Paste this prompt to Claude:
> "Run this use_figma script: `const f = figma.createFrame(); f.name = 'Hook Test'; return f.id;`"

Expected: Claude Code shows "Figma harness: checking discovery gate..." status, then the call is blocked. Claude's response should include the error message about running discovery first.

- [ ] **Step 3: Run the discovery script — expect passthrough**

Paste this prompt to Claude:
> "Run the discovery audit from scripts/discovery-audit.js"

Expected: hook allows it through, state file now has `discoveryRan: true`.

Verify:
```bash
cat .claude/figma-harness-state.json | jq '.discoveryRan'
```

- [ ] **Step 4: Attempt the same write call again — expect allow**

Paste the same write prompt from Step 2 again.

Expected: hook allows it through, call executes against Figma.

- [ ] **Step 5: Verify observation capture**

After the write call succeeds, wait ~30 seconds for the agent hook to complete, then:

```bash
FILE_KEY=$(cat .claude/figma-harness-state.json | jq -r '.fileKey')
cat "design-skills/${FILE_KEY}/observations.md" 2>/dev/null || echo "No observations yet (response may not have been novel)"
```

Expected: either a bullet entry exists, or the file is absent/empty because the response contained nothing novel.

---

## Task 7: Verify `tool_input` field name (if Task 1 confirmed a different field)

Only needed if Task 1 found the field is NOT `code`. If Task 1 confirmed `code`, skip this task.

**Files:**
- Modify: `.claude/hooks/figma-pre.sh` — update `jq` path on line extracting `SCRIPT`

- [ ] **Step 1: Update the field name in figma-pre.sh**

If Task 1 found the field is `script`:
```bash
# In figma-pre.sh, change:
SCRIPT=$(echo "$INPUT" | jq -r '.tool_input.code // ""')
# To:
SCRIPT=$(echo "$INPUT" | jq -r '.tool_input.script // ""')
```

If Task 1 found the field is `javascript`:
```bash
SCRIPT=$(echo "$INPUT" | jq -r '.tool_input.javascript // ""')
```

- [ ] **Step 2: Re-run the smoke tests from Task 2 Steps 4–6 to confirm they still pass**

- [ ] **Step 3: Commit**

```bash
git add .claude/hooks/figma-pre.sh
git commit -m "fix: use correct tool_input field name for use_figma script"
```
