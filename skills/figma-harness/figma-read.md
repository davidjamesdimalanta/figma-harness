---
name: figma-read
description: "Capability reference for reading existing Figma design state. Use when a source reference is provided, when recreating or translating an existing design, when auditing current token usage, or when any task needs to understand what already exists before writing."
metadata:
  mcp-server: figma
---

# Figma Read — Reading Existing Design State

Select this capability when: a source URL is provided for recreation, the task is an audit or refactor analysis, or any write task needs to understand the current state of specific nodes before touching them.

Always complete Stage 2 parallel discovery in `SKILL.md` before using any tool in this file.

---

## When to Use Each Reading Tool

| Tool | Use for |
|---|---|
| `get_metadata` | Structural map: layer IDs, types, names, positions, sizes. Call first on any large frame. |
| `get_design_context` | Full layout, spacing, fill, and style data for implementation. Call on specific target nodes, never a full page. |
| `get_screenshot` | Visual reference and post-write validation. Take before any write as the comparison baseline. |
| `get_variable_defs` | Which tokens are already bound to a specific node. Use for audit and refactor scoping. |
| `use_figma` (audit) | Local variable collections and styles — the full discovery script from SKILL.md Stage 2. |
| `search_design_system` | Published library components and assets. Returns keys needed for `importComponentByKeyAsync`. |

---

## Source Frame Reading — Recreation Protocol

When recreating an existing design, call `get_design_context` on the source node to extract the full specification. Then call `get_screenshot` for visual reference.

```
get_design_context(nodeId: "<source_node_id>")
get_screenshot(nodeId: "<source_node_id>")
```

Parse the design context output to extract:
- Frame dimensions and auto-layout settings
- Child node names, types, and positions
- Fill colors (map to token names via the session context variable list)
- Typography (match to text style names)
- Spacing and padding values (map to spacing tokens)
- Image and vector nodes (note IDs for clone operations)

Build a **source spec** before writing anything:
```
SOURCE SPEC
Dimensions    : [W × H, layout mode]
Sections      : [ordered list of major regions]
Colors used   : [hex → token name mapping]
Text styles   : [style names in use]
Images/vectors: [node IDs to clone]
Components    : [any instances — record mainComponent.key for reimport]
```

The source spec feeds directly into the execution plan's component map and sections list.

---

## Reading Bound Tokens on Existing Nodes

`get_variable_defs` returns only tokens already bound to a node — not the full available token list. Use it to audit what is and is not connected to the design system before a refactor or migration pass.

```js
// Identify hardcoded fills (no variable binding)
const node = await figma.getNodeByIdAsync(targetNodeId);
if (!node) return;
const boundVars = node.boundVariables ?? {};
const hasColorBinding = 'fills' in boundVars;
// No binding = hardcoded — flag for migration
```

For a full audit across a frame:
```js
const frame = await figma.getNodeByIdAsync(frameId);
const results = [];
frame.findAll(n => 'fills' in n).forEach(n => {
  const bound = n.boundVariables?.fills;
  if (!bound && n.fills?.length) {
    results.push({ id: n.id, name: n.name, fill: n.fills[0] });
  }
});
return JSON.stringify(results);
```

---

## Reading Component Instance Sources

When a node is a component instance, record its `mainComponent.key` — this is the stable library key for reimporting via `importComponentByKeyAsync`.

```js
const node = await figma.getNodeByIdAsync(instanceId);
if (node?.type === 'INSTANCE') {
  const key = node.mainComponent?.key;
  const remote = node.mainComponent?.remote;
  return JSON.stringify({ key, remote });
}
```

Remote keys are stable across files. Use them in the component map rather than searching `search_design_system` again.

---

## Library Drift Detection

To check if an instance is out of sync with its library source:

```js
const instance = await figma.getNodeByIdAsync(instanceNodeId);
if (instance?.type === 'INSTANCE') {
  const main = instance.mainComponent;
  return JSON.stringify({
    remote: main?.remote,
    key: main?.key,
    name: main?.name,
  });
}
```

If drift is confirmed, surface the list of affected instances before proposing any update. Updates to library instances must be accepted through the Figma UI (Assets panel → Libraries → Updates available) — they cannot be triggered programmatically.

---

## Anti-Patterns

- Calling `get_design_context` on a full page node — target specific frames or components only.
- Using `get_variable_defs` to discover what tokens are *available* — it only returns what is already bound. Use the Stage 2 audit script for discovery.
- Reading the source frame and immediately starting to write without building a source spec first.
- Skipping `get_screenshot` before writing — the screenshot is the comparison baseline for post-write validation.
- Using `get_metadata` as a substitute for `get_design_context` — metadata returns structure only, not fill or style data.