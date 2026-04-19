---
name: figma-vectors
description: "Capability reference for vectors, shapes, boolean operations, gradients, image fills, effects, and exports. Use whenever a task involves VECTOR nodes, icon geometry, shape creation beyond frames and text, gradients, drop shadows, blur effects, or node exports."
metadata:
  mcp-server: figma
---

# Figma Vectors — Shapes, Paths, Effects, and Exports

Select this capability when: copying or creating icons, building custom shapes, applying boolean operations, creating gradient or image fills, adding drop shadows or blur effects, exporting nodes, or reading/setting transform and rotation.

Always read `figma-code.md` before writing any use_figma script — it contains the API constraints (sizing lifecycle, font loading, async lookup) that apply to every script.

---

## Vector Nodes — Critical Rules

### The `vectorPaths` getter can throw

`node.vectorPaths` serializes the internal vector network into SVG path strings. This fails when the network has degenerate geometry or was produced by complex boolean operations:

```
Error: in get_vectorPaths: Failed to retrieve vector network, network data is invalid
```

Never call `vectorPaths` as the first read attempt on an unknown vector node. Always wrap it or use the clone strategy.

### Clone strategy — correct pattern for copying vectors (icons)

When duplicating a vector (e.g. copying icons into components), do not read the path data. Clone directly:

```js
const source = await figma.getNodeByIdAsync(vectorId);
if (!source) { console.log('node not found'); return; }
const cloned = source.clone();
parent.appendChild(cloned);
cloned.resize(targetWidth, targetHeight);
```

This avoids network serialization entirely and is the correct approach for icon work.

### Safe read pattern for when path data is needed

```js
async function readVectorData(nodeId) {
  const node = await figma.getNodeByIdAsync(nodeId);
  if (!node || node.type !== 'VECTOR') return null;
  try {
    const paths = node.vectorPaths;
    return { strategy: 'paths', paths };
  } catch (e) {
    console.log(`vectorPaths failed (${e.message}), falling back to vectorNetwork`);
    try {
      const network = node.vectorNetwork;
      return { strategy: 'network', network };
    } catch (e2) {
      console.log(`vectorNetwork also failed: ${e2.message}`);
      return null;
    }
  }
}
```

---

## VectorPath API — Simple Geometry

`VectorPath` is the recommended way to set geometry when the shape can be described as SVG path commands.

```typescript
interface VectorPath {
  windingRule: 'EVENODD' | 'NONZERO' | 'NONE';
  data: string;  // SVG path command string
}
```

### Create a vector from SVG path data

```js
const v = figma.createVector();
figma.currentPage.appendChild(v);
v.vectorPaths = [{
  windingRule: 'EVENODD',
  data: 'M 0 100 L 100 100 L 50 0 Z',
}];
v.resize(24, 24);
```

### Multiple paths (compound shapes)

```js
v.vectorPaths = [
  { windingRule: 'EVENODD', data: 'M 0 0 L 10 0 L 10 10 L 0 10 Z' },  // outer rect
  { windingRule: 'EVENODD', data: 'M 2 2 L 8 2 L 8 8 L 2 8 Z' },       // inner cutout
];
```

| Winding rule | Effect |
|---|---|
| `'EVENODD'` | Alternating fill/no-fill based on crossing count. Correct for most icon cutouts. |
| `'NONZERO'` | Fill determined by winding direction. Default for solid shapes. |
| `'NONE'` | Stroke path only, no fill. |

---

## VectorNetwork API — Full Control

Use when constructing geometry programmatically with precise control over vertices and curves, or when `vectorPaths` fails and you need to inspect the underlying structure.

### Triangle example (straight edges)

```js
const v = figma.createVector();
figma.currentPage.appendChild(v);
v.vectorNetwork = {
  vertices: [
    { x: 50, y: 0 },    // apex — vertex 0
    { x: 100, y: 100 }, // bottom-right — vertex 1
    { x: 0, y: 100 },   // bottom-left — vertex 2
  ],
  segments: [
    { start: 0, end: 1 },
    { start: 1, end: 2 },
    { start: 2, end: 0 },
  ],
  regions: [
    { windingRule: 'EVENODD', loops: [[0, 1, 2]] },
  ],
};
```

### Curved segment (Bézier)

Supply non-zero tangents to make a cubic Bézier. Tangents are relative to the vertex position:

```js
segments: [
  {
    start: 0, end: 1,
    tangentStart: { x: 30, y: 0 },
    tangentEnd:   { x: -30, y: 0 },
  }
]
```

A region's loop must form a closed chain — each segment must share endpoint vertices with adjacent segments. An unclosed loop causes the region fill to be ignored.

---

## Shape Creation Reference

All shape creators return a node that must be appended before sizing.

```js
// Rectangle — use createFrame for layout containers; createRectangle for visual shapes only
const rect = figma.createRectangle();
figma.currentPage.appendChild(rect);
rect.resize(80, 80);
rect.cornerRadius = 8;

// Ellipse / circle
const ellipse = figma.createEllipse();
figma.currentPage.appendChild(ellipse);
ellipse.resize(48, 48);
// Partial arcs (pie slices, progress rings)
ellipse.arcData = { startingAngle: 0, endingAngle: Math.PI, innerRadius: 0.5 };

// Line
const line = figma.createLine();
figma.currentPage.appendChild(line);
line.resize(100, 0);  // width = length, height always 0
line.strokeWeight = 2;
line.strokes = [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }];

// Star
const star = figma.createStar();
figma.currentPage.appendChild(star);
star.resize(48, 48);
star.pointCount = 5;
star.innerRadius = 0.4;  // 0–1, ratio of inner to outer radius

// Polygon
const poly = figma.createPolygon();
figma.currentPage.appendChild(poly);
poly.resize(48, 48);
poly.pointCount = 6;  // hexagon

// Vector (blank — populate with vectorPaths or vectorNetwork)
const vec = figma.createVector();
figma.currentPage.appendChild(vec);
```

---

## Strokes

```js
node.strokes = [{ type: 'SOLID', color: { r: 0.2, g: 0.2, b: 0.2 } }];
node.strokeWeight = 1.5;
node.strokeAlign = 'INSIDE';   // 'INSIDE' | 'OUTSIDE' | 'CENTER'
node.strokeCap = 'ROUND';      // 'NONE' | 'ROUND' | 'SQUARE' | 'ARROW_LINES' | 'ARROW_EQUILATERAL'
node.strokeJoin = 'ROUND';     // 'MITER' | 'BEVEL' | 'ROUND'
node.dashPattern = [4, 2];     // dashed: [dash length, gap length]
```

Bind a stroke color to a variable (same pattern as fills — see `figma-tokens.md`):

```js
const strokes = node.strokes.length
  ? [...node.strokes]
  : [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }];
strokes[0] = figma.variables.setBoundVariableForPaint(strokes[0], 'color', variable);
node.strokes = strokes;
```

---

## Complex Paints and Effects

Full workflow: `references/vector-effects-exports.md`. Read that file when a task requires gradients, image fills, drop shadows, inner shadows, layer blur, background blur, or binding effect colors to variables.

Short summary:

- Gradient types: `'GRADIENT_LINEAR'`, `'GRADIENT_RADIAL'`, `'GRADIENT_ANGULAR'`, `'GRADIENT_DIAMOND'`. Bind stop colors with the same namespace helper used for solid fills.
- Image fills: `await figma.createImageAsync(url)`, then assign `{ type: 'IMAGE', imageHash, scaleMode }`.
- CSS-string shortcut for solids: `figma.util.solidPaint('#3B82F6')`.
- Effects are immutable arrays; mutate a copy and reassign to `node.effects`. Bind effect properties with `figma.variables.setBoundVariableForEffect`.

---

## Boolean Operations

Boolean operations consume source nodes and return a new node. Source nodes are removed from the canvas after the operation.

```js
const result = figma.union([nodeA, nodeB], figma.currentPage);      // combine
const result = figma.subtract([nodeA, nodeB], figma.currentPage);   // remove B from A
const result = figma.intersect([nodeA, nodeB], figma.currentPage);  // keep overlap only
const result = figma.exclude([nodeA, nodeB], figma.currentPage);    // XOR — non-overlapping only
```

All source nodes must share the same parent before calling the operation. The returned node is a `BooleanOperationNode` — it has `fills`, `strokes`, and `effects`. Clone sources first if you need to keep the originals:

```js
const cloneA = nodeA.clone();
const cloneB = nodeB.clone();
parent.appendChild(cloneA);
parent.appendChild(cloneB);
const result = figma.union([cloneA, cloneB], parent);
```

---

## Transform, Rotation, and Opacity

```js
node.rotation = 45;          // degrees, clockwise
node.opacity = 0.5;          // 0–1
node.cornerRadius = 12;      // uniform corner radius

// Per-corner
node.topLeftRadius = 8;
node.topRightRadius = 8;
node.bottomRightRadius = 0;
node.bottomLeftRadius = 0;

// Full 2D affine matrix — precise rotation + translation
node.relativeTransform = [[1, 0, 100], [0, 1, 200]];

// Flip horizontal
node.relativeTransform = [[-1, 0, node.width], [0, 1, 0]];
```

---

## Export Settings

Full workflow: `references/vector-effects-exports.md`. Short summary:

- `node.exportSettings = [...]` makes a node appear in Figma's export panel but does not trigger anything.
- `await node.exportAsync({ format })` returns bytes (`'PNG'`, `'PDF'`) or a string (`'SVG_STRING'`). Use this when the script needs the output in hand.
- SVG options include `svgOutlineText`, `svgIdAttribute`, and `svgSimplifyStroke`.

---

## Anti-Patterns

- Calling `node.vectorPaths` without a try/catch on a VECTOR node from an unknown source — it throws on complex network data. Use the clone strategy if you only need a copy.
- Using `node.vectorNetwork` to clone icons — read it only when you need to inspect or modify geometry.
- Setting `node.vectorPaths` or `node.vectorNetwork` before appending to a parent.
- Performing a boolean operation on nodes that do not share the same parent.
- Forgetting that boolean operations consume source nodes — clone if you need the originals.
- Using `figma.createRectangle()` for layout containers — use `figma.createFrame()` for anything that will hold children.
- Hardcoding gradient stop colors when color tokens exist.
- Assigning `imageHash: null` — always verify `figma.createImageAsync` resolved before assigning the hash.