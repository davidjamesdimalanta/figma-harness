# Vector Effects and Exports

Workflow reference for: applying gradients, applying image fills, applying drop shadows or blur effects, and setting up node exports. Parent capability: `figma-vectors.md`.

Read this when a task involves any of the above. For core vector geometry (shape creation, vector paths, vector networks, boolean operations, transforms, strokes), stay in `figma-vectors.md`.

---

## Complex Paints

### Gradient fills

```js
// Linear gradient, left to right
node.fills = [{
  type: 'GRADIENT_LINEAR',
  gradientTransform: [[1, 0, 0], [0, 1, 0]],
  gradientStops: [
    { position: 0, color: { r: 0.1, g: 0.1, b: 0.9, a: 1 } },
    { position: 1, color: { r: 0.9, g: 0.1, b: 0.1, a: 1 } },
  ],
}];
```

Gradient types: `'GRADIENT_LINEAR'`, `'GRADIENT_RADIAL'`, `'GRADIENT_ANGULAR'`, `'GRADIENT_DIAMOND'`.

Bind a gradient stop color to a variable using the same namespace pattern as solid fills; see `figma-tokens.md`.

### Image fills

```js
const image = await figma.createImageAsync('https://example.com/photo.jpg');
node.fills = [{
  type: 'IMAGE',
  imageHash: image.hash,
  scaleMode: 'FILL',   // 'FILL' | 'FIT' | 'CROP' | 'TILE'
}];
```

Always verify `figma.createImageAsync` resolved before assigning `imageHash`; assigning `null` produces a silent no-op.

### Utility: solid paint from CSS string

```js
node.fills = [figma.util.solidPaint('#3B82F6')];
node.fills = [figma.util.solidPaint('#3B82F680')];       // 50% opacity via hex alpha
node.fills = [figma.util.solidPaint('rgba(59,130,246,0.5)')];
```

---

## Effects

```js
// Drop shadow
node.effects = [{
  type: 'DROP_SHADOW',
  color: { r: 0, g: 0, b: 0, a: 0.25 },
  offset: { x: 0, y: 4 },
  radius: 8,
  spread: 0,
  visible: true,
  blendMode: 'NORMAL',
}];

// Inner shadow
node.effects = [{
  type: 'INNER_SHADOW',
  color: { r: 0, g: 0, b: 0, a: 0.15 },
  offset: { x: 0, y: 2 },
  radius: 4,
  spread: 0,
  visible: true,
  blendMode: 'NORMAL',
}];

// Layer blur
node.effects = [{ type: 'LAYER_BLUR', radius: 10, visible: true }];

// Background blur
node.effects = [{ type: 'BACKGROUND_BLUR', radius: 20, visible: true }];

// Multiple effects stack in the array
node.effects = [shadowEffect, blurEffect];
```

Bind a shadow color to a variable:

```js
const effects = [...node.effects];
effects[0] = figma.variables.setBoundVariableForEffect(effects[0], 'color', shadowColorVar);
node.effects = effects;
```

Bind other effect properties the same way: `'radius'`, `'spread'`, and so on. The namespace helper returns a modified effect; reassign the array.

---

## Export Settings

```js
// Make a node exportable (shows in Figma's export panel)
node.exportSettings = [
  { format: 'PNG', constraint: { type: 'SCALE', value: 2 } },
  { format: 'SVG', svgOutlineText: false, svgIdAttribute: true },
  { format: 'PDF' },
];

// Export to bytes in-script
const pngBytes = await node.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: 2 } });
const svgString = await node.exportAsync({ format: 'SVG_STRING' });
const pdfBytes  = await node.exportAsync({ format: 'PDF' });
```

SVG options:

- `svgOutlineText: true` renders text as paths.
- `svgIdAttribute: true` includes layer names as `id` attributes.
- `svgSimplifyStroke: true` approximates strokes with path data.

---

## Anti-patterns

- Hardcoding gradient stop colors when color tokens exist. Bind the stop color the same way fills are bound.
- Assigning `imageHash: null`. Always await `figma.createImageAsync` and check the result before assigning.
- Forgetting to reassign `node.effects` after mutating the array. The Plugin API treats effects arrays as immutable; mutations on a copy are invisible until the array is assigned back.
- Setting `exportSettings` and then not calling `exportAsync` in-script when the task actually wanted bytes. The settings flag makes the node appear in the UI export panel but does not trigger an export.
