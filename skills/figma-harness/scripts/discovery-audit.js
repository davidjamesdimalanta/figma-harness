/**
 * figma-harness: Stage 2 Discovery Audit
 *
 * Paste this entire script into a use_figma call.
 * Returns local variable collections, text/paint/effect styles.
 * Run alongside search_design_system calls (see SKILL.md Stage 2).
 */
const [cols, text, paint, effect] = await Promise.all([
  figma.variables.getLocalVariableCollectionsAsync(),
  figma.getLocalTextStylesAsync(),
  figma.getLocalPaintStylesAsync(),
  figma.getLocalEffectStylesAsync(),
]);

return JSON.stringify({
  variableCollections: cols.map(c => ({
    id: c.id,
    name: c.name,
    modes: c.modes.map(m => m.name),
    variables: c.variableIds.map(id => {
      const v = figma.variables.getVariableById(id);
      return v ? `${v.name} [${v.resolvedType}]` : id;
    }),
  })),
  textStyles: text.map(s => ({
    id: s.id,
    name: s.name,
    fontSize: s.fontSize,
    fontFamily: s.fontName?.family,
  })),
  paintStyles: paint.map(s => ({ id: s.id, name: s.name })),
  effectStyles: effect.map(s => ({ id: s.id, name: s.name })),
}, null, 2);