# Wrapping FHS/Binary Apps for Wayland/XWayland Compatibility

Closed-source or vendor-shipped Linux binaries often link against Qt-XCB
(X11) and fail under Wayland/XWayland because GTK/Qt auto-detect Wayland
and get confused inside `buildFHSEnv` bubbles where portals are not fully
wired.

## Symptom

- App launches but the **Open File dialog crashes** or fails to appear.
- `gpg: Sorry, we are in batchmode - can't get input` or similar pinentry
  deadlocks in headless contexts.
- Dialog appears off-screen, with incorrect scaling, or not at all.

## Root Cause

Inside an FHS environment (e.g. `buildFHSEnv`, AppImage, Flatpak without
portal passthrough), GTK/Qt detect `WAYLAND_DISPLAY` and try to use native
Wayland protocols. The `xdg-desktop-portal` file chooser is unavailable or
misconfigured, so the dialog either crashes or falls back to a broken path.

## Fix: Force Explicit X11 Backends via Wrapper

Use `symlinkJoin` + `makeWrapper` to inject environment variables:

```nix
{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).someApp or { };
  enabled = cfg.enable or false;

  appFixed = pkgs.symlinkJoin {
    name = "some-app";
    paths = [ pkgs.some-app ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/some-app \
        --set QT_QPA_PLATFORM xcb \
        --set GDK_BACKEND x11 \
        --set GTK_USE_PORTAL 1
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ appFixed ];
}
```

### Environment Variables Explained

| Variable | Value | Purpose |
|---|---|---|
| `QT_QPA_PLATFORM` | `xcb` | Forces Qt to use the X11 backend instead of Wayland |
| `GDK_BACKEND` | `x11` | Forces GTK to use X11 instead of Wayland |
| `GTK_USE_PORTAL` | `1` | Tells GTK apps to use `xdg-desktop-portal` for file chooser (more stable inside FHS) |

## When This Applies

- Any `buildFHSEnv` or AppImage package running under a Wayland compositor
  (Hyprland, Sway, Niri, etc.)
- Closed-source binaries with bundled Qt/GTK libs (e.g. DaVinci Resolve,
  Bambu Studio AppImage, Autodesk Fusion)
- Any app where the native file chooser or dialog crashes under XWayland

## When This Does NOT Apply

- Apps compiled natively against `qtwayland` or `gtk4-wayland` with proper
  portal support (e.g. Firefox, modern GTK4 apps)
- Apps already running inside a Flatpak with `--socket=wayland` and proper
  portal wiring (the Flatpak runtime handles this)

## Variation: Gamescope as Nested Compositor

If forcing X11 backends is not enough (e.g. tearing, scaling issues), wrap
the app in `gamescope` as a nested X11 compositor:

```nix
appWithGamescope = pkgs.writeShellScriptBin "some-app" ''
  exec ${pkgs.gamescope}/bin/gamescope -W 1920 -H 1080 -- \
    ${pkgs.some-app}/bin/some-app "$@"
'';
```

This is still technically XWayland from the host's perspective, but Gamescope
provides stable VSync and fractional scaling.
