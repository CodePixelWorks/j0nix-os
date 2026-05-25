# Dank Material Shell Analysis

## Source Snapshot
- Flake input: `inputs.dank-material-shell` (`github:AvengeMedia/DankMaterialShell`)
- Locked rev: `babc8feb2bd829f3f7500e8d2ab10f9fe57e13f4`
- Companion source: `inputs.quickshell-overview` (`github:Shanu-Kumawat/quickshell-overview`, rev `cb67d28f8b61ec3aa8d8e54c3d16652a513d53cb`)

## Integration Contract In j0nix-os
- Module: `nix/user/wm/hyprland/shells/dank-material-shell/default.nix`
- Supports `settings.dms.mode = integrated | separate`.
- Package wiring: `j0nix.user.shells.quickshell.packages` via shared list-merge helper.
- Font wiring: `j0nix.user.shells.fonts.packages`.
- Install aggregator: `j0nix.user.software.packages` (through `shells/common/default.nix`).

## Runtime Assumptions
- Integrated mode expects DMS package from flake input.
- Separate mode uses `dms-install`/`dms-uninstall` helpers and user profile artifacts.
- Launcher flow is driven by `wm-shell-start`/`wm-shell-stop` in `nix/user/wm/shell-launcher.nix`.

## Maintenance Notes
- Update this file when DMS mode behavior, source pins, or overview integration changes.
