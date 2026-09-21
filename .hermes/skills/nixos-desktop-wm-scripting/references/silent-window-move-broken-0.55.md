---
Session: 2026-06-11, updated 2026-07-08
Author: agent
---

# `window.move()` in Hyprland 0.55

## Initial symptom (2026-06-11)

Some window-movement keybinds silently did nothing. The config loaded without parser errors, but the binds had no effect.

## Initial diagnosis (partially wrong)

`lua-fragments.nix` rendered `movetoworkspace` and `movewindow` as native Lua calls:

```nix
else if dispatcher == "movetoworkspace" then
  "hl.dsp.window.move({ workspace = ${builtins.toJSON argumentString} })"
else if dispatcher == "movewindow" then
  "hl.dsp.window.move({ direction = ${builtins.toJSON argumentString} })"
```

At the time, the working fix was to remove these handlers and fall back to:

```nix
"hl.dsp.exec_cmd(${builtins.toJSON (renderRawDispatchCommand bind)})"
```

This emitted:

```bash
hl.dsp.exec_cmd("hyprctl dispatch -- movetoworkspace 1")
hl.dsp.exec_cmd("hyprctl dispatch -- movewindow l")
```

## Correction (2026-07-08)

The fallback itself became the problem inside the Caelestia `global` submap. `movetoworkspace` via `exec_cmd("hyprctl dispatch -- movetoworkspace -1")` failed silently, while `workspace` rendered natively as `hl.dsp.focus({ workspace = ... })` worked fine.

Re-introducing the native `hl.dsp.window.move({ workspace = ... })` path for `movetoworkspace` fixed the issue. This matches the official Hyprland 0.55 example config:

```lua
hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
```

## Current recommendation

| Dispatcher | Preferred Lua rendering | Notes |
|---|---|---|
| `movetoworkspace` | `hl.dsp.window.move({ workspace = "N" })` | Native, reliable in Caelestia submap |
| `workspace` | `hl.dsp.focus({ workspace = "N" })` | Native, reliable |
| `movewindow` spatial (`u/d/l/r`) | `hl.dsp.exec_cmd("hyprctl dispatch -- movewindow l")` | Native `hl.dsp.window.move({direction = ...})` still unreliable in 0.55 |

## Other mistakes found in the same session

### Wrong dispatcher for spatial directions

`mainMoveBinds` had been defined as:

```nix
mainMoveBinds = map (
  entry: mkMainBind "ALT" entry.key "movetoworkspace" entry.direction
)
```

`movetoworkspace` does **not** accept spatial directions (`l`, `r`, `u`, `d`). Only `movewindow` does. The correct bind for spatial window shifting is:

```nix
mainMoveBinds = map (
  entry: mkMainBind "SHIFT" entry.key "movewindow" entry.direction
)
```

### Dead duplicate workspace-switch binds

`baseBind` contained both `$mainMod, left/right, workspace, -1/+1` and `$mainMod, left/right, movefocus, l/r` for the same key. The later entries take precedence in the Lua `define_submap` loop; the workspace-switch binds for `left/right` were unreachable.

Working convention:

| Modifier | Arrows | H/J/K/L | Action |
|---|---|---|---|
| `$mainMod` | `movefocus` | `movefocus` | Window focus |
| `$mainMod ALT` | `workspace` | `movetoworkspace` | Switch/move workspace |
| `$mainMod SHIFT` | `movewindow` | `movewindow` | Spatial window shift |
| `$mainMod CTRL` | `movetoworkspace ±1` | — | Window to adjacent ws |

### Caelestia `launcherInterrupt` shadowing

The Caelestia shell overlay adds `launcherInterrupt` binds for many modifier combinations with `ignore_mods = true` and `non_consuming = true`. These intercept key combos before the real binds fire. When a bind works in isolation but fails inside the Caelestia submap, suspect this shadowing. Native `hl.dsp.*` calls are generally more robust against it than nested `exec_cmd("hyprctl dispatch -- ...")` wrappers.

## Commit

- `02967ae` — fix(hyprland): restore window movement binds by removing invalid Lua handlers
- 2026-07-08 — fix(hyprland): render `movetoworkspace` natively and add scroll binds
