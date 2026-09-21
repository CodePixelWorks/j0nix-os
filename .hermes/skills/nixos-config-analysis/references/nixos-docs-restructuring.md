# Documentation Restructuring Pattern

Pattern from refactoring j0nix-os docs from scattered ROOT-level and SHOUT_CASE files into a unified `docs/` directory.

## Motivation

- Root gets cluttered with `.md` files
- Inconsistent naming (`ARCHITECTURE.md`, `DMS.md`, `WM_STARTUP_AND_LAUNCH_FLOW.md`)
- No master index — newcomers can't find docs
- Full walkthroughs (e.g. `secrets/SETUP.md`) are too long for quick reference

## Result Structure

Phase 1 (gather from root):
```
docs/
├── README.md           # Master index: every doc, audience, topic
├── architecture.md     # Flake graph, module layers
├── dms.md              # Shell-specific config
├── qmlgreet.md         # Greeter config
├── startup-flow.md     # WM startup order
├── caelestia.md        # Keybind regression runbook
├── keybinds.md         # Keybind reference
├── secrets.md          # Condensed quick-ref
└── ci-pipeline.md      # CI mirror pipeline
```

Phase 2 (subdivide by topic):
```
docs/
├── README.md              # Master index with grouped TOC
├── architecture.md        # Cross-cutting architecture
├── wm/                    # Window manager / shell guides
│   ├── caelestia.md
│   ├── dms.md
│   ├── keybinds.md
│   ├── qmlgreet.md
│   └── startup-flow.md
├── devops/                # CI / pipeline docs
│   └── ci-pipeline.md
└── operations/            # Security / ops runbooks
    └── secrets.md
```

**When to stop**: Flat is fine for < 8 docs. Subdivide when:
- One topic dominates (e.g. 5+ WM docs vs 1 CI doc)
- Different audiences never read each other's docs
- Subsystem maintainers need to own a whole directory

## Master Index Pattern (docs/README.md)

Use a table with audience column so readers self-select. When using subdirectories, **group the TOC by directory**:

```markdown
### Desktop / Window Manager

| Doc | Audience | Topic |
|-----|----------|-------|
| [qmlgreet.md](./wm/qmlgreet.md) | Users, contributors | QMLGreet greeter config |

### DevOps / CI

| Doc | Audience | Topic |
|-----|----------|-------|
| [ci-pipeline.md](./devops/ci-pipeline.md) | DevOps, maintainers | Drone CI mirror pipeline |

## Cross-Link Validation

After moving files into subdirectories, verify no broken relative links remain. Markdown links like `./old-name.md` must be updated to `subdirectory/new-name.md` from the referencing file's perspective:

```bash
# Python snippet — scan all .md files for broken relative links
python3 -c "
import os, re
link_re = re.compile(r'\\]\\(([^)]+\\.md)\\)')
for root, _, files in os.walk('docs'):
    for f in files:
        if not f.endswith('.md'): continue
        fp = os.path.join(root, f)
        with open(fp) as fh:
            content = fh.read()
        for m in link_re.finditer(content):
            target = os.path.normpath(os.path.join(os.path.dirname(fp), m.group(1)))
            if not os.path.exists(target):
                print(f'BROKEN: {fp} -> {m.group(0)}')
"
```

Fix every broken link, then commit. Do not assume `grep` caught everything — relative links resolve from the *referencing* file's directory.

Also list per-directory READMEs (the ones embedded near code) so the index is comprehensive.

## Naming Convention

- All docs: `lowercase-kebab.md`
- No SHOUT_CASE, no camelCase
- Short names: `startup-flow.md` not `wm-startup-and-launch-flow.md`
- Prefer subsystem name over full sentence: `caelestia.md` not `caelestia-keybind-stability.md`

## Architecture Change Documentation Surface Checklist

When the flake architecture or host mapping changes, update ALL documentation surfaces in the same commit scope — never defer:

- [ ] `docs/architecture.md` — build graph, module flow diagrams, multi-user data flow
- [ ] `AGENTS.md` — Configuration Flow section, directory structure, any rules referencing old patterns
- [ ] `docs/README.md` (master index) — if new docs added or old ones renamed
- [ ] `README.md` — settings contract table, build commands, feature categories
- [ ] `.example` templates — when real config fields change
- [ ] Per-directory READMEs near code (e.g. `system/lib/README.md`)

**Specific sync patterns:**
- `flake.nix` host mapping changed → update `docs/architecture.md` build graph AND `AGENTS.md` step 1/2
- `settings.nix` field renamed/removed → update `AGENTS.md` Key Settings Contracts AND `README.md` tables
- `wmShell` or shell selection changed → update `docs/architecture.md` shell-selection diagram AND `AGENTS.md` Supported Hyprland Shell Modes

## Move Checklist

1. `git mv OLD docs/new.md` — preserves history
2. Update all internal links in moved files (e.g. `./QMLGREET.md` → `./qmlgreet.md`)
3. Update all external links (README.md, AGENTS.md, other docs)
4. Create condensed quick-reference if a full walkthrough exists elsewhere (e.g. `docs/secrets.md` pointing to `secrets/SETUP.md` for full steps)
5. `nix flake check --no-build` — doc-only changes shouldn't break Nix, but flake checks validate
6. Commit as `docs:` scope

**Commit message pitfall**: Multi-line bodies with backticks break `git commit -m` in bash (command substitution). Prefer `git commit -F <message-file>` when the body contains backticks, newlines, or other shell-sensitive characters.

## Condensed Reference vs Full Walkthrough

| | Condensed (`docs/secrets.md`) | Full (`secrets/SETUP.md`) |
|--|-------------------------------|---------------------------|
| Length | 50-100 lines | 400+ lines |
| Content | Commands + minimal context | Rationale, edge cases, migration, troubleshooting |
| Audience | "I know SOPS, just remind me the commands" | "I've never set this up, walk me through" |
| Updates | Only when commands change | When behavior or recommendations change |

Keep both. The condensed doc lives in `docs/` and links to the full walkthrough.

## Nix Eval for .example Files

After rewriting `.example` templates, verify they are valid Nix expressions:

```bash
# Simple attrset files (settings.nix.example, details.nix.example)
nix-instantiate --eval --expr 'import ./settings.nix.example {}'

# Files needing lib argument (hardware-configuration.nix.example)
nix-instantiate --eval --expr 'import ./hardware-configuration.nix.example { config = {}; lib = import <nixpkgs/lib>; pkgs = {}; modulesPath = ""; }'
```

This catches syntax errors and missing fields before a user copies the template.
