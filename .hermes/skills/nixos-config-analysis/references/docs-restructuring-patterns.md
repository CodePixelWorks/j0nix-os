# Docs Restructuring Patterns for Module-Based Nix Projects

## Problem

As a NixOS flake grows, the `docs/` folder accumulates flat markdown files with no natural grouping. Navigation becomes difficult, and the mental model of what belongs where gets lost. A flat list of 8–12 files with names like `caelestia.md`, `dms.md`, `qmlgreet.md` requires readers to already know the taxonomy.

## Solution: Topical Subdirectories

Group docs by **audience concern**, not by file name alphabet:

```
docs/
├── README.md           # Central index with grouped TOC
├── architecture.md     # Cross-cutting: flake graph, module layers
├── operations/         # Security, secrets, sysadmin runbooks
│   └── secrets.md
├── devops/             # CI/CD, pipelines, mirroring
│   └── ci-pipeline.md
└── wm/                 # Window manager / shell guides
    ├── keybinds.md
    ├── qmlgreet.md
    ├── startup-flow.md
    └── quickshell/     # Subgroup: all Quickshell-based shells
        ├── caelestia.md
        └── dark-material-shell.md   # was: dms.md
```

### Grouping Rules

- **Use full product names**, not abbreviations or codenames. `dark-material-shell.md` is better than `dms.md` because:
  - New readers can discover it via grep without knowing the abbreviation
  - It avoids collision with other "DMS" acronyms (document management system, etc.)
  - The upstream repo name is the natural canonical name
- **Subgroup by technology family**, not by individual product. All Quickshell-based shells (`caelestia`, `dark-material-shell`, `noctalia`) belong under `wm/quickshell/`. GTK-based shells or AGS would get their own sibling subgroup (`wm/ags/`, `wm/gtk-shells/`).
- **Keep the README TOC grouped**, not flat. Use `### H3` sections per subgroup with their own mini table.

## Migration Procedure

1. **Plan the target structure on paper first** — decide group names, full names, and which files move.
2. **`git mv` in batches** by subgroup to keep renames trackable:
   ```bash
   git mv docs/ci-pipeline.md docs/devops/
   git mv docs/secrets.md docs/operations/
   ```
3. **Update the central index** (`docs/README.md`) — remove old entries, add grouped sections with updated relative paths (`./wm/quickshell/caelestia.md`).
4. **Fix cross-file links** — grep for all `](*.md)` patterns in docs, verify each resolves correctly after the move:
   ```bash
   # Broken link detection script
   python3 -c "
   import os, re
   for root, _, files in os.walk('docs'):
       for f in files:
           if not f.endswith('.md'): continue
           fp = os.path.join(root, f)
           with open(fp) as fh:
               content = fh.read()
           for m in re.findall(r'\]\(([^)]+\.md)\)', content):
               target = os.path.normpath(os.path.join(os.path.dirname(fp), m))
               if not os.path.exists(target):
                   print(f'BROKEN: {fp} -> {m}')
   "
   ```
5. **Update external references** — README.md root, AGENTS.md, templates/README.md.tmpl, and any scripts that embed doc paths.
6. **Do NOT rename upstream identifiers in code** — The Nix flake references upstream repos like `dank-material-shell` and `dms-greeter`. Keep those as-is in `.nix` files to avoid breaking the actual evaluation. Rename docs only.
7. **Commit per scope** — one commit for the move, one for the index update, optionally one for external reference cleanup.

## Pitfalls

- **Partial renames leave broken links.** If you move a file but forget to update a sibling doc that links to it, the link checker will catch it — but only if you run it. Always run the link check.
- **Codename leakage.** If `dms.md` is renamed to `dark-material-shell.md` but the README still says "DMS setup guide" in prose, readers searching for "dark material" won't find it. Search-and-replace prose as well as filenames.
- **Over-nesting.** Don't go deeper than 3 levels (`docs/wm/quickshell/shell.md` is fine; `docs/wm/quickshell/dark/shell.md` is probably too much). If you need 4 levels, the grouping is too granular.

## Verification Checklist

- [ ] All `.md` files live in a subdirectory (or are the root README / architecture anchor)
- [ ] docs/README.md has a grouped TOC with no flat list longer than 5 items
- [ ] No broken internal links (`python3` script above returns empty)
- [ ] External references (root README, AGENTS.md, templates) updated
- [ ] Upstream code identifiers NOT changed (flake.nix, settings.nix, module paths)
- [ ] Conventional Commits used (`docs(wm):`, `refactor(docs):`)
