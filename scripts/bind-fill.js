/**
 * figma-harness: Token Binding Utilities
 *
 * Paste bindFill and bindStroke at the top of any use_figma script
 * that applies color token bindings to nodes.
 *
 * These work on ALL node types: COMPONENT, COMPONENT_SET, FRAME, RECTANGLE, TEXT.
 * The namespace helper returns a modified paint — the array must be reassigned back.
 */

function bindFill(node, variable, idx = 0) {
  if (!variable) return;
  const fills = node.fills.length
    ? [...node.fills]
    : [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }];
  fills[idx] = figma.variables.setBoundVariableForPaint(fills[idx], 'color', variable);
  node.fills = fills;
}

function bindStroke(node, variable, idx = 0) {
  if (!variable) return;
  const strokes = node.strokes.length
    ? [...node.strokes]
    : [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }];
  strokes[idx] = figma.variables.setBoundVariableForPaint(strokes[idx], 'color', variable);
  node.strokes = strokes;
}

// Safe append: appends child to parent then sets sizing
function safeAppend(parent, child, fillH = false, fillV = false) {
  parent.appendChild(child);
  if (fillH) child.layoutSizingHorizontal = 'FILL';
  if (fillV) child.layoutSizingVertical = 'FILL';
  return child;
}
