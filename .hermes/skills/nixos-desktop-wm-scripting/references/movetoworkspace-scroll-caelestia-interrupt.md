# Session 2026-07-08: `movetoworkspace ±1` scroll binds + native Lua rendering

## Problem

User reported that `SUPER + CTRL + left/right` and `SUPER + CTRL + scroll` did not move the focused window to the adjacent workspace (`movetoworkspace -1/+1`), while `SUPER + ALT + left/right` for switching workspaces (`workspace -1/+1`) worked.

## Root causes

1. **Missing scroll binds**: `core.nix` only defined arrow-key binds for `movetoworkspace ±1`; there was no `mouse_up`/`mouse_down` variant.
2. **Wrong Lua rendering**: The Hyprland Lua renderer (`lua-fragments.nix`) did not have a native path for the `movetoworkspace` dispatcher. It fell back to:
   ```lua
   hl.dsp.exec_cmd("hyprctl dispatch -- movetoworkspace -1")
   ```
   Inside the Caelestia `global` submap this wrapper can fail silently, especially because a parallel `launcherInterrupt` bind with `ignore_mods = true` fires on the same physical key combination.
3. **Caelestia `launcherInterrupt` shadowing**: `lua-fragments.nix` emits a `caelestia:launcherInterrupt` bind for every bind that uses `mainMod`, with `ignore_mods = true`. That means `SUPER + left` and `SUPER + CTRL + left` both trigger the interrupt. While `non_consuming` should let the real bind run, in practice it can prevent the wrapped `exec_cmd` variant from executing.

## Fix

### 1. Add scroll binds in `nix/user/wm/hyprland/config/keybinds/core.nix`

```nix
"$mainMod CTRL, mouse_down, movetoworkspace, -1"
"$mainMod CTRL, mouse_up, movetoworkspace, +1"
```

### 2. Render `movetoworkspace` natively in `nix/user/wm/hyprland/config/lua-fragments.nix`

```nix
else if dispatcher == "movetoworkspace" then
  "hl.dsp.window.move({ workspace = ${builtins.toJSON argumentString} })"
```

This matches the official Hyprland 0.55 example config:

```lua
hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
```

## Generated output (excerpt)

```lua
hl.bind(mainMod .. " + CTRL + left",      hl.dsp.window.move({ workspace = "-1" }), { submap_universal = true })
hl.bind(mainMod .. " + CTRL + right",     hl.dsp.window.move({ workspace = "+1" }), { submap_universal = true })
hl.bind(mainMod .. " + CTRL + mouse_down", hl.dsp.window.move({ workspace = "-1" }), { submap_universal = true })
hl.bind(mainMod .. " + CTRL + mouse_up",   hl.dsp.window.move({ workspace = "+1" }), { submap_universal = true })
```

## Verification

```bash
nix flake check --no-build
make check
```

Both passed.

## Lesson

When a Hyprland Lua bind works in raw `hyprctl dispatch '...'` but not inside a generated config, check two things:

1. Is the dispatcher rendered natively (`hl.dsp.<namespace>.<fn>(...)`) or wrapped in `exec_cmd("hyprctl dispatch -- ...")`? Prefer native.
2. Does a shell-specific interrupt bind with `ignore_mods = true` shadow the modifier combination? If so, native rendering is more reliable than nested `exec_cmd` calls.

## Follow-up: scroll binds were removed again

After testing, the user found that modifier scroll binds collide with the plain
`SUPER + mouse_up/down` workspace-switch bind. Because Caelestia's
`launcherInterrupt` binds use `ignore_mods = true`, a `SUPER + CTRL + scroll`
event also matches the plain `SUPER + scroll` interrupt and workspace-switch
binds, causing both actions to fire at once.

Conclusion: keep scroll-based workspace switching on `SUPER + scroll` only.
Do **not** add `SUPER + ALT + scroll` (workspace switch) or
`SUPER + CTRL + scroll` (movetoworkspace) binds while the plain
`SUPER + scroll` binds exist. Arrow keys are the safe modifier-bearing
alternative.

The old belief that `hl.dsp.window.move({ workspace = ... })` was broken on Hyprland 0.55 was wrong; the actual problem was the `exec_cmd` fallback combined with Caelestia interrupt binds.
