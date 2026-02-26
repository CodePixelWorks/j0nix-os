# Hyprland Shell Modules

Selectable shell implementations for Wayland WMs (hyprland, mangowc, niri).

## Available Shells

- `ags/`
- `caelestia-shell/`
- `dank-material-shell/`
- `noctalia-shell/`
- `none/`

## Selection Key

Set globally via:

- `settings.wmShell`
- legacy alias: `settings.hyprlandShell`

## DMS Modes

For `dank-material-shell`, behavior is controlled by `settings.dms.mode`:

- `integrated`: Nix-managed runtime, no install script
- `separate`: provides `dms-install` and `dms-uninstall`
