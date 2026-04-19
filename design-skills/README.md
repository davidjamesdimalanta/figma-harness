# Design Skills

Design skills are non-obvious, file-specific or library-specific knowledge that the harness learns while working. They are the Figma analogue of browser-harness's `domain-skills/<site>/`: written by the agent, auto-loaded by `figma-harness` at the start of a session, and scoped to the file or library they describe.

They are not authoritative the way capability files are. They reflect what has worked in a specific file before; if reality diverges, observation wins and the skill gets corrected.

## When the harness writes here

Three kinds of facts land in `design-skills/`:

- A token or style is named in a way that is not obvious from the name alone (example: the file uses `brand/primary/600` instead of the documented `color/primary`).
- A component lives at a non-obvious node, or the file's canonical anatomy reference is at a specific node id.
- The file has a quirk in how modes, variant keys, or scoping are set up.

The harness writes these observations without asking the user, because they are descriptive and verifiable from the file itself. Each entry must include the date observed and the node id or search query that surfaced it.

## Directory layout

```
design-skills/
  README.md                                 this file
  <file-key>/                               one folder per Figma file worked on
    file.md                                 file-level notes: canvas map, quirks, preferred frames
    components.md                           component map, gold-standard anatomy node ids
    tokens.md                               token architecture notes specific to this file
  libraries/
    <library-key>/                          one folder per shared library that surfaces
      components.md                         library-level component keys and drift notes
      tokens.md                             library-level variable collections and modes
```

`<file-key>` is the string between `/design/` and the next slash in a Figma URL. Example: in `figma.com/design/AbCdEf123456/MyFile?node-id=1-2`, the file key is `AbCdEf123456`. Always use the file key, never the human name. Keys are stable; names are not.

`<library-key>` is the key that surfaces from `search_design_system` results for remote assets.

## File format

Each file is plain markdown. A new entry looks like this:

```markdown
## Entry title

- **Observed:** 2026-04-18
- **Surfaced by:** search_design_system("button") / node-id 456:17556 / Stage 2 Call 3
- **Fact:** Brand primary is named `brand/primary/600`, not the expected `color/primary`. Any binding to primary brand color in this file must resolve the full chain.
- **Why it matters:** A generic `color/primary` lookup returns null here and silently fails binding. Use the full three-level chain or look up by id from the audit output.
```

Keep entries short. One observation per entry, dated, with the signal that revealed it. If an observation becomes stale — for example the file is renamed or the token is removed — update the date and the fact; do not leave silent stale content behind.

## Auto-load contract

At Stage 2 Call 6, the harness reads every markdown file under `design-skills/<resolved-file-key>/` and, if library keys surface in Call 2 or Call 3, also reads every file under `design-skills/libraries/<library-key>/`. Content is loaded as session context, weighted below the capability files but above generic defaults.

If a design skill contradicts a capability file, trust the capability file and update the design skill. Capability files are protected; design skills are observational.

## What does not go here

- Reusable code snippets longer than twenty lines: those go in `scripts/` with an entry in `scripts/README.md`.
- API behaviors that apply to every Figma file: those go in the relevant capability file (usually `figma-code.md`) and require the agent to propose the change before writing.
- User workflow preferences: those are captured via `figma-personal-workflow.md`. Design skills are about the file; preferences are about the user.

## A note on portability

A Figma file key is not a secret, but it is identifying. When sharing this skill across a team, treat each `<file-key>/` folder as internal to that team. When publishing the harness for others to download, ship `design-skills/` empty or with generic example entries; each user seeds their own.
