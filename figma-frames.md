---
name: figma-frames
description: "Capability reference for frame and layout creation. Use whenever a new frame, screen, section, or layout scaffold is being created. Covers rightEdge placement, root wrapper, section-by-section build, auto-layout rules, and the screenshot gate."
metadata:
  mcp-server: figma
---

# Figma Frames — Frame and Layout Creation

Select this capability when any new frame, screen, section, or layout container is being created.

Always read `figma-code.md` before writing any use_figma script — it contains the API constraints (sizing lifecycle, font loading, async lookup) that apply to every frame operation.

---

## Rule 1: Always Create New — Never Modify Existing

**A destination URL means "place new content here." It never means "empty and repopulate this frame."**

- If the destination URL points to a page: switch to that page, compute rightEdge, place a new frame at rightEdge + 200.
- If the destination URL points to a frame: use the page that frame lives on, place the new frame alongside it at rightEdge + 200.
- Never call `.remove()` on existing nodes.
- Never call `findOne` or `find` to locate an existing frame for the purpose of modifying or repopulating it.

## Rule 2: Build Inside the Final Parent — Never Reparent

**`appendChild()` silently fails when moving an already-placed node to a different parent.** The call appears to succeed, but the node becomes an orphaned frame — detached from the layout tree, invisible in auto-layout calculations, and impossible to recover without deleting it.

Always create sections directly inside their final wrapper:

```js
// WRONG — creates at page level then tries to move it
const section = figma.createFrame();
figma.currentPage.appendChild(section); // placed at page level
wrapper.appendChild(section);           // silently fails — section is now orphaned

// CORRECT — first appendChild goes to the final parent
const section = figma.createFrame();
wrapper.appendChild(section);           // one appendChild, correct parent
section.layoutSizingHorizontal = 'FILL'; // sizing set after append
```

This is especially easy to trigger when building section templates outside a loop and then inserting them. Build the template directly inside the wrapper on each iteration.

```js
await figma.setCurrentPageAsync(destinationPage);
const allFrames = figma.currentPage.children.filter(n => n.type === 'FRAME');
const rightEdge = allFrames.length > 0
  ? Math.max(...allFrames.map(f => f.x + f.width))
  : 0;
const newFrame = figma.createFrame();
newFrame.x = rightEdge + 200;
newFrame.y = 0;
figma.currentPage.appendChild(newFrame);
```

---

## Root Wrapper Frame

Fixed width matching the target device. Height starts small and grows as sections are appended with `AUTO` sizing.

```js
const screen = figma.createFrame();
screen.name = "ScreenName";
screen.layoutMode = "VERTICAL";
screen.primaryAxisSizingMode = "AUTO";
screen.counterAxisSizingMode = "FIXED";
screen.resize(targetWidth, 100);   // height will grow
screen.itemSpacing = 0;
screen.paddingTop = 0;
screen.paddingBottom = 0;
screen.x = rightEdge + 200;
screen.y = 0;
figma.currentPage.appendChild(screen);
return JSON.stringify({ screenId: screen.id });
```

For two-column layouts: set `layoutMode = 'HORIZONTAL'` with two VERTICAL children.
For dashboard grids: set `layoutWrap = 'WRAP'`.

---

## Section-by-Section Build

One use_figma call per major section (header, content block, footer, nav). Never build the full screen in one call. Return the parent frame ID at the end of each call so the next phase can reference it.

```js
// At the start of each subsequent phase — retrieve the parent by ID
const screen = await figma.getNodeByIdAsync(screenId);
if (!screen) return 'screen not found';

const section = figma.createFrame();
screen.appendChild(section);           // append before sizing
section.layoutSizingHorizontal = 'FILL';
section.layoutMode = 'VERTICAL';
section.primaryAxisSizingMode = 'AUTO';
section.paddingLeft = section.paddingRight = 24;
section.paddingTop = section.paddingBottom = 24;
section.itemSpacing = 16;
section.name = 'Section / Name';
section.fills = [];

return JSON.stringify({ screenId: screen.id, sectionId: section.id });
```

---

## Screenshot Gate

After every section is built, call `get_screenshot` on the root frame before starting the next section. This is a required output, not a conditional checkpoint. The screenshot confirms the section rendered correctly and serves as the rollback reference if the next phase fails.

```
get_screenshot(nodeId: "<screenId>")
```

If the screenshot reveals a layout issue (collapsed frame, wrong sizing, missing content), fix it before proceeding to the next section.

---

## Low-Fidelity Placeholders

For wireframes or rough layouts where no design system tokens or components are needed:

```js
const placeholder = figma.createFrame();
section.appendChild(placeholder);
placeholder.layoutSizingHorizontal = 'FILL';
placeholder.resize(placeholder.width, 48);
placeholder.fills = [{ type: 'SOLID', color: { r: 0.9, g: 0.9, b: 0.9 } }];
placeholder.name = '[Placeholder / ButtonRow]';
```

Names use `[Placeholder / Purpose]` format so they are easy to find and replace.

---

## Auto-Layout Rules

Set `layoutMode` before setting sizing modes. The order matters.

```js
frame.layoutMode = 'VERTICAL';                    // set first
frame.primaryAxisSizingMode = 'AUTO';             // then sizing
frame.counterAxisSizingMode = 'FIXED';
frame.resize(targetWidth, 100);                   // resize after sizing modes
```

`'HUG'` is not a valid API value. Use `'AUTO'` for all hug-equivalent sizing.

Cannot set `layoutSizingHorizontal = 'FILL'` before the node is appended to an auto-layout parent:
```js
parent.appendChild(child);                        // append first
child.layoutSizingHorizontal = 'FILL';            // then fill
```

---

## Bottom-Up Sizing: Hug from Child to Parent

When sizing a hierarchy, always work from the innermost child outward to the outermost parent. This gives the layout engine a fixed anchor at each level before the parent tries to calculate its own size.

**Order of operations:**
1. Set all leaf (childmost) nodes to hug both axes: `primaryAxisSizingMode = 'AUTO'`, `counterAxisSizingMode = 'AUTO'`
2. Move up to each intermediate parent and apply the same hug sizing
3. Apply to the outermost parent last: width fill, height hug

The outermost parent uses `layoutSizingHorizontal = 'FILL'` and `primaryAxisSizingMode = 'AUTO'` (height hug). This requires the parent to already be appended to a frame that provides a fill container context — see the lifecycle rule below.

```js
// Step 1: leaf nodes — hug both axes
// (Plugin API — primaryAxisSizingMode / counterAxisSizingMode)
leaf.layoutMode = 'VERTICAL';            // must set layoutMode first
leaf.primaryAxisSizingMode = 'AUTO';     // hug on primary axis
leaf.counterAxisSizingMode = 'AUTO';     // hug on counter axis

// Step 2: intermediate parents — same hug pattern
mid.layoutMode = 'VERTICAL';
mid.primaryAxisSizingMode = 'AUTO';
mid.counterAxisSizingMode = 'AUTO';

// Step 3: outermost parent — fill width, hug height
// Append to its container first, then set FILL
container.appendChild(outermost);
outermost.layoutMode = 'VERTICAL';
outermost.primaryAxisSizingMode = 'AUTO';      // hug height
outermost.layoutSizingHorizontal = 'FILL';     // fill width
```

**API surface note:**
- `primaryAxisSizingMode` and `counterAxisSizingMode` are Plugin API properties on auto-layout frames. The value for hug is `'AUTO'` — never `'HUG'`.
- `layoutSizingHorizontal` and `layoutSizingVertical` are also Plugin API properties. Use `'FILL'` for fill container, `'FIXED'` for fixed. These are only valid after the node is appended to an auto-layout parent.
- The REST API exposes these as `layoutSizing` on the node object but is read-only for layout sizing in most contexts. All sizing mutations go through the Plugin API via `use_figma`.
- The MCP tool (`use_figma`) executes Plugin API code. It does not have a separate sizing API.

---

## Avoiding the 10px Collapse

When a Hug parent (`primaryAxisSizingMode = 'AUTO'`) has all Fill children, the frame collapses to 10px because there is no fixed anchor.

Fix: give at least one child a Fixed dimension, or set the parent to a Fixed width first:
```js
screen.primaryAxisSizingMode = 'FIXED';
screen.resize(targetWidth, screen.height);
```

---

## Documentation and Specimen Frames

Set `clipsContent = false` on any frame used for style guide specimens, token references, or component documentation — content frequently overflows the design-time bounds.

```js
docFrame.clipsContent = false;
```

---

## Anti-Patterns

- Building the entire screen in one use_figma call — always phase by section.
- Placing a new frame at (0, 0) without checking for existing content — always compute rightEdge first.
- Emptying an existing frame and rebuilding inside it — always create a new frame.
- Creating a frame at page level and reparenting it into a wrapper — `appendChild()` silently fails on reparenting; build inside the wrapper from creation.
- Setting `layoutSizingHorizontal = 'FILL'` before appending the node to its parent.
- Using `'HUG'` as a sizing value — use `'AUTO'`.
- Skipping `get_screenshot` after a section — the screenshot gate is mandatory.
- Setting `layoutMode` after `primaryAxisSizingMode` — set `layoutMode` first.
- Using `figma.createRectangle()` for layout containers — use `figma.createFrame()` for anything that will hold children.