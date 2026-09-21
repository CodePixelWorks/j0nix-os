# Greetd Session Duplication — Duplicate Login Screen Buttons

## Symptom

The login screen (greeter) shows multiple identical-looking session buttons:
- "Hyprland" AND "Hyprland (UWSM)"
- "Hibernate" AND "Hybrid Sleep" AND "Suspend then Hibernate" (all with same icon)

## Root Causes

There are two independent duplication vectors:

### A. Session `.desktop` Duplicates (backend / config-driven)

In `system/wm/hyprland.nix`, the `greetdEnvironments` list determines which session files appear in the greeter:

```nix
# BUGGY: both variants unconditionally present
greetdEnvironments = [
  "auto-wm-session.desktop"
  "${hyprlandSessionName}.desktop"  # e.g. "hyprland-uwsm.desktop"
]
++ lib.optional useUWSM "hyprland.desktop"          ← redundant opposite
++ lib.optional (!useUWSM) "hyprland-uwsm.desktop"  ← redundant opposite
```

`hyprlandSessionName` already resolves to the correct variant based on `useUWSM`. The two `lib.optional` lines unconditionally add the OTHER variant, producing both buttons regardless of setting.

**Fix**: Remove the two `lib.optional` lines that add the opposite variant. Only `${hyprlandSessionName}.desktop` should stay.

### B. UI Action Button Duplicates (source-level, not config-driven)

QMLGreet's `qml/main.qml` hardcodes 6 power action buttons in a `RowLayout`:

```qml
StyledButton { iconName: "system-suspend"; visible: power.canSuspend(); onClicked: power.suspend() }
StyledButton { iconName: "system-suspend-hibernate"; visible: power.canHibernate(); onClicked: power.hibernate() }
StyledButton { iconName: "system-suspend-hibernate"; visible: power.canHybridSleep(); onClicked: power.hybridSleep() }
StyledButton { iconName: "system-suspend-hibernate"; visible: power.canSuspendThenHibernate(); onClicked: power.suspendThenHibernate() }
StyledButton { iconName: "system-reboot"; visible: power.canReboot(); onClicked: power.reboot() }
StyledButton { iconName: "system-shutdown"; visible: power.canPowerOff(); onClicked: power.powerOff() }
```

Three hibernation variants share the same `system-suspend-hibernate` icon → visually identical.

**Fix**: Patch the derivation with `postPatch` to remove the duplicate-icon lines from `qml/main.qml`:

```nix
postPatch = ''
  sed -i '/StyledButton { iconName: "system-suspend-hibernate";/d' qml/main.qml
'';
```

## Verification After Fix

```bash
# 1. Check flake still evaluates
nix flake check --no-build

# 2. Rebuild the greeter package
nix build --no-link .#nixosConfigurations.<hostname>.pkgs.qmlgreet

# 3. (Optional) Verify source patch applied inspect
nix eval --json '.# pkgs.qmlgreet.src.outPath' \
  | xargs -I{} grep -c "system-suspend-hibernate" {}/qml/main.qml
# Expected: 0
```

## When to Distinguish Source vs Config Duplicates

| Dimension | Config-driven (Vector A) | Source-driven (Vector B) |
|---|---|---|
| *Control knob* | Nix expression list | Upstream QML source |
| *Fix scope* | Nix module wiring | Derivation `postPatch` |
| *Risk* | Accidentally removes valid option | Breaks if upstream renames field |
| *Example* | `greetdEnvironments` | `qml/main.qml` bottom bar |
