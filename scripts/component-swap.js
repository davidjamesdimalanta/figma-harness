/**
 * figma-harness: Component Swap Protocol
 *
 * Replaces all instances of an old component/set with a new library component.
 * Searches all pages. Preserves x/y position of each replaced instance.
 * Deletes the old master after all instances are replaced.
 *
 * Paste into use_figma. Replace LIBRARY_KEY, OLD_COMPONENT_ID, OLD_SET_ID.
 */
const LIBRARY_KEY     = 'abc123'; // new component key from search_design_system
const OLD_COMPONENT_ID = '0:0';  // old master COMPONENT node ID
const OLD_SET_ID       = '0:0';  // old COMPONENT_SET node ID (use same as above if no set)

// Import replacement first — imports can invalidate existing node references
const replacement = await figma.importComponentByKeyAsync(LIBRARY_KEY);

// Find all instances across all pages
const allInstances = [];
for (const page of figma.root.children) {
  page.findAllWithCriteria({ types: ['INSTANCE'] }).forEach(inst => {
    if (
      inst.mainComponent?.id === OLD_COMPONENT_ID ||
      inst.mainComponent?.parent?.id === OLD_SET_ID
    ) {
      allInstances.push(inst);
    }
  });
}

// Replace each — record position, place new, remove old
for (const old of allInstances) {
  const { parent, x, y } = old;
  const newInst = replacement.createInstance();
  parent.appendChild(newInst);
  newInst.x = x;
  newInst.y = y;
  old.remove();
}

// Delete old master after all instances are replaced
const oldMain = await figma.getNodeByIdAsync(OLD_SET_ID);
if (oldMain) oldMain.remove();

return JSON.stringify({
  replaced: allInstances.length,
  newComponentKey: replacement.key,
});