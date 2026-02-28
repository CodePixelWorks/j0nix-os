# User Hyprland Module

Main user-side Hyprland module (`default.nix`) plus shell-specific variants.

## Core Responsibilities

- base Hyprland settings
- startup command dispatch (`noctalia-start`/AGS always, `dms-start` only when `settings.dms.startup.mode = "exec-once"`)
- debug quickshell guard handling

## Shell Selection

Modules under `shells/` are selected by global `wmShell` (legacy alias: `hyprlandShell`).

## Hyprland Rule Syntax Notes (0.53.2+)

- Older window rule syntax is parsed much more strictly.
- `windowrulev2`-style configs from older dotfiles may fail hard.
- `windowrule` rules require explicit values for flags (for example `float 1`, `center 1`).
- Use snake_case fields (`no_blur`, `initial_title`).
- `idleinhibit` window rule was removed; configure idle behavior via `hypridle`.

## Keybind Overview

The module defines a shared base keymap in `user/wm/hyprland/default.nix` and merges shell-specific binds (Caelestia, DMS, etc.) on top.

## Core Binds (Hyprland)

- `SUPER+Q`: close active window
- `SUPER+T`: toggle floating
- `SUPER+F`: fullscreen (mode `0`, hides shell/waybar)
- `SUPER+SHIFT+F`: maximize-like fullscreen (mode `1`, keeps shell/waybar)
- `SUPER+Return`: open preferred terminal
- `SUPER+B`: open preferred browser
- `SUPER+L`: lock screen (`hyprlock` fallback to `loginctl lock-session`)
- `SUPER+SHIFT+Q`: exit Hyprland session
- `SUPER+Arrow`: move window
- `CTRL+ALT+Arrow`: move focus (remote-friendly fallback)
- `SUPER+SHIFT+Arrow`: move window to relative workspace (`-1/+1`, currently follows)
- `SUPER+1..0`: switch workspace
- `SUPER+SHIFT+1..0`: move window to workspace (with following it)
- `SUPER+CTRL+c`: center active window

## Remote / Moonlight Fallback Binds

These exist because `SUPER` (Windows key) is often unreliable through Moonlight/KVM/remote sessions.

- `CTRL+ALT+Q`: close active window
- `CTRL+ALT+T`: toggle floating
- `CTRL+ALT+F`: fullscreen (mode `0`)
- `CTRL+SHIFT+ALT+F`: maximize-like fullscreen (mode `1`)
- `CTRL+ALT+Return`: open preferred terminal
- `CTRL+ALT+L`: lock screen (`hyprlock` fallback to `loginctl lock-session`)
- `CTRL+ALT+C`: center active window
- `CTRL+ALT+Arrow`: move focus
- `CTRL+SHIFT+ALT+Arrow`: move window
- `CTRL+ALT+1..0`: switch workspace
- `CTRL+SHIFT+ALT+1..0`: move window to workspace
- `CTRL+ALT+M`: mute output
- `CTRL+SHIFT+ALT+M`: mute microphone
- `CTRL+ALT+=`: volume up
- `CTRL+ALT+-`: volume down
- `CTRL+SHIFT+ALT+=`: brightness up (`brightnessctl`)
- `CTRL+SHIFT+ALT+-`: brightness down (`brightnessctl`)

## Shell-Specific Launcher / Overview Fallbacks

- `Caelestia`: `CTRL+ALT+Space` opens launcher, `CTRL+SHIFT+ALT+Space` opens "show all"
- `Caelestia`: `CTRL+ALT+/` opens control center
- `Caelestia`: `CTRL+ALT+BackSpace` locks session
- `DMS` overview enabled: `CTRL+ALT+Space` toggles DMS overview

## Caelestia App Binds

- `SUPER+E`: open preferred file manager
- `SUPER+V`: open preferred editor
- `SUPER+SHIFT+V`: Caelestia clipboard
- `SUPER+ALT+V`: Caelestia clipboard delete

## Planned Relative Workspace Move Binds (README Plan)

Planned split for arrow-based relative workspace moves (`left/right`, optional `up/down` parity later):

- `SUPER+SHIFT+Left/Right`: `movetoworkspacesilent, -1/+1` (move window without following)
- `SUPER+CTRL+SHIFT+Left/Right`: `movetoworkspace, -1/+1` (move window and follow)

Notes for implementation:

- This keeps a clear distinction between "stash/move only" and "move + jump".
- `movetoworkspacesilent` is the intended dispatcher for the non-follow variant.
- Shell-specific binds (especially Caelestia) must be checked for conflicts before applying the change.

## Notes

- Some binds are added conditionally based on `settings.wmShell`, `settings.dms.overview.enable`, and related toggles.
- Additional shell-specific media, screenshot, and workflow binds are defined in the selected shell block inside `user/wm/hyprland/default.nix`.
- Generic screenshot helpers are always available:
  - `Win+P`: fullscreen screenshot via `wm-screenshot-full`
  - `Ctrl+Print`: fullscreen screenshot via `wm-screenshot-full` (intended as the game-safe fallback)
  - `Ctrl+Shift+Print`: area screenshot via `wm-screenshot-area`
  - Files are saved to `~/Pictures/Screenshots`
