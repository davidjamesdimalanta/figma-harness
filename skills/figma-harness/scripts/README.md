# Scripts

Reusable `use_figma` snippets. These are the Figma analogue of browser-harness's `helpers.py` functions: conveniences that exist because a pattern showed up often enough to extract, but never between the agent and the Figma MCP. An agent can always drop down and write the script inline.

## Contract

Every script file must:

1. Start with a block comment that contains:
   - A one-line description of what the script does.
   - The capability file it belongs to (for example `figma-tokens`, `figma-components`).
   - A minimal usage example showing how it is pasted into `use_figma`.
2. Be idempotent where possible. Running the same script twice should leave the file in the same state as running it once, unless the script is explicitly a mutator whose purpose is accumulation.
3. Return structured data via `return`, not `console.log`. Console output is invisible to the agent.
4. Use `await figma.getNodeByIdAsync(id)`, never the synchronous form. See `figma-code.md`.
5. Append child nodes to their parent before setting `layoutSizingHorizontal/Vertical = 'FILL'`. See `figma-code.md`.

## Adding a script

Any agent may propose a new script following the Stage 7 capture protocol in `SKILL.md`:

- If a snippet is longer than about twenty lines and would generalize beyond the current file, extract it to `scripts/<name>.js`.
- Add a one-line entry to the index below.
- Mention the extraction in the response so the user can push back if the script is premature.

Shorter snippets stay inline. Extracting every three-liner creates index sprawl; leaving every thirty-liner inline creates rediscovery.

## Current scripts

| File | Capability | Purpose |
|---|---|---|
| `discovery-audit.js` | `figma-harness` Stage 2 | Local variable collections and styles in one call. Pastes into Call 1. |
| `rightedge-placement.js` | `figma-frames` | Computes rightEdge for new frame placement, avoids overlap. |
| `wcag-contrast.js` | `figma-tokens` | `getLuminance` and `contrastRatio` helpers for WCAG checks. |
| `bind-fill.js` | `figma-tokens` | `bindFill`, `bindStroke`, `safeAppend` wrappers for the namespace binding API. |
| `token-audit.js` | `figma-tokens` | Finds hardcoded fills and logs token gaps before a migration pass. |
| `component-swap.js` | `figma-components` | Full instance swap and master deletion protocol. See `references/component-swap.md`. |

## Anti-patterns

- Writing a script that calls `figma.getNodeById` synchronously. Use the async form.
- Writing a script that reports via `console.log`. Use `return JSON.stringify(...)`.
- Adding a script for a snippet that is only ever used in one file. That is file-specific and belongs in a `design-skills/<file-key>/` entry with the inline code.
- Deleting a script without checking whether the capability file or a reference still points at it.
