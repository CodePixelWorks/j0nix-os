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

`qmlgreet` is rendered from the official upstream config shape and controlled via:
- `settings.greetd.qmlgreet.defaultSession`
- `settings.greetd.qmlgreet.colorSchemePath`
- `settings.greetd.qmlgreet.backgroundImage`
- `settings.greetd.qmlgreet.iconTheme`
- `settings.greetd.qmlgreet.font`
- `settings.greetd.qmlgreet.fontSize`
- `settings.greetd.qmlgreet.showAvatars`

Leave `defaultSession` empty for the most robust behavior; hardcoding a session label is brittle when session display names change.
