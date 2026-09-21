# Session: Programme Module Enable-Toggle Consistency Audit (j0nix-os, May 22 2026)

## Problem

During an AppImage integration review, the following inconsistencies were found in program modules under `user/programs/`:

| Module | `enabled = cfg.enable or` | `settings.nix` has `enable =`? | Always-on risk? |
|--------|--------------------------|-------------------------------|-----------------|
| streambert | `false` | **NO** — missing entirely | silent off |
| autodesk-fusion | `false` | `true` | no |
| bambulab | **NO `enable` at all** — module always active | **NO `enable` toggle** | **YES** — always on regardless of user intent |
| betterdiscord | `true` | `true` | **YES** — defaults to on even if user doesn't set it |
| fastfetch | `true` | `true` | **YES** — same |
| element-desktop | `false` | `false` | no |
| twintail-launcher | `false` | `false` | no |
| windows-exe | `false` | `true` | no |
| windows-apps | `mkIf (requestedPackages != [])` | `packages = []` | no |

## Root Causes

1. **bambulab**: Missing `enable` toggle in both `settings.nix` and HM module. Module was unconditionally active — only `provider` was configurable.
2. **streambert**: Added to overlay and HM module, but `settings.nix` never received the `programs.streambert` block. Users had no discoverable contract.
3. **betterdiscord / fastfetch**: Module default `cfg.enable or true` means even if the user *removes* the toggle from their settings, the module stays active. This violates the principle that "absence of a toggle = disabled."

## Fixes Applied

### bambulab Refactor
```bash
# 1. Move AppImage package to system-level location (consistent with streambert)
mv user/programs/bambulab/appimage-package.nix \
   system/software/pkgs/printing/bambu-studio-appimage.nix

# 2. Wire via overlay
# system/lib/flake/overlays.nix:
#   bambu-studio-appimage = final.callPackage (...) { };

# 3. HM module now reads pkgs.bambu-studio-appimage

# 4. Add enable toggle to settings.nix
programs.bambulab = {
  enable = true;  # matching previous "always-on" behavior for compatibility
  provider = "flatpak";
};

# 5. Guard HM module with lib.mkIf enabled
```

### Module Default Fixes
```nix
# user/programs/betterdiscord/default.nix
- enabled = cfg.enable or true;
+ enabled = cfg.enable or false;

# user/programs/fastfetch/default.nix
- enabled = cfg.enable or true;
+ enabled = cfg.enable or false;
```

### streambert Settings Contract
```nix
# settings.nix
programs.streambert = {
  enable = false;
};
```
Also added to `settings.nix.example`.

## Validation
nix flake check --no-build passed after all changes.

## Guideline for Future Program Modules

Every program module must follow this checklist:
- [ ] `settings.nix` contains `programs.<name> = { enable = <bool>; ... }`
- [ ] `settings.nix.example` documents the toggle
- [ ] HM module uses `enabled = cfg.enable or false;`
- [ ] HM module body is wrapped in `lib.mkIf enabled`
- [ ] Package lives under `system/software/pkgs/<category>/` if reusable
- [ ] Package is wired via overlay if referenced as `pkgs.<name>`
- [ ] Commit includes `settings.nix` AND `settings.nix.example` updates

## Anti-Pattern: `or true` in Module Defaults

`cfg.enable or true` is dangerous because:
1. It makes the feature impossible to disable by omission
2. It violates the settings contract (settings.nix should be the single source of truth for defaults)
3. It surprises users who expect "I didn't configure it = it's off"

The only legitimate use of `or true` is for opt-out features that have been stable for a long time and where disabling would break expected behavior (e.g. base system utilities). New integrations should always default to `or false`.
