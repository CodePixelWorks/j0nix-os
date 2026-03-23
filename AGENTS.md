# AGENTS.md

This file provides guidance to coding agents working in this repository.

## Repository Overview

j0nix-os is an independent, modular NixOS setup for gaming and development.

Primary goals:
- Robust daily-driver NixOS configuration
- Multi-user support with per-user customization
- Hyprland-first desktop with optional GNOME
- Strong gaming + dev tooling defaults
- Clear module boundaries and maintainable architecture

## Non-Negotiable Rules

1. Never import local modules from `AlfheimOS/`, `black-don-os/`, or `athena-nix/`.
2. Those folders are reference-only for ideas and patterns.
3. Active configuration must live under the repo root and be wired by root `flake.nix`.
4. Keep user-facing configuration centralized in `settings.nix`.
5. Validate changes with `nix flake check --no-build` before finishing.
6. Before adding a new system script, evaluate whether an existing script, module, or settings contract should be extended instead.
7. System scripts must have a single clear authority, high-quality input/output handling, and no overlapping side effects with other scripts.
8. User-facing outputs from scripts and tooling must be written in English and kept localization-friendly so multilingual usage remains possible.

## Agent Workflow (Required)

Follow this sequence for production changes in this repo:

1. Inspect the relevant modules and settings contracts before editing.
2. Make the smallest coherent change for the requested scope.
3. Validate with `nix flake check --no-build` before finishing (unless the user explicitly interrupts).
4. Commit each completed change scope immediately (do not accumulate unrelated changes).
5. Continue with the next scope in a new commit.

Definition of a "scope":
- One logically complete change that can be described with a single intent.
- Examples: "add a desktop app", "fix a Hyprland keybind", "adjust Bluetooth stability settings".

## Commit Policy (Required)

Agents must create commits during the task, not only at the end, when a scope is finished.

Rules:
- Use Conventional Commits style.
- Create one commit per completed scope.
- Do not bundle unrelated changes into one commit.
- Commit immediately after a completed scope without asking for permission first (unless the user explicitly said not to commit).
- Commit message must clearly state *what* changed and *why* (short subject + optional body).
- Prefer non-interactive git commands.
- When using `git commit -m ...` from a shell, avoid unescaped backticks in the commit body/subject (shell command substitution). Prefer single quotes, escaping, or `git commit -F <message-file>`.

### Conventional Commit Format

Subject line:
```text
type(scope): short summary
```

Examples:
- `feat(desktop): add blender and keepassxc`
- `fix(hyprland): add moonlight-friendly fallback keybinds`
- `docs(hyprland): document keybind overview`
- `refactor(settings): point dotfiles path to repo root`

Allowed common `type` values:
- `feat`
- `fix`
- `docs`
- `refactor`
- `chore`

### Commit Body (Recommended)

Use a commit body for non-trivial changes. This is the "extra description" and should be added when:
- multiple files are touched
- behavior changes
- there is a migration/compatibility implication
- the reason is not obvious from the subject

Recommended template:
```text
type(scope): short summary

- What changed
- Why it changed
- Any caveats or follow-up notes
```

### Commit Timing

- Commit right after a scope is implemented and verified.
- Do not ask "should I commit?" for a finished scope; commit directly and report the commit hash.
- If validation is interrupted by the user, commit only when the user explicitly asks for it or after stating validation was interrupted.
- Keep the working tree clean between scopes whenever possible.

## Common Commands

### Evaluate / Build
```bash
# Validate flake outputs (fast, no build)
nix flake check --no-build

# Show available outputs
nix flake show

# Build and switch current host
sudo nixos-rebuild switch --flake .#Jonas-PC

# Build only (no switch)
sudo nixos-rebuild build --flake .#Jonas-PC

# Debug trace
sudo nixos-rebuild build --flake .#Jonas-PC --show-trace
```

### Flake Maintenance
```bash
# Update all inputs
nix flake update

# Update a single input
nix flake lock --update-input nixpkgs
```

## Architecture

### Configuration Flow
1. Root `flake.nix` loads `settings.nix`.
2. `mkUserSettings` applies per-user overrides from `settings.userSettings`.
3. System profile from `profiles/desktop/configuration.nix` is built.
4. Home Manager modules are composed per user from `user/*`, `profiles/`, and `user-roles/home/`.
5. WM shell layer is selected per user via `settings.userSettings.<name>.wmShell` (legacy alias: `hyprlandShell`).

### Key Directories
- `settings.nix`: central settings, feature toggles, per-user overrides
- `profiles/desktop/`: system + home profile entrypoints
- `system/wm/`: display manager and system WM modules
- `system/lib/`: reusable helper functions/generators for modules (no host/profile data)
- `system/gaming/`: system gaming modules
- `system/dev/`: system dev modules (Docker/BuildKit/Codex)
- `system/tuning/sysctl/`: split sysctl profiles
- `user/wm/hyprland/shells/`: user-selectable Hyprland shells
- `user/editors/`: editor modules (VSCode, Neovim)
- `user/dev/`: user dev toolchain + AI CLI integration
- `user/gaming/`: user gaming tools and launchers

### Supported Hyprland Shell Modes
For `settings.userSettings.<name>.wmShell` (legacy: `hyprlandShell`):
- `ags`
- `caelestia-shell`
- `dank-material-shell`
- `noctalia-shell`
- `none`

Debug toggle:
- `settings.hyprland.debug.installRawQuickshell`
- Keep disabled with `dank-material-shell` (collision guard is enforced in module assertions).

Associated helper tools:
- DMS mode `integrated`: `dms-start`, `dms-stop`
- DMS mode `separate`: `dms-install`, `dms-start`, `dms-stop`, `dms-uninstall`
- Noctalia: `noctalia-start`, `noctalia-stop` (installed declaratively)

## Key Settings Contracts

### Multi-User
- Users are derived from the keys of `settings.userSettings`.
- User behavior is set in `settings.userSettings.<name>`.
- Keep user-specific settings inside `settings.userSettings.<name>`.

### DMS
Controlled by `settings.dms.*`:
- `mode` (`integrated` or `separate`)
- `startup.mode` (`systemd` or `exec-once`)
- `install.flakeRef`, `install.dgopRef`, `install.cliVersion` (used in `separate` mode)

### Gaming
Controlled by `j0nix.desktop.gaming.*` (typically set in `profiles/desktop/modules/gaming.nix`):
- `steam`, `proton`, `performance`, `controllers`, `launchers`, `extras`

### Dev
Controlled by `settings.dev.*`:
- Docker and build settings
- AI CLI toggles (`codex`, `gemini`)
- Git identity + per-host git overrides (`userSettings.<name>.dev.git.*`)
- SSH client policy and host definitions (`userSettings.<name>.dev.ssh.*`)

### Sysctl
Controlled by:
- `settings.sysctlProfiles.fileMax`
- `settings.sysctlProfiles.gaming.*`
- `settings.sysctlProfiles.dev.*`
- `settings.sysctlProfiles.network.*`
- `settings.sysctlProfiles.custom`

### Audio
Controlled by:
- `settings.audio.backend` (`pipewire` or `pulseaudio`)
- `settings.audio.bluetooth.enableHiFiCodecs`
- `settings.audio.bluetooth.enableMsbc`
- `settings.audio.bluetooth.codecs`

### Network
Controlled by:
- `settings.network.tailscale.enable`

## Do's and Don'ts

### Do
- Keep modules small and purpose-specific.
- Evaluate whether existing scripts or modules can absorb the requested behavior before introducing a new script.
- Keep each system script responsible for one clear contract and one authoritative state path.
- Make system scripts robust: explicit inputs, deterministic outputs, predictable cleanup, and no hidden cross-script coupling.
- Keep `profiles/*/modules/` focused on theme/profile configuration (data + simple toggles), not heavy transformation logic.
- Put reusable processing logic (generators, validations, mappers) into `system/*` modules and `system/lib/*` helpers.
- Prefer generic list/attr-driven models (e.g. declarative mount lists) over one-off `fooDisk*` variable trees.
- Use append-style aggregation for extensible config snippets (e.g. `mkAfter` / list aggregation) so modules do not overwrite each other.
- Keep kernel preset/config modules outside `profiles/` (e.g. under `system/`), and let profiles select/import them.
- When modules have software/package requirements, aggregate them into a central install list/module instead of scattering package additions; the aggregation path must deduplicate entries.
- Prefer explicit assertions for invalid user settings.
- Preserve backwards compatibility with sensible `or` defaults.
- Keep README and AGENTS docs aligned with architecture changes.

### Don't
- Don’t add imports to reference folders.
- Don’t create a new system script when extending an existing script or module would keep the architecture simpler.
- Don’t let multiple scripts mutate the same runtime file, service, or state path without a single declared owner.
- Don’t ship user-facing script output in ad-hoc mixed languages; default to English and keep phrasing localization-friendly.
- Don’t hardcode host-specific absolute paths.
- Don’t duplicate package declarations across system/home modules without reason.
- Don’t put host/profile-specific data into `system/lib/*`.
- Don’t put reusable logic helpers into `profiles/*`.
- Don’t introduce speculative features not requested.

## Common Tasks

### Add a new user
1. Add a new `settings.userSettings.<name>` block.
2. Configure per-user settings (editors, browsers, roles, programs, dev, secrets).
3. Set `shell` and `defaultWMS` (`hyprland` | `gnome` | `mangowc` | `niri`).
4. Rebuild and set user password.

### Switch WM shell layer
1. Update `settings.userSettings.<name>.wmShell` (or legacy `hyprlandShell` inside that user block).
2. Use one of: `ags`, `dank-material-shell`, `noctalia-shell`, `none`.
3. Rebuild.

### Extend dev tooling
1. Add system-level components in `system/dev/default.nix`.
2. Add user-level tools in `user/dev/default.nix`.
3. Gate new features behind `settings.dev.*` toggles.

## Troubleshooting

### Unknown WM shell assertion
- Check `settings.userSettings.<name>.wmShell` spelling.
- Ensure matching module exists in `user/wm/hyprland/shells/`.

### Docker permission issues
- Ensure Docker is enabled in `settings.userSettings.<name>.dev.docker.enable`.
- Ensure user is in `docker` group (configured automatically when enabled).
- Re-login after rebuild.

### Input/lock mismatch
- Run `nix flake lock --update-input <name>`.
- Re-run `nix flake check --no-build`.

### Hyprland 0.53.2+ rule syntax
- `windowrulev2` is treated as removed/deprecated in practice; prefer `windowrule`.
- Rule flags now require explicit values (`float 1`, `center 1`, `pin 1`).
- Use snake_case field names (`no_blur`, `initial_title`).
- `idleinhibit` rule is removed; use `hypridle` instead.
- When migrating old dotfiles (e.g. JaKooLit-based), expect strict parser errors instead of warnings.

## Final Reminder

All production configuration work must happen in the repo root (`j0nix-os/`).
Reference folders are never valid include targets.
