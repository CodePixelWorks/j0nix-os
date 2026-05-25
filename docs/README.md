# j0nix-os Documentation

Single source of truth for architecture, subsystem docs, and operational runbooks.

For agent coding rules and commit policy, see [`AGENTS.md`](../AGENTS.md) in the repo root.

## Table of Contents

| Doc | Audience | Topic |
|-----|----------|-------|
### Desktop / Window Manager

| Doc | Audience | Topic |
|-----|----------|-------|
| [qmlgreet.md](./wm/qmlgreet.md) | Users, contributors | QMLGreet greeter config, theming inputs, compositor paths |
| [dark-material-shell.md](./wm/quickshell/dark-material-shell.md) | Users | Dark Material Shell wallpaper, startup mode, workspace config |
| [keybinds.md](./wm/keybinds.md) | Users | Current keybind reference (default: caelestia-shell) |
| [caelestia.md](./wm/quickshell/caelestia.md) | Debuggers | Keybind regression runbook |
| [startup-flow.md](./wm/startup-flow.md) | Contributors, debuggers | WM startup order: DM -> compositor -> shell -> apps |

### DevOps / CI

| Doc | Audience | Topic |
|-----|----------|-------|
| [ci-pipeline.md](./devops/ci-pipeline.md) | DevOps, maintainers | Drone CI mirror pipeline, environment variables, sync modes |

### Operations / Security

| Doc | Audience | Topic |
|-----|----------|-------|
| [secrets.md](./operations/secrets.md) | Users | SOPS-nix quickstart: host key, user key, `.sops.yaml`, SSH secrets |

## Per-Directory READMEs

These give context for their local scope and should stay close to the code:

| Directory | README |
|-----------|--------|
| `profiles/` | `profiles/README.md` — Profile composition overview |
| `profiles/desktop/` | `profiles/desktop/README.md` — Desktop profile entrypoints |
| `nix/system/` | `nix/system/README.md` — System module categories |
| `nix/system/wm/` | `nix/system/wm/README.md` — Display manager + WM integration |
| `nix/system/gaming/` | `nix/system/gaming/README.md` — Gaming stack reference |
| `nix/user/` | `nix/user/README.md` — Home Manager module categories |
| `nix/roles/` | `nix/roles/README.md` — Role naming and composition rules |
| `themes/` | `themes/README.md` — Theme contract |
