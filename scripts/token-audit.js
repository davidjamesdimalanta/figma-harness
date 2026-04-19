/**
 * figma-harness: Token Audit — Hardcoded Fill Finder + Gap Logger
 *
 * Pass a frameId to audit. Returns two lists:
 *   bound:    nodes already connected to variables (good)
 *   hardcoded: nodes with no variable binding (need migration or gap-logging)
 *
 * Paste into use_figma. Replace FRAME_ID with the target node ID.
 */
const FRAME_ID = '0:0'; // replace with actual frame ID

function rgbToHex({ r, g, b }) {
  const toHex = n => Math.round(n * 255).toString(16).padStart(2, '0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
}

const frame = await figma.getNodeByIdAsync(FRAME_ID);
if (!frame) return JSON.stringify({ error: 'Frame not found' });

const bound = [];
const hardcoded = [];

frame.findAll(n => 'fills' in n && n.fills?.length).forEach(n => {
  if (n.boundVariables?.fills) {
    bound.push({ id: n.id, name: n.name });
  } else if (n.fills[0]?.type === 'SOLID') {
    hardcoded.push({
      id: n.id,
      name: n.name,
      hex: rgbToHex(n.fills[0].color),
    });
  }
});

return JSON.stringify({ bound: bound.length, hardcoded }, null, 2);

/**
 * Token gap pattern — use this after attempting binds:
 *
 * const tokenGaps = [];
 * for (const { id, name, hex } of hardcoded) {
 *   const matched = findMatchingVariable(hex); // your lookup
 *   if (matched) {
 *     bindFill(await figma.getNodeByIdAsync(id), matched);
 *   } else {
 *     tokenGaps.push({ nodeId: id, nodeName: name, hardcodedHex: hex });
 *   }
 * }
 * if (tokenGaps.length) return JSON.stringify({ status: 'gaps_found', tokenGaps });
 */