# Session 2026-06-10 — Hyprland 0.55 Dispatch Syntax Migration

## Problem Report

User reported: "das keybind macht nur nix mehr" — `$mainMod SHIFT + P` (KeePassXC toggle) and `WIN + L` (lock screen) both stopped working.

## Root Cause Diagnosis

Hyprland was upgraded to 0.55.1. In this version, `hyprctl dispatch` **parses its argument as a Lua expression** instead of a legacy Hyprlang dispatcher string. Scripts and keybinds that used the old syntax silently failed or produced parser errors.

### Diagnostic steps

```bash
# Old lock-screen command that worked before 0.55
hyprctl dispatch global caelestia:lock
# error: [string "return hl.dispatch(global caelestia:lock)"]:1: ')' expected near 'caelestia'

# Old KeePassXC toggle command (indirectly via shell scripts)
hyprctl dispatch focuswindow "class:foo"
# error: ')' expected near 'class'

# Dispatcher still works if passed a valid Lua expression
hyprctl dispatch 'hl.dsp.global("caelestia:lock")'
# → ok
```

The `global` keyword in `hyprctl dispatch global caelestia:lock` was being parsed as Lua's `global` statement, causing a syntax error. All other dispatchers with arguments containing colons, brackets, or bare strings hit the same issue.

### Secondary issue: keybind collision

KeePassXC toggle bind (`$mainMod SHIFT + p`) was additionally shadowed by Caelestia upstream's `pin` dispatcher on the same key combination. Both binds were rendered into the `global` submap, with `pin` winning. Moving `pin` to `$mainMod SHIFT + i` resolved the collision.

## Files modified and migration examples

### 1. `nix/user/wm/hyprland/config/keybinds/core.nix` — keybind collision fix

```nix
# Before: $mainMod SHIFT, p collided with keepassxc-toggle
"$mainMod SHIFT, p, pin"

# After: pin moved to $mainMod SHIFT, i
"$mainMod SHIFT, i, pin"
```

### 2. `nix/user/wm/shell-launcher.nix` — lock-screen script

```bash
# Before (pre-0.55)
${hyprctlExec} dispatch global caelestia:lock >/dev/null 2>&1 && exit 0

# After (0.55 Lua syntax)
${hyprctlExec} dispatch 'hl.dsp.global("caelestia:lock")' >/dev/null 2>&1 && exit 0
```

### 3. `nix/user/programs/keepassxc/default.nix` — focus + workspace dispatchers

```bash
# Before
${pkgs.hyprland}/bin/hyprctl dispatch focuswindow "class:^(KeePassXC)$" >/dev/null 2>&1 || true
${pkgs.hyprland}/bin/hyprctl dispatch exec "[workspace special:${workspaceName} silent] ${lib.getExe launchScript}"
${pkgs.hyprland}/bin/hyprctl dispatch togglespecialworkspace ${lib.escapeShellArg workspaceName} >/dev/null 2>&1 || true

# After
${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.focus({window = "class:^(KeePassXC)$"})' >/dev/null 2>&1 || true
${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.exec_cmd("[workspace special:${workspaceName} silent] ${lib.getExe launchScript}")'
${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.focus({workspace = "special:${workspaceName}"})' >/dev/null 2>&1 || true
```

## Complete dispatcher mapping

| Legacy dispatcher | Lua equivalent for `hyprctl dispatch` |
|---|---|
| `exec "[workspace 2 silent] kitty"` | `'hl.dsp.exec_cmd("[workspace 2 silent] kitty")'` |
| `focuswindow "class:^foo$"` | `'hl.dsp.focus({window = "class:^foo$"})'` |
| `togglespecialworkspace passwords` | `'hl.dsp.exec_cmd("hyprctl dispatch togglespecialworkspace passwords")'` **(see toggle pitfall below)** |
| `global caelestia:lock` | `'hl.dsp.global("caelestia:lock")'` |
| `workspace 1` | `'hl.dsp.focus({workspace = "1"})'` |
| `killactive` | `hl.dsp.window.close()` |
| `togglefloating` | `hl.dsp.window.float({action = "toggle"})` |
| `fullscreen 0` | `hl.dsp.window.fullscreen({mode = "fullscreen", action = "toggle"})` |
| `fullscreen 1` | `hl.dsp.window.fullscreen({mode = "maximized", action = "toggle"})` |
| `resizewindowpixel exact $w $h` | `'hl.dsp.window.resize({x = '"$w"', y = '"$h"'})'` |
| `centerwindow 1` | **No direct Lua equivalent.** Compute center coords manually: `cx = (mon_w - win_w) / 2`, `cy = (mon_h - win_h) / 2`, then `hl.dsp.window.move({x = cx, y = cy})` (see script pattern below) |
| `movewindow u/d/l/r` | `hl.dsp.exec_cmd("hyprctl dispatch -- movewindow u")` etc. — **(see `window.move` silent-failure pitfall below)** |
| `movetoworkspace N` | `hl.dsp.exec_cmd("hyprctl dispatch -- movetoworkspace N")` — **(do NOT use `hl.dsp.window.move`)** |
| `movefocus u/d/l/r` | `hl.dsp.focus({direction = "u"})` etc. |

The `window.move` family is documented in the Hyprland Lua API, but not all variants actually drive the compositor state in 0.55:

### `hl.dsp.window.move({workspace = ...})` — silent failure on `movetoworkspace`

Attempting to map the legacy `movetoworkspace` dispatcher to `hl.dsp.window.move({workspace = "5"})` renders syntactically valid Lua, but the compositor does **nothing** (no error, no window move, returns `ok`). The exact cause is either an unimplemented overload or a silently ignored parameter in this Hyprland release.

**Evidence from session 2026-06-11:**
- `workspaceMoveBinds` generated `hl.dsp.window.move({workspace = "1"})` for `$mainMod + SHIFT + 1`.
- `mainMoveBinds` generated `hl.dsp.window.move({workspace = "l"})` for `$mainMod + ALT + h` (and `l/d/u/r`). The argument `"l"` is not even a valid workspace identifier, so the dispatch was doubly broken.
- `mainMoveBinds` (spatial arrow/hjkl moves) generated `hl.dsp.window.move({direction = "u"})` which also silently failed.
- Result: **all window-move keybinds stopped working simultaneously** after a refactor added explicit `movetoworkspace` / `movewindow` handlers to `lua-fragments.nix`.

**Fix:** Remove the explicit handlers and let the binds fall back to the working `exec_cmd` wrapper:

```nix
# In lua-fragments.nix — REMOVED broken handlers
# else if dispatcher == "movetoworkspace" then
#   "hl.dsp.window.move({ workspace = ${builtins.toJSON argumentString} })"
# else if dispatcher == "movewindow" then
#   "hl.dsp.window.move({ direction = ${builtins.toJSON argumentString} })"
```

With those removed, the generic fallback renders:

```lua
hl.dsp.exec_cmd("hyprctl dispatch -- movetoworkspace 1")
hl.dsp.exec_cmd("hyprctl dispatch -- movewindow u")
```

Both execute correctly because the inner legacy dispatch is still supported when called this way.

### Verifying whether a Lua API call actually works

Do not trust a Lua expression just because `hyprctl dispatch '...'` returns `ok`. Test observable state changes:

```bash
# Get current workspace before
BEFORE=$(hyprctl activewindow -j | jq -r '.workspace.id')

# Run the dispatch
hyprctl dispatch 'hl.dsp.window.move({workspace = "2"})'

# Check if window actually moved
AFTER=$(hyprctl activewindow -j | jq -r '.workspace.id')
[ "$BEFORE" != "$AFTER" ] && echo "WORKS" || echo "SILENT FAILURE"
```

Use this pattern whenever adding a new `hl.dsp.*` handler to `lua-fragments.nix`.

## `hyprctl keyword` also changed

```bash
# Before
hyprctl keyword monitor DP-1,disable

# After
hyprctl eval 'hl.monitor({output = "DP-1", disabled = true})'
```

## Diagnostic tricks for 0.55+ script debugging

When a toggle or dispatcher script "macht nur nix mehr", verify step by step:

```bash
# Check which window is actually active before and after a dispatch
hyprctl activewindow -j | jq '{class, floating, fullscreen, at, size}'

# List all windows on a specific workspace
hyprctl clients -j | jq '.[] | select(.workspace.id == 5) | {class, address, floating}'

# Test a dispatcher interactively before embedding it in a script
hyprctl dispatch 'hl.dsp.window.float({action = "toggle"})'
# Response must be "ok". Any "error:" means the Lua syntax is wrong.

# Find an exact window address for precise targeting
hyprctl clients -j | jq '.[] | select(.class == "kitty") | .address'
# Then focus by address: hyprctl dispatch 'hl.dsp.focus({window = "address:0x..."})'
```

Common silent failure modes:
- The dispatch returns `ok` but the window state does not change → the active window is not what you think it is. Use `activewindow -j` to verify.
- Floating toggle works but resize/move has no effect → the window may still be in `fullscreen` mode (check `.fullscreen != 0`). Exit fullscreen first.
- `hl.dsp.focus({window = "class:..."})` returns `warning: window not found` → use `^...$` regex anchors, verify the exact class string, or switch to `address:` targeting.

### Special workspace toggle does not work with `hl.dsp.focus`

`hl.dsp.focus({workspace = "special:NAME"})` only **activates** the special workspace as an overlay. It does **not toggle** it off when called again. For true toggle behavior, use the `exec_cmd` workaround:

```bash
# WRONG — activates overlay only, no toggle
hyprctl dispatch 'hl.dsp.focus({workspace = "special:passwords"})'

# CORRECT — preserves legacy togglespecialworkspace behavior
hyprctl dispatch 'hl.dsp.exec_cmd("hyprctl dispatch togglespecialworkspace passwords")'
```

This was discovered in Session 2026-06-10 when the KeePassXC toggle script activated the special workspace but could never hide it again, causing the user to think the binding was broken.

### Window class matching: verify before scripting

The `class` field often differs from the application name. For example, KeePassXC reports `org.keepassxc.KeePassXC`, not `KeePassXC`:

```bash
hyprctl clients -j | jq '.[] | select(.title | contains("KeePass")) | {class, title, address}'
```

Output:
```json
{
  "class": "org.keepassxc.KeePassXC",
  "title": "*Passwords* - KeePassXC",
  "address": "0x12345678"
}
```

When a script relies on `class:` matching and the regex is wrong, the dispatch silently fails (returns `ok` but the window is not found). Always verify the exact class string with `hyprctl clients -j` before writing matchers.

## `hyprctl keyword` also changed

When Hyprland upgrades past 0.55, **search the entire repo for `hyprctl dispatch` and `hyprctl keyword` calls** and migrate them to the Lua expression syntax. Do not assume only interactive commands are affected — system scripts, toggle scripts, startup scripts, and lock-screen wrappers all break simultaneously.

Verify interactively before committing:

```bash
hyprctl dispatch 'hl.dsp.focus({workspace = "special:passwords"})'
```

If the response is `ok`, the syntax is valid. Parser errors start with `error:` and include the malformed Lua string.
