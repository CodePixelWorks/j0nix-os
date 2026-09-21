# Program Module Enable Consistency in NixOS Flakes

**Scope**: Ensuring every Home Manager program module follows a consistent `enable` toggle pattern and is wired through the settings contract.

## Required Pattern

Every program module under `user/programs/<name>/default.nix` must implement:

```nix
{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).<name> or { };
  enabled = cfg.enable or false;  # NOT `or true`
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ pkgs.<name> ];
  # ...other module-specific config...
}
```

## Anti-Patterns to Catch

| Problem | Code Smell | Detection |
|---------|-----------|-----------|
| **Always-on module** | Missing `lib.mkIf enabled` wrapper | Search `user/programs/*/default.nix` for files lacking `lib.mkIf` |
| **Missing `enable` toggle** | `settings.nix` defines `foo = { url = "..."; }` but no `enable = true/false` | Scan settings.nix for program blocks without `.enable` |
| **Deceptive default** | `enabled = cfg.enable or true` | Grep `or true` in program module files |
| **Settings not in example** | New program exists but isn't in `settings.nix.example` | Compare `settings.nix` `programs.*` keys against `settings.nix.example` |
| **Package in wrong place** | `user/programs/foo/appimage-package.nix` instead of `system/software/pkgs/` | See `references/appimage-package-location-pattern.md` |

## Validation Script

```bash
#!/usr/bin/env bash
set -euo pipefail

# Check 1: All program modules must have lib.mkIf enabled
echo "=== Checking lib.mkIf guards ==="
for f in user/programs/*/default.nix; do
  if ! grep -q 'lib\.mkIf enabled' "$f"; then
    echo "  WARNING: $f lacks lib.mkIf enabled guard"
  fi
done

# Check 2: All settings.nix program blocks must have 'enable' key
echo "=== Checking settings.nix for missing enable toggles ==="
grep -nP '^\s+\w+ = \{' settings.nix | while read -r line; do
  block_start="$(echo "$line" | grep -oP '^\d+')"
  block_name="$(echo "$line" | grep -oP '\w+(? = \{)')"
  # Check next 3 lines for 'enable'
  if ! sed -n "$((block_start+1)),$((block_start+5))p" settings.nix | grep -q 'enable'; then
    echo "  WARNING: $block_name may lack 'enable' toggle (around line $block_start)"
  fi
done

# Check 3: settings.nix vs settings.nix.example parity
echo "=== Checking example file parity ==="
# Manual: ensure every program.* key in settings.nix also appears in .example
```

## Fix Checklist (in one commit scope)

- [ ] Add `enable = true/false` to `settings.nix` matching production default
- [ ] Add `enable = false` to `settings.nix.example` (examples should be conservative)
- [ ] Wrap HM module with `lib.mkIf enabled` if missing
- [ ] Change `cfg.enable or true` → `cfg.enable or false` if needed
- [ ] Move AppImage package to `system/software/pkgs/` + overlay if not already there
- [ ] `nix flake check --no-build`

## Historical Context

- **betterdiscord + fastfetch**: Originally defaulted to `cfg.enable or true`, silently installing packages even when users never requested them. Fixed to `or false` with explicit `enable = true` in `settings.nix`.
- **bambulab**: Was "always-on" because it lacked an `enable` toggle entirely (`settings.nix` only had `provider`). Added `enable = true` (matching previous behavior) and wrapped module in `lib.mkIf`. Also moved the AppImage package from `user/programs/bambulab/` to `system/software/pkgs/printing/` + overlay wiring for consistency with other AppImage packages.
- **streambert**: HM module existed but `settings.nix` entry was missing entirely. Added `streambert.enable = false` for explicit opt-in.
- **user-scoped enable**: Per-user overrides under `settings.userSettings.<name>.programs.*.enable` take precedence. The global `settings.programs.*.enable` is the default; users can opt in/out individually.
