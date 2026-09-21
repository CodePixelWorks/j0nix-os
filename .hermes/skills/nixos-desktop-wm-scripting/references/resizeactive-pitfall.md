# Session 2026-06-08 — Resizeactive vs Resizewindowpixel Fix

## Problem Report

User reported: "das floating toggle klappt nicht" (the floating toggle doesn't work).

## Root Cause

The `wm-toggle-float-resize` script used `resizeactive exact $w $h` after toggling floating mode. `resizeactive` is a **delta-based** dispatcher — it adds the given values to the current window size, not sets them absolutely. The `exact` prefix does not change this behavior. The window either did not resize or resized unpredictably.

### Wrong code

```bash
"$hyprctl_bin" dispatch resizeactive exact "$w" "$h"
```

### Correct code

```bash
"$hyprctl_bin" dispatch resizewindowpixel exact "$w" "$h"
```

## Same Bug in wm-windowed-mode

The pre-existing `wm-windowed-mode` script (SUPER+SHIFT+T) had the identical bug:

```bash
# WRONG (pre-existing)
"$hyprctl_bin" dispatch resizeactive exact 1400 920

# Corrected
"$hyprctl_bin" dispatch resizewindowpixel exact 1400 920
```

## Key Lesson

Always verify dispatcher semantics before assuming a parameter changes the behavior:
- `resizeactive` — relative/delta sizing
- `resizewindowpixel` — absolute pixel sizing

This applies to ALL Hyprland dispatcher invocations, not just window resize. When in doubt, check `hyprctl dispatch --help` or the Hyprland wiki.
