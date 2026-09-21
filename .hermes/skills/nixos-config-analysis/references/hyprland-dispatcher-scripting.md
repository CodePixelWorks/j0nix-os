# Hyprland Dispatcher Scripting Patterns

Common patterns and pitfalls when writing shell scripts that wrap `hyprctl dispatch` for custom keybind behavior in NixOS Home Manager configurations.

## resizeactive vs resizewindowpixel

| Dispatcher | Behavior | Use case |
|-----------|----------|----------|
| `resizeactive` | **Delta-based** — adds/subtracts from current size | Resizing with mouse or keyboard incrementally |
| `resizewindowpixel` | **Absolute** — sets exact pixel dimensions | Setting a specific window size (e.g., 50% monitor, fixed 1400x920) |

**Pitfall**: Using `resizeactive exact 1400 920` does NOT set the window to 1400x920. It treats `exact` as a delta axis mode, not as an absolute sizing flag. The window will resize by some delta, not to the target size.

**Correct pattern for absolute sizing**:
```bash
# After toggling to floating, set exact dimensions
hyprctl dispatch resizewindowpixel exact 1400 920
hyprctl dispatch centerwindow 1
```

**Correct pattern for percentage-based sizing**:
```bash
# Query focused monitor dimensions
mon_w=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .width')
mon_h=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .height')

w=$(( mon_w / 2 ))
h=$(( mon_h / 2 ))

hyprctl dispatch resizewindowpixel exact "$w" "$h"
hyprctl dispatch centerwindow 1
```

## Toggle → Query → Conditional Action Pattern

When a keybind needs smart behavior based on the new state after a toggle:

```bash
hyprctl_bin="${hyprctlExec}"

# 1. Toggle the state
"$hyprctl_bin" dispatch togglefloating >/dev/null 2>&1 || true

# 2. Query the new state
floating=$("$hyprctl_bin" activewindow -j 2>/dev/null | jq -r '.floating // false' 2>/dev/null || echo false)

# 3. Apply conditional actions only if in the desired state
if [ "$floating" = "true" ]; then
    # Window is now floating — resize and center
    mon_w=$("$hyprctl_bin" monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .width' 2>/dev/null || true)
    mon_h=$("$hyprctl_bin" monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .height' 2>/dev/null || true)
    if [ -n "$mon_w" ] && [ -n "$mon_h" ]; then
        w=$(( mon_w / 2 ))
        h=$(( mon_h / 2 ))
        "$hyprctl_bin" dispatch resizewindowpixel exact "$w" "$h" >/dev/null 2>&1 || true
    fi
    "$hyprctl_bin" dispatch centerwindow 1 >/dev/null 2>&1 || true
fi
# If toggled back to tiled, the resize/center steps are skipped — window snaps to layout
```

## Keybind Wiring in Nix

Replace bare dispatcher binds with `exec` calls to custom scripts:

```nix
# In keybinds/core.nix — before:
"$mainMod, t, togglefloating,"

# After:
"$mainMod, t, exec, ${homeBinDir}/wm-toggle-float-resize"
```

Then declare the script in the Hyprland HM module:

```nix
hyprlandToggleFloatResizeScript = pkgs.writeShellScriptBin "wm-toggle-float-resize" ''
  # ... script body from above pattern
'';
```

And include it in `home.packages` (or `j0nix.user.software.packages`):

```nix
j0nix.user.software.packages = [
  # ... other packages
  hyprlandToggleFloatResizeScript
];
```

## Common Dispatchers Reference

| Dispatcher | Argument | Effect |
|-----------|----------|--------|
| `togglefloating` | none | Toggle floating/tiled state |
| `resizewindowpixel` | `exact <w> <h>` | Set absolute pixel size |
| `resizeactive` | `<dx> <dy>` | Resize by delta pixels |
| `centerwindow` | `1` or none | Center window on monitor |
| `fullscreen` | `0` | True fullscreen (hides bar/shell) |
| `fullscreen` | `1` | Maximized (keeps bar/shell visible) |
| `killactive` | none | Close active window |
| `movefocus` | `l/r/u/d` | Move focus directionally |
| `movewindow` | `l/r/u/d` | Move active window directionally |
