# Tool Reference

Every tool the harness calls, grouped by whether it reads or writes. Referenced from `SKILL.md` Tool Reference section.

---

## Reading tools

Safe to call in parallel during Stage 2 discovery only. Once edits are in progress, do not run the discovery battery again.

| Tool | Returns |
|---|---|
| `use_figma` (audit script) | Variable collections, text/paint/effect styles. See `scripts/discovery-audit.js` |
| `search_design_system` | Published library components; with `{ includeVariables: true, includeStyles: true }`, also remote variables and styles |
| `get_metadata` | Layer IDs, names, types, positions, sizes |
| `get_screenshot` | Visual capture of a node or page |
| `get_design_context` | Structured layout, fill, and style data for a specific node |
| `get_variable_defs` | Tokens already bound to a specific node. Not a discovery tool |
| `get_code_connect_map` | Node IDs mapped to codebase components |
| `get_figjam` | FigJam diagram metadata |
| `whoami` | Authenticated user identity |

---

## Writing tools

Always sequential. One write call at a time. Never run two `use_figma` write calls in parallel; atomic failure on one can leave the next writing to a stale state.

| Tool | Purpose |
|---|---|
| `use_figma` | Create, edit, delete Figma objects; bind variables; build components |
| `generate_diagram` | Creates FigJam diagrams from Mermaid syntax |
| `create_new_file` | Creates a blank Figma file |
| `create_design_system_rules` | Generates design system constraints from file patterns |
| `send_code_connect_mappings` | Confirms accepted Code Connect suggestions |
| `add_code_connect_map` | Manually adds a node-to-code mapping |

---

## Core Technical Rules

These apply to every `use_figma` script regardless of which capabilities are active. Each rule links to the capability file that documents the full detail.

**10px collapse:** hug parent plus all Fill children collapses the frame to 10px. Fix: give at least one child a Fixed or Hug dimension. See `figma-frames.md`.

**Append before fill:** cannot set `layoutSizingHorizontal/Vertical = 'FILL'` before appending to a parent. Order: create, append, then set sizing. See `figma-code.md`.

**Auto-layout default:** all new frames use auto-layout. Set `layoutMode` first, then `primaryAxisSizingMode` and `counterAxisSizingMode`. See `figma-frames.md`.

**No clipping on specimens:** `clipsContent = false` on documentation and specimen frames. See `figma-documentation.md`.

**Token binding over hardcoding:** use `figma.variables.setBoundVariableForPaint` on the namespace for colors. Use `node.textStyleId` for typography. Hardcode only when no token exists. See `figma-tokens.md`.

**Naming:** `ComponentName/State`, for example `Button/Hover`. Hidden building blocks use the `_` prefix. See `figma-components.md`.

**Script size limit:** `use_figma` scripts are capped at 50,000 characters. Break large tasks into phases and return created node IDs at the end of each phase. See `figma-code.md`.

**Script atomicity:** `use_figma` scripts are atomic. If a script fails mid-run, no changes are applied. This is safe for retrying, but always read the error and fix the script before retrying. Never retry blind. See `figma-code.md`.

**Vector safety:** never read `node.vectorPaths` without a try/catch. For copying vectors, use `.clone()`. See `figma-vectors.md`.
