# Hyprland + Caelestia Keybind Stability Plan

## Purpose

This runbook documents the keybind regression work around:

- `wmShell = "caelestia-shell"`
- `programs.caelestia.quickshellRuntime = "upstream-dev"`
- `displayManager = "greetd"` with `greetd.greeter = "qmlgreet"`

It exists so future debugging does not restart from zero.

## Problem Statement

Observed behavior:

- Hyprland starts normally.
- Config parses successfully.
- `~/.config/hypr/hyprland.conf` contains expected binds.
- But keybinds intermittently stop working at runtime.

This indicates a runtime/session ordering problem rather than a static config generation bug.

## Known Working vs Risky Paths

Known-good historical baseline:

- `quickshellRuntime = "wrapped"`
- `greetd.greeter = "tuigreet"`
- Caelestia submap pattern (`submap = global`) from upstream dots.

Current risky combo under investigation:

- `quickshellRuntime = "upstream-dev"`
- `greetd.greeter = "qmlgreet"`
- auto session entry (`auto-wm-session`), Hyprland as qmlgreet compositor.

## Relevant Change Timeline

- `55b3ec4`: switched Caelestia runtime to `upstream-dev`.
- `91d98a7`: forwarded QML/plugin paths for upstream runtime wrapper.
- `601302a`: removed bare-Super catchall submap lines.
- `afd29ab`: removed submap-only keybind path and returned to normal bind tables.
- `db9b89f`: enabled `binds.disable_keybind_grabbing = true`.
- `b74e6c9`: added runtime keybind diagnostics snapshots.

## Current Instrumentation

Temporary diagnostics are enabled via:

```nix
settings.hyprland.debug.keybindDiagnostics = {
  enable = true;
  delaySeconds = 8;
};
```

This writes snapshots to:

- `~/.local/state/hyprland/diagnostics/`

and captures:

- `hyprctl configerrors`
- `hyprctl globalshortcuts`
- `hyprctl binds`
- `hyprctl devices`
- `hyprctl layers`
- session/environment metadata

## Root-Cause Isolation Matrix

Run these four permutations and collect diagnostics for each:

1. `wrapped + tuigreet`
2. `wrapped + qmlgreet`
3. `upstream-dev + tuigreet`
4. `upstream-dev + qmlgreet`

Only change one axis at a time:

- Axis A: `settings.programs.caelestia.quickshellRuntime`
- Axis B: `settings.greetd.greeter`

## Data Collection Checklist (per permutation)

After login (without manual recovery commands first):

1. Validate symptom: test `SUPER+Return`, `SUPER+R`, `SUPER+J/K/H/L`.
2. Collect newest diagnostics file:
   - `ls -1t ~/.local/state/hyprland/diagnostics | head`
3. Collect Hyprland runtime log:
   - `/run/user/$UID/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log`
4. Record whether Caelestia shell process is alive:
   - `pgrep -af 'quickshell|caelestia shell'`
5. Record whether restarting shell changes behavior:
   - `wm-shell-recover`

## Decision Gates

Use the matrix results to classify root cause:

- If failures correlate with `qmlgreet` only:
  - focus fix on greetd/qmlgreet Hyprland handoff and environment sanitization.
- If failures correlate with `upstream-dev` only:
  - focus fix on upstream quickshell runtime behavior and IPC/shortcuts registration timing.
- If only `upstream-dev + qmlgreet` fails:
  - treat as interaction bug; add explicit ordering/retry barrier between user Hyprland start and Caelestia startup.
- If all fail:
  - revisit recent keybind architecture changes independent of greeter/runtime.

## Stable Fix Strategy

Implement in this order:

1. Identify the failing matrix quadrant(s) and lock a reproducible trigger.
2. Add a deterministic startup barrier (only if required by evidence), e.g.:
   - wait for Hyprland IPC readiness
   - then start Caelestia and force bind registration stage
3. Keep one canonical keybind model:
   - either upstream submap model, or standard Hyprland binds
   - avoid dual behavior without explicit feature flag.
4. Add assertions/guards to prevent unsupported combinations.
5. Keep diagnostics optional but retained behind debug flags for future incidents.

## Exit Criteria for This Incident

A fix is accepted when:

- keybinds work after fresh login across reboots,
- no manual `hyprctl dispatch submap ...` workaround is needed,
- no shell double-start or dead UI phase appears,
- and the selected supported combinations are documented.

## Upstream Reference

- `caelestia-dots/caelestia` uses submap/global-shortcut pattern and documents `greetd + tuigreet` as recommended.
- This repo may diverge for multi-WM/multi-greeter support, but must keep one clearly documented stable path.
