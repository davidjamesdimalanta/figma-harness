# Figma Harness Hooks — Design Spec
_2026-04-19_

## Problem

The `figma-harness` SKILL.md enforces orchestration through prose instructions — Claude reads them and tries to follow them. This is advisory, not enforced. A real harness needs to intercept `use_figma` calls at the tool layer, gate writes behind discovery, and capture observations without relying on Claude's self-discipline.

## Goal

Wire three Claude Code hooks into `.claude/settings.json` that:
1. Block `use_figma` write calls until discovery has run this session
2. Persist novel file-specific observations to `design-skills/<fileKey>/` after each successful call

No sidecar process. No changes to SKILL.md. No new dependencies beyond `jq` (already available on macOS).

---

## Architecture

```
PreToolUse  → hooks/figma-pre.sh        (command hook — gate + state write)
PostToolUse → hooks/figma-post.sh       (command hook — state update)
PostToolUse → prompt hook (agent type)  (observation capture, conditional)
```

All three use matcher: `mcp__figma__use_figma`.

Shared state: `.claude/figma-harness-state.json`

---

## State File

Path: `.claude/figma-harness-state.json`

```json
{
  "sessionId": "abc123",
  "fileKey": "XYZ987",
  "discoveryRan": true,
  "lastUpdated": "2026-04-19T04:33:58Z"
}
```

| Field | Set by | Meaning |
|---|---|---|
| `sessionId` | pre-hook | From `session_id` in hook input. Scopes state to current session. |
| `fileKey` | pre-hook or post-hook | Parsed from Figma URL regex in `use_figma` script. |
| `discoveryRan` | pre-hook | `true` when script contains discovery signals. |
| `lastUpdated` | any hook | ISO timestamp, for debugging. |

On session start, if the state file exists but `sessionId` doesn't match the current session, the hooks treat it as stale and reset `discoveryRan` to `false`.

---

## PreToolUse Hook

**File:** `hooks/figma-pre.sh`  
**Matcher:** `mcp__figma__use_figma`  
**Type:** `command`

### Logic

1. Read stdin JSON, extract `session_id` and `tool_input.code` (the JS snippet).
2. Attempt file key extraction via regex: `figma\.com\/(?:design|file)\/([A-Za-z0-9]+)`. If found, write to state.
3. **Discovery detection:** script contains any of:
   - `getLocalVariableCollectionsAsync`
   - `getLocalTextStylesAsync`
   - `search_design_system`
   
   If matched → set `discoveryRan: true` in state, exit 0.

4. **Write detection:** script contains any of:
   ```
   appendChild, createFrame, createComponent, setSharedPluginData,
   setPluginData, insertChild, createVector, createText, createRectangle,
   createEllipse, createPolygon, createStar, createLine,
   createBooleanOperation, createImage, createPage, deleteNode, detachInstance
   ```

5. If write detected AND (`discoveryRan === false` OR state file missing OR sessionId mismatch):
   - Exit 2 with stderr:
     ```
     [figma-harness] Discovery has not run this session.
     Paste scripts/discovery-audit.js into use_figma before writing.
     ```

6. Otherwise: exit 0.

### Output JSON (on allow)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
```

---

## PostToolUse Hook 1 — State Update

**File:** `hooks/figma-post.sh`  
**Matcher:** `mcp__figma__use_figma`  
**Type:** `command`

Reads `tool_response` from stdin. If a Figma file key can be extracted from the response (e.g. from a node ID pattern or metadata), writes it to state if not already set. Always exits 0.

This is a cheap fallback for cases where the file key wasn't in the script itself.

---

## PostToolUse Hook 2 — Observation Capture

**Matcher:** `mcp__figma__use_figma`  
**Type:** `agent`

Only fires when `fileKey` is set in `.claude/figma-harness-state.json`.

### Prompt

```
You are a Figma design knowledge extractor.

Given a use_figma API response, decide if it contains a novel, file-specific 
observation worth persisting to the design-skills knowledge base.

"Novel" means: a token name, component key, node ID, mode name, or structural 
pattern not likely to be obvious from the Figma API docs alone — something that 
is specific to THIS file and would help future sessions avoid re-discovery.

If YES: append a single markdown bullet to design-skills/<fileKey>/observations.md:
  - YYYY-MM-DD: [observation]. Node/query: [id or search string].

If NO: do nothing. Do not write anything.

Do not explain your reasoning. Either write the bullet or exit silently.
```

The agent has `Write` and `Read` tool access. It creates `design-skills/<fileKey>/observations.md` if it doesn't exist.

---

## Settings Wire-up

In `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__figma__use_figma",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/figma-pre.sh",
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
            "command": "bash .claude/hooks/figma-post.sh",
            "timeout": 5
          },
          {
            "type": "agent",
            "prompt": "...(see above)...",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

---

## File Layout

```
figma-harness/
├── .claude/
│   ├── settings.json              ← hook config added here
│   ├── figma-harness-state.json   ← runtime state (gitignored)
│   └── hooks/
│       ├── figma-pre.sh
│       └── figma-post.sh
├── design-skills/
│   └── <fileKey>/
│       └── observations.md        ← written by agent hook
└── ... (existing SKILL.md, capability files, scripts/)
```

`figma-harness-state.json` should be added to `.gitignore` — it's ephemeral session state.

---

## Out of Scope

- Intercepting `mcp__figma__get_design_context`, `get_metadata`, `get_screenshot` — these are read-only and need no gate
- Modifying `tool_input` to inject annotations — the gate approach is sufficient
- Handling the `search_design_system` MCP tool — not a write surface
- Multi-file sessions (multiple file keys in one session) — defer; state file holds one key

---

## Success Criteria

1. A `use_figma` write call attempted before discovery is blocked with a clear message
2. After discovery runs, writes proceed without friction
3. After each successful `use_figma` call, `design-skills/<fileKey>/observations.md` gains a bullet if the response contained something novel, and nothing otherwise
4. The SKILL.md discovery requirement becomes self-enforcing rather than advisory
