# movetoworkspace native Lua rendering + scroll collision

Session: 2026-07-08 — j0nix-os Hyprland keybind fix.

## Problem

`$mainMod + CTRL + left/right` for `movetoworkspace -1/+1` was present in the
config but did nothing. `$mainMod + ALT + left/right` for `workspace -1/+1`
worked fine.

## Root cause

The Lua bind generator in `nix/user/wm/hyprland/config/lua-fragments.nix` did
not have a native renderer for `movetoworkspace`. It fell through to:

```lua
hl.dsp.exec_cmd("hyprctl dispatch -- movetoworkspace -1")
```

Inside the Caelestia `global` submap, this `exec_cmd` wrapper interacted badly
with the parallel `launcherInterrupt` binds (which set `ignore_mods = true` and
therefore fire on `$mainMod + CTRL + left` too). The native `workspace`
dispatcher rendered as `hl.dsp.focus({ workspace = "..." })` and worked.

## Fix

Add a native renderer for `movetoworkspace`:

```nix
else if dispatcher == "movetoworkspace" then
  "hl.dsp.window.move({ workspace = ${builtins.toJSON argumentString} })"
```

This matches the official Hyprland Lua example:

```lua
hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
```

Resulting binds now look like:

```lua
hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.move({ workspace = "-1" }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ workspace = "+1" }))
```

## Secondary issue: shell misconfiguration

`nix/user/wm/hyprland/config/keybinds/shells.nix` had:

```nix
"$mainMod ALT, mouse_down, movetoworkspace, -1"
"$mainMod ALT, mouse_up, movetoworkspace, +1"
```

This made `$mainMod + ALT + scroll` move the active window to another workspace,
contradicting the user's intent that `$mainMod + ALT` should only switch focus.
Changed to:

```nix
"$mainMod ALT, mouse_down, workspace, -1"
"$mainMod ALT, mouse_up, workspace, +1"
```

## Scroll collision pitfall

Adding `$mainMod + CTRL + mouse_up/down` for `movetoworkspace` and
`$mainMod + ALT + mouse_up/down` for `workspace` does **not** work safely
because the existing `$mainMod + mouse_up/down` workspace binds (and their
Caelestia `launcherInterrupt` companions with `ignore_mods = true`) already
claim the scroll wheel. In Hyprland's bind model a less-specific bind with
`ignore_mods` can still fire when extra modifiers are held, causing both the
workspace switch and the attempted window move to trigger.

Keep relative workspace/window moves on arrow keys only when scroll is already
bound on the base modifier.

## Verification

```bash
nix flake check --no-build
nix build .#homeConfigurations."jonas@Jonas-PC".activationPackage --no-link
readlink -f result/home-files/.config/hypr/j0nix/shell.lua | xargs grep -nE 'window\.move|focus.*workspace'
```

Expected output for the fix:

```
70:  hl.bind(mainMod .. " + ALT + left", hl.dsp.focus({ workspace = "-1" }))
71:  hl.bind(mainMod .. " + ALT + right", hl.dsp.focus({ workspace = "+1" }))
72:  hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "-1" }))
73:  hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "+1" }))
83:  hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.move({ workspace = "-1" }))
84:  hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ workspace = "+1" }))
```

## Commits

- `495469a fix(hyprland): render movetoworkspace natively in lua config`
- `6a358ea fix(hyprland): correct caelestia shell workspace binds`
