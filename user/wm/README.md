# User WM Modules

User-space WM behavior and home-level WM composition.

## Files

- `hyprland/default.nix`: core Hyprland user config
- `niri.nix`: Niri user config
- `hyprland/shells/*`: selectable Hyprland shell modules
- `shell-launcher.nix`: generic shell launcher for hyprland/mangowc/niri
- `mangowc.nix`: MangoWC user packages
- `gnome.nix`: GNOME user-level settings

## Control

- `settings.wms` (global installed WM modules)
- `settings.wmShell` (legacy alias: `settings.hyprlandShell`)
- `settings.userSettings.<name>.defaultWMS`
