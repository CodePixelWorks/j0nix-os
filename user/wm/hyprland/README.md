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

`~/.config/hypr/hyprland.lua` is now the active production entrypoint.

Generated Lua modules:

- `~/.config/hypr/hyprland.lua`
- `~/.config/hypr/j0nix/vars.lua`
- `~/.config/hypr/j0nix/env.lua`
- `~/.config/hypr/j0nix/monitors.lua`
- `~/.config/hypr/j0nix/startup.lua`
- `~/.config/hypr/j0nix/input.lua`
- `~/.config/hypr/j0nix/general.lua`
- `~/.config/hypr/j0nix/decoration.lua`
- `~/.config/hypr/j0nix/misc.lua`
- `~/.config/hypr/j0nix/window-rules.lua`
- `~/.config/hypr/j0nix/keybinds.lua`
- `~/.config/hypr/j0nix/shell.lua`
- `~/.config/hypr/j0nix/user-overrides.lua`

Compatibility alias:

- `~/.config/hypr/j0nix-scaffold.lua`

The user override include is always loaded last:

- `~/.config/hypr/shell-overrides/<wmShell>/user-overrides.lua`

## Lua Scaffold

The Lua scaffold is now the active session config.

- `~/.config/hypr/hyprland.lua`
- `~/.config/hypr/j0nix/*.lua`

Current scaffold coverage:

- env
- monitors
- startup
- input
- general
- decoration
- misc
- window rules
- keybinds
- shell-specific overlays for `caelestia-shell`

Current shell migration status:

- `caelestia-shell`: active Lua overlay present, including the global submap bootstrap
- `dank-material-shell`: temporarily marked broken during the Lua migration
- other shells: no dedicated Lua overlay yet

## Session Environment

Hyprland now generates two environment entrypoints from the same declarative source:

- `~/.config/hypr/j0nix/env.lua`
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

- `~/.config/hypr/shell-overrides/<wmShell>/user-overrides.lua`

This file is auto-created once by Home Manager activation and then left mutable for manual per-user overrides.
Legacy hyprlang override files are no longer sourced automatically. If `~/.config/hypr/user-overrides.conf` or the shell-scoped `user-overrides.conf` exists, Home Manager now creates a Lua override file with a migration note instead of trying to execute the old syntax.
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

Hyprland itself keeps headless outputs disabled during session startup. The normal startup path is intentionally generic:

- physical outputs come from the profile output state model plus the fallback `monitor = ,preferred,auto,1`
- the Sunshine display target is rendered as disabled by default in the generated Lua monitor config
- Sunshine is the single authority that enables its target output when a stream starts

On this host, the static monitor topology still comes from `profiles/desktop/details.nix`. `settings.hyprland.initialOutputStates` is now only needed when you want to override the default disabled-at-start behavior for the Sunshine target output.

## Monitor Policy

Runtime monitor management is Lua-native. `wm-monitor` writes current managed output state to `~/.config/hypr/j0nix/runtime-monitors.lua`, which is loaded after the declarative monitor defaults.

Supported controls:

- `SUPER+CTRL+1/2/3`: toggle managed outputs
- `SUPER+CTRL+SHIFT+1/2/3`: restore saved output state
- `SUPER+ALT+1/2/3`: move active workspace to output
- `SUPER+CTRL+ALT+1/2/3`: move focused workspaces to output

The monitor behavior declaratively managed in the Hyprland user module is:

- the initial output state model from `profiles/desktop/details.nix`
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
