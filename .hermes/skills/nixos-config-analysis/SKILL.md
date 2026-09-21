---
name: nixos-config-analysis
description: Systematic analysis of NixOS flake configuration repositories for understanding and improvement opportunities.
triggers:
  - Analyze a NixOS flake repository
  - Review NixOS configuration for improvements
  - Understand a NixOS project structure
  - Audit NixOS system or home-manager configuration
  - Find refactoring opportunities in nix configs
---

# NixOS Config Analysis

Use this skill when asked to understand, review, audit, or find improvement opportunities in a NixOS flake configuration repository (including Home Manager and custom module-based setups).

## Entry Point / File Order

Always read in this sequence to understand the architecture before making any conclusions:

1. **flake.nix** — Identifies `nixosConfigurations`, `homeConfigurations`, flake inputs, overlays, and the entry-point module chain
2. **settings.nix** (or equivalent) — The central settings contract; reveals users, features, defaults, roles, and host overrides
3. **integrations/** — Vendored subflakes / external NixOS modules imported as flake inputs (`path:./integrations/...`). Must use `follows` for nixpkgs/home-manager to keep versions aligned with the main flake.
4. **profiles/*/configuration.nix** — The system profile wiring (imports kernel, audio, gaming, WM modules)
5. **profiles/*/modules/*.nix** — Profile-specific overrides and toggles
6. **nix/system/** — System-level modules (WM, audio, networking, drivers, tuning)
7. **nix/user/** — Home Manager modules (shells, editors, browsers, desktop, programs)
8. **nix/roles/** — Role bundles (system/ + home/ pairs: gaming, developer, office, streaming, etc.)
9. **nix/system/lib/** — Reusable generators, validators, aggregators (not host-specific)
10. **themes/** — Theme/color/icon contracts

### Recommended Directory Structure

For medium-to-large module-based NixOS flakes, consolidate all Nix module code under a single `nix/` directory. This separates code from repo-level resources (docs, scripts, assets, templates) and communicates the architecture at a glance:

```
flake.nix              # Entry point, host mapping, flake inputs
settings.nix           # Central settings contract
profiles/              # Host-specific hardware + secrets
  desktop/
    configuration.nix
    home.nix
    modules/
    secrets.nix
    details.nix
nix/                   # ALL Nix code — system, user, roles
  system/              # NixOS modules
    wm/
    audio/
    gaming/
    drivers/
    lib/               # Reusable helpers, overlays, generators
  user/                # Home Manager modules
    shells/
    editors/
    wm/
    dev/
    gaming/
  roles/               # Role bundles (system/ + home/ pairs)
    system/
    home/
integrations/          # Vendored subflakes
secrets/               # SOPS secrets
themes/                # Stylix theme contracts
docs/                  # Markdown documentation
scripts/               # CI helpers, generators, mirror scripts
templates/             # Template files (README generator, .example files)
wallpapers/            # Static assets
icons/                 # App icons
```

**Pros:**
- Root stays clean — repo-level resources are distinguishable from Nix code at a glance.
- `nix/` becomes the single authority for "all code that goes into the flake evaluation".
- Traversal patterns are simpler (`find nix/ -name '*.nix'`) and `.gitignore` is easier to reason about.
- Newcomers immediately understand: `nix/` = flake code, everything else = assets/scripts/docs.

**Cons:**
- Relative imports inside `nix/` need adjustment if moved from root — use `git mv` followed by a mass-replace pass on `import` paths.
- Files referencing root-level dirs (e.g., `../../../icons/` from `nix/user/programs/foo/default.nix`) gain one extra `../` level.
- `baseDir` or `repoRoot` path strings in helper functions must be updated (e.g., `baseDir + "/system/lib/"` → `baseDir + "/nix/system/lib/"`).

When migrating, do it in three phases:
1. `git mv system nix/system && git mv user nix/user && git mv user-roles nix/roles`
2. Update all imports: `baseDir + "/system/` → `baseDir + "/nix/system/`, profile imports `../../system/` → `../../nix/system/`, etc.
3. Update any root-level relative paths (icon/image references to `icons/`, `wallpapers/`) — these gain one extra `../` because of the `nix/` parent.

Verification after migration:
```bash
nix flake check --no-build

# Also verify no stale root-level dirs remain:
rmdir system user user-roles 2>/dev/null
ls -d system user user-roles 2>/dev/null && echo "Dangling dirs found"
```

## Baseline Evaluation First

Before deep reading, kick off `nix flake check --no-build` as a BACKGROUND
terminal process and continue reading files while it evaluates. Whole-flake
eval errors (option merge conflicts, type clashes, failed assertions) are
VERIFIED bugs — they outrank every static finding and usually become the
report headline. Repos can look clean locally while latent breakage hides
from narrow scoped evals; only the full-flake baseline exposes it. If red,
lead with it; if green, you also gain confidence that later findings are
improvement opportunities rather than symptoms.

## Search Patterns for Quick Win Detection

Run these searches early; they surface issues before deep reading:

```bash
# Legacy / deprecation / debt markers
grep -rn "TODO\|FIXME\|HACK\|TEMP\|BUG\|legacy\|deprecated" --include="*.nix" .

# Duplicate top-level attrset blocks in a single file (Nix merges them silently)
grep -rn "^  \w\+ = {$" --include="*.nix" . | grep -v "let\|in"
# Then verify each file with repeated keys is actually a single merged attrset:
#   grep -n "^  programs = {$" file.nix   # should show only one match per file
# If two matches, check offsets to see if they're truly separate declarations.

# String-literal references to a known-broken feature (for fallback cleanup)
# Replace 'broken-feature' with the actual name found in assertions
grep -rn '"broken-feature"' --include="*.nix" .
# Also check theme files which often set shell/wm defaults:
grep -rn '"broken-feature"' --include="*.nix" themes/

# Broken / temp assertions
grep -rn "broken.*migration\|temporarily broken\|temporarily marked" --include="*.nix" .

# TEMP comments that may have fossilized into permanent config
grep -rn "TEMP" --include="*.nix" . | grep "= true\|= false"

# File size audit (anything > 500 lines deserves scrutiny)
find . -name '*.nix' -exec wc -l {} + | sort -rn | head -20
```

## Analysis Dimensions

Evaluate each dimension and list findings with concrete file:line references.

### 0. Thin-Pipe Profile Modules
Profile modules (`profiles/*/modules/*.nix`) should be *thin pipes* — they pass settings through to system/home modules without duplicating defaults or physical wiring (packages, `pkgs` references, enable-logic). If a profile module contains package lists, hardcoded defaults, or assertions that shadow `settings.nix`, it is doing too much. Physical wiring belongs in `system/`; profile modules should read `settings.*` and assign it to the corresponding `j0nix.*` or `config.*` option.

**Exception**: Host-specific data (resume UUIDs, `resumeOffset`, fan controller configs, kernel module names, kernel params) belongs *in the profile module*, not in `settings.nix`. Settings is for cross-platform feature toggles; profiles are for machine-local constants that another host would never reuse. Do NOT thin-pipe host-specific data into settings — that destroys the settings/profiles boundary.

### 2. Settings Architecture
- Is there a single `settings.nix` or are settings scattered?
- Are there duplicate top-level attrset keys (e.g. two `programs = { ... }` blocks)?
- Is the merge logic clean (baseSettings + userOverrides + themeDetails)?
- Are deprecated aliases still exposed as defaults (e.g. `hyprlandShell` as fallback)?
- **Does a setting select between multiple flake inputs?** If `settings.*.channel` or similar toggles between `stable` and `dev` inputs, map the active value to the actual `inputs.<name>` before updating locks. See `references/settings-driven-flake-input-selection.md`.

### 2. Broken Defaults
- Does a default value point to a known-broken feature?
- Are assertions in place, but the default still triggers them?
- Is a `TEMP`/`FIXME` hardcoded as the active configuration?
- **Theme files deserve scrutiny**: `themes/*.nix` often set shell/wm defaults that override or shadow user settings. A theme setting `shell = "broken-shell"` will silently propagate even when users explicitly choose a different shell.

### 2b. Module Settings Priority Conflicts (framework vs operator hatch)
Modules that expose a freeform `settings` passthrough (`types.attrs`) AND map
their own typed options into the same upstream settings block are a latent
merge-conflict class. If both write the same key at default priority (100),
evaluation of every host dies with "conflicting definition values" — even when
both sides agree on the value. Audit with:
```bash
grep -rn "settings = mkMerge\|// cfg.settings\|cfg.settings$" modules/
```
For each hit, check whether derived keys and the passthrough can collide, and
whether consumers actually override framework-derived keys. Fix: wrap derived
values in `lib.mkDefault` (or `mkOverride 900`) so operators win; migrate
consumers to the typed options. See `references/module-settings-priority-conflicts.md`
for a full case study (headscale DNS whole-flake outage) and the sibling trap
of eval-check assertions left asserting literals a later module fix changed —
locate ownership fast with `git log -S "<stale literal>" -- tests/ modules/`.

### 3. Duplication
- Same window rules / keybinds / assertions defined twice?
- Identical logic copied between `system/` and `user/` instead of using shared lib?

### 4. File Size / Concern Splitting
- Files > 500 lines: could they be split into focused submodules?
- Files mixing generated config + package lists + activation scripts?

### 5. Localization
- Hardcoded locale-specific strings (e.g. German dialog titles) that break on non-German systems?
- User-facing output in a language other than the configured locale without toggle?

### 6. Consistency
- Does the README / AGENTS.md match the actual code (option names, valid values)?
- Are example/template files synced with real configs?

### 7. Dead Code & Misplaced Data (Architecture Boundaries)
## Dead Code & Misplaced Data (Architecture Boundaries)
- **`.public-export/`, `.private/`, `export/`, `mirror/` directories**: Search for complete repo copies that drift out of sync. If a public export exists, check whether it is generated by a script or committed manually; manual copies are almost always stale and should be replaced by an on-demand export script.
- **Empty placeholder files**: `system/lib/types.nix` and similar zero-byte files that have no imports and no references. These are fossil scaffolding from early design phases.
- **Host-specific data in settings.nix**: Settings is for cross-platform feature toggles and user preferences that stay correct across different machines. If you see `resumeDevice`, `resumeOffset`, fan controller configs (`it87`, `hwmonName`), kernel module blacklists, or per-device GPU package versions in `settings.nix`, that data belongs in the profile module (`profiles/*/modules/*.nix`).
- **Profile modules containing cross-platform toggles**: Conversely, if a profile module hardcodes a feature toggle (e.g. `steam.enable = true`, `docker.enable = true`) that a different host might want to disable, consider whether it belongs in `settings.nix` instead.

**Cross-check rule**: Ask "would a laptop or server need to override this?" If yes → settings. If no → profile.

## Output Format

Present findings sorted by **impact** (not by file order):

- **Kritisch**: Broken defaults, duplicate keys causing merge issues, assertions that always fire
- **Hoch**: Duplizierte Logik, Defaults die auf broken Features zeigen, Legacy Aliases als primrer Wert
- **Mittel**:berschreitende Dateien, gemischte Concerns, inkonsistente Hierarchie
- **Niedrig**: TEMP-Kommentare die sedimentiert sind, Debug-Telemetry default aktiviert, Localization-Lcken

For each finding include:
- File path and line number
- Concrete current code
- Why it's a problem
- Recommended fix

### Audit Workflow Contract (Jonas, learned 2026-08-24)

When asked to audit/review ("Analysiere das Projekt und auditiere es"):

1. Deliver ONE consolidated report in German, severity-sorted (Kritisch → Hoch
   → Mittel → Niedrig), each finding with file:line + symptom + root cause +
   fix. End with a proposed fix ORDER. Do NOT start fixing uninvited.
2. Jonas then drives fixes slice by slice ("fix K1", "mach weiter mit den
   offenen punkten", "go"). Apply fixes directly via tools.
3. VERIFICATION DISCIPLINE — explicit correction: "mach nicht so viele checks,
   die dauern lange — wir sammeln erstmal und checken dann durch". Verify each
   fix with TARGETED builds (`nix build .#checks.x86_64-linux.<check>`,
   toplevel builds for renderer changes); run ONE full `make check` /
   `nix flake check` at the END of the batch only. Never fire repeated full
   flake checks mid-session; expect layered failures and peel them with
   batched targeted builds instead.
4. Domain boundaries: state them explicitly when touching adjacent concerns
   (e.g. headscale `dns.*` = tailnet-side DNS pushed to mesh clients,
   independent of host `services.resolved`) and never unify them silently.
5. Shared renderers/publishing paths: state the invariant ("App-Renderer
   dürfen nicht kaputt gehen"), then prove non-regression by building an
   app-only host AND a stack-using host toplevel before/after.
6. Commits only on request ("leg erstmal die commits an"): Conventional
   Commit scopes, signed, one concern per commit, body carries
   symptom/root-cause/verification. Push NOT included unless asked.

### 8. Documentation Surface Maintenance
When architecture changes occur, the documentation surface must be updated in the same commit scope — never deferred. This prevents drift between code and docs.

**README**: Must stay in sync with actual options, valid values, and build commands. If a new feature category is added (e.g. `dev.ai.codex`), the README's settings contract table must include it.

**Contributing / Open Tasks**: Maintain a `Contributing` section with an explicit TODO table. Known gaps that don't have immediate priority should be listed so contributors can pick them up. Each row needs: task name, status, and enough context (e.g. "currently using hacky Stylx theme") to orient a newcomer.

**AGENTS.md**: Is living documentation, not a charter. When an architecture principle is clarified or a rule is removed (e.g. reference-only directories no longer exist), update AGENTS.md immediately. Renumber rules when items are deleted to keep the list contiguous.

**Docs folder structure**: As the project grows, a flat `docs/` folder becomes hard to navigate. Restructure into topical subdirectories (`wm/`, `devops/`, `operations/`, etc.) and further subgroups by technology family (`wm/quickshell/`, `wm/ags/`). Use full product names in filenames, not abbreviations. See `references/docs-restructuring-patterns.md` for the full migration procedure and verification checklist.

**Stale References**: Search for references to external projects, directories, or upstream sources that may no longer exist or are no longer relevant. Clean up:
- Upstream source URLs in READMEs of vendored assets (wallpapers, themes)
- Convention bullets naming deleted reference directories
- Code comments referencing external projects (e.g. "Keep parity with black-don behavior")
- AGENTS.md rules prohibiting imports from non-existent directories

Use `grep -rn` to find all occurrences before deleting the directory or concept, then clean every reference site.

**Example Files**: When real config changes (new fields, removed fields, changed defaults), `.example` templates must be updated in the same PR. Treat example files as an onboarding contract — a fresh clone should produce a valid starting point.

Checklist for architecture change:
- [ ] Real config updated
- [ ] Example files updated (all `.example` templates)
- [ ] README mentions changed/removed options
- [ ] AGENTS.md rules updated if boundaries shifted
- [ ] Stale references cleaned (grep + remove)
- [ ] Conventional Commits used (e.g. `docs(readme):`, `refactor(flake):`)
- [ ] `nix flake check --no-build` passed

- **Do not trust comments**: A `TEMP` comment from 6 months ago is often permanent. Verify if it's still needed.
- **Don't assume defaults are harmless**: In Nix/attrset merges, defaults that reference broken features can silently fail or trigger assertions during build.
- **Legacy aliases propagate far**: If `hyprlandShell` is kept as a fallback, grep for every occurrence to understand blast radius before removing.
- **Settings.nix is the contract**: Most bugs stem from settings that are read but never validated, or validated differently in system vs home modules.
- **Eval-check assertions are behavior contracts**: When a module fix changes a rendered value (URLs, paths, defaults), grep the `tests/*-eval.nix` files for the old literal — stale assertions turn green pipelines red and nobody updated them with the fix.
- **Render chains escape eval coverage**: Custom config renderers that write per-item files (vhosts, drop-ins) and a glob `include` elsewhere can silently produce dead files on hosts lacking the including stack. Eval tests assert option values, not the generated file graph — verify with a VM test or by grepping the rendered output.
- **Flake inputs != runtime packages**: Check overlays to understand how inputs are transformed; the input name and the installed package name may differ.

- **Monolithic settings.nix → Modular settings/ Refactor**: `references/monolithic-settings-refactor-pattern.md` — splitting a 1000+ line `settings.nix` into a modular `settings/` directory with a thin wrapper, template fallback, and flake discovery chain. Includes the **template-based monolith alternative** (single `.example` file with safe defaults) for when the user explicitly wants to keep everything in one file.
- **AI-Ergonomic Docs Layering + Module Split Mechanics**: `references/docs-layering-and-module-split-patterns.md` — Phase 2/3 of the nixos-server-base optimization: documentation authority split (each fact in exactly one layer; module-status never restates README usage), per-directory <1KB AGENTS.md signposts (dedupe BEFORE adding guides), and the monolithic stack-module split recipe with the `nix-instantiate --parse` assembly check and eval+VM verification requirement.

## Related Skills

- **nixos-server-module-development**: Extending and fixing NixOS server-base modules (authentik, matrix, gitea, OIDC integrations). Covers Python-in-Nix pitfalls, foldl' merge bugs, Synapse OIDC extra, SOPS secrets, and verification workflow. Use when *adding features* to server modules; use this skill (nixos-config-analysis) when *auditing/reviewing* existing configs. Its `references/audit-2026-08-framework-findings.md` holds the complete nixos-server-base audit findings (K1 equal-priority settings collisions, dead nginx vhost includes, the checkmkAgent unguarded-reference rollout with both guard patterns, backup include* API break, atticd environmentFile convention gap) plus the batched-targeted-builds verification discipline Jonas requires.

## References

- **Role-Scoped Program Imports & Global Defaults**: `references/role-scoped-program-imports.md` — attaching program modules to roles via `imports`, plus the `defaultHomePrograms` / `homePrograms` per-user override mechanism in `mk-home-modules.nix`.
- **FHS/Wayland App Wrapping**: `references/fhs-wayland-xwayland-wrapper.md` — fixing GTK/Qt file dialogs and crashes for FHS/binary apps under XWayland with `symlinkJoin` + `makeWrapper`.
- **Python Runtime Library Injection**: `references/python-runtime-library-injection.md` — injecting missing Python dependencies into an existing Nix binary's runtime environment without modifying the upstream derivation, using `makeWrapper --prefix PYTHONPATH :` and an overlay shim.
- **PyPI Package to Nix Build**: `references/pypi-package-to-nix.md` — building a Python package from PyPI as a Nix derivation when it is not in nixpkgs: version discovery with `nix-prefetch-url`, handling `setuptools`/`poetry`/`pyproject` builds, and resolving missing transitive dependencies iteratively.
- **Flatpak Program Module Pattern**: `references/flatpak-program-module.md` — adding apps only available as Flatpak to the NixOS flake via Home Manager `services.flatpak.packages`.
- **Adding User Roles (Recipe)**: `references/adding-user-roles-pattern.md` — minimal deterministic recipe for adding home-only or system+home roles, package discovery, and `rolesWithSystemModules` registration.
- **Cross-Module Integration Coverage Audit**: `references/cross-module-integration-coverage-audit.md` — systematic technique for finding gaps where modular stacks fail to register hooks in shared subsystems (checkmk agent, restic, nginx, SELinux registry, etc.). Includes grep patterns, classification rules, and common guard pitfalls.
- **Module Settings Priority Conflicts**: `references/module-settings-priority-conflicts.md` — case study of a whole-flake eval outage caused by a framework's derived settings colliding with the freeform operator passthrough at equal priority; includes fix pattern, audit grep, severity guidance, and the orphaned-eval-assertion sibling trap.
- **Settings Passthrough Priority Collisions**: `references/settings-passthrough-priority-collisions.md` — companion to the above: mkDefault fix shape, consumer migration grep, cross-stack global-option ownership (mkForce vs conditional mkIf write), sweep candidates, and the Nix `''` string escaping traps hit while patching shell-in-Nix blocks.
- **Nginx Vhost Include Chain**: `references/nginx-vhost-include-chain.md` — how the proxy stack's per-vhost files actually get loaded (single glob inside the rendered http block), the audit bug where app vhosts were dead files without the web stack, the build-and-grep verification recipe, and the appendConfig top-level-context trap for nginx.custom.conf.
- **Nix CI Pipeline Discovery**: `references/nix-ci-pipeline-discovery.md` — finding CI configs in self-hosted Git environments (Drone, Forgejo, Woodpecker), the `nixos/nix` container experimental-features trap, and step disabling patterns.
- **Settings vs Profiles Boundary**: `references/session-settings-vs-profiles-boundary.md` — host-specific data belongs in profiles, cross-platform toggles in settings.nix.
- **Settings-Driven Flake Input Selection**: `references/settings-driven-flake-input-selection.md` — mapping `settings.*.channel` (or similar selectors) to the actual flake input name before running `nix flake lock --update-input`.
- **Keybind Module Hierarchy**: `references/session-j0nix-os-keybind-refactor.md` — splitting monolithic Nix files into `lib.nix` + `core.nix` + `shells.nix` with typed bind data model.
- **Flake explicit host mapping**: `references/flake-explicit-host-mapping.md` — removing `profileName` from `settings.nix` and making host→profile mapping explicit in `flake.nix` to support multi-host.
- **Git commit message escaping**: `references/git-commit-message-escaping.md` — safe `git commit -F /tmp/msg.txt` pattern for messages containing backticks, Nix interpolation, or shell-sensitive characters.
- **QMLGreet button cleanup**: `references/qmlgreet-button-cleanup.md` — inspecting upstream QML source via `nix eval <pkg>.src.outPath`, patching with `sed` in `postPatch`, and avoiding stale `.gitignore` rules.
- **README Contributing / Open Tasks**: `references/readme-contributing-open-tasks.md` — pattern for a Contributing section with a gap table so newcomers know where help is needed.
- **Hyprland Dispatcher Scripting Patterns**: `references/hyprland-dispatcher-scripting.md` — `resizewindowpixel` vs `resizeactive` (absolute vs delta sizing), toggle→query→conditional action pattern, and wiring custom scripts into Home Manager keybinds.
- **Nix Eval in Shell Anti-Pattern**: `references/nix-eval-in-shell-anti-pattern.md` — why inline `nix eval --expr` inside bash is fragile, the `--expr 'import ...'` pattern for subdirectory .nix files, `or`-in-lambda pitfall, and bash stdout scope traps.
- **Nix Package Source Inspection and Patching**: `references/nix-package-patching-patterns.md` — inspecting upstream QML/C++/GTK source via `pkgs.foo.src.outPath`, choosing between `sed`, `substituteInPlace`, and `.patch` files, and rebuilding without forking upstream.
- **Rust Package to Nix Build**: `references/rust-package-to-nix.md` — building a Rust application from source with `buildRustPackage` when it is not in nixpkgs: hash discovery, workspace dependency version mismatch diagnosis, `postPatch = "cargo update --workspace"`, and when to prefer OCI containers instead.
- **AppImage Integration Pattern**: `references/appimage-integration-pattern.md` — adding a third-party AppImage into a NixOS flake: hash prefetch, `appimageTools.wrapType2`, overlay wiring, minimal HM module, icon/desktop handling, real build verification, validation.
- **Settings Scope in Home Manager Modules**: `references/settings-scope-in-hm-modules.md` — `settings` in HM modules is already per-user merged from `mkUserSettings`. Never double-traverse with `settings.userSettings.<name>` or hardcode usernames.
- **NixOS Lab VM Workflow Pitfalls**: `references/nixos-lab-vm-workflow-pitfalls.md` — untracked files in flake repos, `lib.mkForce` for QEMU port forwards, eval-vs-build distinction, and the git-add requirement before Nix can see new files.
- **GPG Key Deployment via sops-nix**: `references/gpg-key-deployment-sops-nix.md` — full workflow for adding SOPS-backed GPG keys: generation, YAML insertion, settings.nix registration, singular vs plural `keygrip` handling, and post-deploy verification.
- **SOPS Secret Migration Between Repos**: `references/sops-secret-migration-pattern.md` — moving SOPS-encrypted material between files / repos: `chmod 700`/`600` temp contract, `sops --filename-override` vs explicit `--age` recipients, `lib/` path-resolution bug, backward-compat fallback pattern, lockfile-bump sequencing. Companion script: `scripts/sops-migrate-between-repos.sh`.
- **AppImage Package Location Pattern**: `references/appimage-package-location-pattern.md` — canonical location for AppImage packages (`system/software/pkgs/` vs `user/programs/`), decision rules, and migration examples.
- **Program Module Enable Consistency**: `references/program-module-enable-consistency.md` — ensuring all program HM modules have an `enable` toggle, default to `or false`, and are wired through `settings.nix` + `settings.nix.example`.
- **Stale .gitignore Rule Cleanup**: `references/gitignore-stale-rule-cleanup.md` — hazard of removing ignore rules for files that still exist in working tree, and the procedure to avoid accidental re-introduction.
- **Example File Drift**: `references/session-j0nix-os-example-file-drift.md` — keeping `.example` files in sync with real config as an onboarding contract.
- **Vendored Subflake Integration**: `references/vendored-subflake-integration-pattern.md` — embedding third-party NixOS/HM modules as local `integrations/` subflakes with `path:` inputs and `follows` pinning.
