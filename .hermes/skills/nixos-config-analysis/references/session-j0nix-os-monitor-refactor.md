# Session: j0nix-os Monitor Refactoring + Profile Thin-Piping

Date: 2026-05-21
Repo: j0nix-os (NixOS gaming/dev flake)
Goal: Migrate monitor/resolution settings from raw strings to typed attrsets, thin-pipe 4 profile modules.

---

## Session Scope (9 commits total from multi-part session)

### Commits produced this session

```
ab5a0b8 refactor(profiles): migrate kernel, thermal, drivers modules to thin pipes
27af0dd refactor(profiles-boot): convert to thin-pipe, move data to settings.boot
b22fd28 chore(system/lib): remove empty types.nix placeholder
55343e3 refactor(profiles/gaming): migrate sunshine virtualDisplay resolutions to typed attrsets
5237ec8 refactor(sunshine): migrate displayTarget resolutions to typed attrsets
c018b9c refactor(monitors): migrate details.nix to typed monitor attrsets
475929b feat(monitor-api): introduce shared j0nix.system.lib.monitor module
fdd7f8e refactor(profiles): convert back to simple pipes (prepare for thin-piping)
<earlier> ... profile modules slimmed in prep phase
```

---

## Part 1 — Monitor API (string → attrset migration)

### New file: `system/lib/monitor.nix` (149 lines)

**normalizeMonitor** — accepts string or attrset, returns canonical attrset:
```nix
normalizeMonitor = mon:
  if builtins.isString mon then parseMonitorRule mon
  else {
    output = mon.output or (throw "monitor.attrset requires 'output'");
    mode = mon.mode or null;
    position = mon.position or null;
    scale = mon.scale or null;
    extra = mon.extra or null;
  };
```

**renderMonitorRule** — renders to Hyprland `monitor=` syntax:
```nix
renderMonitorRule = mon:
  let m = normalizeMonitor mon;
  in ... # "${output},${mode},${position},${scale},${extra}"
```

**renderMonitorLua** — renders to Lua table fragment:
```nix
renderMonitorLua = mon:
  let m = normalizeMonitor mon;
  in ''{ output = "${m.output}",${optional "mode" m.mode}${optional "position" m.position}${optional "scale" m.scale}${optional "extra" m.extra} }''
```

**parseMonitorRule** — inverse, from Hyprland string:
```nix
parseMonitorRule = str:
  let parts = lib.splitString "," str;
  in {
    output   = lib.trim (lib.elemAt parts 0);
    mode     = if lib.length parts > 1 then lib.trim (lib.elemAt parts 1) else null;
    position = if lib.length parts > 2 then lib.trim (lib.elemAt parts 2) else null;
    scale    = if lib.length parts > 3 then let s = lib.trim (lib.elemAt parts 3); in builtins.tryEval (lib.toIntBase10 s) else null;
    extra    = if lib.length parts > 4 then lib.trim (lib.concatStringsSep "," (lib.drop 4 parts)) else null;
  };
```

**Resolution helpers** (same pattern, smaller):
```nix
renderResolution = res: let r = normalizeResolution res; in "${toString r.width}x${toString r.height}"
normalizeResolution = res:
  if builtins.isString res then parseResolution res
  else { width = res.width; height = res.height; };
parseResolution = str:
  let parts = lib.splitString "x" str;
  in { width = lib.toIntBase10 (lib.trim (lib.elemAt parts 0)); height = lib.toIntBase10 (lib.trim (lib.elemAt parts 1)); };
```

### Resolution type with `coercedTo`

```nix
resolutionList = lib.types.listOf (lib.types.coercedTo lib.types.str parseResolution (lib.types.submodule {
  options.width  = lib.mkOption { type = lib.types.ints.positive; };
  options.height = lib.mkOption { type = lib.types.ints.positive; };
}));
```

### Consumer migration paths

| Consumer | Before | After |
|----------|--------|-------|
| `details.nix` (Hyprland config) | `["DP-1,3440x1440@144,0x0,1", "HDMI-A-1,1920x1080@100,3440x0,1"]` | `[{output="DP-1";mode="3440x1440@144";position="0x0";scale=1;}]` etc. |
| `streaming.nix` (Sunshine display targets) | `["3440x1440", "1920x1080"]` | `[{width=3440;height=1440;}]` etc. |
| `settings.nix` (Sunshine virtualDisplay) | `["1920x1080", "1280x720"]` | `[{width=1920;height=1080;}]` etc. |

---

## Part 2 — Profile Thin-Piping (4 modules)

### Before / After matrix

| Module | Before (lines) | After (lines) | Data now in |
|--------|---------------|---------------|-------------|
| `modules/boot.nix` | 46 | 11 | `settings.boot.*` |
| `modules/kernel.nix` | 40 | 4 | `settings.kernel.*` |
| `modules/thermal.nix` | 16 | 4 | `settings.thermal.*` |
| `modules/drivers.nix` | 35 | 4 | `settings.drivers.*` |

### Example: boot.nix conversion

Before:
```nix
{ ... }:
{
  boot = {
    loader = {
      systemd-boot.editor = false;
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot/efi";
      timeout = 3;
    };
    tmp.useTmpfs = true;
    resumeDevice = "/dev/disk/by-uuid/...";
    resumeOffset = 12345;
    swapfile = { name = "swapfile"; sizeMiB = 16384; };
  };
}
```

After:
```nix
{ config, lib, settings, ... }:

{ # Boot
  boot.loader = settings.boot.loader or { };
  boot.tmp = settings.boot.tmp or { };
  boot.resumeDevice = settings.boot.resumeDevice or "nodev";
  boot.resumeOffset = settings.boot.resumeOffset or 0;
  boot.zswap.enable = settings.boot.zswap.enable or false;
  boot.kernelPackages = settings.boot.kernelPackages or lib.mkDefault config.boot.kernelPackages;
}
```

Settings.nix additions:
```nix
{
  boot = {
    loader = {
      systemd-boot.editor = false;
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot/efi";
      timeout = 3;
    };
    tmp.useTmpfs = true;
    resumeDevice = "/dev/disk/by-uuid/...";
    resumeOffset = 12345;
    swapfile = { name = "swapfile"; sizeMiB = 16384; };
  };
}
```

---

## Validation Protocol

After every single commit:
```bash
nix flake check --no-build 2>&1 | head -20
```

No accumulated changes between validations — commit per scope.

---

## Remaining non-migrated profile modules (intentional)

| Module | Reason |
|--------|--------|
| `gaming.nix` | Profile-base configuration, not host-specific |
| `support-drivers.nix` | Host-specific USB device IDs + IT87 config |
| `printing.nix` | Printer model + IP (entire file commented out) |
| `storage.nix` | Aggregates lists from userSettings — functional logic, not pure data |
| `logging.nix` | 17 lines, mix of defaults and `settings.logging or { }` |

---

## Key Techniques

1. **Consumer-specific renderers** over single canonical string — avoids format leakage into data model.
2. **Normalize at boundary** — `map normalizeMonitor` at consumer entrypoint.
3. **`coercedTo` option types** — legacy strings auto-convert at Nix option boundary.
4. **Thin-pipe modules** — `settings.<domain> or { }` with no physical wiring in profile.
5. **Optional-domain pass-through** — pipe unset optional settings; system module handles empty gracefully.
