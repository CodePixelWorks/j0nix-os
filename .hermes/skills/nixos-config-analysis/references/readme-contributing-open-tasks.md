# README Contributing Section with Open Tasks Table

## Problem

Personal repos often have a generic "contributions welcome" section that doesn't communicate where help is actually needed. Contributors don't know what gaps exist or what's in scope.

## Pattern

Add a `Contributing` section with two subsections: **Open Tasks** and **Conventions**.

### Open Tasks table

Use a markdown table with columns: `# | Task | Status | Notes`. Each row is a known gap.

```markdown
### 🛠️ Open Tasks

These are known gaps where help or exploration is appreciated:

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | **Unified QT/GTK/KDE theming** | Hacky workaround | Currently using a custom Stylx theme; needs a clean declarative cross-toolkit approach |
| 2 | **Fusion 360 on Proton** | Not working | Likely needs winetricks, bottle tweaks, or a dedicated Nix derivation |
| 3 | **Hibernate / Standby** | Not functional | Needs resume device, swap, and kernel param alignment |

If you want to pick one up, comment on an existing issue or open a new one.
```

**Status values**: use plain language — "Not working", "Hacky workaround", "Partial", "Not functional", "Exploratory". Avoid false precision (don't say "70% done" unless you actually track it).

**Notes column**: include enough context that someone can orient themselves. Mention the current workaround or the blocker.

### Conventions subsection

Keep project conventions (commit style, validation commands, architecture rules) separate from the task list so they don't get lost.

```markdown
### Conventions

- Conventional Commits (`feat(desktop):`, `fix(hyprland):`)
- One commit per logical scope
- Validate with `nix flake check --no-build` before committing
- Settings = cross-platform generics; Profiles = host-specific hardware
```

## When to update

- When a task is completed → remove the row or mark "Done"
- When a new gap is discovered → add a row immediately (don't defer)
- When status changes → update the Status cell in the same PR that changes the code

## anti-pattern: deferring documentation

Don't add a feature without updating the README. If the PR touches settings, monitors, or profiles, the README table must reflect it. Treat the README as living documentation, not a post-hoc summary.
