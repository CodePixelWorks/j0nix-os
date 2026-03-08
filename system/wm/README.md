# System WM Modules

Display manager and system WM integration.

## Files

- `hyprland.nix`: Hyprland system integration, sessions, greeter path
- `mangowc.nix`: MangoWC compositor session integration
- `niri.nix`: Niri compositor session integration
- `gnome.nix`: GNOME integration
- `kde.nix`: KDE integration
- `common/wayland.nix`: shared Wayland/X11 foundation packages/options
- `display-manager/greetd/variants.nix`: shared greetd greeter constructors
- `display-manager/contract.nix`: shared display-manager contract resolution and valid values

## Control Keys

- `settings.wms`
- `settings.displayManager`
- `settings.greetd.*`
- `settings.hyprland.useUWSM`

## Greetd Greeters

- `tuigreet`
- `regreet`
- `qmlgreet`
- `dms-greeter` (legacy alias: `darkmaterialshell`)
