# User Hyprland Module

Main user-side Hyprland module (`default.nix`) plus shell-specific variants.

## Core Responsibilities

- base Hyprland settings
- startup orchestration via Hyprland `exec-once` + app launch policy
- shell-aware keybind composition
- window rule composition
- optional diagnostics/minimizer integration

## Shell Selection

Modules under `shells/` are selected per user via `settings.userSettings.<name>.wmShell` (legacy alias: `hyprlandShell`).

## Hyprland Rule Syntax Notes (0.53.2+)

- Older window rule syntax is parsed much more strictly.
- `windowrulev2`-style configs from older dotfiles may fail hard.
- `windowrule` rules require explicit values for flags (for example `float 1`, `center 1`).
- Use snake_case fields (`no_blur`, `initial_title`).
- `idleinhibit` window rule was removed; configure idle behavior via `hypridle`.

## Keybind Overview

The module now composes keybinds from:

- `user/wm/hyprland/config/keybinds.nix` (base + shell-specific bind maps)
- `user/wm/hyprland/default.nix` (wiring + startup)

Window rules are split into:

- `user/wm/hyprland/config/window-rules.nix`

For the active incident/runbook around Caelestia keybind regressions (`upstream-dev` runtime + greetd variants), see:

- `docs/HYPRLAND_CAELESTIA_KEYBINDS.md`
- `docs/WM_STARTUP_AND_LAUNCH_FLOW.md`

## User Overrides

The generated Hyprland config sources a user-local file last:

- `~/.config/hypr/user-overrides.conf`

This file is auto-created once by Home Manager activation and then left mutable for manual per-user overrides.  
Typical use: local binds, monitor tweaks, one-off rules that should not be committed into Nix modules.

## Optional Minimizer

Per-user toggle:
- `settings.userSettings.<name>.hyprland.minimizer.enable`
- `settings.userSettings.<name>.hyprland.minimizer.variant` (`denis` | `0rteip`)
- `settings.userSettings.<name>.hyprland.minimizer.command` (optional override; auto-selected by variant when unset)
- `settings.userSettings.<name>.hyprland.minimizer.orteip.appId`
- `settings.userSettings.<name>.hyprland.minimizer.binds.{toggle,restore,menu}`

When enabled:
- Hyprland binds are added:
  - `SUPER+CTRL+M`: minimize/toggle
  - `SUPER+CTRL+SHIFT+M`: restore-last (`denis`) or toggle same app (`0rteip`)
  - `SUPER+CTRL+C`: menu (`denis`) or toggle same app (`0rteip`)
- If `pkgs.hyprland-minimizer` exists in nixpkgs, it is added automatically.
- For `0rteip`, `hyprland-minimizer-orteip` is built from source and installed automatically.

## KeePassXC Workspace Integration

Per-user toggle under `settings.userSettings.<name>.programs.keepassxc`:
- `workspace.enable`
- `workspace.mode` (`special-workspace` | `minimizer`)
- `workspace.name` (used as `special:<name>` when mode is `special-workspace`)
- `workspace.toggleBind` (default: `SUPER+CTRL+P`)
- `autoUnlock.mode` (`strict` | `balanced` | `convenient` | `full-auto`)

Behavior:
- `special-workspace`: KeePassXC windows are routed to `special:<workspace.name>`.
- `minimizer`: `keepassxc-toggle` uses the configured Hyprland minimizer backend.
- `keepassxc-toggle` is the single command used by keybinds and shell actions.

## Core Binds (Hyprland)

- `SUPER+Q`: close active window
- `SUPER+T`: toggle floating
- `SUPER+F`: fullscreen (mode `0`, hides shell/waybar)
- `SUPER+SHIFT+F`: maximize-like fullscreen (mode `1`, keeps shell/waybar)
- `SUPER+Return`: open preferred terminal
- `SUPER+SHIFT+L`: lock screen (`hyprlock` fallback to `loginctl lock-session`)
- `SUPER+B`: open preferred browser
- `SUPER+SHIFT+Q`: exit Hyprland session
- `SUPER+H/J/K/L`: Vim-style window movement (`left/down/up/right`)
- `SUPER+ALT+H/J/K/L`: resize the active window (`shrink width / grow height / shrink height / grow width`)
- `SUPER+CTRL+V`: preselect a vertical split for the next tiled window (side-by-side)
- `SUPER+CTRL+SHIFT+V`: preselect a horizontal split for the next tiled window (stacked)
- `CTRL+ALT+H/J/K/L`: Vim-style focus movement (`left/down/up/right`, remote-friendly fallback)
- `SUPER+Left/Right`: switch relative workspace (`-1/+1`)
- `SUPER+SHIFT+Left/Right`: move window to relative workspace (`-1/+1`, currently follows)
- `SUPER+1..0`: switch workspace
- `SUPER+SHIFT+1..0`: move window to workspace (with following it)
- `SUPER+CTRL+c`: center active window
- `SUPER+CTRL+P`: toggle KeePassXC (special workspace or minimizer mode)

## Remote / Moonlight Fallback Binds

These exist because `SUPER` (Windows key) is often unreliable through Moonlight/KVM/remote sessions.

- `CTRL+ALT+Q`: close active window
- `CTRL+ALT+T`: toggle floating
- `CTRL+ALT+F`: fullscreen (mode `0`)
- `CTRL+SHIFT+ALT+F`: maximize-like fullscreen (mode `1`)
- `CTRL+ALT+Return`: open preferred terminal
- `CTRL+ALT+C`: center active window
- `CTRL+ALT+H/J/K/L`: move focus
- `CTRL+SHIFT+ALT+H/J/K/L`: move window
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

- Some binds are added conditionally based on the active per-user `wmShell`, `settings.dms.overview.enable`, and related toggles.
- Additional shell-specific media, screenshot, and workflow binds are defined in the selected shell block inside `user/wm/hyprland/default.nix`.
- Generic screenshot helpers are always available:
  - `Win+P`: fullscreen screenshot via `wm-screenshot-full`
  - `Ctrl+Print`: fullscreen screenshot via `wm-screenshot-full` (intended as the game-safe fallback)
  - `Ctrl+Shift+Print`: area screenshot via `wm-screenshot-area`
  - Files are saved to `~/Pictures/Screenshots`
