---
name: figma-documentation
description: "Capability reference for design system documentation, style guide specimens, Code Connect setup, token export, and FigJam diagrams. Use whenever creating a style guide, documenting a component, setting up Code Connect mappings, exporting tokens as CSS variables, or building a FigJam architecture diagram."
metadata:
  mcp-server: figma
---

# Figma Documentation — Style Guides, Code Connect, Token Export, FigJam

Select this capability when: building design system documentation, creating color/typography/spacing specimens, setting up Code Connect mappings, generating token export files, or creating FigJam diagrams.

Always complete Stage 2 parallel discovery in `SKILL.md` before using any tool in this file. Token and style IDs used throughout this capability come from the discovery audit.

---

## Style Guide — Phase Pattern

Build documentation in phases, one `use_figma` call per phase. Call `get_screenshot` on the root doc frame after each phase — the screenshot confirms variable bindings are visible (colored swatches, not gray placeholders) and nothing is clipped. Never build all phases in one call.

### Phase 1 — Root frame and color specimens

```js
// Root frame — clipsContent must be false on all documentation frames
const docFrame = figma.createFrame();
docFrame.name = "Design System / Documentation";
docFrame.resize(canvasWidth, 100);
docFrame.layoutMode = "VERTICAL";
docFrame.primaryAxisSizingMode = "AUTO";
docFrame.counterAxisSizingMode = "FIXED";
docFrame.clipsContent = false;
figma.currentPage.appendChild(docFrame);

// Color swatch — bind to variable, never hardcode hex
const swatch = figma.createFrame();
swatchGrid.appendChild(swatch);
swatch.resize(120, 80);
const fills = [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }];
fills[0] = figma.variables.setBoundVariableForPaint(fills[0], 'color', variable);
swatch.fills = fills;

return JSON.stringify({ docFrameId: docFrame.id });
```

For developer-facing documentation, add a text node below each swatch with the token name and hex value, and annotate the WCAG contrast ratio against white and black:

```js
function contrast(fg, bg) {
  const lum = hex => {
    const rgb = [parseInt(hex.slice(1,3),16)/255, parseInt(hex.slice(3,5),16)/255, parseInt(hex.slice(5,7),16)/255]
      .map(c => c <= 0.03928 ? c/12.92 : Math.pow((c+0.055)/1.055, 2.4));
    return 0.2126*rgb[0] + 0.7152*rgb[1] + 0.0722*rgb[2];
  };
  const L1 = lum(fg), L2 = lum(bg);
  return ((Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05)).toFixed(2);
}
```

### Phase 2 — Typography specimens

One row per text style. Each row shows the style applied to a sample string alongside its metadata.

```js
async function createTypeRow(parent, style, labelStyleId) {
  const row = figma.createFrame();
  row.layoutMode = "HORIZONTAL";
  row.itemSpacing = 24;
  row.counterAxisAlignItems = "CENTER";
  parent.appendChild(row);
  row.layoutSizingHorizontal = "FILL";
  row.primaryAxisSizingMode = "AUTO";
  row.fills = [];

  const specimen = figma.createText();
  row.appendChild(specimen);
  await figma.loadFontAsync(style.fontName);
  specimen.characters = "The quick brown fox";
  specimen.textStyleId = style.id;

  const meta = figma.createText();
  row.appendChild(meta);
  await figma.loadFontAsync({ family: "Inter", style: "Regular" });
  meta.characters = `${style.name} — ${style.fontSize}px / ${style.fontName.family} ${style.fontName.style}`;
  if (labelStyleId) meta.textStyleId = labelStyleId;
}
```

### Phase 3 — Spacing and effect tokens

Visualize spacing variables as labeled bars sized to their resolved value:

```js
const bar = figma.createFrame();
spacingSection.appendChild(bar);
bar.resize(resolvedSpacingValue, 24);
bar.fills = [{ type: "SOLID", color: { r: 0.2, g: 0.5, b: 1 } }];
```

Visualize effect styles as specimen cards with the effect applied:

```js
const surfaceCard = figma.createFrame();
surfaceSection.appendChild(surfaceCard);
surfaceCard.resize(200, 120);
surfaceCard.effectStyleId = effectStyle.id;
```

### Phase 4 — Token reference table

Structured grid — one row per token — with columns appropriate to the audience (designers: name + swatch; developers: name + hex + CSS var syntax).

```js
const table = figma.createFrame();
table.layoutMode = "VERTICAL";
table.itemSpacing = 1;
table.primaryAxisSizingMode = "AUTO";
table.counterAxisSizingMode = "FIXED";
docFrame.appendChild(table);
table.layoutSizingHorizontal = "FILL";
```

Pull token names from the discovery audit — never hardcode them.

### Phase 5 — Component documentation (when requested)

For each named component:
1. Call `get_screenshot` of the component set — use as the anatomy reference.
2. Create a "Use When" text frame: "Use [ComponentName] when [context]. It supports [variant count] states and [size count] sizes."
3. Create a placeholder Do/Don't frame with a green-bordered "Do" box and a red-bordered "Don't" box for the designer to fill.

Section headers use an H2 or H3 text style from the discovery audit.

---

## Code Connect

### Setup workflow

1. Call `get_code_connect_map()` before generating anything. If a mapping exists for the target component, use it to determine the import path and props signature — do not override existing mappings.
2. Call `get_code_connect_suggestions` — Figma may have auto-suggestions from component names.
3. Confirm suggestions with the designer. Verify: is the import path correct? Are prop names correct?
4. Call `send_code_connect_mappings` to confirm accepted suggestions.
5. For manual mappings, use `add_code_connect_map`.

### Generating `.figma.tsx` definitions

For complex components, call `get_context_for_code_connect` to generate the definition:

```tsx
import figma from "@figma/code-connect";
import { Button } from "./Button";

figma.connect(Button, "https://figma.com/file/.../...", {
  props: {
    label: figma.string("Label"),
    disabled: figma.boolean("Disabled"),
    variant: figma.enum("Variant", { primary: "primary", secondary: "secondary" }),
  },
  example: ({ label, disabled, variant }) => (
    <Button variant={variant} disabled={disabled}>{label}</Button>
  ),
});
```

Figma-only state variants (Hover, Active, Focus) must not map to code props. These states are handled by CSS pseudo-classes. Confirm with the designer which variants are design-only before generating mappings.

### Token-to-code mapping reference

| Figma asset | React/Tailwind | CSS Modules |
|---|---|---|
| Variable `spacing/4` (16px) | `p-4` | `padding: var(--spacing-4)` |
| Text style `scale/h2` | `text-3xl font-semibold` | `@apply text-style-h2` |
| Color variable `brand/primary` | `text-brand-primary` | `color: var(--brand-primary)` |
| Component `Button/Default` | `<Button variant="default">` | `<Button variant="default">` |
| Auto-layout horizontal, 8px gap | `flex flex-row gap-2` | `display: flex; gap: 8px` |

---

## Token Export

Generate a CSS custom property file from the variable audit result:

```js
const cssVars = variableCollections.flatMap(col =>
  col.variables.map(v => `  --${v.name.replace(/\//g, "-")}: ${resolveValue(v)};`)
);
return `:root {\n${cssVars.join("\n")}\n}`;
```

Pull variable data from the Stage 2 discovery audit — do not call `get_variable_defs` for discovery (it only returns already-bound tokens, not the full available set).

---

## FigJam Diagrams

Use `generate_diagram` with Mermaid syntax for architecture diagrams, flow charts, and system maps. Call `get_figjam` first if editing an existing FigJam file to understand its current structure.

```
generate_diagram(mermaidSyntax: "graph TD\n  A[User] --> B[Auth]\n  B --> C[Dashboard]")
```

Diagrams are placed on the current FigJam canvas. If working in a design file, switch to a FigJam file first — `generate_diagram` is not available on design file canvases.

---

## Anti-Patterns

- Building all documentation phases in one script — if it fails, nothing is recoverable.
- Setting `clipsContent = true` on specimen or documentation frames — overflow is expected.
- Using `get_variable_defs` to discover tokens for a documentation frame — it returns nothing on new frames. Use the Stage 2 discovery audit instead.
- Hardcoding token names in labels — pull names from the audit result.
- Fixed heights on auto-layout documentation containers — let content drive height with `primaryAxisSizingMode = 'AUTO'`.
- Building component documentation without first calling `get_screenshot` on the component.
- Generating Code Connect without checking `get_code_connect_map` first — risks conflicting with existing mappings.
- Mapping Hover, Active, and Focus variants as Code Connect props — these belong to CSS.
- Hardcoding hex values in color specimens when variable bindings are available.