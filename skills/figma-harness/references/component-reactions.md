# Component Reactions

Workflow reference for wiring prototype reactions to boolean variables. Read this when the task is: making filter chips mutually exclusive, toggling a selected state on tap, driving variant properties from variables, or any click-to-set-variable interaction. Parent capability: `figma-components.md`.

---

## Where reactions can be set

Reactions live on `INSTANCE` and `COMPONENT` nodes. `COMPONENT_SET` nodes do **not** have a `reactions` property. Reading or writing it throws `no such property 'reactions' on COMPONENT_SET node`. Always target the component or instance children, never the set wrapper.

```js
// WRONG — throws on COMPONENT_SET
const set = await figma.getNodeByIdAsync(componentSetId);
set.reactions = [...]; // Error

// CORRECT — target the instance directly
const inst = await figma.getNodeByIdAsync(instanceId);
inst.reactions = [...];
```

---

## The CONDITIONAL reaction pattern

Figma's prototype reaction actions support a `CONDITIONAL` type that wraps `SET_VARIABLE` actions in an if/else block. This is the required pattern for variable-driven interactions. A bare `SET_VARIABLE` at the top level works syntactically but always fires, even when the element is already in its target state.

The condition uses an `EXPRESSION` to check whether the element's own variable is currently `false` (not already active). If true, run the if-block actions. If false (already active), the empty else block means nothing happens.

```js
// Helper: build a single SET_VARIABLE action
const setVar = (variableId, value) => ({
  type: 'SET_VARIABLE',
  variableId,
  variableValue: { value, type: 'BOOLEAN', resolvedType: 'BOOLEAN' },
});

// Helper: build a CONDITIONAL reaction for a toggle chip or button in a mutually-exclusive group.
// myVarId      — variable ID for THIS element
// allVarMap    — { label: variableId } for every element in the group
// clickedLabel — the label of THIS element
const buildToggleReaction = (myVarId, allVarMap, clickedLabel) => {
  const ifActions = Object.entries(allVarMap).map(([label, id]) =>
    setVar(id, label === clickedLabel)
  );

  return {
    trigger: { type: 'ON_CLICK' },
    actions: [
      {
        type: 'CONDITIONAL',
        conditionalBlocks: [
          {
            // Condition: myVariable == false (only fire if not already selected)
            condition: {
              type: 'EXPRESSION',
              resolvedType: 'BOOLEAN',
              value: {
                expressionFunction: 'EQUALS',
                expressionArguments: [
                  {
                    type: 'VARIABLE_ALIAS',
                    resolvedType: 'BOOLEAN',
                    value: { type: 'VARIABLE_ALIAS', id: myVarId },
                  },
                  { type: 'BOOLEAN', resolvedType: 'BOOLEAN', value: false },
                ],
              },
            },
            actions: ifActions, // set self=true, all others=false
          },
          { actions: [] }, // else: do nothing (already selected)
        ],
      },
    ],
  };
};
```

Usage example, applying to a row of filter chips:

```js
const varIds = {
  All:      'VariableID:xxx:1',
  Tools:    'VariableID:xxx:2',
  Kitchen:  'VariableID:xxx:3',
};
const chipInstanceIds = {
  '1443:10596': 'All',
  '1443:10597': 'Tools',
  '1443:10598': 'Kitchen',
};

for (const [instanceId, label] of Object.entries(chipInstanceIds)) {
  const inst = await figma.getNodeByIdAsync(instanceId);
  inst.reactions = [buildToggleReaction(varIds[label], varIds, label)];
}
```

---

## Binding a variable to a component variant property

To drive a component's variant state from a boolean variable, use `setProperties` with a `VARIABLE_ALIAS` object. The `setBoundVariable` method does not work for component variant properties:

```js
// WRONG — throws: "componentProperties variable bindings must be set on componentProperties directly"
inst.setBoundVariable('componentProperties', { propertyName: 'state', variable });

// CORRECT — pass a VARIABLE_ALIAS object as the property value
inst.setProperties({
  state: { type: 'VARIABLE_ALIAS', id: variable.id }
});
```

This binds the `state` variant property so when the variable is `true` the component resolves to its `selected` variant and when `false` it resolves to `default`. Figma maps booleans to variant options in declaration order, so verify the ordering on the component set matches the intended true/false mapping.

---

## Binding a variable to layer visibility

To show or hide any layer based on a boolean variable, use `setBoundVariable` on the `visible` property directly:

```js
const variable = figma.variables.getVariableById(varId);
node.setBoundVariable('visible', variable);
// true = visible, false = hidden
```

This works on any node type (INSTANCE, FRAME, GROUP, etc.) and is separate from component variant property binding.

---

## Reading reactions back for verification

After writing reactions, read one representative instance back to confirm the structure is correct before continuing:

```js
const inst = await figma.getNodeByIdAsync(instanceId);
const r = inst.reactions?.[0];
return JSON.stringify({
  triggerType: r?.trigger?.type,                        // 'ON_CLICK'
  actionType: r?.actions?.[0]?.type,                    // 'CONDITIONAL'
  conditionFn: r?.actions?.[0]?.conditionalBlocks?.[0]?.condition?.value?.expressionFunction, // 'EQUALS'
  conditionVarId: r?.actions?.[0]?.conditionalBlocks?.[0]?.condition?.value?.expressionArguments?.[0]?.value?.id,
  ifActionCount: r?.actions?.[0]?.conditionalBlocks?.[0]?.actions?.length,
  elseActionCount: r?.actions?.[0]?.conditionalBlocks?.[1]?.actions?.length, // should be 0
}, null, 2);
```

---

## Anti-patterns

- Reading or writing `reactions` on a `COMPONENT_SET` node. It doesn't exist there; target instance or component children.
- Using a bare `SET_VARIABLE` as the top-level reaction action. Always wrap in `CONDITIONAL`, even when the else block is empty. A bare `SET_VARIABLE` always fires regardless of current state.
- Using `setBoundVariable('componentProperties', ...)` to bind a variable to a variant property. Use `setProperties({ propName: { type: 'VARIABLE_ALIAS', id: varId } })` instead.
- Forgetting the empty else block `{ actions: [] }`. `conditionalBlocks` must always have at least two entries, if and else.
