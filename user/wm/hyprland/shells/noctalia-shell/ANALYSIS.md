# Noctalia Shell Analysis

## Source Snapshot
- Flake input: `inputs.noctalia` (`github:noctalia-dev/noctalia-shell`)
- Locked rev: `487afcea420cd32050776948418241e70eb1472d`

## Integration Contract In j0nix-os
- Module: `user/wm/hyprland/shells/noctalia-shell/default.nix`
- Package wiring: `j0nix.user.shells.quickshell.packages` via shared list-merge helper.
- Font wiring: `j0nix.user.shells.fonts.packages`.
- Install aggregator: `j0nix.user.software.packages` (through `shells/common/default.nix`).

## Runtime Assumptions
- Requires input to expose either:
  - `homeModules.default`, or
  - `packages.<system>.default`
- Startup/stop entrypoints are `noctalia-start` and `noctalia-stop`.

## Maintenance Notes
- Update this file whenever the upstream input pin or JSON settings contract changes.
