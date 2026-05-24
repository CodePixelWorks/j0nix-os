# j0nix-os Documentation

Single source of truth for architecture, subsystem docs, and operational runbooks.

For agent coding rules and commit policy, see [`AGENTS.md`](../AGENTS.md) in the repo root.

## Table of Contents

| Doc | Audience | Topic |
|-----|----------|-------|
| [architecture.md](./architecture.md) | Contributors, agents | Flake graph, module layers, settings resolution, multi-user model |
| [ci-pipeline.md](./ci-pipeline.md) | DevOps, maintainers | Drone CI mirror pipeline, environment variables, sync modes |
| [startup-flow.md](./startup-flow.md) | Contributors, debuggers | WM startup order: DM -> compositor -> shell -> apps |
| [qmlgreet.md](./qmlgreet.md) | Users, contributors | QMLGreet greeter config, theming inputs, compositor paths |
| [dms.md](./dms.md) | Users | Dank Material Shell wallpaper, startup mode, workspace config |
| [keybinds.md](./keybinds.md) | Users | Current keybind reference (default: caelestia-shell) |
| [caelestia.md](./caelestia.md) | Debuggers | Keybind regression runbook: isolation matrix, diagnostics, fix strategy |
| [secrets.md](./secrets.md) | Users | SOPS-nix quickstart: host key, user key, `.sops.yaml`, SSH secrets |

## Per-Directory READMEs

These give context for their local scope and should stay close to the code:

| Directory | README |
|-----------|--------|
| `profiles/` | `profiles/README.md` — Profile composition overview |
| `profiles/desktop/` | `profiles/desktop/README.md` — Desktop profile entrypoints |
| `system/` | `system/README.md` — System module categories |
| `system/wm/` | `system/wm/README.md` — Display manager + WM integration |
| `system/gaming/` | `system/gaming/README.md` — Gaming stack reference |
| `user/` | `user/README.md` — Home Manager module categories |
| `user-roles/` | `user-roles/README.md` — Role naming and composition rules |
| `themes/` | `themes/README.md` — Theme contract |
