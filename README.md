# figma-harness

The thinnest self-healing harness that gives an LLM full freedom to complete any Figma design task.

Not a framework. Not a code-gen wrapper. The agent writes plain `use_figma` scripts against the Figma MCP server; this skill is the harness that sits around those calls: parallel discovery before any write, an execution plan the user can correct, and a capture protocol that turns every surprise into a durable file.

Built for Figma designers who work through an LLM (Claude Code, Codex, Claude Desktop, or any client that loads Anthropic-style skills) and want a running, growing set of patterns instead of a frozen prompt.

## What makes it a harness

Three properties, smallest to largest.

**Micro-healing inside a single call.** `figma-code.md` teaches the agent how to recover from known failure modes atomically: font not loaded, sizing set before append, `vectorPaths` thrown on complex networks, `setBoundVariableForPaint` called as a node method. The agent fixes and retries without surfacing the glitch.

**Mid-task script growth.** When the agent writes a snippet that will generalize, it extracts the snippet to `scripts/<name>.js` and adds an entry to `scripts/README.md`. Next session, that script exists. Contract in `scripts/README.md`.

**Per-file knowledge accretion.** When the agent discovers something non-obvious about a specific Figma file (a token named oddly, a component at a weird node id, a mode setup that doesn't match the documented pattern), it writes a markdown file into `design-skills/<file-key>/`. At the start of the next session touching that file, Stage 2 Call 6 auto-loads every file in that folder. The harness gets smarter about that file, one observation at a time.

Every "heal" is a file-level change that persists. It is not runtime patching; the agent writes durable code and markdown that future runs pick up.

## Three layers

| Layer | Files | Who writes |
|---|---|---|
| Capabilities | `figma-read.md`, `figma-frames.md`, `figma-components.md`, `figma-tokens.md`, `figma-vectors.md`, `figma-documentation.md`, `figma-files.md`, `figma-code.md` | Protected. Edited only when Figma itself changes, via `AskUserQuestion` confirmation. |
| Script library | `scripts/*.js` | Agent-extensible. Any snippet over twenty lines that generalizes. |
| Design skills | `design-skills/<file-key>/*.md` | Agent-written. Observational, file-scoped, dated. |

User workflow preferences sit alongside these layers, captured via `figma-personal-workflow.md`.

> Design skills are written by the harness, not by you. Just run your task with the agent; when it figures something non-obvious out, it files the skill itself.

## Install

figma-harness is a standalone skill folder. Any tool that loads Anthropic skills can use it.

### Claude Code (CLI)

Claude Code reads skills from `~/.claude/skills/` and from any project's `.claude/skills/`.

```bash
# Global install (available in every project)
git clone https://github.com/davidjamesdimalanta/figma-harness.git ~/.claude/skills/figma-harness

# Per-project install
git clone https://github.com/davidjamesdimalanta/figma-harness.git .claude/skills/figma-harness
```

Start Claude Code in a project that has the Figma MCP server connected (`claude mcp add figma`) and the skill will load automatically on any Figma-related request. For detailed MCP setup, see [Figma's MCP documentation](https://help.figma.com/hc/en-us/articles/32132100833559).

### Codex

Codex treats skills as local markdown context. Drop the folder anywhere Codex can read from and reference it in your settings:

```bash
git clone https://github.com/davidjamesdimalanta/figma-harness.git ~/.codex/skills/figma-harness
```

Then point Codex at the `SKILL.md` in your project configuration. The Figma MCP server must be reachable from the Codex runtime.

### Claude Desktop and Cowork mode

Install through the skills registry if figma-harness is published there, or drop the folder into your Cowork workspace and reference it the way Cowork references any other skill.

### Other Anthropic skill hosts

The skill follows the Anthropic skill contract: a single `SKILL.md` with frontmatter (`name`, `description`), plus referenced capability files in the same directory. Any host that loads skills by reading `SKILL.md` will work. No install scripts, no build step, no dependencies beyond the Figma MCP server the LLM is already calling.

## Quick start

Connect the Figma MCP server to your LLM client, then prompt as usual:

```
Recreate the screen at figma.com/design/<key>/<name>?node-id=<id>
as a mobile-first React mockup. Match token usage to the existing system.
```

What happens automatically:

1. **Stage 2 parallel discovery** fires. The harness reads local variable collections, published library assets, remote variables, file metadata, and a visual baseline screenshot in one batched response.
2. **Stage 3 URL resolution** converts the URL's `node-id` to the internal colon form and confirms the target page.
3. **Stage 2 Call 6** loads any existing `design-skills/<file-key>/` entries for this file.
4. **Stage 4 capability selection** picks the right capability files (`figma-read`, `figma-frames`, `figma-components`, `figma-tokens`) and reads them.
5. **Stage 5 execution plan** prints before any write. The plan lists the component map, token sources, and section order, with one ambiguity question if there is one.
6. Once the plan is accepted, writes execute one section per `use_figma` call, with `get_screenshot` between phases.
7. **Stage 7 capture** runs after any surprise: new API behavior goes to a capability file (via confirmation), new file-specific facts go silently to `design-skills/<file-key>/`.

## How the harness grows

Every session is an opportunity to widen the harness. See `SKILL.md` Stage 7 for the full capture rules. In short:

- A Figma API quirk the docs don't mention lands in the relevant capability file after confirmation.
- A reusable snippet longer than twenty lines lands in `scripts/`.
- A file-specific observation lands in `design-skills/<file-key>/` silently, with a date and the signal that surfaced it.

A session that doesn't capture anything is still useful; a session that captures is compounding.

## Directory layout

```
figma-harness/
  SKILL.md                          orchestration hub; read first
  README.md                         this file
  figma-read.md                     reading existing design state
  figma-frames.md                   frame and layout creation
  figma-components.md               component import, creation, hierarchy
  figma-tokens.md                   variable and style binding, WCAG
  figma-vectors.md                  vector geometry, shapes, boolean ops
  figma-documentation.md            style guides, Code Connect, token export
  figma-files.md                    file and page management
  figma-code.md                     protected API constraints and patterns
  figma-personal-workflow.md        user preferences capture protocol
  references/
    tool-reference.md               every MCP tool, grouped read/write
    component-swap.md               swap-every-instance workflow
    component-reactions.md          prototype reactions with CONDITIONAL pattern
    vector-effects-exports.md       gradients, shadows, blur, node exports
  scripts/
    README.md                       script library contract
    discovery-audit.js              Stage 2 Call 1 audit
    rightedge-placement.js          rightEdge placement boilerplate
    wcag-contrast.js                contrast utilities
    bind-fill.js                    token binding wrappers
    token-audit.js                  hardcoded fill finder
    component-swap.js               swap script with guards
  design-skills/
    README.md                       format, auto-load contract
    <file-key>/                     one folder per file worked on
      components.md                 gold-standard node ids, component map
      tokens.md                     token architecture notes
      file.md                       general quirks
    libraries/
      <library-key>/                library-scoped observations
```

## What ships empty

A fresh install of figma-harness has `design-skills/` empty except for its `README.md`. Each user seeds their own file keys as they work. This is intentional: design skills that ship pre-seeded become stale quickly, and the file-key path is identifying per team.

If a team wants to share design skills across members, commit the `design-skills/<file-key>/` folder to a shared fork. For public distribution, keep it empty.

## Requirements

- An LLM client that loads Anthropic skills: Claude Code, Codex, Claude Desktop, Cowork, or any compatible host.
- The Figma MCP server connected to that client. The harness calls tools like `use_figma`, `search_design_system`, `get_metadata`, `get_screenshot`, `get_design_context`, and `get_variable_defs`.
- Figma plan with library publishing if `search_design_system` should return remote components and variables.

## Contributing

Pull requests that widen the capability files are welcome when they document a Figma platform behavior that applies to every file, not a one-off quirk. File-specific observations belong in your own fork's `design-skills/`, not in the shared skill.

If a script pattern in `scripts/` has broken with a Figma API change, fix it and update the capability file that references it.

## License

MIT. See `LICENSE`.

## Acknowledgments

The harness architecture is adapted from [browser-use/browser-harness](https://github.com/browser-use/browser-harness), applied to Figma instead of Chrome: the `domain-skills/` pattern maps to `design-skills/<file-key>/`, the `helpers.py` surface maps to `scripts/`, and the "agent can modify the harness while it runs" property drives the Stage 7 capture protocol.
