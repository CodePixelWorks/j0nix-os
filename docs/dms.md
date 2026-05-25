# DMS Configuration Notes

This repo configures Dank Material Shell (DMS) via:
- `settings.nix` (`settings.dms.*`)
- `nix/user/wm/hyprland/shells/dank-material-shell/default.nix`

## Wallpaper Defaults

Use `settings.dms.wallpaper` in `settings.nix`:

```nix
dms.wallpaper = {
  wallpaperPath = "/run/current-system/sw/share/wallpapers/nix-wallpaper-stripes-logo.png";
  wallpaperFillMode = "PreserveAspectCrop"; # PreserveAspectCrop | PreserveAspectFit | Stretch
  monitorWallpapers = {
    # "DP-1" = "/path/to/monitor1-wallpaper.jpg";
    # "HDMI-A-1" = "#1a1a1a";
  };
};
```

These values are written once to:
- `~/.local/state/DankMaterialShell/session.json`

This keeps `~/.local/state/DankMaterialShell/session.json` user-editable:
- defaults are applied only when the file does not exist
- later UI/manual changes are not forced back on activation

## Startup Mode

Controlled via:

```nix
dms.startup.mode = "systemd"; # or "exec-once"
```

- `systemd`: enables `programs.dank-material-shell.systemd.enable`
- `exec-once`: starts via Hyprland `exec-once` path

## Workspaces

Use `settings.dms.workspaces` in `settings.nix`:

```nix
dms.workspaces = {
  count = 10; # 1..10
  showOccupiedOnly = false;
};
```

- `count`: creates Hyprland binds for `SUPER+1..0` and `SUPER+SHIFT+1..0`
- `showOccupiedOnly`: seeded once in `~/.config/DankMaterialShell/settings.json`
