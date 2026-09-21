# Dead Code & Misplacement Patterns in NixOS Flakes

> Session: j0nix-os, 2024-05-21 — Audit for misplaced data and stale copies

## Pattern 1: Committed Repo Mirror (`public-export/`, `public/`, `export/`)

### Detection
```bash
# Look for complete repo copies
find . -maxdepth 2 -type d \( -name 'public-export' -o -name '.public' -o -name 'export' -o -name 'mirror' \)
# Check if any .nix file exists under it
test -n "$(find .public-export -name '*.nix' 2>/dev/null | head -1)" && echo "MIRROR FOUND"
```

### Why it happens
- Developer manually copies repo to strip secrets before sharing
- No automated script, so copy becomes stale after next commit
- 41k+ lines of Nix code that silently diverge

### Fix strategy
1. **Delete** the committed mirror entirely
2. **Add** an on-demand export script, e.g. `scripts/export-public.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-.}"
DST="${2:-../j0nix-os-public}"
rsync -av --exclude='.git' --exclude='secrets/' --exclude='settings.nix' \
  "$SRC/" "$DST/"
echo "Exported to $DST"
```
3. **Document** the script in README/CONTRIBUTING

### Pitfall: Don't .gitignore it
If the directory is `.gitignore`d but was committed earlier, it stays in the repo. Use `git rm -rf .public-export/` to actually remove it from history (or from HEAD at minimum).

---

## Pattern 2: Empty Placeholder Files

### Detection
```bash
find . -name '*.nix' -size 0
```

### Why it happens
- Scaffolded early (`types.nix` for future type definitions)
- Never populated, never imported
- Lies dormant for months

### Fix
Delete immediately. If types are needed later, the file is trivial to recreate. An empty file sends the wrong signal ("this is wired, don't touch it") to future contributors.

---

## Pattern 3: Host-Specific Constants in Profile Modules

### Detection
Scan profile modules for patterns that smell like one host:
```bash
grep -rn 'resumeDevice\|resumeOffset\|by-uuid\|swapfile\|sizeMiB' profiles/
grep -rn 'kernelModule.*=.*"\|hwmonName\|acpiEnforceResources' profiles/
grep -rn 'PCI:[0-9]:[0-9]:[0-9]' profiles/
grep -rn 'cachyos-\|xanmod-\|linux_' profiles/  # kernel preset names
grep -rn 'it87\|nct6775\|jc42\|lm75' profiles/   # hwmon chip names
```

### The architecture rule
AGENTS.md / README says:
- `profiles/*/modules/` → theme/profile configuration (data + simple toggles)
- `system/lib/*` → reusable helper functions (no host data)
- **Corollary**: Host data belongs in `settings.*` or `profileDetails`

### What "host data" means
| Category | Examples | Where it belongs |
|----------|----------|------------------|
| Boot | `resumeDevice` UUID, `resumeOffset`, swap path | `settings.boot.resumeDevice`, `settings.boot.resumeOffset` |
| Kernel | Preset name (`cachyos-x86_64-v4`), module list | `settings.kernel.preset`, `settings.kernel.modules` |
| Thermal | `it87`/`it8718`, `acpiEnforceResourcesLax` | `settings.thermal.fan.kernelModule` |
| Drivers | NVIDIA open/GSP flags, Prime BusIDs | `settings.drivers.nvidia.open` |

### Fix strategy (per module)
1. **Declare** option in `system/<domain>/default.nix` or appropriate module
2. **Migrate** hardcoded value to `settings.nix` with same default
3. **Convert** profile module to thin pipe: `settings.<domain> or { }`
4. **Validate** `nix flake check --no-build`
5. **Commit** per scope

### Thin-Pipe Normal Form

A properly thinned profile module looks like this (4-12 lines typically):

```nix
{ config, lib, settings, ... }:

{ # Boot
  boot.loader = settings.boot.loader or { };
  boot.tmp = settings.boot.tmp or { };
  boot.resumeDevice = settings.boot.resumeDevice or "nodev";
  boot.resumeOffset = settings.boot.resumeOffset or 0;
  # …
}
```

or, when the option itself is already an attrset:

```nix
{ config, lib, settings, ... }:

{
  boot.kernel = settings.kernel or { };
  boot.thermal = settings.thermal or { };
  boot.drivers = settings.drivers or { };
}
```

The `or { }` fallback on attrsets is idiomatic: it lets the profile pass through whatever keys the caller provides without the profile module knowing the schema. Physical wiring (packages, assertions, `mkMerge`, conditional guards on `settings.*` values) happens in `system/` modules, not here.

### Optional-Settings-Domain Fallback

When a domain is being introduced gradually, the profile module can simply pass the optional attrset through:

```nix
# profiles/desktop/modules/thermal.nix
{ config, lib, settings, ... }:

{
  j0nix.system.thermal = settings.thermal or { };
}
```

This works even if the caller has not set `settings.thermal` yet. The corresponding system module (`system/tuning/thermal/default.nix`) must accept empty values gracefully (using `mkDefault`, `or` fallbacks, or assertions guarding required fields).

This pattern avoids the need to gate the import with `lib.mkIf (settings.thermal or null != null)` — just pass it through and let the system module decide.

---

## Checklist for Audits

- [ ] Search for `.public-export/`, `export/`, `mirror/` directories
- [ ] Find zero-byte `.nix` files
- [ ] Scan profile modules for UUIDs, PCI IDs, chip names, kernel presets
- [ ] Verify `nix flake check --no-build` still passes after each cleanup
- [ ] Commit each removal/migration as its own scope
