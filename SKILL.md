---
name: figma-harness
description: "Self-healing harness for Figma design work. Read this skill first on every Figma request. Runs parallel discovery, resolves URL targets, auto-loads file-specific design skills, selects the API capabilities needed for the task, emits an execution plan before any write, and captures new knowledge into durable files. References: figma-read, figma-frames, figma-components, figma-tokens, figma-vectors, figma-documentation, figma-files, figma-code, figma-personal-workflow."
metadata:
  mcp-server: figma
---

# Figma Harness: Master Orchestration Hub

Read this skill first. Every Figma session starts here: preference check, parallel discovery, URL resolution, capability selection, execution plan.

---

## Global Rule: AskUserQuestion

Any time the agent needs to ask the user a question — for clarification, ambiguity resolution, preference confirmation, or page selection — use the `AskUserQuestion` method. This applies at every stage of the workflow without exception.

---

## Three-layer model

The harness has three layers, each with a different rule for who writes to it.

1. **Capability files** (`figma-*.md`): protected reference libraries for one API surface. Read the ones your task needs. Edit only when Figma itself changes or a new platform-wide constraint is discovered, and only after proposing the change via `AskUserQuestion`.
2. **Script library** (`scripts/*.js`): reusable `use_figma` snippets. Any new reusable snippet longer than twenty lines becomes a script. See `scripts/README.md` for the contract.
3. **Design skills** (`design-skills/<file-key>/*.md`): file-specific and library-specific observations. Auto-loaded at Stage 2 Call 6. The harness writes these without asking; they are descriptive, not opinionated. See `design-skills/README.md` for the format.

User workflow preferences sit alongside these layers, not inside them. See `figma-personal-workflow.md` for the capture protocol.

## Capability Files

These are reference libraries, not sequential workflows. Read every file whose capability is needed for the current task. Multiple files are read together, not exclusively.

| File | API surface covered |
|---|---|
| `figma-read.md` | Reading existing design state: get_design_context, get_metadata, get_variable_defs, source parsing |
| `figma-frames.md` | Frame and layout creation: createFrame, auto-layout, rightEdge placement, section pattern |
| `figma-components.md` | Component instances, library import, component creation, bottom-up build order |
| `figma-tokens.md` | Variable and style binding, token architecture, WCAG, migration |
| `figma-vectors.md` | Vectors, shapes, boolean ops, gradients, image fills |
| `figma-documentation.md` | Style guide specimens, Code Connect, token export, FigJam diagrams |
| `figma-files.md` | File creation, page management |
| `figma-code.md` | Protected API constraints: font loading, async lookup, sizing lifecycle, binding patterns |
| `figma-personal-workflow.md` | Capturing and applying user preferences |

## Workflow References

Longer workflows live alongside their parent capability files. Read these when their specific workflow applies.

| File | When to read |
|---|---|
| `references/component-swap.md` | Replacing every instance of a deprecated component across a file |
| `references/component-reactions.md` | Wiring prototype reactions to boolean variables (filter chips, toggle states) |
| `references/vector-effects-exports.md` | Applying effects, gradients, or setting up node exports |

## Bundled Scripts

| Folder | Contents |
|---|---|
| `scripts/discovery-audit.js` | Stage 2 Call 1 local audit. Paste into use_figma |
| `scripts/rightedge-placement.js` | rightEdge frame placement boilerplate |
| `scripts/wcag-contrast.js` | getLuminance + contrastRatio utilities |
| `scripts/bind-fill.js` | bindFill, bindStroke, safeAppend utilities |
| `scripts/token-audit.js` | Hardcoded fill finder + token gap logger |
| `scripts/component-swap.js` | Full instance swap + master deletion protocol |

---

## Stage 1: Preference Check

Before any tool call, check whether a `## Designer Workflow Preferences` section exists in any capability file relevant to the task. If preferences are present, load them into working memory — they override all defaults for this session.

---

## Stage 2: Parallel Discovery

Run once per session at first contact with a file. Never repeat while edits are in progress.

The full discovery audit script is in `scripts/discovery-audit.js` — paste it directly into a `use_figma` call. Call all five in the same response:

**Call 1 — Local audit (use_figma — see `scripts/discovery-audit.js`):**
```js
const [cols, text, paint, effect] = await Promise.all([
  figma.variables.getLocalVariableCollectionsAsync(),
  figma.getLocalTextStylesAsync(),
  figma.getLocalPaintStylesAsync(),
  figma.getLocalEffectStylesAsync(),
]);
return JSON.stringify({
  variableCollections: cols.map(c => ({
    id: c.id, name: c.name,
    modes: c.modes.map(m => m.name),
    variables: c.variableIds.map(id => {
      const v = figma.variables.getVariableById(id);
      return v ? `${v.name} [${v.resolvedType}]` : id;
    }),
  })),
  textStyles: text.map(s => ({ id: s.id, name: s.name, fontSize: s.fontSize, fontFamily: s.fontName?.family })),
  paintStyles: paint.map(s => ({ id: s.id, name: s.name })),
  effectStyles: effect.map(s => ({ id: s.id, name: s.name })),
}, null, 2);
```

**Call 2 — Published library components:** `search_design_system("")`

**Call 3 — Remote library variables and styles (critical — Call 1 misses these entirely):**
`search_design_system("", { includeVariables: true, includeStyles: true })`

> `getLocalVariableCollectionsAsync()` only returns variables created in this file. Files using a shared/published library will have remote variables invisible to Call 1. Call 3 surfaces them. Merge both results before building the Session Context token picture.

**Call 4 — File/node structure:** `get_metadata(resolvedNodeId ?? fileRoot)`

**Call 5 — Visual baseline (only if a target node-id was provided):** `get_screenshot(resolvedNodeId)`

**Call 6 — Design-skill load (runs after Stage 3 URL resolution returns the file key):**

Read every markdown file under `design-skills/<file-key>/`. If library keys surface in Call 2 or Call 3, also read every file under `design-skills/libraries/<library-key>/`. Treat contents as session context: they reflect what has worked in this file before, but they are not authoritative the way capability files are. If a design skill contradicts a capability file, trust the capability file and flag the design skill for update.

If no folder exists for the resolved file key, continue without error. The first time the harness works on a file, `design-skills/` may be empty for it; Stage 7 will seed it with the first durable observation.

After all six return, synthesize a **Session Context**:

```
SESSION CONTEXT
Target node              : [name, type, page] — or — [no URL target, full file]
Local variable collections: [N collections, M variables total]
Remote library variables  : [N from search_design_system includeVariables]
Text styles : [N]   Paint styles : [N]   Effect styles : [N]
Library components       : [N from search_design_system]
File state               : [empty | partial system | mature system]
```

File state classification:
- `empty` — 0 variable collections, 0 styles
- `partial system` — some tokens or styles exist, gaps present
- `mature system` — 2+ variable collections with meaningful coverage, text and paint styles present

---

## Stage 3: URL Target Resolution

1. Extract `node-id` from the URL. Hyphens in the URL (`node-id=21-173`) become colons internally (`21:173`). Confirm the node's page, name, and type from the `get_metadata` result.
2. If the node is a page (canvas), the output will be a new frame placed on that page. If it is a frame, the output will be placed alongside it.
3. If the URL has no `node-id`, surface all top-level frames and ask which page to work on using `AskUserQuestion`.

Node ID is the only authoritative target reference. Never match by name.

---

## Stage 3b: Context Extraction

Scan the message for structured signals and hold them as **Project Context**:

| Category | Signals | Name |
|---|---|---|
| Device / platform | "mobile", "iOS", "desktop", width in px | `device` |
| Code framework | "React", "Tailwind", "SwiftUI" | `framework` |
| Brand / visual | hex codes, "our brand color" | `brandColors` |
| Fidelity intent | "rough", "high-fi", "production-ready" | `fidelityIntent` |
| Product domain | "fintech", "SaaS", "health" | `domain` |
| Screen / component type | named screen, named component | `targetType` |
| Source reference | URL to existing design to recreate/translate | `sourceRef` |

---

## Stage 4: Capability Selection

Read the task and the Session Context. Mark every capability the task requires, then read all marked files before writing any code.

| Capability | Select when the task requires… |
|---|---|
| `figma-read` | Source reference provided, recreation/translation task, audit, reading existing tokens or structure |
| `figma-frames` | Creating any new frame, screen, section, or layout scaffold |
| `figma-components` | Any component instance, library import, component creation, or UI element that may exist in the design system |
| `figma-tokens` | Applying, migrating, or creating design system color, spacing, or typography tokens |
| `figma-vectors` | Icons, shapes, paths, boolean ops, gradients, image fills, effects, or exports |
| `figma-documentation` | Style guide, Code Connect, token export, FigJam diagram, dev handoff artifact |
| `figma-files` | New file or new page creation |

Multiple capabilities are the norm, not the exception. A screen recreation with a mature design system typically requires figma-read + figma-frames + figma-components + figma-tokens.

Always read `figma-code.md` before writing any use_figma script. Its constraints apply universally.

**Design-skill loading:** Stage 2 Call 6 has already read any file under `design-skills/<file-key>/` that matches the resolved file key. If that folder contains `components.md` with gold-standard anatomy node ids or `tokens.md` with architecture notes, load the referenced canvas examples via `get_design_context` + `get_screenshot` before writing. These examples define what correct output looks like for this specific file.

---

## Stage 5: Execution Plan

Before any write call, emit this plan. No SKIP conditions — it fires every time.

```
EXECUTION PLAN
Task           : [one-sentence description]
Target         : new frame at rightEdge + 200 on page [name] (node [id])
                 — or — editing [specific property] on node [id]
Capabilities   : [list of selected capability files]
Component map  : [element → component key] / [element → raw frame if no match]
                 (omit if figma-components not selected)
Token sources  : [variable collection names to use]
                 (omit if figma-tokens not selected)
Sections       : [ordered list of build phases]
Ambiguity      : [one question if any execution decision is genuinely unclear — otherwise "none"]
```

The execution plan is visible to the designer before any write. It naturally invites correction. If the ambiguity line contains a question, deliver it using `AskUserQuestion` and wait for the answer before proceeding.

---

## Stage 6: Personal Workflow Layer

When a designer states a preference mid-session, offer to save it using `AskUserQuestion`:
> "Want me to save that as a workflow preference so I follow it automatically going forward?"

When the same answer appears twice across separate sessions, offer proactively using `AskUserQuestion`:
> "You have picked [answer] twice now. Want me to save that so I stop asking?"

See `figma-personal-workflow.md` for how to persist preferences and which sections of each file are safe to edit.

---

## Stage 7: Capturing New Knowledge

Every Figma session has the chance to widen the harness. Three kinds of new knowledge can surface, each with a different destination and capture rule.

**1. A new Figma API constraint or failure mode.**

Something changed what scripts can safely do: a method was renamed, a property started throwing on a node type it used to accept, an async call started returning stale references. This is platform knowledge and belongs in the relevant capability file, usually `figma-code.md`.

Capture rule: capability files are protected. Propose the new entry to the user via `AskUserQuestion` before writing, quoting the exact error or behavior observed. Include a minimal reproduction.

**2. A new reusable script pattern.**

The harness wrote a snippet once and would use it again. If the snippet is more than twenty lines and generalizes beyond the current file, extract it. Destination: `scripts/<name>.js` with an entry added to `scripts/README.md` following that contract.

Capture rule: the harness may extract scripts without asking, but must mention it in the response so the user can push back if the extraction was premature. Snippets shorter than twenty lines stay inline.

**3. A file-specific or library-specific fact.**

A token is named `brand/primary/600` not `color/primary`. A component lives at a non-obvious node. This file's modes are set up in an unusual way. Destination: `design-skills/<file-key>/*.md`.

Capture rule: the harness writes these without asking, because they are observational, not opinionated. Each entry must include the date observed and the node id or search query that surfaced it. See `design-skills/README.md` for the format.

**Anti-pattern:** treating a `use_figma` script failure as one-off. Every unknown failure mode is a candidate for `figma-code.md`; every unknown file-specific fact is a candidate for `design-skills/`. The harness grows through Stage 7 or it does not grow at all.

---

## Tool Reference and Core Technical Rules

Every tool the harness calls and the rules that apply to every `use_figma` script live in `references/tool-reference.md`. Read that file once per session, or whenever a tool name appears that you do not immediately recognize.

---

## Anti-Patterns

- Running the parallel discovery phase again while edits are in progress.
- Resolving a target node by name instead of node-id.
- Running two use_figma write calls simultaneously.
- Using `search_design_system` as the only discovery step — it misses all local assets.
- Running only Call 1 for variable discovery and skipping Call 3 — remote library variables are invisible to `getLocalVariableCollectionsAsync()`.
- Using `get_variable_defs` to discover available tokens — it only returns already-bound tokens.
- Skipping `get_screenshot` after any write.
- Building an entire screen or component set in one use_figma call.
- Clearing an existing frame's children and rebuilding inside it. A destination URL means "place new content here" — always as a new frame. Never empty and repurpose an existing one.
- Creating frames as top-level page children intending to reparent them later. `appendChild()` silently fails when moving nodes across parents, producing orphaned frames. Build directly inside the final wrapper from the start.
- Building UI elements (buttons, chips, nav bars) as raw frames when matching library components exist. The component map in the execution plan must be completed before building.
- Reading `node.vectorPaths` without error handling on any VECTOR node from an unknown source.
- Selecting only one capability when the task clearly needs several.
- Emitting an execution plan with no ambiguity and then asking clarifying questions anyway — plan first, then build.