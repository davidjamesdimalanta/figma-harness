# Context Injection Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `figma-pre.sh` PreToolUse hook to inject the relevant capability file contents into Claude's context as `additionalContext` before every `use_figma` call, making the figma-harness skill files load automatically without Claude needing to read them manually.

**Architecture:** The existing `figma-pre.sh` already classifies `use_figma` calls (discovery vs. write vs. read). This plan adds a second output path: after the gate check, the hook emits a JSON `additionalContext` block containing (1) a compact excerpt of `figma-code.md` universal constraints, and (2) the full content of whichever capability file(s) the call type requires — all within the 10,000-character `additionalContext` cap enforced by Claude Code. A separate `scripts/summarize-capability.sh` helper truncates files to fit.

**Tech Stack:** Bash, `jq`, Claude Code `PreToolUse` hook `additionalContext` output field

---

## Background: How `additionalContext` Works

The `PreToolUse` hook can return JSON to stdout. Claude Code reads it and injects `additionalContext` into the conversation context before the tool executes. Cap: 10,000 characters. If exceeded, Claude Code saves to a file and replaces with a preview + path.

Output format the hook must emit (exit 0 + stdout):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "...capability file content here..."
  }
}
```

On a blocking exit (exit 2), the hook writes to stderr and emits nothing to stdout — that path is unchanged.

---

## Capability File Selection Logic

| Call type (detected by script content) | Inject |
|---|---|
| Discovery signals (`getLocalVariableCollectionsAsync`, `search_design_system`, etc.) | `figma-read.md` + `figma-code.md` excerpt |
| Write: frame/layout signals (`createFrame`, `insertChild`, `appendChild`) | `figma-frames.md` + `figma-code.md` excerpt |
| Write: component signals (`createComponent`, `detachInstance`) | `figma-components.md` + `figma-code.md` excerpt |
| Write: token/variable signals (`setSharedPluginData`, `setPluginData`) | `figma-tokens.md` + `figma-code.md` excerpt |
| Write: vector/shape signals (`createVector`, `createRectangle`, `createEllipse`, `createPolygon`, `createStar`, `createLine`, `createBooleanOperation`, `createImage`) | `figma-vectors.md` + `figma-code.md` excerpt |
| Write: page/file signals (`createPage`, `deleteNode`) | `figma-files.md` + `figma-code.md` excerpt |
| Any write (fallback — no specific match above) | `figma-code.md` excerpt only |
| Pure read (no write or discovery signals) | `figma-code.md` excerpt only |

Multiple signal types in one script → inject all matching capability files, truncating proportionally to stay under 10,000 chars total.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `.claude/hooks/figma-pre.sh` | Add `additionalContext` JSON output after the gate check |
| Create | `.claude/hooks/lib/select-context.sh` | Pure function: given signal flags, returns file list and truncated content |
| Create | `.claude/hooks/lib/truncate-to-budget.sh` | Truncates content to a char budget, appending `…[truncated, full file at PATH]` |

No changes to capability files (`figma-*.md`). No new dependencies.

---

## Task 1: Write `truncate-to-budget.sh`

**Files:**
- Create: `.claude/hooks/lib/truncate-to-budget.sh`

This helper takes a file path and a character budget, outputs the file content truncated to that budget with a trailing note if cut.

- [ ] **Step 1: Create the lib directory**

```bash
mkdir -p "/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness/.claude/hooks/lib"
```

- [ ] **Step 2: Write the script**

```bash
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
```

- [ ] **Step 3: Make executable**

```bash
chmod +x ".claude/hooks/lib/truncate-to-budget.sh"
```

- [ ] **Step 4: Smoke test — file under budget**

```bash
echo "hello world" > /tmp/test-cap.md
bash .claude/hooks/lib/truncate-to-budget.sh /tmp/test-cap.md 100
```
Expected: `hello world`

- [ ] **Step 5: Smoke test — file over budget**

```bash
python3 -c "print('x' * 200)" > /tmp/test-cap.md
bash .claude/hooks/lib/truncate-to-budget.sh /tmp/test-cap.md 50
```
Expected: 50 `x` characters followed by `…[truncated — full file at /tmp/test-cap.md]`

- [ ] **Step 6: Commit**

```bash
cd "/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness"
git add .claude/hooks/lib/truncate-to-budget.sh
git commit -m "feat: add truncate-to-budget helper for context injection"
```

---

## Task 2: Write `select-context.sh`

**Files:**
- Create: `.claude/hooks/lib/select-context.sh`

This helper takes the JS script content on stdin and outputs the combined capability file content to inject, staying within 9,500 chars (leaving 500 chars headroom for the JSON wrapper `figma-pre.sh` adds).

- [ ] **Step 1: Write the script**

```bash
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

[[ "$is_discovery" == "true" ]] && FILES+=("${DIR}/figma-read.md")
[[ "$is_frame"     == "true" ]] && FILES+=("${DIR}/figma-frames.md")
[[ "$is_component" == "true" ]] && FILES+=("${DIR}/figma-components.md")
[[ "$is_token"     == "true" ]] && FILES+=("${DIR}/figma-tokens.md")
[[ "$is_vector"    == "true" ]] && FILES+=("${DIR}/figma-vectors.md")
[[ "$is_file"      == "true" ]] && FILES+=("${DIR}/figma-files.md")

# ── Allocate budget equally across files ────────────────────────
FILE_COUNT=${#FILES[@]}
PER_FILE=$(( BUDGET / FILE_COUNT ))

# ── Build output ────────────────────────────────────────────────
OUTPUT=""
for F in "${FILES[@]}"; do
  CHUNK=$(bash "$TRUNCATE" "$F" "$PER_FILE")
  OUTPUT+="$(basename "$F" .md | tr '[:lower:]-' '[:upper:]_'):\n${CHUNK}\n\n---\n\n"
done

printf '%s' "$OUTPUT"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x ".claude/hooks/lib/select-context.sh"
```

- [ ] **Step 3: Smoke test — frame write script**

```bash
CLAUDE_PROJECT_DIR="/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness" \
  bash .claude/hooks/lib/select-context.sh <<'EOF' | wc -c
const f = figma.createFrame();
f.name = 'Test';
EOF
```
Expected: a number ≤ 9500

- [ ] **Step 4: Smoke test — output includes figma-code.md and figma-frames.md headers**

```bash
CLAUDE_PROJECT_DIR="/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness" \
  bash .claude/hooks/lib/select-context.sh <<'EOF' | grep -E "^FIGMA_CODE|^FIGMA_FRAMES"
const f = figma.createFrame();
EOF
```
Expected output lines:
```
FIGMA_CODE:
FIGMA_FRAMES:
```

- [ ] **Step 5: Smoke test — discovery script includes figma-read.md**

```bash
CLAUDE_PROJECT_DIR="/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness" \
  bash .claude/hooks/lib/select-context.sh <<'EOF' | grep "^FIGMA_READ"
const cols = await figma.variables.getLocalVariableCollectionsAsync();
EOF
```
Expected: `FIGMA_READ:`

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/lib/select-context.sh
git commit -m "feat: add capability file selector for context injection"
```

---

## Task 3: Extend `figma-pre.sh` to emit `additionalContext`

**Files:**
- Modify: `.claude/hooks/figma-pre.sh`

The existing hook ends with `exit 0` on the allow path. Replace that final `exit 0` with a block that builds and emits the JSON output containing `additionalContext`.

The gate logic (discovery check, write block) is unchanged. Only the exit path changes.

- [ ] **Step 1: Read the current end of `figma-pre.sh`**

```bash
tail -20 "/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness/.claude/hooks/figma-pre.sh"
```

Locate the final `exit 0` (the allow path — after the write block either passes or is skipped).

- [ ] **Step 2: Replace the final `exit 0` with context injection**

Find the last `exit 0` in the file (line number from step 1) and replace it with:

```bash
# ── Inject capability context ────────────────────────────────────
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
```

- [ ] **Step 3: Verify the existing smoke tests still pass**

**Smoke test A — write before discovery (must still block, exit 2):**
```bash
cd "/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness"
CLAUDE_PROJECT_DIR=$(pwd) bash .claude/hooks/figma-pre.sh <<'EOF'
{"session_id":"test-001","hook_event_name":"PreToolUse","tool_name":"mcp__figma__use_figma","tool_input":{"code":"const f = figma.createFrame(); f.name = 'Test'; return f.id;","fileKey":"ABC123","description":"test"}}
EOF
echo "Exit: $?"
```
Expected: exit 2, stderr contains `[figma-harness] Discovery has not run this session.`

**Smoke test B — write after discovery (must allow AND emit JSON with additionalContext):**
```bash
echo '{"sessionId":"test-001","discoveryRan":true,"fileKey":"","lastUpdated":"2026-04-19T00:00:00Z"}' > .claude/figma-harness-state.json
CLAUDE_PROJECT_DIR=$(pwd) bash .claude/hooks/figma-pre.sh <<'EOF'
{"session_id":"test-001","hook_event_name":"PreToolUse","tool_name":"mcp__figma__use_figma","tool_input":{"code":"const f = figma.createFrame(); f.name = 'Test'; return f.id;","fileKey":"ABC123","description":"test"}}
EOF
echo "Exit: $?"
```
Expected: exit 0, stdout is valid JSON containing `hookSpecificOutput.additionalContext` with content from `figma-frames.md` and `figma-code.md`.

Validate the JSON:
```bash
echo '{"sessionId":"test-001","discoveryRan":true,"fileKey":"","lastUpdated":"2026-04-19T00:00:00Z"}' > .claude/figma-harness-state.json
CLAUDE_PROJECT_DIR=$(pwd) bash .claude/hooks/figma-pre.sh <<'EOF' | jq '.hookSpecificOutput.additionalContext' | head -5
{"session_id":"test-001","hook_event_name":"PreToolUse","tool_name":"mcp__figma__use_figma","tool_input":{"code":"const f = figma.createFrame(); f.name = 'Test'; return f.id;","fileKey":"ABC123","description":"test"}}
EOF
```
Expected: first 5 lines of a non-null string containing capability file content.

**Smoke test C — discovery call (must allow AND emit JSON):**
```bash
rm -f .claude/figma-harness-state.json
CLAUDE_PROJECT_DIR=$(pwd) bash .claude/hooks/figma-pre.sh <<'EOF' | jq '.hookSpecificOutput.permissionDecision'
{"session_id":"test-002","hook_event_name":"PreToolUse","tool_name":"mcp__figma__use_figma","tool_input":{"code":"const cols = await figma.variables.getLocalVariableCollectionsAsync(); return JSON.stringify(cols);","fileKey":"ABC123","description":"discovery"}}
EOF
```
Expected: `"allow"`

- [ ] **Step 4: Verify context size is under 10,000 chars**

```bash
echo '{"sessionId":"test-001","discoveryRan":true,"fileKey":"","lastUpdated":"2026-04-19T00:00:00Z"}' > .claude/figma-harness-state.json
CLAUDE_PROJECT_DIR=$(pwd) bash .claude/hooks/figma-pre.sh <<'EOF' | jq -r '.hookSpecificOutput.additionalContext' | wc -c
{"session_id":"test-001","hook_event_name":"PreToolUse","tool_name":"mcp__figma__use_figma","tool_input":{"code":"const f = figma.createFrame(); f.name = 'Test'; return f.id;","fileKey":"ABC123","description":"test"}}
EOF
```
Expected: a number less than 10000.

- [ ] **Step 5: Clean up test state**

```bash
rm -f .claude/figma-harness-state.json
```

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/figma-pre.sh
git commit -m "feat: inject capability file context into use_figma PreToolUse hook"
```

---

## Task 4: Verify `figma-code.md` excerpt quality

**Files:**
- Read: `figma-code.md` (no changes)
- Possibly modify: `.claude/hooks/lib/select-context.sh` if the `figma-code.md` allocation is too small to be useful

`figma-code.md` is 11,971 bytes. With two files sharing a 9,500-char budget, each gets ~4,750 chars. Check whether the first 4,750 chars of `figma-code.md` contain the most critical constraints (font loading, async patterns, sizing lifecycle).

- [ ] **Step 1: Check what the first 4,750 chars of `figma-code.md` contain**

```bash
head -c 4750 "/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness/figma-code.md"
```

- [ ] **Step 2: Decision point**

If the first 4,750 chars contain the critical sections (font loading, async/await patterns, sizing lifecycle, binding patterns) → no change needed, Task 4 is done.

If the most critical content is buried deeper in the file → reorder `figma-code.md` to put the highest-priority constraints first (the most commonly violated rules). This makes truncation a feature rather than a bug.

To reorder: move the following sections to the top of `figma-code.md` if they aren't already:
1. Font loading rules (loadFontAsync must precede any text property set)
2. Async call patterns (no parallel use_figma calls)
3. Sizing lifecycle (resize before positioning)
4. Binding patterns (bindFill, bindStroke contract)

- [ ] **Step 3: If reordered, verify no content was lost**

```bash
wc -c "/Users/daviddimalanta/Documents/Claude/Projects/figma plugin development/figma-harness/figma-code.md"
```
Expected: same byte count as before reorder (±whitespace).

- [ ] **Step 4: Commit if changed**

```bash
git add figma-code.md
git commit -m "refactor: reorder figma-code.md so critical constraints appear first (for context injection truncation)"
```

If no change was needed, skip this commit.

---

## Success Criteria

1. Every `use_figma` call (read or write) results in the relevant capability file content appearing in `additionalContext` before the call executes
2. Context size never exceeds 10,000 chars (verified by smoke test in Task 3 Step 4)
3. The existing gate (block writes before discovery) still works — exit 2 path is unchanged
4. `figma-code.md` universal constraints always appear in the injected context regardless of call type
5. Task-specific capability files (frames, components, tokens, vectors, files, read) appear only when the script signals that capability is needed
