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
3. Active configuration must live under `j0nix-os/` and be wired by root `flake.nix`.
4. Keep user-facing configuration centralized in `j0nix-os/settings.nix`.
5. Validate changes with `nix flake check --no-build` before finishing.

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
1. Root `flake.nix` loads `j0nix-os/settings.nix`.
2. `mkUserSettings` applies per-user overrides from `settings.userSettings`.
3. System profile from `j0nix-os/profiles/desktop/configuration.nix` is built.
4. Home Manager modules are composed per user from `j0nix-os/user/*`.
5. Hyprland shell module is selected per user via `hyprlandShell`.

### Key Directories
- `j0nix-os/settings.nix`: central settings, feature toggles, per-user overrides
- `j0nix-os/profiles/desktop/`: system + home profile entrypoints
- `j0nix-os/system/wm/`: display manager and system WM modules
- `j0nix-os/system/gaming/`: system gaming modules
- `j0nix-os/system/dev/`: system dev modules (Docker/BuildKit/Codex)
- `j0nix-os/system/tuning/sysctl/`: split sysctl profiles
- `j0nix-os/user/wm/hyprland/shells/`: user-selectable Hyprland shells
- `j0nix-os/user/editors/`: editor modules (VSCode, Neovim)
- `j0nix-os/user/dev/`: user dev toolchain + AI CLI integration
- `j0nix-os/user/gaming/`: user gaming tools and launchers

### Supported Hyprland Shell Modes
For `userSettings.<name>.hyprlandShell`:
- `ags`
- `dank-material-shell`
- `noctalia-shell`

Debug toggle:
- `settings.hyprland.debug.installRawQuickshell`
- Keep disabled with `dank-material-shell` (collision guard is enforced in module assertions).

Associated helper tools:
- DMS mode `integrated`: `dms-start`, `dms-stop`
- DMS mode `separate`: `dms-install`, `dms-start`, `dms-stop`, `dms-uninstall`
- Noctalia: `noctalia-start`, `noctalia-stop` (installed declaratively)

## Key Settings Contracts

### Multi-User
- Users are declared in `settings.users`.
- User behavior is set in `settings.userSettings.<name>`.
- Keep defaults in top-level settings and only override differences per user.

### DMS
Controlled by `settings.dms.*`:
- `mode` (`integrated` or `separate`)
- `startup.mode` (`systemd` or `exec-once`)
- `install.flakeRef`, `install.dgopRef`, `install.cliVersion` (used in `separate` mode)

### Gaming
Controlled by `settings.gaming.*`:
- `steam`, `proton`, `performance`, `controllers`, `launchers`, `extras`

### Dev
Controlled by `settings.dev.*`:
- Docker and build settings
- AI CLI toggles (`codex`, `gemini`)
- Git identity + host overrides (`git.*`)
- SSH agent/keyring/match settings (`ssh.*`)

### Sysctl
Controlled by:
- `settings.sysctlProfiles.fileMax`
- `settings.sysctlProfiles.gaming.*`
- `settings.sysctlProfiles.dev.*`
- `settings.sysctlProfiles.custom`

### Audio
Controlled by:
- `settings.audio.backend` (`pipewire` or `pulseaudio`)
- `settings.audio.bluetooth.enableHiFiCodecs`
- `settings.audio.bluetooth.enableMsbc`
- `settings.audio.bluetooth.codecs`

## Do's and Don'ts

### Do
- Keep modules small and purpose-specific.
- Prefer explicit assertions for invalid user settings.
- Preserve backwards compatibility with sensible `or` defaults.
- Keep README and AGENTS docs aligned with architecture changes.

### Don't
- Don’t add imports to reference folders.
- Don’t hardcode host-specific absolute paths.
- Don’t duplicate package declarations across system/home modules without reason.
- Don’t introduce speculative features not requested.

## Common Tasks

### Add a new user
1. Add username to `settings.users`.
2. Add `settings.userSettings.<name>` block.
3. Set `shell`, `wms`, `defaultSession`, and optionally `hyprlandShell`.
4. Rebuild and set user password.

### Switch Hyprland shell per user
1. Update `userSettings.<name>.hyprlandShell`.
2. Use one of: `ags`, `dank-material-shell`, `noctalia-shell`.
3. Rebuild.

### Extend dev tooling
1. Add system-level components in `j0nix-os/system/dev/default.nix`.
2. Add user-level tools in `j0nix-os/user/dev/default.nix`.
3. Gate new features behind `settings.dev.*` toggles.

## Troubleshooting

### Unknown Hyprland shell assertion
- Check `userSettings.<name>.hyprlandShell` spelling.
- Ensure matching module exists in `j0nix-os/user/wm/hyprland/shells/`.

### Docker permission issues
- Ensure Docker is enabled in `settings.dev.docker.enable`.
- Ensure user is in `docker` group (configured automatically when enabled).
- Re-login after rebuild.

### Input/lock mismatch
- Run `nix flake lock --update-input <name>`.
- Re-run `nix flake check --no-build`.

## Final Reminder

All production configuration work must happen in `j0nix-os/`.
Reference folders are never valid include targets.
