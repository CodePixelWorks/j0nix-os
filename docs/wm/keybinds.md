# Keybind Overview

This document summarizes the current commonly used Hyprland keybinds for the default desktop setup.

Scope:

- Current default user flow with `wmShell = "caelestia-shell"`
- Hyprland core binds from `nix/user/wm/hyprland/config/keybinds.nix`
- Current monitor bindings from `settings.nix`

Notes:

- `SUPER` means the main modifier key.
- `SHIFT`, `CTRL`, and `ALT` are additional modifiers.
- Monitor bind `3` follows the active Sunshine display target.
  - Current default: `DP-2` (Sunshine Dummy Plug)
  - Alternate backend: `SUNSHINE-HEADLESS`

## Core Window Actions

- `SUPER+Q`: close the active window
- `SUPER+T`: toggle floating for the active window
- `SUPER+F`: real fullscreen
- `SUPER+SHIFT+F`: maximize-style fullscreen while keeping shell bars visible
- `SUPER+CTRL+Backslash`: center the active window
- `SUPER+Return`: open the preferred terminal
- `SUPER+SHIFT+L`: lock the session
- `SUPER+SHIFT+Q`: exit Hyprland
- `SUPER+,`: open the keybind reference popup
- `SUPER+R`: recover the shell session

## Focus And Move

- `SUPER+H`: focus left
- `SUPER+J`: focus down
- `SUPER+K`: focus up
- `SUPER+L`: focus right
- `SUPER+SHIFT+H`: move window left
- `SUPER+SHIFT+J`: move window down
- `SUPER+SHIFT+K`: move window up
- `SUPER+SHIFT+L`: move window right
- `SUPER+ALT+H`: resize active window, shrink width
- `SUPER+ALT+J`: resize active window, grow height
- `SUPER+ALT+K`: resize active window, shrink height
- `SUPER+ALT+L`: resize active window, grow width
- `SUPER+mouse-left`: move window with mouse
- `SUPER+mouse-right`: resize window with mouse
- You can also resize tiled windows directly by dragging their borders or gaps.
- `SUPER+CTRL+G`: jump back to the previous workspace on the current monitor

## Layout And Splits

- `SUPER+CTRL+H`: preselect left split
- `SUPER+CTRL+J`: preselect down split
- `SUPER+CTRL+K`: preselect up split
- `SUPER+CTRL+L`: preselect right split
- `SUPER+CTRL+V`: quick vertical split alias
- `SUPER+CTRL+SHIFT+V`: quick horizontal split alias
- `SUPER+-`: decrease split ratio
- `SUPER++`: increase split ratio
- `SUPER+CTRL+BackSpace`: toggle keyboard layout
- `SUPER+TAB`: toggle overview

## Workspaces

- `SUPER+CTRL+Tab`: jump back to the previous workspace on the current monitor
- `SUPER+1..0`: switch to workspace `1..10`
- `SUPER+SHIFT+1..0`: move the active window to workspace `1..10`
- `SUPER+Left`: previous workspace
- `SUPER+Right`: next workspace
- `SUPER+SHIFT+Left`: move window to previous workspace
- `SUPER+SHIFT+Right`: move window to next workspace
- `SUPER+mouse-down`: previous workspace
- `SUPER+mouse-up`: next workspace
- `SUPER+PageUp`: previous workspace
- `SUPER+PageDown`: next workspace
- `SUPER+ALT+PageUp`: move window to previous workspace
- `SUPER+ALT+PageDown`: move window to next workspace

## Screenshots And Recording

- `SUPER+P`: fullscreen screenshot
- `CTRL+SHIFT+Print`: area screenshot
- `Print`: shell screenshot action
- `SUPER+SHIFT+S`: frozen screenshot flow
- `SUPER+SHIFT+ALT+S`: screenshot flow
- `SUPER+ALT+R`: start selective recording
- `CTRL+ALT+R`: start recording
- `SUPER+SHIFT+ALT+R`: start region recording

## Apps And Launchers

- `SUPER+B`: open preferred browser
- `SUPER+E`: open preferred file manager
- `SUPER+V`: open preferred editor
- `SUPER+G`: open GitHub Desktop
- `CTRL+ALT+V`: open `pavucontrol`
- `CTRL+ALT+Escape`: open `qps`
- `SUPER+.`: open emoji picker
- `SUPER+Space`: show all
- `SUPER+Escape`: session actions
- `SUPER+/`: open the control center

## Special Workspaces And Shell Actions

- `SUPER+S`: toggle the generic special workspace
- `SUPER+ALT+S`: move the active window to the special workspace
- `SUPER+M`: toggle media special workspace
- `SUPER+C`: toggle Discord special workspace
- `SUPER+X`: toggle system monitor special workspace
- `SUPER+SHIFT+P`: toggle KeePassXC / passwords workspace
- `SUPER+N`: clear notifications
- `SUPER+SHIFT+N`: clear notifications
- `SUPER+SHIFT+V`: clipboard picker
- `SUPER+ALT+V`: clipboard delete action
- `SUPER+SHIFT+C`: copy color with `hyprpicker`

## Monitor Controls

Current numeric monitor map:

- `1` -> `DP-1` (Primary PC Monitor)
- `2` -> `HDMI-A-2` (Living Room TV)
- `3` -> current Sunshine target (`DP-2` by default)

Actions:

- `SUPER+CTRL+1`: toggle monitor `1`
- `SUPER+CTRL+2`: toggle monitor `2`
- `SUPER+CTRL+3`: toggle monitor `3`
- `SUPER+CTRL+SHIFT+1`: restore monitor `1`
- `SUPER+CTRL+SHIFT+2`: restore monitor `2`
- `SUPER+CTRL+SHIFT+3`: restore monitor `3`
- `SUPER+ALT+1`: move active workspace to monitor `1`
- `SUPER+ALT+2`: move active workspace to monitor `2`
- `SUPER+ALT+3`: move active workspace to monitor `3`
- `SUPER+CTRL+ALT+1`: move all normal workspaces from the other active monitors to monitor `1`
- `SUPER+CTRL+ALT+2`: move all normal workspaces from the other active monitors to monitor `2`
- `SUPER+CTRL+ALT+3`: move all normal workspaces from the other active monitors to monitor `3`

## Audio And Brightness

- `XF86AudioMute`: toggle output mute
- `XF86AudioMicMute`: toggle microphone mute
- `XF86AudioRaiseVolume`: raise volume
- `XF86AudioLowerVolume`: lower volume
- `SUPER+SHIFT+M`: toggle output mute
- `XF86MonBrightnessUp`: brightness up
- `XF86MonBrightnessDown`: brightness down

## Media Keys

- `XF86AudioPlay`: play/pause
- `XF86AudioPause`: play/pause
- `XF86AudioNext`: next track
- `XF86AudioPrev`: previous track
- `XF86AudioStop`: stop playback
- `CTRL+SUPER+Space`: play/pause
- `CTRL+SUPER+=`: next track
- `CTRL+SUPER+-`: previous track

## Diagnostics And Recovery

- `SUPER+SHIFT+F12`: keybind probe
- `SUPER+SHIFT+BackSpace`: shell debug / lock path
- `CTRL+SUPER+SHIFT+R`: kill QuickShell
- `CTRL+SUPER+ALT+R`: restart Caelestia shell

## Monitor Discovery Helpers

These are commands rather than direct keybinds:

- `wm-monitor-list`
- `wm-monitor-debug`
- `wm-monitor-discover`
- `wm-monitor-new-dialog`
- `wm-monitor-suggest <monitor-name>`

## Source Of Truth

Primary sources:

- `nix/user/wm/hyprland/config/keybinds.nix`
- `nix/user/wm/hyprland/default.nix`
- `nix/user/wm/hyprland/README.md`
- `settings.nix`
