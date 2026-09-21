# Monolithic settings.nix → Modular settings/ Refactor Pattern

**Context**: A single `settings.nix` grew to 1000+ lines (1124 in this case, with 24 sections, 35 top-level keys, 493 lines of `userSettings`). Monolithic settings files become hard to navigate, increase merge-conflict surface, and discourage new-user onboarding. Additionally, `settings.nix` often contains host-specific or personal data (usernames, SSH keys, mount UUIDs) that should not be committed to a public repo.

**Goal**: Split into a modular `settings/` directory with a thin wrapper, while keeping Nix's `lib.recursiveUpdate` semantics and backwards-compatible flake discovery.

---

## Target Structure

```
.
├── settings.nix              # LIVE, .gitignored — thin wrapper (5 lines)
├── settings/                 # .gitignored — active config split into modules
│   ├── default.nix           # aggregator: lib.foldr recursiveUpdate over all modules
│   ├── locale.nix            # timezone, keyboard, locale
│   ├── secrets.nix           # SOPS defaults, GPG key references
│   ├── programs.nix          # kitty, VSCode, app toggles
│   ├── gaming.nix            # Steam, Proton, open-source games
│   ├── storage.nix           # systemMounts, device UUIDs, gvfs
│   ├── network.nix           # WiFi, Tailscale, DNS resolver, routing
│   ├── hardware.nix          # boot, drivers, audio backend, logging, scanning
│   ├── dev.nix               # Docker, BuildKit, git, SSH, AI CLI toggles
│   ├── desktop.nix           # wms, theme, colorScheme, iconTheme, hyprland, DMS, DM
│   ├── userSettings.nix      # per-user overrides (the biggest single block)
│   └── custom.nix            # escape hatches, one-offs
├── templates/settings/       # COMMITTED — example / starting point
│   ├── default.nix
│   ├── locale.nix
│   └── ... (mirror of settings/ but with neutral defaults)
└── scripts/init-settings.sh  # one-shot: cp -r templates/settings ./settings + create wrapper
```

## Wrapper (`settings.nix`)

```nix
{ inputs, ... }:
import ./settings { inherit inputs; }
```

## Aggregator (`settings/default.nix`)

```nix
{ inputs, ... }:
let
  lib = inputs.nixpkgs.lib;
  modules = [
    ./locale.nix
    ./secrets.nix
    ./programs.nix
    ./gaming.nix
    ./storage.nix
    ./network.nix
    ./hardware.nix
    ./dev.nix
    ./desktop.nix
    ./userSettings.nix
    ./custom.nix
  ];
in
lib.foldr lib.recursiveUpdate {} (map (f: import f { inherit inputs; }) modules)
```

## Flake Discovery (`flake.nix`)

Change `settingsFile` from a single-file path to a priority chain:

1. `settings.nix` (legacy single-file, still supported for existing setups)
2. `settings/default.nix` (new modular standard)
3. `templates/settings/default.nix` (fallback for fresh clones)

```nix
settingsFile =
  if builtins.pathExists (baseDir + "/settings.nix") then
    baseDir + "/settings.nix"
  else if builtins.pathExists (baseDir + "/settings/default.nix") then
    baseDir + "/settings/default.nix"
  else
    baseDir + "/templates/settings/default.nix";
```

## Git & Mirror Considerations

| Concern | Action |
|---------|--------|
| Prevent accidental commit of live settings | Add `settings.nix` and `settings/` to `.gitignore` |
| Root whitelist | Remove `settings.nix` from `.mirror-root-whitelist` (irrelevant once ignored) |
| Fresh clone must build | `templates/settings/default.nix` provides safe neutral defaults |
| User onboarding | `scripts/init-settings.sh` copies templates + creates wrapper in one step |

## Splitting Heuristics

Use these rules to decide where each key goes:

1. **One top-level key per file** — if a section (e.g. `programs`) spans >150 lines, it gets its own file.
2. **Host-specific data stays in profiles** — mount UUIDs, resume devices, GPU packages. If a setting is only valid for one machine, it does not belong in `settings/` at all.
3. **Cross-platform toggles go in** — anything another host might want to change (steam on/off, docker on/off, WM choice, theme).
4. **Per-user overrides in one file** — `userSettings` is typically the largest block; keep it together because it is conceptually one concern (multi-user overrides).
5. **Escape hatches at the end** — `custom` is the last merge target so it can override anything above.

## Alternative: Template-based Monolith (Keep Single File)

When the user explicitly wants to keep everything in one file (e.g. "lass erstmal alles in einer datei"), do NOT split into a `settings/` directory. Instead keep the monolithic structure but provide a clean, safe `.example` template.

### Target Structure

```
.
├── settings.nix              # LIVE, .gitignored — user's real config (copied from template)
├── settings.nix.example      # COMMITTED — template with safe defaults, placeholder data, comments
└── .gitignore                # ignores settings.nix, settings.local.nix
```

### Template Requirements

1. **Safe defaults** — every application/feature toggle set to `false` so a fresh clone builds immediately without leaking private data.
2. **Placeholder user** — use a neutral name (e.g. `alice`) with fake email/SSH hosts; real data stays in the ignored live file.
3. **Section comments with types** — each option annotated with valid values and purpose so the file doubles as documentation.
4. **No host-specific data** — resume UUIDs, mount paths, fan controllers belong in `profiles/`, never in `settings.nix` or its template. The template models cross-platform toggles only.
5. **All consumed options present** — cross-check `system/` and `user/` for every `settings.<key>` reference; missing keys in the template cause eval errors when a new user copies it.

### Discovery Pattern in flake.nix

Point directly at `settings.nix`; rely on the user having created it locally from the template. The repo should NOT build without it (the template is documentation, not a fallback build input):

```nix
settingsFile = ./settings.nix;   # user must copy from settings.nix.example
```

### Migration Steps

1. Write the new `settings.nix.example` with safe defaults and clean comments.
2. Add `settings.nix` and `settings.local.nix` to `.gitignore`.
3. Remove `settings.nix` from `.mirror-root-whitelist` (if it was listed).
4. Run `git rm --cached settings.nix` to untrack from index while preserving local file.
5. Validate: `nix flake check --no-build` with the user's existing local `settings.nix`.
6. Commit `settings.nix.example`, `.gitignore`, and whitelist changes together.
7. Do NOT delete the user's local `settings.nix` — it contains real data and must survive the migration.

## Validation Checklist

- [ ] `nix flake check --no-build` passes after refactor
- [ ] Fresh clone builds without `settings.nix` present (tests template fallback)
- [ ] `settings.nix.example` is replaced by `templates/settings/` or removed
- [ ] All imports in `settings/` receive the same arguments as the old monolithic file
- [ ] No duplicate top-level keys introduced across files (recursiveUpdate silently overwrites)
- [ ] Template version has all options consumed by `system/` and `user/` modules
- [ ] Template builds safely with all toggles on `false` (no missing paths, no dead SSH hosts)

## Pitfalls

- **recursiveUpdate overwrites, not merges lists** — if two files define `programs.kitty.extensions = [...]` only the last one wins. Use list-append aliases in the aggregator if list-merging is needed.
- **Stale `.gitignore` after removing ignore rules** — if `settings.nix` was previously committed and is now ignored, it remains tracked until `git rm --cached`. Clean up before the next commit.
- **Template drift** — `templates/settings/` (or `settings.nix.example`) must be treated as an onboarding contract. When real `settings.nix` gains a new field, update the template in the same PR.
- **xdg.configFile with lib.mkIf on `.text`** — writing `xdg.configFile."foo.json".text = lib.mkIf (...) "..."` evaluates `.text` to `null` when the condition is false, causing an attrset type error. Move `lib.mkIf` to the attrset level: `xdg.configFile."foo.json" = lib.mkIf (...) { text = "..."; };`.
- **Forgetting host-specific data in profiles** — when sanitizing `settings.nix` into a template, host-specific values (resume UUIDs, GPU packages, fan controllers) must be moved to the relevant `profiles/*/modules/*.nix`, not left commented-out in the template and not moved into `settings.nix.example`.
