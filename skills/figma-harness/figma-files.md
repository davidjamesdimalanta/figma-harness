---
name: figma-files
description: "Capability reference for file and page creation, page switching, and page targeting by ID. Use whenever a task requires creating a new Figma file, adding a new page, or switching the current page before placing content."
metadata:
  mcp-server: figma
---

# Figma Files — File and Page Management

Select this capability when: creating a new Figma file, adding a new page to an existing file, or switching to a specific page before placing frames.

---

## Creating a New File

Use `create_new_file` when the task explicitly requires a new Figma file. This tool returns a new file URL — hold it for subsequent tool calls targeting that file.

```
create_new_file(name: "Design System v2")
```

After creation, all subsequent `use_figma` calls targeting this file must reference its returned file ID. The new file starts with one empty page named "Page 1".

---

## Adding a New Page

```js
const page = figma.createPage();
page.name = "Notifications";
figma.root.appendChild(page);
await figma.setCurrentPageAsync(page);
return JSON.stringify({ pageId: page.id });
```

Return the new page ID at the end of the call. All subsequent calls that place content on this page must call `figma.setCurrentPageAsync(page)` first using the returned ID.

---

## Switching Pages

Always switch to the target page at the start of any use_figma script that places or modifies content.

```js
// Switch by page object (within the same script)
await figma.setCurrentPageAsync(targetPage);

// Switch by ID (across separate use_figma calls)
const pages = figma.root.children;
const target = pages.find(p => p.id === targetPageId);
if (!target) return 'page not found';
await figma.setCurrentPageAsync(target);
```

Resolve page targets by ID — never by name. Page names are not unique and can be renamed. The node-id from a Figma URL is the authoritative target reference (see Stage 3 in `SKILL.md` for URL resolution).

---

## Page Targeting from a URL

When a Figma URL contains a `node-id` parameter, the node lives on a specific page. Confirm the page before switching:

```js
const node = await figma.getNodeByIdAsync(targetNodeId);
if (!node) return 'node not found';
const page = node.parent?.type === 'PAGE' ? node.parent : figma.currentPage;
await figma.setCurrentPageAsync(page);
```

After switching, compute rightEdge for new frame placement (see `figma-frames.md`).

---

## Anti-Patterns

- Assuming the current page is the correct target without checking — always switch explicitly.
- Targeting pages by name — use IDs. Names change; IDs do not.
- Creating a new file when the task only requires a new page in an existing file.
- Placing content before calling `setCurrentPageAsync` — content will be placed on whichever page is currently active, which may not be correct.