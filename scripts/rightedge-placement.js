/**
 * figma-harness: rightEdge Frame Placement
 *
 * Computes the rightEdge of existing top-level frames on the current page
 * and places a new wrapper frame 200px to the right.
 *
 * Paste into use_figma. Replace TARGET_WIDTH with the device width (e.g. 390, 1440).
 * Returns { screenId } for use in subsequent phase calls.
 */
const TARGET_WIDTH = 390; // replace with actual device width
const SCREEN_NAME  = 'ScreenName'; // replace with actual name

await figma.setCurrentPageAsync(figma.currentPage);

const allFrames = figma.currentPage.children.filter(n => n.type === 'FRAME');
const rightEdge = allFrames.length > 0
  ? Math.max(...allFrames.map(f => f.x + f.width))
  : 0;

const screen = figma.createFrame();
screen.name = SCREEN_NAME;
screen.layoutMode = 'VERTICAL';
screen.primaryAxisSizingMode = 'AUTO';
screen.counterAxisSizingMode = 'FIXED';
screen.resize(TARGET_WIDTH, 100); // height grows with content
screen.itemSpacing = 0;
screen.paddingTop = 0;
screen.paddingBottom = 0;
screen.x = rightEdge + 200;
screen.y = 0;
figma.currentPage.appendChild(screen);

return JSON.stringify({ screenId: screen.id, rightEdge });