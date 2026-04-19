---
name: figma-components
description: "Capability reference for component instances, library import, component creation, and component swapping. Use whenever any UI element might exist as a design system component, whenever building new components or variants, or whenever swapping deprecated components."
metadata:
  mcp-server: figma
---

# Figma Components — Instances, Library, Creation, and Swaps

Select this capability when: any UI element in the task could exist as a library component, when building new components or variant sets, or when swapping components during a refactor.

---

## Component Match Map (Mandatory Before Any Build)

Before writing any section code, build a component match map. List every distinct UI element and check whether the design system covers it.

**Source:** Stage 2 discovery results plus targeted follow-up searches. Do not rely on a single broad `search_design_system("")` call — it returns noisy results and misses components whose names don't surface well in a general query. Run multiple short, specific searches for each unresolved element:

```
search_design_system("button")
search_design_system("input")
search_design_system("card")
search_design_system("nav")
search_design_system("chip")
search_design_system("avatar")
```

Deduplicate results by `componentKey`. For elements still unresolved after targeted searches, build as raw frames.

For every element with a match, record its `componentKey`. Elements without a match will be built as raw frames.

```
COMPONENT MAP (include in execution plan)
- Top app bar      → key: abc123  ✓
- Filter chip      → key: def456  ✓
- Notification card → no match   → raw frame
- Primary button   → key: ghi789  ✓
- Bottom nav bar   → key: jkl012  ✓
```

**Building a matched element as a raw frame is a build error.** If `importComponentByKeyAsync` throws, fall back to a raw frame and note the fallback explicitly — do not build from scratch silently.

---

## Importing and Instantiating Library Components

```js
// Single component
const component = await figma.importComponentByKeyAsync(componentKey);
const instance = component.createInstance();
parent.appendChild(instance);
instance.layoutSizingHorizontal = 'FILL';

// Component set (variant group) — uses default variant
const set = await figma.importComponentSetByKeyAsync(setKey);
const instance = set.defaultVariant.createInstance();
parent.appendChild(instance);
```

**Deprecation check before inserting:**
```js
if (component.description?.toLowerCase().includes('deprecated') ||
    component.description?.toLowerCase().includes('use instead')) {
  return `Component "${component.name}" is deprecated. Surface before inserting.`;
}
```

**Import before fetching node references.** Async imports can invalidate existing references. Re-fetch all node references after any import resolves.

---

## Overriding Instance Properties

After instantiating, override only what differs from the default:

```js
// Variant state switch
instance.setProperties({ 'State': 'Active', 'Size': 'MD' });

// Nested text node override
const labelNode = instance.findOne(n => n.type === 'TEXT' && n.name === 'Label');
if (labelNode) {
  await figma.loadFontAsync(labelNode.fontName);
  labelNode.characters = 'Accept';
}
```

Never detach an instance to customize it. Use `setProperties` and nested node overrides — detaching breaks the library link.

---

## Component Hierarchy: Bottom-Up Build Order

When building a component system (multiple related components, not a single isolated one), always build in Atomic Design order: atoms first, then molecules composed from atom instances, then organisms composed from molecules. Never build a molecule before all atoms it depends on exist.

```
Phase 1 — Atoms:    Icon, Label, Badge, Avatar, Divider
Phase 2 — Molecules: Button (Icon + Label), Chip (Icon + Label + Badge), ListItem
Phase 3 — Organisms: NavigationBar (multiple ListItems), Card (Avatar + ListItem)
```

Naming convention:
- Atoms: `Atom/Name` (e.g., `Atom/Icon`, `Atom/Label`)
- Molecules: `Molecule/Name` (e.g., `Molecule/Button`)
- Organisms: `Organism/Name` (e.g., `Organism/NavigationBar`)

Each level gets its own `use_figma` call. Never build atoms and molecules in the same script — atoms must exist on the canvas before molecules import and reference them.

---

## Building New Components

Use `figma.createComponent()`, never `figma.createFrame()`:

```js
const comp = figma.createComponent();
comp.name = "ComponentName/Type=Primary,State=Default,Size=MD";
comp.layoutMode = "HORIZONTAL";
comp.primaryAxisSizingMode = "AUTO";
comp.counterAxisSizingMode = "AUTO";
comp.paddingLeft = comp.paddingRight = 16;
comp.paddingTop = comp.paddingBottom = 10;
comp.itemSpacing = 8;
figma.currentPage.appendChild(comp);
```

### Anatomy Slots

Append before sizing. A slot never controls its own inset padding — that belongs to the containing frame.

```js
const slot = figma.createFrame();
comp.appendChild(slot);
slot.name = "_Slot/Icon";
slot.layoutSizingHorizontal = 'FILL';
slot.primaryAxisSizingMode = 'AUTO';
slot.clipsContent = false;
```

### Component Properties

`addComponentProperty` returns the canonical key Figma assigns — capture it. It is required to wire the property to a child node via `componentPropertyReferences`.

```js
const labelKey = comp.addComponentProperty("Label", "TEXT", "Button");
const showKey  = comp.addComponentProperty("Show Icon", "BOOLEAN", true);
const iconKey  = comp.addComponentProperty("Icon", "INSTANCE_SWAP", defaultIconId);
```

Wire each property to its child node immediately. A property added but not wired appears in the panel but has no effect.

```js
// TEXT → characters on the text node
labelNode.componentPropertyReferences = { characters: labelKey };

// BOOLEAN → visible on the node it shows/hides
iconSlot.componentPropertyReferences = { visible: showKey };

// INSTANCE_SWAP → mainComponent on the nested instance
iconInstance.componentPropertyReferences = { mainComponent: iconKey };
```

Do not assign `componentPropertyReferences` twice on the same node — the second write silently overwrites the first. Combine all keys into one object.

Wire before cloning variants — clones inherit the wiring automatically.

### Variant Siblings and ComponentSet

```js
const hover = comp.clone();
hover.name = "ComponentName/Type=Primary,State=Hover,Size=MD";
// modify only what differs: fills, stroke, opacity

const set = figma.combineAsVariants([comp, hover], figma.currentPage);
set.name = "ComponentName";
```

Name pattern: `ComponentName/Property1=Value,Property2=Value`. Required for Figma to map the variant matrix correctly. Bind tokens after `combineAsVariants`. See `figma-tokens.md`.

---

## Post-Build Validation

After `combineAsVariants` and token binding are complete, run two validation steps before declaring the component done:

**1. Visual screenshot**
```
get_screenshot(nodeId: "<componentSetId>")
```
Check for: collapsed frames, missing slot content, incorrect variant spacing, tokens not applied (gray placeholder instead of color).

**2. WCAG contrast check on actual output**
Run contrast on the built component's actual foreground/background color pairs — not just the planned token values. Token binding can silently fail or apply the wrong variable, so checking the rendered output catches real contrast failures.

```js
// Pull resolved fill colors from the built component
const comp = await figma.getNodeByIdAsync(compId);
const textNodes = comp.findAllWithCriteria({ types: ['TEXT'] });
for (const t of textNodes) {
  const fg = t.fills[0]?.boundVariables ? resolvedColor(t.fills[0]) : rgbToHex(t.fills[0]?.color);
  // compare against nearest background fill ancestor
}
```

Minimum thresholds: text roles 4.5:1 (WCAG AA), UI component boundaries 3:1.

**3. Annotation frame**
Create a lightweight annotation frame to the right of the component set documenting: component name, variant dimensions, token bindings applied, and any token gaps logged during binding.

```js
const annotationFrame = figma.createFrame();
annotationFrame.name = `_annotation/${componentName}`;
annotationFrame.x = componentSet.x + componentSet.width + 80;
annotationFrame.y = componentSet.y;
annotationFrame.layoutMode = 'VERTICAL';
annotationFrame.primaryAxisSizingMode = 'AUTO';
annotationFrame.counterAxisSizingMode = 'AUTO';
annotationFrame.paddingLeft = annotationFrame.paddingRight = 16;
annotationFrame.paddingTop = annotationFrame.paddingBottom = 16;
annotationFrame.itemSpacing = 8;
annotationFrame.clipsContent = false;
figma.currentPage.appendChild(annotationFrame);
```

The annotation frame uses the `_` prefix so it is hidden from publishing. It serves as the handoff artifact — token names, gap list, and contrast results all land here.

---

## Component Swap Protocol

Full workflow: `references/component-swap.md`. Short summary:

- Import the replacement first. Imports can invalidate existing node references.
- Walk every page, find every `INSTANCE` whose `mainComponent` matches the old id, record position, create a replacement, remove the old one.
- Delete the old master after every instance is replaced.
- The bundled script with extra guards is `scripts/component-swap.js`.

Node-type rules (never modify a `COMPONENT` directly; never append `INSTANCE` or `FRAME` to a `COMPONENT_SET`) live in the reference.

---

## Naming Rules

| Pattern | Example |
|---|---|
| `ComponentName/Property=Value` | `Button/Type=Primary,State=Hover` |
| `_Slot/Purpose` | `_Slot/Icon` — hidden from publish |
| `_base-[name]` | `_base-button-shape` — hidden from publish |

---

## Prototype Interactions (Reactions)

Full workflow: `references/component-reactions.md`. Short summary:

- Reactions live on `INSTANCE` and `COMPONENT` nodes, never `COMPONENT_SET`. Writing to the set throws.
- For variable-driven state changes (filter chips, toggle buttons), wrap `SET_VARIABLE` actions in a `CONDITIONAL` block. A bare `SET_VARIABLE` fires every click regardless of state; the conditional prevents no-op re-selection.
- Bind a variable to a variant property with `setProperties({ name: { type: 'VARIABLE_ALIAS', id } })`, not `setBoundVariable('componentProperties', ...)`.
- Bind a variable to layer visibility with `setBoundVariable('visible', variable)` on any node.

Read the reference when wiring any click-to-set-variable prototype interaction.

---

## Anti-Patterns

- Building any matched element from scratch instead of using `importComponentByKeyAsync`.
- Skipping the component match map before building. This is the leading cause of wrong nav items and broken design system links.
- Using `figma.createFrame()` for a component node. Instances will not propagate updates.
- Assigning `componentPropertyReferences` twice on the same node.
- Wiring properties after cloning variants. Wire first on the base component.
- Appending INSTANCE or FRAME nodes to a `COMPONENT_SET`.
- Detaching a library instance to customize it. Use property overrides.
- Importing after fetching node references. Always import first.
- Inserting a deprecated component without surfacing it first.
- Moving an old component off-canvas instead of deleting it after swap. See `references/component-swap.md`.
- Treating prototype reaction patterns as freeform. See `references/component-reactions.md` for the `CONDITIONAL` pattern.