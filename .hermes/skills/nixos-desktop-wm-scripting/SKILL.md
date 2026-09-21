---
name: nixos-desktop-wm-scripting
category: software-development
description: Write Hyprland dispatch scripts, keybinds, and window-manipulation behavior for NixOS desktop configurations.
triggers:
  - User wants to change Hyprland keybind behavior
  - Need a custom dispatcher script (toggle, resize, center, move window)
  - Adding floating/windowed-mode behavior to a keybind
  - Window resize/move logic that depends on monitor dimensions
  - Fixing a WM script that "klappt nicht" / does not work as expected
---

# NixOS Desktop WM Scripting

Writing custom Hyprland dispatcher scripts in a NixOS/Home Manager context. Covers keybind wiring, window manipulation, common dispatcher pitfalls, and the script → package → keybind integration flow.

## Script → Package → Keybind Integration Flow

1. Write the script body in the Hyprland module (e.g. `nix/user/wm/hyprland/default.nix`) as a `pkgs.writeShellScriptBin`.
2. Add it to `home.packages` or `j0nix.user.software.packages` so it lands in `~/home/profileDirectory/bin`.
3. Reference it from the keybind config (e.g. `nix/user/wm/hyprland/config/keybinds/core.nix`) via `${homeBinDir}/<script-name>`.
4. Reference `homeBinDir` in the keybind module arguments so the path resolves correctly.

Example wiring in `default.nix`:

```nix
hyprlandToggleFloatResizeScript = pkgs.writeShellScriptBin "wm-toggle-float-resize" ''
  hyprctl_bin="${hyprctlExec}"
  [ -x "$hyprctl_bin" ] || exit 0
  # ... script body
'';
```

Then add to packages:

```nix
j0nix.user.software.packages = [
  hyprlandToggleFloatResizeScript
];
```

And in the keybind module:

```nix
"$mainMod, t, exec, ${homeBinDir}/wm-toggle-float-resize"
```

## Hyprland 0.55+ Dispatch Syntax Migration (Critical)

Starting with Hyprland 0.55, `hyprctl dispatch` **interprets its argument as Lua code**, not as a legacy Hyprlang dispatcher string. The old syntax no longer works.

### What broke

| Old command (pre-0.55) | Result on 0.55+ | Fix |
|---|---|---|
| `hyprctl dispatch global caelestia:lock` | `')' expected near 'caelestia'` — `global` is a Lua keyword | `hyprctl dispatch 'hl.dsp.global("caelestia:lock")'` |
| `hyprctl dispatch focuswindow "class:foo"` | `')' expected near 'class'` | `hyprctl dispatch 'hl.dsp.focus({window = "class:^foo$"})'` |
| `hyprctl dispatch exec "[workspace 2 silent] kitty"` | `')' expected near '[` | `hyprctl dispatch 'hl.dsp.exec_cmd("[workspace 2 silent] kitty")'` |
| `hyprctl dispatch togglespecialworkspace passwords` | `')' expected near 'passwords'` | `hyprctl dispatch 'hl.dsp.exec_cmd("hyprctl dispatch togglespecialworkspace passwords")'` **(see Special Workspace Toggle pitfall below)** |
| `hyprctl keyword monitor DP-1,disable` | `keyword can't work with non-legacy parsers. Use eval.` | `hyprctl eval 'hl.monitor({output = "DP-1", disabled = true})'` |
| `resizewindowpixel exact $w $h` | `'x' and 'y' are required` or silent failure | `hyprctl dispatch 'hl.dsp.window.resize({x = '"$w"', y = '"$h"'})'` |
| `centerwindow 1` | `')' expected near '1'` | Compute center manually: `cx=$(( (mon_w - win_w) / 2 ))`, `cy=$(( (mon_h - win_h) / 2 ))`, then `hyprctl dispatch 'hl.dsp.window.move({x = '"$cx"', y = '"$cy"'})'` |

### General migration rules

- **`dispatch <dispatcher> <args>`** → wrap the whole dispatcher call in a Lua expression passed as a single quoted string: `hyprctl dispatch 'hl.dsp.<dispatcher>({key = "value"})'`
- Use **`hl.dsp.exec_cmd(...)`** for `exec` dispatcher with workspace qualifiers.
- Use **`hl.dsp.exec_cmd("hyprctl dispatch togglespecialworkspace NAME")`** for actual toggling behavior. `hl.dsp.focus({workspace = "special:NAME"})` only activates the special workspace as an overlay — it does not toggle it off when already visible.
- Use **`hl.dsp.window.move({ workspace = "N" })`** for `movetoworkspace` and **`hl.dsp.focus({ workspace = "N" })`** for `workspace`. These are the native Lua equivalents and are the preferred rendering path.
- Avoid falling back to **`hl.dsp.exec_cmd("hyprctl dispatch -- movetoworkspace N")`** inside generated Lua binds. In practice this wrapper can fail silently inside the Caelestia `global` submap, especially when the same key also has a `launcherInterrupt` bind with `ignore_mods = true`.
- For spatial window movement, use **`hl.dsp.exec_cmd("hyprctl dispatch -- movewindow u")`** if the native `hl.dsp.window.move({direction = "u"})` variant proves unreliable in your Hyprland version.
- Use **`hl.dsp.focus({window = "class:^PATTERN$"})`** instead of `focuswindow`.
- Use **`hyprctl eval`** instead of `hyprctl keyword`.
- **Always single-quote the Lua argument** so the shell does not expand it.

### Shell-script migration checklist

When updating WM scripts or Nix modules that call `hyprctl dispatch`/`hyprctl keyword`:

1. Find every `hyprctl dispatch` invocation.
2. Map the old dispatcher to the equivalent `hl.dsp.*` Lua call.
3. For `exec`, wrap the command string in `hl.dsp.exec_cmd("...")`.
4. For `keyword`, switch to `hyprctl eval` with the matching `hl.*` config function.
5. Test interactively with `hyprctl dispatch '...'` before committing the script change.
6. Watch for binds that silently fail — the Hyprland config may still load without error even if a dispatch is invalid.

## Common Dispatcher Pitfalls

### Absolute vs Relative Resize

| Dispatcher | Behavior | Use when |
|-----------|----------|----------|
| `resizeactive` | **Delta** — adds/subtracts from current size | Growing/shrinking by a fixed increment |
| `resizewindowpixel` | **Absolute** — sets exact pixel dimensions | Setting a window to an exact size (e.g. 50% of monitor) |

**Common bug:** Using `resizeactive exact 1400 920` to set an exact size silently fails because `resizeactive` treats the arguments as a delta. Always use `resizewindowpixel` for absolute sizing.

```bash
# WRONG — resizeactive is delta-based
hyprctl dispatch resizeactive exact 1400 920

# CORRECT — resizewindowpixel is absolute
hyprctl dispatch resizewindowpixel exact 1400 920
```

### Floating Toggle Script Pattern

When you want `SUPER+T` to toggle floating AND resize the window to a specific size when it enters floating mode:

```bash
# Toggle floating state (0.55+ Lua syntax)
hyprctl dispatch 'hl.dsp.window.float({action = "toggle"})'

# Read the new floating state
floating="$(hyprctl activewindow -j | jq -r '.floating // false')"
if [ "$floating" = "true" ]; then
  mon_w="$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .width')"
  mon_h="$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .height')"
  if [ -n "$mon_w" ] && [ -n "$mon_h" ]; then
    w=$(( mon_w / 2 ))
    h=$(( mon_h / 2 ))
    # 0.55+ resize syntax
    hyprctl dispatch 'hl.dsp.window.resize({x = '"$w"', y = '"$h"'})'
    # centerwindow has no Lua equivalent; compute center coords
    win_w="$(hyprctl activewindow -j | jq -r '.size[0] // 0')"
    win_h="$(hyprctl activewindow -j | jq -r '.size[1] // 0')"
    if [ "$win_w" -gt 0 ] && [ "$win_h" -gt 0 ]; then
      cx=$(( (mon_w - win_w) / 2 ))
      cy=$(( (mon_h - win_h) / 2 ))
      hyprctl dispatch 'hl.dsp.window.move({x = '"$cx"', y = '"$cy"'})'
    fi
  fi
fi
```

Key points:
- Query `activewindow -j` AFTER `togglefloating` to read the new state.
- Query `monitors -j` for the focused monitor dimensions.
- Use integer division for percentage calculations.
- `centerwindow 1` centers the window (the `1` means "center on current monitor").

### Special Workspace Toggle Pitfall (0.55+)

`hl.dsp.focus({workspace = "special:NAME"})` **does not toggle** the special workspace. It only activates it as an overlay. If the special workspace is already visible, calling it again leaves it visible instead of hiding it.

**Correct toggle pattern:**

```bash
hyprctl dispatch 'hl.dsp.exec_cmd("hyprctl dispatch togglespecialworkspace passwords")'
```

This nests a legacy `togglespecialworkspace` dispatch inside `exec_cmd`, which Hyprland still executes. The outer `hl.dsp.exec_cmd(...)` wrapper satisfies the Lua parser while the inner string preserves the actual toggle behavior.

**Clean toggle script design:**

```bash
# Check if the app is already running
window_addr=$(hyprctl clients -j | jq -r '.[] | select(.class == "org.keepassxc.KeePassXC") | .address' | head -n1)

if [ -z "$window_addr" ]; then
  # Not running — start it on the special workspace
  hyprctl dispatch 'hl.dsp.exec_cmd("[workspace special:passwords silent] keepassxc-startup")'
else
  # Running — toggle the special workspace visibility
  hyprctl dispatch 'hl.dsp.exec_cmd("hyprctl dispatch togglespecialworkspace passwords")'
  # After toggling on, focus the window
  hyprctl dispatch 'hl.dsp.focus({window = "address:'"$window_addr"'"})'
fi
```

Key points:
- Never kill-and-restart the process as a "fallback" — this causes endless restart loops.
- Query `.address` from `hyprctl clients -j` for precise targeting instead of regex class matching.
- Focus by `address:` after toggling on to ensure keyboard input reaches the window.

### Directional workspace move vs spatial window move

Two similar-sounding dispatchers accept completely different arguments.

| Dispatcher | Valid arguments | Meaning |
|-----------|----------------|---------|
| `movewindow` | `u`, `d`, `l`, `r` | Shift the focused window spatially within the *current* workspace (up/down/left/right) |
| `movetoworkspace` | `1`, `2`, `...`, `+1`, `-1`, `special:NAME` | Move the focused window to a *different* workspace by name or relative offset |

**Common bug:** Writing `movetoworkspace l` (or `r`, `u`, `d`) to shift a window spatially. Hyprland does not error on this, but the bind silently does nothing because the argument is not a valid workspace identifier.

```nix
# WRONG — movetoworkspace does not accept l/d/u/r
"$mainMod SHIFT, h, movetoworkspace, l"

# CORRECT — spatial shift within the same workspace
"$mainMod SHIFT, h, movewindow, l"
```

### Nix Shell Script Quote Escaping Pitfall

When a Nix-generated shell script wraps a `bash -lc` call that itself contains a
`hyprctl dispatch '...'` with parentheses, the single-quote nesting collapses:

```nix
# WRONG — inner single quote closes outer bash -lc quote
bash -lc '
  hyprctl dispatch 'hl.dsp.dpms({state = "on"})'
'
```

Generated script becomes unparseable because bash sees `'hl.dsp` as closing the
`bash -lc '` string, then chokes on the bare `(`.

**Fix:** Use double quotes for `bash -lc` and escape inner double quotes with
`\"`:

```nix
bash -lc "
  hyprctl dispatch 'hl.dsp.dpms({state = \"on\"})'
"
```

Always run `bash -n` on the generated store path before deploying. See
`references/nix-shell-quote-escaping-dispatch.md` for full rules, the
`$variable`-expansion trap, and other Nix script contexts where this pattern
applies (systemd service scripts, `home.file.<path>.text`, etc.).

## Window Class Matching Gotchas

| Modifier combo | Arrows (left/right/up/down) | H/J/K/L | Effect |
|---|---|---|---|
| `$mainMod` | `movefocus` | `movefocus` | Focus neighboring window |
| `$mainMod ALT` | `workspace -1/+1` | `movetoworkspace` (rel) | Switch / move to adjacent workspace |
| `$mainMod SHIFT` | `movewindow u/d/l/r` | `movewindow u/d/l/r` | Spatially shift focused window |
| `$mainMod CTRL+SHIFT` | `movetoworkspace ±1` | — | Move window to adjacent workspace |

When arrow keys are used for `movefocus`, do **not** also bind them to
`workspace` on the same modifier — the later bind in the Lua submap wins
and the workspace switch becomes unreachable. This appeared as a hidden
duplicate bind that was cleaned up alongside the Lua handler fix.
(Reference: `references/silent-window-move-broken-0.55.md`.)

### Window Class Matching Gotchas

The `class` field in `hyprctl clients -j` often differs from the application's display name.

| Application | Display name | Actual `class` value |
|---|---|---|
| KeePassXC | KeePassXC | `org.keepassxc.KeePassXC` |
| Firefox | Firefox | `firefox` or `Firefox` depending on build |
| VS Code | Visual Studio Code | `code-oss` (OSS build) or `code` (Microsoft build) |

**Always verify the class before writing a script:**

```bash
hyprctl clients -j | jq '.[] | select(.title | contains("KeePass")) | {class, title, address}'
```

When matching by class in Lua dispatcher calls, use `^...$` regex anchors and the exact class string:

```bash
# WRONG — never matches
hyprctl dispatch 'hl.dsp.focus({window = "class:^(KeePassXC)$"})'

# CORRECT
hyprctl dispatch 'hl.dsp.focus({window = "class:^org.keepassxc.KeePassXC$"})'
```

Prefer `address:` targeting over `class:` when possible — it is unambiguous and survives title changes.

## Keybind Merge Architecture and Shell Overrides

The keybind system has a three-layer architecture in `nix/user/wm/hyprland/config/keybinds/`:

- `core.nix` — Core binds (navigation, window management, media, layout). Exports `coreBinds` (interactive binds that go into the Caelestia submap), `baseBind` (navigation + workspace), `baseBinde` (repeating), `baseBindm` (mouse), `baseBindl` (locked), `baseBindle` (locked+repeating).
- `shells.nix` — Shell-specific binds per shell (currently only `caelestia`). Each shell attrset can include an `overrides` list.
- `lib.nix` — Pure helper library (parsing, rendering, categorization). No bind definitions.
- `keybinds.nix` — Orchestrator. Merges Core + Shell binds per type, parses into structured attrsets for Lua rendering.

### The Override Mechanism (anti-collision pattern)

When a shell (e.g. Caelestia) wants to replace a Core bind rather than add to it, it declares an `overrides` list:

```nix
caelestia = {
  overrides = [
    { type = "bindl"; mods = ""; key = "XF86AudioPlay"; }
    { type = "bindle"; mods = ""; key = "XF86AudioRaiseVolume"; }
    # ...
  ];
  # shell-specific binds...
};
```

`keybinds.nix` filters Core entries matching `(type, mods, key)` before appending shell entries:

```nix
mergedBindList = key:
  (lib.filter (entry: !(isOverridden key entry)) (baseHyprKeybinds.${key} or [ ]))
  ++ (shellHyprKeybinds.${key} or [ ]);
```

This replaces the old pattern of appending shell binds on top of Core binds and relying on Hyprland's last-wins semantics. Without it, `hyprctl binds` shows duplicate entries and debugging is harder.

### When to use overrides

- A shell provides its own media/brightness/screenshot handling (e.g. Caelestia routes `XF86AudioPlay` to `caelestia:mediaToggle` instead of `playerctl`).
- A shell replaces a Core mouse bind with different modifiers.
- Any case where the same `(type, mods, key)` triple would appear in both Core and Shell lists.

### When NOT to use overrides

- Shell adds a bind on a key Core doesn't use → just add it to the shell's bind list.
- Shell wants to augment (not replace) a Core bind → not possible with overrides; use a different key or a wrapper script.

### Pitfall: silent duplicates without overrides

Before the override mechanism was added, Core and Shell both emitted binds for `XF86AudioPlay`, `XF86MonBrightnessUp`, `Print`, volume keys, etc. These worked by accident (last-wins), but:
- `hyprctl binds` showed 12+ duplicate entries.
- Changing the order of Core vs Shell in the merge would silently change behavior.
- The Core entries were dead code that couldn't be removed without breaking non-Caelestia shells.

Always check for `(type, mods, key)` collisions when adding a new shell or modifying existing shell binds. See `references/keybind-override-mechanism.md` for the full architecture map.

### Pitfall: Caelestia launcherInterrupt binds mask modifier combinations (and scroll)

For the Caelestia shell, `lua-fragments.nix` emits a parallel `caelestia:launcherInterrupt` bind for every bind that uses `mainMod`, including binds that already carry `CTRL` or `SHIFT`. These interrupt binds set `ignore_mods = true`, which means they fire on `SUPER + left` **and** on `SUPER + CTRL + left`, `SUPER + SHIFT + left`, etc. Although they are also `non_consuming`, in practice they can prevent the real action (`movetoworkspace -1/+1`) from executing inside the `global` submap when that action is rendered as a wrapped `exec_cmd("hyprctl dispatch -- ...")` call.

Symptoms:
- `$mainMod + CTRL + left/right` appears in the generated `shell.lua` as `movetoworkspace -1/+1`, but pressing it does nothing.
- Modifier scroll binds (e.g. `$mainMod + CTRL + mouse_up/down`) cannot be added safely because the existing `$mainMod + mouse_up/down` workspace-switch bind and its parallel `launcherInterrupt` bind already claim the scroll wheel with `ignore_mods = true`. The modifier variant collides and triggers both workspace switch and window move at once.

Fix:
Render `movetoworkspace` natively in the Lua generator:

```nix
else if dispatcher == "movetoworkspace" then
  "hl.dsp.window.move({ workspace = ${builtins.toJSON argumentString} })"
```

This was the only reliable fix in practice for `$mainMod + CTRL + left/right`
when using the Caelestia shell. The `exec_cmd("hyprctl dispatch -- ...")`
fallback always failed inside the `global` submap.

Important:
Do **not** add modifier scroll binds (`$mainMod + CTRL + mouse_up/down` or
`$mainMod + ALT + mouse_up/down`) while `$mainMod + mouse_up/down` is bound to
`workspace`. The `launcherInterrupt` binds use `ignore_mods = true`, so the
base scroll bind fires even when extra modifiers are held. This causes both the
workspace switch and the attempted window move to trigger at once.

Also verify shell-specific keybind files (`shells.nix`) do not accidentally map
`$mainMod + ALT + mouse_up/down` to `movetoworkspace` when the intent is only
`workspace` focus switching.

See `references/movetoworkspace-native-lua-and-scroll-collision.md` for the
full session trace, generated bind output, and verification commands.
See `references/movetoworkspace-scroll-caelestia-interrupt.md` for the earlier
attempt that added scroll binds and why they were removed.

## Window Rule References

Remember the window rule module (`nix/user/wm/hyprland/config/window-rules.nix`) exists for declarative window behavior. Scripts are for interactive/dynamic behavior that window rules cannot express (e.g. "resize to 50% when user presses a key").

## Reference files

- `references/resizeactive-pitfall.md` — Session 2026-06-08: resizeactive vs resizewindowpixel dispatcher confusion.
- `references/hyprland-0.55-dispatch-syntax.md` — Session 2026-06-10: Hyprland 0.55+ broke `hyprctl dispatch` by switching to Lua expression parsing. Complete migration table per dispatcher and interactive verification steps.
- `references/special-workspace-toggle-pitfall.md` — Session 2026-06-10: KeePassXC toggle script had three separate bugs (kill-on-mismatch, non-toggling special workspace focus, wrong window class). Covers the clean toggle design pattern and the `exec_cmd` workaround for `togglespecialworkspace`.
- `references/silent-window-move-broken-0.55.md` — Session 2026-06-11: `hl.dsp.window.move({workspace = ...})` and `hl.dsp.window.move({direction = ...})` render valid Lua but are silently ignored by Hyprland 0.55. Shows the fallback to `exec_cmd("hyprctl dispatch -- ...")` and the `movewindow` vs `movetoworkspace` direction argument pitfall.
- `references/nix-shell-quote-escaping-dispatch.md` — Session 2026-06-12: Nix `writeShellScript` with `bash -lc '...'` containing a `hyprctl dispatch 'hl.dsp.dpms({state = \"on\"})'` call breaks because the inner single quote closes the outer `bash -lc` quote. Fix: switch outer quote to double quotes and escape inner `\"` as `\\\"`. Always verify with `bash -n` on the generated store path.
- `references/keybind-override-mechanism.md` — Session 2026-07-07: Full architecture map of the three-layer keybind system (core.nix / shells.nix / lib.nix / keybinds.nix), the shell-override anti-collision pattern, dual hyprlang+Lua render paths, configurable bind variables, and remaining known duplicate/type-conflict issues.
- `references/movetoworkspace-native-lua-and-scroll-collision.md` — Session 2026-07-08: `movetoworkspace +1/-1` failed silently because the Lua generator fell back to `exec_cmd("hyprctl dispatch -- ...")`; Caelestia's `launcherInterrupt` binds with `ignore_mods = true` masked the bind. The fix renders `movetoworkspace` natively as `hl.dsp.window.move(...)`. Also covers the `$mainMod+ALT+scroll` misconfiguration in `shells.nix` and why modifier scroll binds collide with base-modifier scroll.
- `references/movetoworkspace-scroll-caelestia-interrupt.md` — Session 2026-07-08: earlier attempt that added scroll binds and the collision analysis that led to their removal.

## Commit Policy

Split WM script changes and keybind wiring into separate atomic commits per the repo's required Conventional Commits style. Do not bundle unrelated desktop tweaks.
