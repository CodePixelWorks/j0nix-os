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

- `settings.userSettings.<name>.wmShell`
- legacy alias: `settings.userSettings.<name>.hyprlandShell`

## DMS Modes

For `dank-material-shell`, behavior is controlled by `settings.dms.mode`:

- `integrated`: Nix-managed runtime, no install script
- `separate`: provides `dms-install` and `dms-uninstall`

Current status:

- `caelestia-shell` is the active migration target and remains supported.
- `dank-material-shell` is temporarily marked broken during the Hyprland Lua migration and should not be selected for user sessions.
