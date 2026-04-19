---
name: figma-tokens
description: "Capability reference for variable and style binding, token architecture, WCAG contrast, and token migration. Use whenever design system colors, spacing, or typography need to be applied, created, or migrated."
metadata:
  mcp-server: figma
---

# Figma Tokens — Variable and Style Binding

Select this capability when: applying design system tokens to nodes, creating new token structures, migrating hardcoded values to variables, or binding text/paint styles.

Always use `figma-code.md` binding patterns. The critical rule: `setBoundVariableForPaint` lives on the `figma.variables` namespace, not on nodes.

---

## Token Discovery

Use the Stage 2 audit script to discover all local collections and styles. Do not use `get_variable_defs` for discovery — it only returns tokens already bound to a specific node.

**Local variables only — `getLocalVariableCollectionsAsync()` is not enough on its own.** Files using a shared or published library store their tokens remotely. Stage 2 Call 3 (`search_design_system("", { includeVariables: true })`) surfaces those. Always cross-reference both before declaring a token missing.

```js
// Traverse all local collections to find a variable by name
const getVar = async (name) => {
  const cols = await figma.variables.getLocalVariableCollectionsAsync();
  for (const col of cols) {
    for (const id of col.variableIds) {
      const v = figma.variables.getVariableById(id);
      if (v && v.name === name) return v;
    }
  }
  return null;
};
```

For remote (library) variables — import by key once found via `search_design_system`:
```js
const remoteVar = await figma.variables.importVariableByKeyAsync(remoteVariableKey);
```

---

## Binding Color Tokens

The namespace helper returns a modified paint — reassign the array back to `node.fills`.

```js
function bindFill(node, variable, idx = 0) {
  if (!variable) return;
  const fills = node.fills.length
    ? [...node.fills]
    : [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }];
  fills[idx] = figma.variables.setBoundVariableForPaint(fills[idx], 'color', variable);
  node.fills = fills;
}
```

Same pattern for strokes:
```js
const strokes = node.strokes.length
  ? [...node.strokes]
  : [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }];
strokes[0] = figma.variables.setBoundVariableForPaint(strokes[0], 'color', variable);
node.strokes = strokes;
```

---

## Binding Typography

Apply text style after setting content, not before:
```js
node.characters = "label text";
node.textStyleId = styleId;
```

Apply paint style (fill style):
```js
node.fillStyleId = paintStyleId;
```

---

## Binding Spacing Tokens

```js
node.setBoundVariable("paddingLeft", spacingVar);
node.setBoundVariable("paddingRight", spacingVar);
node.setBoundVariable("paddingTop", spacingVar);
node.setBoundVariable("paddingBottom", spacingVar);
node.setBoundVariable("itemSpacing", gapVar);
```

---

## Token Migration (Hardcoded → Variable)

Run as a separate audit + bind phase. Identify hardcoded nodes, present the changeset, then execute.

```js
// Audit: find nodes with hardcoded fills (no variable binding)
const frame = await figma.getNodeByIdAsync(frameId);
const hardcoded = [];
frame.findAll(n => 'fills' in n && n.fills?.length).forEach(n => {
  if (!n.boundVariables?.fills) {
    hardcoded.push({ id: n.id, name: n.name, fill: n.fills[0] });
  }
});
return JSON.stringify(hardcoded);
```

```js
// Bind: color migration pass (one use_figma call for color category only)
for (const nodeId of targetIds) {
  const node = await figma.getNodeByIdAsync(nodeId);
  if (!node || !('fills' in node)) continue;
  bindFill(node, colorVar);
}
```

```js
// Style to variable migration
const nodes = figma.currentPage.findAllWithCriteria({ types: ['FRAME','RECTANGLE','TEXT'] });
for (const node of nodes) {
  if ('fillStyleId' in node && node.fillStyleId === oldStyleId) {
    node.fillStyleId = '';
    bindFill(node, newVar);
  }
}
```

Run one category per use_figma call: color, then typography, then spacing. Never mix categories in one script. After each category, take a screenshot before proceeding.

### Token gap logging

When the audit finds a hardcoded value and no variable can be matched to it, do not silently hardcode it in the output. Log it as a **token gap** and surface the list to the designer before executing any binds.

```js
const tokenGaps = [];
for (const { id, name, fill } of hardcoded) {
  const matched = findMatchingVariable(fill); // your lookup logic
  if (matched) {
    bindFill(await figma.getNodeByIdAsync(id), matched);
  } else {
    tokenGaps.push({ nodeId: id, nodeName: name, hardcodedHex: rgbToHex(fill.color) });
  }
}
if (tokenGaps.length) {
  return JSON.stringify({ status: 'gaps_found', tokenGaps });
}
```

Present the gap list: "X nodes could not be bound — no matching token for these values: [list]. Would you like to create new tokens for these, keep them hardcoded, or skip them?"

---

## WCAG Contrast Check

Run before any color token creation or migration. Each semantic color role must pass contrast in both Light and Dark modes.

```js
function getLuminance(hex) {
  const rgb = [
    parseInt(hex.slice(1,3), 16) / 255,
    parseInt(hex.slice(3,5), 16) / 255,
    parseInt(hex.slice(5,7), 16) / 255,
  ].map(c => c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
}
function contrastRatio(fg, bg) {
  const L1 = getLuminance(fg), L2 = getLuminance(bg);
  return ((Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05)).toFixed(2);
}
// Minimum: text roles 4.5:1 (WCAG AA), UI components 3:1
```

If a role fails, adjust the primitive assignment before creating the token.

---

## Variable Scopes and Code Syntax

Set scopes on every variable when creating it. Never use `ALL_SCOPES` — it makes the variable appear in every property dropdown (fills, strokes, spacing, corner radius, opacity) regardless of its type, polluting the picker.

```js
// Color variable — scope to fills and strokes only
colorVar.scopes = ['FILL_COLOR', 'STROKE_COLOR', 'EFFECT_COLOR'];

// Spacing variable — scope to gap and padding only
spacingVar.scopes = ['GAP', 'WIDTH_HEIGHT'];

// Corner radius variable
radiusVar.scopes = ['CORNER_RADIUS'];

// Opacity variable
opacityVar.scopes = ['OPACITY'];
```

Add code syntax to every variable so Dev Mode shows the correct CSS/token reference:

```js
// WEB — always wrap in var()
colorVar.setVariableCodeSyntax('WEB', `var(--${tokenName})`);
spacingVar.setVariableCodeSyntax('WEB', `var(--spacing-${scale})`);

// iOS / Android (optional — add when platform is in scope)
colorVar.setVariableCodeSyntax('iOS', `Color.${swiftName}`);
colorVar.setVariableCodeSyntax('ANDROID', `R.color.${androidName}`);
```

---

## Token Architecture Reference

The standard three-tier structure. All design system decisions follow this model unless the designer's preferences specify otherwise.

**Primitive tokens** — raw values, the source of truth. Hidden from publishing.
```
blue-400 = #60A5FA
spacing-4 = 16px
```

**Semantic tokens** — contextual roles pointing to primitives. Themes and modes operate here.
```
color-interactive-primary → blue-400
space-component-gap → spacing-4
```

**Component tokens** (optional, for large systems) — scoped to one component.
```
button-primary-bg → color-interactive-primary
```

Semantic tokens must reference primitives, not hardcoded values. Components consume semantic tokens, not primitives. Changing a theme means only changing semantic-to-primitive mappings.

---

## Color System Principles

Three categories: **Neutrals** (text, backgrounds, borders), **Primary** (brand identity, 5–10 shades), **Accent** (semantic states: danger, warning, success).

Building a shade scale:
1. Pick the base shade — must work as a button background
2. Pick the darkest shade — darkest text using this color
3. Pick the lightest shade — lightest tinted background
4. Fill gaps; no two adjacent shades closer than ~25% apart perceptually

Structural roles: one dominant tone (used most widely), one or more subordinate tones, one accent (used sparingly). Trust the eye over the math.

---

## Spacing and Type Scale Reference

Practical spacing scale (non-linear, adjacent values differ by ~25%):
```
2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128
```

Practical type scale:
```
12, 14, 16, 18, 20, 24, 30, 36, 48, 60, 72
```

Use `px` or `rem`, never `em`. Em units are relative to the current element's font size and produce computed values that fall outside the scale.

---

## Enterprise Aliasing (Two-Tier Token Systems)

When a team uses a global library aliased to a brand collection, create an alias variable — do not copy the primitive value. Copying breaks the library connection.

```js
const globalVar = await figma.variables.importVariableByKeyAsync(globalKey);
const localCollection = (await figma.variables.getLocalVariableCollectionsAsync())
  .find(c => c.name === 'Brand');
const alias = figma.variables.createVariable('brand/primary', localCollection.id, 'COLOR');
alias.setValueForMode(localCollection.defaultModeId, {
  type: 'VARIABLE_ALIAS',
  id: globalVar.id,
});
```

---

## Anti-Patterns

- Calling `node.setBoundVariableForPaint(...)` as a node method — use `figma.variables.setBoundVariableForPaint` on the namespace.
- Hardcoding hex values when a token exists for the same semantic role.
- Running color, typography, and spacing migration in one script — execute by category.
- Deleting styles before migrating all references — create the variable, bind all nodes, then remove the style.
- Creating local copies of remote variables instead of binding to the imported reference.
- Using `get_variable_defs` to discover available tokens — use the Stage 2 audit script.
- Skipping the WCAG check when creating semantic color roles.
- Using `em` units for type scale values.
- Presenting a changeset and immediately executing — wait for confirmation before any write.