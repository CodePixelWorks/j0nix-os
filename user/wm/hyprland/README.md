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
- `SUPER+CTRL+K`: toggle the `wvkbd` on-screen keyboard
- `SUPER+Return`: open preferred terminal
- `SUPER+SHIFT+L`: lock screen via `wm-lock-screen`
- `SUPER+B`: open preferred browser
- `SUPER+SHIFT+Q`: exit Hyprland session
- `SUPER+H/J/K/L`: Vim-style focus movement (`left/down/up/right`)
- `SUPER+SHIFT+H/J/K/L`: move the active window (`left/down/up/right`)
- `SUPER+ALT+H/J/K/L`: resize the active window (`shrink width / grow height / shrink height / grow width`)
- `SUPER+CTRL+H/J/K/L`: preselect the next split direction directly (`left/down/up/right`)
- Drag window borders or gaps with the mouse to resize tiled windows.
- `SUPER+CTRL+BackSpace`: switch keyboard layout
- `SUPER+CTRL+L`: quick vertical split for the next tiled window (side-by-side)
- `SUPER+CTRL+J`: quick horizontal split for the next tiled window (stacked)
- `SUPER+CTRL+V`: legacy alias for a vertical split (`right`)
- `SUPER+CTRL+SHIFT+V`: legacy alias for a horizontal split (`down`)
- `SUPER+P`: fullscreen screenshot
- `SUPER+-`: decrease the split ratio
- `SUPER++`: increase the split ratio

Lock helpers:

- `wm-lock-screen`: shared lock entrypoint used by Hyprland, wlogout, and the suspend helpers
- `wm-lock-screen-reset`: kill a stuck `hyprlock` process and relaunch the shared lock entrypoint
- `lockfix`: shell alias for `wm-lock-screen-reset`
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

`settings.hyprland.headlessOutputs` remains the declarative source for Hyprland virtual outputs that other modules, especially Sunshine, may reference.

Hyprland itself no longer materializes or manages those virtual outputs during session startup. The normal startup path is intentionally generic:

- physical outputs come from the static profile monitor lines plus the fallback `monitor = ,preferred,auto,1`
- the Sunshine display target is rendered as disabled by default in `10-monitors.conf`
- Sunshine is the single authority that enables its target output when a stream starts

On this host, the static monitor topology still comes from `profiles/desktop/details.nix`. `settings.hyprland.initialOutputStates` is now only needed when you want to override the default disabled-at-start behavior for the Sunshine target output.

## Monitor Policy

The previous runtime monitor management layer has been intentionally removed from the user session.

That means:

- no runtime `11-runtime-monitors.conf`
- no Home Manager services that create, remove, or watch Hyprland outputs
- no monitor toggle, restore, or workspace-handoff keybinds
- no `wm-monitor-*` helper commands in the supported baseline

The only monitor behavior that remains declaratively managed in the Hyprland user module is:

- the static monitor layout from `profiles/desktop/details.nix`
- the wildcard fallback rule for unknown physical outputs
- the disabled-by-default startup override for the configured Sunshine display target

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
