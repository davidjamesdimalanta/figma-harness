---
name: figma-code
description: "Technical implementation standards and JavaScript patterns for the figma.use_figma tool. Consult when generating or debugging scripts for font loading, async node access, auto-layout constraints, variable binding, and the phase pattern for large builds. This skill is a technical reference — do not modify it for workflow preferences."
metadata:
  mcp-server: figma
---

# Figma Code: Technical Implementation Standards

This skill documents specific platform constraints identified in developer logs. It is a protected technical reference. Do not add workflow preferences here; use `figma-personal-workflow` for those.

**Vector nodes, shape creation, boolean operations, gradients, image fills, effects, and export settings are documented in `figma-vectors.md` and `references/vector-effects-exports.md`. Read those before writing any script that touches VECTOR nodes or creates geometry beyond frames and text.**

---

## Script Atomicity and Error Recovery

`use_figma` scripts are **atomic**. If a script fails at any point, none of its changes are applied; the canvas remains exactly as it was before the call. This is safe, but it means retrying the wrong script will produce the same failure twice.

**On any script error:**

1. STOP. Do not immediately retry.
2. Read the full error message carefully.
3. Call `get_metadata` on the target node if you need to verify the current file state.
4. Fix the specific root cause in the script.
5. Retry once with the corrected script.
6. After the fix succeeds, reflect on what caused the failure and capture it in the right place:
   - **Undocumented Figma API behavior.** A method name, a node-type restriction, or an async semantic that no capability file mentions. Propose a new entry to a capability file (usually this one) via `AskUserQuestion` before writing. Include the exact error text and a minimal reproduction.
   - **File-specific quirk.** The file uses an unusual token name, a non-obvious node location, a custom mode setup. Write an entry under `design-skills/<file-key>/` without asking. Date the observation; record the node id or search query that surfaced it. See `design-skills/README.md`.
   - **Typo or one-off logic error.** The script referenced the wrong variable, assumed a node type, forgot an `await`. Do nothing durable; the fix is in the retry.

Step 6 is what turns a one-time save into a durable widening of the harness. Skip it and the next session rediscovers the same failure.

`console.log()` output is invisible to the agent. All diagnostic output must go through `return`.

---

## Core Constraints

### Asynchronous node resolution

Figma's document sharding requires asynchronous access for reliability.

Always use `await figma.getNodeByIdAsync(id)` instead of the synchronous `figma.getNodeById(id)`. Synchronous access produces null references in complex files.

### Font loading protocol

Setting `node.characters` fails immediately if the required font is not loaded.

```js
// Load before setting characters
await figma.loadFontAsync({ family: "FontName", style: "StyleName" });
node.characters = "text content";
```

Fallback strategy: create the node using Inter (always available), set the text, then apply the `textStyleId`. Figma resolves the visual substitution internally once the style is applied.

**Bulk load all fonts at script start:**
```js
await Promise.all([
  figma.loadFontAsync({ family: "Inter", style: "Regular" }),
  figma.loadFontAsync({ family: "Inter", style: "Medium" }),
  figma.loadFontAsync({ family: "Inter", style: "Bold" }),
]);
```

### Sizing and auto-layout mapping

| Figma UI term | API property | API value |
|---|---|---|
| Hug (horizontal) | `primaryAxisSizingMode` (when layoutMode is HORIZONTAL) | `'AUTO'` |
| Hug (vertical) | `counterAxisSizingMode` (when layoutMode is HORIZONTAL) | `'AUTO'` |
| Fill Container | `layoutSizingHorizontal` / `layoutSizingVertical` | `'FILL'` |
| Fixed | `layoutSizingHorizontal` / `layoutSizingVertical` | `'FIXED'` |

`'HUG'` is not a valid API value — use `'AUTO'` for all hug-equivalent sizing.

### The layout sizing lifecycle (critical)

Cannot set a node's sizing to `'FILL'` before it has been appended to an auto-layout parent.

**Mandatory order:**
1. Create the child node
2. Append the child to the parent: `parent.appendChild(child)`
3. Set sizing: `child.layoutSizingHorizontal = 'FILL'`

### Avoiding the 10px collapse

When a Hug parent (`'AUTO'`) has all Fill children (`'FILL'`), the layout engine has no fixed dimension to calculate from and the frame collapses to 10px.

Fix: at least one child must have a Fixed or Hug size to provide an anchor. For high-level sections, set the parent frame to a fixed width first: `node.resize(1440, node.height)`.

### appendChild() reparenting silently fails

`appendChild()` works correctly when adding a newly created node to a parent. It silently fails — producing orphaned frames — when used to move an already-placed node to a different parent. The node appears to move but becomes detached from the layout tree.

**Never create a frame as a top-level page child and reparent it into a wrapper later.** Build inside the final parent from the moment of creation:

```js
// WRONG — creates at page level, then tries to reparent
const section = figma.createFrame();
figma.currentPage.appendChild(section);
wrapper.appendChild(section); // silently fails — section is now orphaned

// CORRECT — create directly inside the wrapper
const section = figma.createFrame();
wrapper.appendChild(section); // first and only appendChild
section.layoutSizingHorizontal = 'FILL';
```

---

## Variable and Style Binding

### Critical: `setBoundVariableForPaint` is a namespace helper, not a node method

`figma.variables.setBoundVariableForPaint` lives on the `figma.variables` namespace, not on nodes. Calling `node.setBoundVariableForPaint(...)` throws `no such property 'setBoundVariableForPaint' on COMPONENT node` (and fails on other node types too). Always use the namespace form.

**Color fills — works on ALL node types including COMPONENT, ComponentSet, Frame, Text:**
```js
// Correct pattern — namespace helper + immutable array reassignment
function bindFill(node, variable, idx = 0) {
  if (!variable) return;
  const fills = node.fills.length
    ? [...node.fills]
    : [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }];
  fills[idx] = figma.variables.setBoundVariableForPaint(fills[idx], 'color', variable);
  node.fills = fills;
}

// Usage
const v = figma.variables.getVariableById('VariableID:264:7');
bindFill(componentNode, v);
```

`figma.variables.setBoundVariableForPaint(paint, fieldName, variable)` takes a paint object, a field key (`'color'`), and a Variable object (not an ID string). It returns the modified paint — you must reassign the array back to `node.fills`.

**Fallback — construct boundVariables manually (use when variable object is unavailable):**
```js
node.fills = [{
  type: 'SOLID',
  color: { r: 0, g: 0, b: 0 },
  boundVariables: { color: { type: 'VARIABLE_ALIAS', id: variable.id } }
}];
```

**Effects:**
```js
// Bind an effect style by ID
node.effectStyleId = effectStyleId;

// Bind a variable to an effect property (e.g. blur radius, spread)
const effects = [...node.effects];
effects[0] = figma.variables.setBoundVariableForEffect(effects[0], 'radius', variable);
node.effects = effects;
```

**Typography:**
```js
// Apply style after setting text content, not before
node.characters = "label text";
node.textStyleId = styleId;
```

**Spacing variables:**
```js
node.setBoundVariable("paddingLeft", spacingVariable);
node.setBoundVariable("itemSpacing", gapVariable);
```

---

## The Phase Pattern

The `use_figma` tool enforces a 50,000 character limit per execution. For large builds, partition into sequential phases. Never build an entire page or component set in one call.

**Standard documentation phases:**
- Phase 1: Root frame, section headers, color swatches
- Phase 2: Typography specimens
- Phase 3: Spacing scale and effect tokens
- Phase 4: Reference tables

**Standard component phases:**
- Phase 1: Base component, anatomy slots, component properties
- Phase 2: Variant clones for state dimension
- Phase 3: Variant clones for type dimension (if applicable)
- Phase 4: `combineAsVariants`, token binding, description

Always return the IDs of created frames at the end of each phase so the next phase can reference parent nodes:
```js
return JSON.stringify({ rootFrameId: docPage.id, colorSectionId: colorSection.id });
```

### State persistence for long-running workflows

For multi-phase builds where a mid-run failure would otherwise lose all phase IDs, persist state directly on a Figma node using shared plugin data. This survives failed scripts and session interruptions.

```js
// Write state at the end of each phase
figma.root.setSharedPluginData('figma-ball', 'dsb-state', JSON.stringify({
  runId: 'run-2024-abc',
  phase: 2,
  rootFrameId: rootFrame.id,
  colorSectionId: colorSection.id,
}));

// Read state at the start of the next phase
const raw = figma.root.getSharedPluginData('figma-ball', 'dsb-state');
const state = raw ? JSON.parse(raw) : null;
if (!state) return 'No state found — run Phase 1 first';
const rootFrame = await figma.getNodeByIdAsync(state.rootFrameId);
```

Use `setSharedPluginData` / `getSharedPluginData` (not `setPluginData` / `getPluginData` — the shared variants persist across sessions and are readable by other plugins). Reserve this for builds spanning 4+ phases; for shorter builds, returned JSON IDs are sufficient.

---

## Implementation Patterns

### Standardized text helper
```js
async function createStyledText(content, styleId, fallbackFont = { family: "Inter", style: "Regular" }) {
  const text = figma.createText();
  await figma.loadFontAsync(fallbackFont);
  text.fontName = fallbackFont;
  text.characters = content;
  if (styleId) {
    try { text.textStyleId = styleId; }
    catch (e) { console.log("Style application failed, keeping fallback."); }
  }
  return text;
}
```

### Safe append factory
```js
function safeAppend(parent, child, fillH = false, fillV = false) {
  parent.appendChild(child);                             // append first
  if (fillH) child.layoutSizingHorizontal = 'FILL';     // then size
  if (fillV) child.layoutSizingVertical = 'FILL';
  return child;
}
```

### Color swatch grid with wrap
```js
const grid = figma.createFrame();
grid.layoutMode = 'HORIZONTAL';
grid.layoutWrap = 'WRAP';
grid.itemSpacing = 12;
grid.counterAxisSpacing = 16;
grid.primaryAxisSizingMode = 'FIXED';
grid.layoutSizingHorizontal = 'FILL';
```

### Async node lookup with null guard
```js
const node = await figma.getNodeByIdAsync(nodeId);
if (!node) { console.log(`Node ${nodeId} not found`); return; }
```

---

## Compliance Checklist

Before submitting any `use_figma` script, verify:
- [ ] All node lookups use `figma.getNodeByIdAsync`, not `figma.getNodeById`
- [ ] All fonts are loaded via `await figma.loadFontAsync` before any `node.characters` assignment
- [ ] All child nodes are appended to their parent before setting `'FILL'` sizing
- [ ] No node is created at page level and then reparented — build inside the final parent from creation
- [ ] All Hug parents have at least one anchor child with a fixed dimension
- [ ] `primaryAxisSizingMode` and `counterAxisSizingMode` use `'AUTO'` not `'HUG'`
- [ ] Color bindings use `figma.variables.setBoundVariableForPaint(fills[i], 'color', variable)` on the namespace — not `node.setBoundVariableForPaint`
- [ ] All diagnostic output uses `return`, not `console.log` (console output is invisible to the agent)
- [ ] Script returns the IDs of all created frames for validation and phase chaining
- [ ] Script is under 50,000 characters; if not, split into phases
- [ ] Any VECTOR node access wraps `node.vectorPaths` in a try/catch, or uses the clone strategy — see `figma-vectors.md`