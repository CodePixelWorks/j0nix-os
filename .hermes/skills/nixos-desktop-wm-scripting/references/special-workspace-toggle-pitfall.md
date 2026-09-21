# Session 2026-06-10 — KeePassXC Toggle Script Rewrite

## Problem Report

User reported: "Wieso geht jetzt keepassxc-toggle nicht - es kommt kein keepass mehr - wie koennen wir das sauber und ordentlich bauen das toggle script?"

The toggle script had completely stopped working after the recent caelestia-shell and Hyprland 0.55 upgrades.

## Root Cause (Three Separate Bugs)

### Bug 1: `client_looks_locked()` killed KeePassXC on title mismatch

The old toggle script checked if the window looked locked by matching the title against the database basename. If the title did not match (e.g. "Neu - KeePassXC" when creating a new entry, or the lock screen view), the script killed the KeePassXC process and restarted it. This caused endless restart loops and made the app unusable.

```bash
# WRONG — kills process when title doesn't match
client_looks_locked() {
  local title="$(hyprctl activewindow -j | jq -r '.title // empty')"
  [[ "$title" =~ ${databaseBasename}$ ]] || return 1
  return 0
}
# ... later: if ! client_looks_locked; then pkill -f keepassxc; exec keepassxc-startup; fi
```

### Bug 2: `hl.dsp.focus({workspace = "special:passwords"})` does not toggle

The script used `hl.dsp.focus({workspace = "special:passwords"})` to show/hide the special workspace. In Hyprland 0.55+, this only **activates** the special workspace as an overlay — it never hides it. The user pressed the toggle key, saw KeePassXC appear, pressed it again, and nothing happened.

```bash
# WRONG — activates overlay only, never hides
hyprctl dispatch 'hl.dsp.focus({workspace = "special:passwords"})'

# CORRECT — preserves legacy toggle behavior via exec_cmd workaround
hyprctl dispatch 'hl.dsp.exec_cmd("hyprctl dispatch togglespecialworkspace passwords")'
```

### Bug 3: Window class regex was wrong

The script tried to focus KeePassXC with `class:^(KeePassXC)$`, but the actual window class is `org.keepassxc.KeePassXC`. This meant the focus dispatch silently failed every time.

```bash
# WRONG — never matches
hyprctl dispatch 'hl.dsp.focus({window = "class:^(KeePassXC)$"})'

# CORRECT
hyprctl dispatch 'hl.dsp.focus({window = "class:^org.keepassxc.KeePassXC$"})'
```

## Clean Toggle Design

The rewritten script follows a simple, robust pattern:

1. **Check if KeePassXC is running** — query `hyprctl clients -j` for the window address by class (`org.keepassxc.KeePassXC`).
2. **If not running** — start it with `keepassxc-startup` on the special workspace.
3. **If running** — toggle the special workspace with `togglespecialworkspace` (via the `exec_cmd` workaround), then focus the window by its exact `address:`.

```nix
# Simplified logic from the rewritten toggle script
toggleScript = pkgs.writeShellScriptBin "keepassxc-toggle" ''
  set -eu
  HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
  WORKSPACE_NAME="${lib.escapeShellArg workspaceName}"

  client_addr="$($HYPRCTL clients -j | ${pkgs.jq}/bin/jq -r \
    '.[] | select(.class == "org.keepassxc.KeePassXC") | .address' | head -n1)"

  if [ -z "$client_addr" ]; then
    # Not running — start on special workspace
    $HYPRCTL dispatch "hl.dsp.exec_cmd(\"[workspace special:$WORKSPACE_NAME silent] ${lib.getExe launchScript}\")"
  else
    # Running — toggle special workspace
    $HYPRCTL dispatch "hl.dsp.exec_cmd(\"hyprctl dispatch togglespecialworkspace $WORKSPACE_NAME\")"
    # Focus the window after toggling on
    $HYPRCTL dispatch "hl.dsp.focus({window = \"address:$client_addr\"})" >/dev/null 2>&1 || true
  fi
'';
```

The startup script was similarly simplified — no more database-basename title matching, no process killing, just straightforward workspace assignment and launch.

## Key Lessons

1. **Never kill-and-restart in toggle scripts.** If the app state is unexpected, investigate why instead of destroying it.
2. **`hl.dsp.focus({workspace = "special:..."})` is not a toggle** — it only shows. Use the `exec_cmd("hyprctl dispatch togglespecialworkspace ...")` workaround for true toggle behavior.
3. **Always verify window class strings** with `hyprctl clients -j | jq '.[].class'` before writing matchers. The class is often the application's Java package name or internal ID, not the display name.
4. **Prefer `address:` targeting** over `class:` when you already have the window address from a previous query. It is unambiguous and survives title changes.
5. **Query first, dispatch second.** The clean pattern is: (a) query `clients -j` to find the window, (b) decide the action, (c) dispatch. The old script tried to dispatch first and recover from failure, which led to the kill-and-restart anti-pattern.
