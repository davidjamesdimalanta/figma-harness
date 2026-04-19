# Component Swap Protocol

Workflow reference for replacing every instance of a deprecated component with a new one. Read this when the task is a component swap or a design-system migration that retires old components. Parent capability: `figma-components.md`.

---

## Node-type rules

| Node type | What it is | What you do |
|---|---|---|
| `COMPONENT` | Master definition | Never modify directly. Delete after all instances are replaced. |
| `COMPONENT_SET` | Variant container | COMPONENT children only. Never append INSTANCE or FRAME. |
| `INSTANCE` | Live usage | Find, replace, remove old one. |

---

## The swap script

```js
// Import replacement first — imports can invalidate existing node references
const replacement = await figma.importComponentByKeyAsync(libraryKey);

// Find all instances across all pages
const allInstances = [];
for (const page of figma.root.children) {
  page.findAllWithCriteria({ types: ['INSTANCE'] }).forEach(inst => {
    if (inst.mainComponent?.id === oldId ||
        inst.mainComponent?.parent?.id === oldSetId) {
      allInstances.push(inst);
    }
  });
}

// Replace each: record position, place new, remove old
for (const old of allInstances) {
  const { parent, x, y } = old;
  const newInst = replacement.createInstance();
  parent.appendChild(newInst);
  newInst.x = x;
  newInst.y = y;
  old.remove();
}

// Delete the old main component after every instance is replaced
const oldMain = await figma.getNodeByIdAsync(oldSetId);
if (oldMain) oldMain.remove();
```

The bundled version of this script with extra guards lives at `scripts/component-swap.js`.

---

## Checklist before running a swap

1. Confirm the replacement component is published and importable. Run `importComponentByKeyAsync` on its key once, in a discovery call, before the swap script runs.
2. Confirm the old component key. `COMPONENT_SET` children share a parent key; swapping the set replaces every variant in one pass.
3. Confirm property shape matches. If the replacement has different property names or variant keys, `setProperties` calls will silently fail on the new instances. Plan overrides in advance.
4. Take a screenshot of representative pages before the swap. Screenshot again after. Visual diff is the only way to catch sizing regressions.
5. If instances are nested inside other instances, the nested swap fails; top-level containers must be swapped first.

---

## Anti-patterns

- Modifying the old master component in place instead of deleting it after the swap.
- Skipping the import step at the top and letting `createInstance` run on a stale reference.
- Moving the old component off-canvas instead of deleting it. Orphan masters leak into library publishes.
- Running the swap script in a file where library permissions are missing. `importComponentByKeyAsync` fails silently in some cases and the script iterates over nothing. Log the length of `allInstances` and bail if zero when you expected matches.
