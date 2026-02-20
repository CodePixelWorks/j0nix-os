# Hyprland Shell Modules

Selectable shell implementations for Hyprland.

## Available Shells

- `ags/`
- `dank-material-shell/`
- `noctalia-shell/`

## Selection Key

Set via:

- `settings.hyprlandShell`
- or `settings.userSettings.<name>.hyprlandShell`

## DMS Modes

For `dank-material-shell`, behavior is controlled by `settings.dms.mode`:

- `integrated`: Nix-managed runtime, no install script
- `separate`: provides `dms-install` and `dms-uninstall`
