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

Portal routing on Hyprland is intentionally split:
- `org.freedesktop.impl.portal.ScreenCast` -> `hyprland`
- `org.freedesktop.impl.portal.FileChooser` -> `gtk`
- `org.freedesktop.impl.portal.Settings` -> `gtk`
- `org.freedesktop.impl.portal.Secret` -> `gnome-keyring`

## Hyprland Rule Syntax Notes (0.53.2+)

- Older window rule syntax is parsed much more strictly.
- `windowrulev2`-style configs from older dotfiles may fail hard.
- `windowrule` rules require explicit values for flags (for example `float 1`, `center 1`).
- Use snake_case fields (`no_blur`, `initial_title`).
- `idleinhibit` window rule was removed; configure idle behavior via `hypridle`.

## Keybind Overview

The module now composes keybinds from:

- `user/wm/hyprland/config/keybinds.nix` (base + shell-specific bind maps)
- `user/wm/hyprland/config/fragments.nix` (Hyprland fragment rendering + section layout)
- `user/wm/hyprland/default.nix` (wiring + startup)

Window rules are split into:

- `user/wm/hyprland/config/window-rules.nix`

## Generated Config Layout

`~/.config/hypr/hyprland.conf` is intentionally thin and only sources include files in a fixed order.

Main include directory:

- `~/.config/hypr/conf.d/00-vars.conf`
- `~/.config/hypr/conf.d/05-env.conf`
- `~/.config/hypr/conf.d/10-monitors.conf`
- `~/.config/hypr/conf.d/20-startup.conf`
- `~/.config/hypr/conf.d/30-input.conf`
- `~/.config/hypr/conf.d/40-general.conf`
- `~/.config/hypr/conf.d/50-decoration.conf`
- `~/.config/hypr/conf.d/60-misc-debug.conf`
- `~/.config/hypr/conf.d/70-window-rules.conf`
- `~/.config/hypr/conf.d/80-keybinds.conf`

Shell-scoped generated include:

- `~/.config/hypr/shells/<wmShell>/generated/95-shell.conf`

The user override include is always loaded last:

- `~/.config/hypr/shell-overrides/<wmShell>/user-overrides.conf`

This split avoids cross-shell collisions and keeps sections readable and easier to diff.

## Session Environment

Hyprland now generates two environment entrypoints from the same declarative source:

- `~/.config/hypr/conf.d/05-env.conf`
- `~/.config/uwsm/env` (when `settings.hyprland.useUWSM = true`)

Source-of-truth:

- `settings.hyprland.sessionEnv.qtPlatformTheme`
- `settings.hyprland.sessionEnv.app2unitSlices`
- `settings.hyprland.sessionEnv.extra`

If `qtPlatformTheme` is set to `hyprqt6engine`, `qt6ct`, or `qt5ct`, the matching package is also installed through `user/desktop/qt-theme.nix`. `qtengine` remains accepted as a compatibility alias and resolves to `hyprqt6engine`.

The module also imports these variables into the systemd user manager during session startup so `app2unit`/D-Bus launched apps inherit the same toolkit/backend environment as direct Hyprland launches.

For the active incident/runbook around Caelestia keybind regressions (`upstream-dev` runtime + greetd variants), see:

- `docs/HYPRLAND_CAELESTIA_KEYBINDS.md`
- `docs/WM_STARTUP_AND_LAUNCH_FLOW.md`

## User Overrides

The generated Hyprland config sources a shell-scoped user-local file last:

- `~/.config/hypr/shell-overrides/<wmShell>/user-overrides.conf`

This file is auto-created once by Home Manager activation and then left mutable for manual per-user overrides.
The old shared path `~/.config/hypr/user-overrides.conf` is migrated automatically on first switch.
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
- `workspace.name` (used as `special:<name>` when mode is `special-workspace`, default: `passwords`)
- `workspace.toggleBind` (default: `SUPER+SHIFT+P`)
- `autoUnlock.mode` (`strict` | `balanced` | `convenient` | `full-auto`)

Behavior:
- `special-workspace`: KeePassXC windows are routed to `special:<workspace.name>`.
- `minimizer`: `keepassxc-toggle` uses the configured Hyprland minimizer backend.
- `keepassxc-toggle` is the single command used by keybinds and shell actions.

## Core Binds (Hyprland)

- `SUPER+Q`: close active window
- `SUPER+T`: toggle floating
- `SUPER+,`: open the generated Hyprland keybind reference popup
- `SUPER+F`: fullscreen (mode `0`, hides shell/waybar)
- `SUPER+SHIFT+F`: maximize-like fullscreen (mode `1`, keeps shell/waybar)
- `SUPER+Return`: open preferred terminal
- `SUPER+SHIFT+L`: lock screen (`hyprlock` fallback to `loginctl lock-session`)
- `SUPER+B`: open preferred browser
- `SUPER+SHIFT+Q`: exit Hyprland session
- `SUPER+H/J/K/L`: Vim-style focus movement (`left/down/up/right`)
- `SUPER+SHIFT+H/J/K/L`: move the active window (`left/down/up/right`)
- `SUPER+ALT+H/J/K/L`: resize the active window (`shrink width / grow height / shrink height / grow width`)
- `SUPER+CTRL+H/J/K/L`: preselect the next split direction directly (`left/down/up/right`)
- `SUPER+CTRL+BackSpace`: switch keyboard layout
- `SUPER+CTRL+L`: quick vertical split for the next tiled window (side-by-side)
- `SUPER+CTRL+J`: quick horizontal split for the next tiled window (stacked)
- `SUPER+CTRL+V`: legacy alias for a vertical split (`right`)
- `SUPER+CTRL+SHIFT+V`: legacy alias for a horizontal split (`down`)
- `SUPER+P`: fullscreen screenshot
- `SUPER+-`: decrease the split ratio
- `SUPER++`: increase the split ratio
- `SUPER+Left/Right`: switch relative workspace (`-1/+1`)
- `SUPER+SHIFT+Left/Right`: move window to relative workspace (`-1/+1`, currently follows)
- `SUPER+1..0`: switch workspace
- `SUPER+SHIFT+1..0`: move the active window to workspace `1..10`
- `SUPER+CTRL+c`: center active window
- `SUPER+SHIFT+P`: toggle KeePassXC (special workspace or minimizer mode)

## Keybind Reference Popup

`SUPER+,` now launches `hyprKCS`, which parses the active Hyprland configuration tree directly and provides the graphical search/editor UI from the upstream project.

- `SUPER+,`

## Headless Outputs

`settings.hyprland.headlessOutputs` declares virtual Hyprland outputs. j0nix materializes them through the user service `hyprland-headless-outputs.service`, and Home Manager restarts that service on rebuilds in an active session. `wm-headless-output-ensure` remains available as the manual fallback command.

## Toggleable Outputs

`settings.hyprland.toggleableOutputs` declares physical outputs that should be manageable at runtime even if Hyprland still sees the connector when the screen itself is powered off.

`settings.hyprland.outputBindings` declares the global numeric monitor map used by the workspace-move binds and the monitor picker list.

Current default TV setup:

- `outputBindings` maps:
  - `1` -> `DP-1` (Primary PC Monitor)
  - `2` -> `DP-3` (Living Room TV)
  - `3` -> `SUNSHINE-HEADLESS` (Adaptive Display)
- `DP-3` is declared as a toggleable output
- `DP-3` uses `bindIndex = 2`
- it starts disabled by default
- `SUPER+CTRL+2`: toggle monitor `2`
- `SUPER+CTRL+SHIFT+2`: restore monitor `2` and move its saved workspaces back
- `SUPER+ALT+1`: move the active workspace to monitor `1`
- `SUPER+CTRL+ALT+1`: move all normal workspaces from the focused monitor to monitor `1`
- `SUPER+ALT+2`: move the active workspace to monitor `2`
- `SUPER+CTRL+ALT+2`: move all normal workspaces from the focused monitor to monitor `2`
- `SUPER+ALT+3`: move the active workspace to monitor `3`
- `SUPER+CTRL+ALT+3`: move all normal workspaces from the focused monitor to monitor `3`

Runtime commands:

- `wm-monitor-list`
- `wm-monitor-debug`
- `wm-monitor-toggle DP-3`
- `wm-monitor-on DP-3`
- `wm-monitor-off DP-3`
- `wm-monitor-restore DP-3`
- `wm-monitor-status DP-3`
- `wm-monitor-workspace-to DP-3`
- `wm-monitor-focused-workspaces-to DP-3`

The toggle layer saves the output's workspace/focus state before disabling it, moves those workspaces onto the configured fallback monitor, and restores them when the output comes back. The same workspace handoff logic is also exposed through the numeric `SUPER+ALT+<number>` and `SUPER+CTRL+ALT+<number>` monitor binds. The “move all” variant only targets normal numbered workspaces (`id > 0`) and leaves special workspaces alone.

Manual `wm-monitor-*` actions also rewrite `11-runtime-monitors.conf`, so the currently chosen monitor state survives later Hyprland config reloads instead of snapping back to the startup defaults.

Initial output states are now expressed in two layers:

- `10-monitors.conf` renders the declarative startup defaults for managed physical outputs
- `11-runtime-monitors.conf` stays empty in the declarative baseline and is reserved for runtime overrides
- the fallback `monitor = ,preferred,auto,1` line is only emitted when no explicit monitor defaults exist

This keeps boot-time monitor state deterministic and gives runtime tools a separate override file instead of racing the startup config.

All extra monitor profile tooling is intentionally disabled for now. The only supported runtime path is the built-in `wm-monitor-*` command set and the corresponding Hyprland binds.

## Caelestia App Binds

- `SUPER+E`: open preferred file manager
- `SUPER+V`: open preferred editor
- `SUPER+N` / `SUPER+SHIFT+N`: clear Caelestia notifications
- `SUPER+C`: toggle special workspace `discord`
- `SUPER+M`: toggle special workspace `media`
- `SUPER+X`: toggle special workspace `sysmon`
- `SUPER+SHIFT+P`: toggle special workspace `passwords` (KeePassXC)
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
