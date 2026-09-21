# Session: Example File Drift (j0nix-os, May 22 2026)

## Problem

Three `.example` files had drifted out of sync with actual configuration after the `profileName` extraction (commit 370ccbc) removed `profileName` from `settings.nix`:

| File | Real config lines | Example file lines | Drift |
|------|-------------------|---------------------|-------|
| `settings.nix.example` (root) | ~1000 (settings.nix) | ~154 | massive — still contained `profileName`, missing full settings contract, outdated program toggles, no dev.git/ssh/gpg examples |
| `profiles/desktop/details.nix.example` | ~100 | ~14 | under-documented — missing field docs, monitor toggle examples, Sunshine notes |
| `profiles/desktop/hardware-configuration.nix.example` | ~50 | ~10 | bare skeleton — missing boot/initrd guidance, swap/hibernate notes, vendor selection |

## Why It Matters

Example files are the **first thing a new user copies** when onboarding to a system-flake repo. If they are stale, the user hits eval errors immediately and loses trust in the project.

## Correction Applied (commit af6e5f7)

Rewrote all three example files to match post-refactor architecture:

1. **settings.nix.example** (root) — Full settings contract including:
   - Removed `profileName` (now lives in `flake.nix` host mapping, see `session-settings-vs-profiles-boundary.md`)
   - Complete category documentation: locale, secrets, programs, storage, network, hardware/boot, audio, dev, desktop/WM, per-user overrides
   - Safe placeholder defaults for all fields (`"your-user"`, `"Your Name"`, `"you@example.com"`)
   - Minimal dev.git / dev.ssh / dev.gpg examples so users don't have to reverse-engineer the attrset shape
   - Commented-out storage mount block with all supported options
   - Gaming, AI, and Sunshine defaults set to `false` / safe values

2. **details.nix.example** — Monitor configuration expanded from 14 to 127 lines:
   - Full field documentation for each monitor attrset key (output, mode, position, scale, disabled, description, bindIndex, focusOnEnable, enabledByDefault, workspaceHandoff)
   - `wlr-randr` discovery command documented inline
   - Commented multi-monitor examples with common layouts (primary + secondary, TV with workspace handoff)
   - Sunshine headless and physical output examples with null fallback
   - Architecture boundary note: "NEVER put device UUIDs in settings.nix"

3. **hardware-configuration.nix.example** — Expanded from 10 to 76 lines:
   - Inline instruction: `sudo nixos-generate-config --show-hardware-config > profiles/<profile>/hardware-configuration.nix`
   - Boot/initrd kernel module documentation
   - EFI System Partition example with `fmask`/`dmask` security options
   - Hibernate guidance: swap device + resume device configuration belongs in profile's boot/kernel module
   - Vendor microcode toggle: `hardware.cpu.amd.updateMicrocode` vs `hardware.cpu.intel.updateMicrocode`
   - Security warning: "Never check real UUIDs into public repo"

## Maintenance Rule

After any change to `settings.nix`, `details.nix`, or `hardware-configuration.nix`, update the corresponding `.example` file in the same commit scope. The example is a contract — breaking the contract breaks onboarding.

After architecture refactor (e.g. moving fields between settings/profiles/flake), audit ALL `.example` files immediately. They do not participate in `nix flake check` and therefore cannot self-heal.

## Verification

Example files are not evaluated by `nix flake check --no-build` (they are not imported). Manual verification required after each edit:

```bash
# Quick eval sanity check (standalone Nix expressions)
nix-instantiate --eval --expr 'import ./settings.nix.example {}'
nix-instantiate --eval --expr 'import ./profiles/desktop/details.nix.example {}'
nix-instantiate --eval --expr 'import ./profiles/desktop/hardware-configuration.nix.example { config={}; lib=import <nixpkgs/lib>; pkgs={}; modulesPath=""; }'
```

If any eval fails, the example is broken for new users.

## Anti-Pattern: Inline Nix Eval in Bash Scripts

When validating example files or ad-hoc .nix snippets, use direct `nix-instantiate --eval --expr` with proper args. Inline `nix eval --expr 'import ./path.nix {}'` inside bash scripts is fragile due to spacing, quoting, and argument-passing issues. See `references/nix-eval-in-shell-anti-pattern.md` for full treatment.
