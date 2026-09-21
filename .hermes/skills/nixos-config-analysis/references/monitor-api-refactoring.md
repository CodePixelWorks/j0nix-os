# Monitor-API Refactoring Pattern

> Session: j0nix-os, Refactoring raw monitor strings to typed attrsets

## Problem

Raw monitor configuration strings (`"OUTPUT, MODE, POSITION, SCALE"`) are:
- Hard to validate at evaluation time
- Require ad-hoc parsing in every consumer (Hyprland config, Lua fragments, Sunshine)
- Brittle when upstream syntax changes
- Require manual string manipulation for derived values (e.g. extracting the output name for rules)

## Solution: Central Typed Monitor Library

Create a single module `system/lib/monitor.nix` that owns the data contract and all rendering/parsing.

### Data Model

```nix
{
  output   = "DP-1";            # Required
  mode     = "3440x1440@144";   # Optional
  position = "0x0";             # Optional
  scale    = 1;                 # Optional
  extra    = "...";             # Optional raw trailing fragment
}
```

### API Surface

| Function | Input | Output | Purpose |
|----------|-------|--------|---------|
| `renderMonitorRule` | attrset | `"DP-1,3440x1440@144,0x0,1"` | Hyprland `monitor=` |
| `renderMonitorLua` | attrset | Lua table fragment | Lua generators |
| `parseMonitorRule` | string | attrset | Legacy import path |
| `normalizeMonitor` | string \| attrset | attrset | Universal entrypoint |

### Typed List Options (Nix `coercedTo`)

When the monitor list is exposed as a NixOS/Home Manager option, declare the list type so both legacy strings and new attrsets are accepted automatically:

```nix
let
  monitorType = lib.types.submodule {
    options.output   = lib.mkOption { type = lib.types.str; };
    options.mode     = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    options.position = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    options.scale    = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
    options.extra    = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
  };

  # Accepts either a raw string or an attrset; strings are parsed automatically
  monitorList = lib.types.listOf (lib.types.coercedTo lib.types.str parseMonitorRule monitorType);
in
{
  options.myMonitors = lib.mkOption { type = monitorList; default = []; };
}
```

Same for resolutions:

```nix
resolutionList = lib.types.listOf (lib.types.coercedTo lib.types.str parseResolution resolutionType);
```

**Key benefit**: Consumers of the option do not need to call `normalizeMonitor` — `coercedTo` handles it at the option boundary. Only internal functions that receive raw values directly (e.g. from `settings.nix` as plain Nix values rather than declared options) need explicit normalization.

### Same Pattern for Resolutions

Applied to `WIDTHxHEIGHT` strings for Sunshine streaming:

```nix
{ width = 1920; height = 1080; }
# renderResolution -> "1920x1080"
```

## Migration Steps

1.  **Create shared library** at `system/lib/<domain>.nix`.
2.  **Add `normalize*` functions** accepting both old strings and new attrsets.
3.  **Update canonical settings site** to attrset format.
4.  **Update each consumer** to call `normalizeMonitor` at boundary, then use target-specific renderer.
5.  **Update assertions** to validate rendered values, not raw inputs.
6.  **Validate** with `nix flake check --no-build`.
7.  **Commit per scope** (library -> settings -> consumers).

## Key Insight: Consumer-Specific Renderers

Provide separate renderers per target syntax (Hyprland direct, Lua table, Sunshine config key). Do not return a single canonical string — that leaks format knowledge into the data model.

## Key Insight: Normalize at the Edge

Every consumer receiving a monitor list should apply `map normalizeMonitor` at its boundary. This makes the rest of the code uniformly attrset-based even when upstream still contains legacy strings.

## Pitfalls Seen in This Session

- **Assertion/input mismatch**: Assertions checking regex on raw input break when input becomes attrsets. Fix: assert on the *rendered* value via the library.
- **Partial consumer updates**: Migrate all call sites together. Missed consumers (Lua fragments, daemon configs, Sunshine display hooks) silently produce wrong output. `grep -rn` first.
- **Removing dead code too early**: Keep `parseMonitorRule` inside `normalizeMonitor` until all legacy strings are gone. Remove only after validation.
- **String-interpolation asymmetry**: Nix `builtins.concatStringsSep` with small attrsets is fragile. Use explicit renderers with named fields.
- **Resolution strings are the same pattern**: Sunshine `virtualDisplay.resolutions` uses `"WxH"` strings — the same normalize/render pipeline applies. Reuse the resolution helpers, don't duplicate.
