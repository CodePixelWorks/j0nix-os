# QMLGreet Integration

This repo supports `qmlgreet` as a first-class `greetd` greeter.

## Where It Is Defined

- Package: `nix/system/software/pkgs/greetd/qmlgreet.nix`
- Maui deps:
  - `nix/system/software/pkgs/maui/mauiman4.nix`
  - `nix/system/software/pkgs/maui/mauikit4.nix`
- Overlay wiring: `flake.nix` (`pkgs.qmlgreet`, `pkgs.mauikit4`, `pkgs.mauiman4`)
- Greetd contract: `nix/system/wm/display-manager/contract.nix`
- Greetd command variants: `nix/system/wm/display-manager/greetd/variants.nix`
- Hyprland runtime wiring: `nix/system/wm/hyprland.nix`

## Settings Contract

In `settings.nix`:

```nix
displayManager = "greetd";
greetd = {
  greeter = "qmlgreet";           # "tuigreet" | "regreet" | "qmlgreet" | "dms-greeter"
  regreetCompositor = "hyprland"; # "cage" | "hyprland" (shared for regreet/qmlgreet)
};
```

## Generated Runtime Files

When `greetd.greeter = "qmlgreet"`:

- `/etc/qmlgreet/qmlgreet.conf`
- `/etc/qmlgreet/QMLGreetDefault.colors`
- `/etc/qmlgreet/hyprland.conf` (only when compositor is `hyprland`)

If compositor is `hyprland`, greetd launches:

- `start-hyprland -- -c /etc/qmlgreet/hyprland.conf`

`/etc/qmlgreet/hyprland.conf` then runs:

- `qmlgreet -c /etc/qmlgreet/qmlgreet.conf`

If compositor is `cage`, greetd launches:

- `cage -s -mlast -- qmlgreet -c /etc/qmlgreet/qmlgreet.conf`

## Theming Inputs Used

`/etc/qmlgreet/qmlgreet.conf` is derived from existing settings:

- Wallpaper from `settings.dms.wallpaper.wallpaperPath`
- Icon theme name from `settings.iconTheme.name`

## Validation

Useful checks:

```bash
nix build --no-link .#nixosConfigurations.Jonas-PC.pkgs.qmlgreet
nix flake check --no-build
```

