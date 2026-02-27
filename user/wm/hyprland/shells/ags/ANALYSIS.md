# AGS Shell Analysis

## Source Snapshot
- Flake input: `inputs.ags` (`git+https://github.com/Aylur/ags`)
- Locked rev: `60180a184cfb32b61a1d871c058b31a3b9b0743d`

## Integration Contract In j0nix-os
- Module: `user/wm/hyprland/shells/ags/default.nix`
- Package wiring: `j0nix.user.software.packages`.
- Waybar is forced off for shell ownership consistency.

## Runtime Assumptions
- Requires `inputs.ags.homeManagerModules.default`.
- Uses ags runtime packages (`ags`, `bun`, `dart-sass`, `gjs`, `gtk3`, `networkmanager`, `pavucontrol`).

## Maintenance Notes
- Update this file when AGS module source, runtime dependencies, or startup strategy changes.
