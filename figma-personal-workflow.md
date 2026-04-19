---
name: figma-personal-workflow
description: "Manages the capture and integration of a designer's personal workflow preferences into Figma skills. Use when a designer states a process preference, naming convention, iteration habit, or working style they want the agent to follow consistently. Governs what is safe to edit vs. protected in each skill file."
metadata:
  mcp-server: figma
---

# Figma Personal Workflow

This skill governs how designer-specific preferences are captured, stored, and applied. Design process is personal — what makes agent output consistent is technical, but how that output is reached belongs to the designer.

---

## The Core Distinction

Every Figma skill has two layers:

**Protected content — do not edit or overwrite:**
- Code samples and API compliance rules (`figma-code`)
- The parallel discovery script in `figma-harness`
- URL target resolution logic
- Anti-patterns documented in each skill
- Any content documenting a known Figma API constraint or failure mode

**Malleable content — open to designer preferences:**
- How much the agent checks in vs. proceeds independently
- Component and layer naming conventions beyond `ComponentName/State`
- The order in which tasks are approached within a taskflow
- How ambiguity is handled (which question to ask, how to frame it)
- Output formatting and annotation style
- Whether to audit the full file or a targeted section first
- How many variants to generate by default
- Default fidelity level for new wireframes
- Default framework for code handoff
- Tone and communication style during a session

When in doubt: if removing it would cause a script to fail or produce broken output, it is protected. If removing it would only change how the agent behaves with the designer, it is malleable.

---

## Capturing a Preference

### When the designer corrects or states a preference mid-session

Do not just apply it once. Offer to persist it using `AskUserQuestion`:
> "Want me to save that as a workflow preference so I follow it automatically going forward?"

If yes, add it to the relevant skill file under `## Designer Workflow Preferences`.

### When the designer gives the same answer to the same question twice

After the second identical answer to any non-deterministic question, offer proactively using `AskUserQuestion`:
> "You have picked [answer] twice now. Want me to save that so I stop asking?"

Do not wait for the designer to ask. The offer is made automatically after the second match across separate sessions.

### What counts as a preference worth saving

Save preferences that would change the agent's default behavior for every future session. Do not save one-off adjustments.

The block below is an **illustrative example** of the format, not a set of defaults. Replace or delete these entries on first use. They exist so the structure is clear, not because they are recommended.

Example good candidates (for illustration only, replace or delete on first use):

- "Always build two layout options before asking which to develop."
- "Default fidelity is [high | medium | low] for all new screens."
- "Token naming convention is the full three-level chain."
- "Always ask before binding tokens; review manually first."
- "Default code framework is [React + Tailwind | SwiftUI | Vue | other]."

Example not-good candidates (task-specific exceptions, not worth saving):

- "Make this specific button larger." One-off adjustment.
- "Use a different color on this frame." Context-specific, not a default.
- "Skip the token audit for this session." Task-specific exception.

---

## Session Preference Cache

At the start of each session, `figma-harness` loads the relevant preferences into working memory. This means:
- Previously saved answers to recurring questions are applied automatically — those questions are not asked again.
- The designer does not need to re-state preferences at the start of each session.

When a preference is applied silently (not asked because it was saved), note it briefly:
> "Applying saved default: [preference]."

This confirms the preference is active without requiring the designer to re-confirm it.

---

## Placement Guide

| Preference type | Skill to update |
|---|---|
| How to approach a new screen — fidelity, layout defaults, iteration mode | `figma-frames` |
| Component anatomy defaults, variant depth, naming conventions | `figma-components` |
| Documentation audience, token detail level, section order | `figma-documentation` |
| Token architecture defaults, color system preferences, spacing base | `figma-tokens` |
| Default code framework, token output format, Code Connect annotation depth | `figma-documentation` |
| Vector and icon handling defaults, export format preferences | `figma-vectors` |
| File and page creation defaults | `figma-files` |
| Global defaults applying across all tasks | `figma-harness` |

---

## Editing Process

### Skills loaded as MD files on disk

Edit the SKILL.md file directly. Add a `## Designer Workflow Preferences` section at the end of the file. Do not insert preferences into existing sections — keep them separate so protected content is easy to identify.

```markdown
---

## Designer Workflow Preferences

> These preferences are set by the designer and take priority over all default agent behavior.
> Do not remove unless the designer asks. Do not overwrite protected content above this line.

- [One clear, actionable sentence per preference]
- [Another preference]
```

Each preference must be one actionable sentence. Vague preferences are not useful:
- Bad: "Be more careful with tokens"
- Good: "Always show me the full changeset and wait for confirmation before binding any tokens"

### Skills running remotely via skill-creator

Use the `skill-creator` skill. Specify:
1. Which skill to update
2. That you are adding to `## Designer Workflow Preferences` only
3. The exact preference text
4. That protected content must not be modified

---

## Line Budget

All Figma skills stay at or under **300 lines**. Before adding preferences, check the current line count. If near the limit:
1. Scan `## Designer Workflow Preferences` for preferences that are now the default behavior and remove them.
2. Combine preferences that address the same behavior into one sentence.
3. Move global preferences (applying across all taskflows) to `figma-harness` and remove the per-skill duplicate.

Do not trim protected content to make room for preferences.

---

## Anti-Patterns

- Adding preferences inline inside protected sections.
- Writing preferences as vague intent rather than specific behavior.
- Saving every micro-correction — only save what should apply to every future session.
- Applying a saved preference without briefly noting it was applied.
- Editing `figma-code` for any reason other than documenting a new Figma API constraint.
- Letting preferences accumulate past the line budget without pruning.