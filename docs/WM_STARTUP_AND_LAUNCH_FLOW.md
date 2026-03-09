# WM Startup And Launch Flow

This document defines the runtime order for compositor/shell startup and app launch dispatch.

## Startup Graph

```text
Display Manager (greetd/sddm/gdm)
-> session command (auto-wm-session)
-> start-hyprland-session
-> Hyprland process
-> Hyprland exec-once
-> wm-start-graphical-session-target
-> wm-shell-start
-> selected shell runtime (caelestia-start | noctalia-start | dms-start)
-> optional wm-overview-start
-> optional wm-hypr-keybind-diagnostics-startup
```

## Ordering Rules

1. Compositor-dependent shell processes start from Hyprland `exec-once` only.
2. `graphical-session.target` is started from Hyprland startup (not before compositor init).
3. Legacy WM user services (`hyprland-shell`, `hyprland-wallpaper`, `hyprland-startup-apps`, `hyprland-keybind-diagnostics`) are removed and cleaned up during activation.
4. Overview can be controlled via `wm-overview.service`, but autostart is handled by Hyprland startup flow.

## App Launch Backend Policy

Shared helper: `system/lib/app-exec-policy.nix`

Input:
- `settings.hyprland.useUWSM`
- `settings.hyprland.appExecBackend` (`auto` | `app2unit` | `uwsm`)

Resolution:
1. If `useUWSM = false`: force `app2unit`.
2. If backend is `auto`: use `app2unit` first.
3. Use `uwsm app` only when UWSM is active and backend selection/fallback requests it.

Result:
- Hyprland bind app launches and shell launcher paths use one consistent backend policy.

## Debug Path

When startup regressions happen:

1. `journalctl --user -b --no-pager | rg 'wm-shell-start|quickshell|xcb|display'`
2. `hyprctl configerrors`
3. `journalctl --user -b --no-pager | rg 'graphical-session.target|wm-overview|hyprland'`
