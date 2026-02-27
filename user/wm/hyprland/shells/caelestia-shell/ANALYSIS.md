# Caelestia Shell Analysis

## Source Snapshot
- Flake input: `inputs.caelestia-shell` (`github:caelestia-dots/shell`)
- Locked rev: `71f291f79bf7c35ad7db2c0061efc80cf768426a`
- CLI source: `inputs.caelestia-cli` (`github:caelestia-dots/cli`, rev `a6defd292136ac3a52fb0d39f045a0882dda6354`)
- Quickshell source: `git+https://git.outfoxxed.me/outfoxxed/quickshell` (rev `dacfa9de829ac7cb173825f593236bf2c21f637e`)

## Integration Contract In j0nix-os
- Module: `user/wm/hyprland/shells/caelestia-shell/default.nix`
- Package wiring: `j0nix.user.shells.quickshell.packages` via shared list-merge helper.
- Font wiring: `j0nix.user.shells.fonts.packages` (Material Symbols + Nerd fonts).
- Install aggregator: `j0nix.user.software.packages` (through `shells/common/default.nix`).

## Runtime Assumptions
- Requires shell input to expose either:
  - `homeManagerModules.default`, or
  - `packages.<system>.with-cli` / `packages.<system>.default`
- Startup/stop entrypoints are `caelestia-start` and `caelestia-stop`.

## Maintenance Notes
- Update this file when the input source, major dependency contract, or startup flow changes.
