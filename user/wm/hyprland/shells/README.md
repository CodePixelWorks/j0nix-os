# Hyprland Shell Modules

Selectable shell implementations for Wayland WMs (hyprland, mangowc, niri).

## Available Shells

- `ags/`
- `caelestia-shell/`
- `dank-material-shell/`
- `noctalia-shell/`
- `none/`

Each shell keeps an `ANALYSIS.md` with:
- upstream source/pin snapshot from `flake.lock`
- current j0nix integration contract
- dependency/runtime assumptions

## Selection Key

Set globally via:

- `settings.wmShell`
- legacy alias: `settings.hyprlandShell`

## DMS Modes

For `dank-material-shell`, behavior is controlled by `settings.dms.mode`:

- `integrated`: Nix-managed runtime, no install script
- `separate`: provides `dms-install` and `dms-uninstall`
