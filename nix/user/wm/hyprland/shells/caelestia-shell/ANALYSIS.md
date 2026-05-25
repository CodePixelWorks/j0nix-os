# Caelestia Shell Analysis

## Source Snapshot
- Flake input: `inputs.caelestia-shell` (`github:caelestia-dots/shell`)
- Locked rev: `71f291f79bf7c35ad7db2c0061efc80cf768426a`
- CLI source: `inputs.caelestia-cli` (`github:caelestia-dots/cli`, rev `a6defd292136ac3a52fb0d39f045a0882dda6354`)
- Quickshell source: `git+https://git.outfoxxed.me/outfoxxed/quickshell` (rev `dacfa9de829ac7cb173825f593236bf2c21f637e`)

## Integration Contract In j0nix-os
- Module: `user/wm/hyprland/shells/caelestia-shell/default.nix`
- Channel switch: `settings.programs.caelestia.channel = "stable" | "dev"`
  - `stable` -> flake input `caelestia-shell`
  - `dev` -> flake input `caelestia-shell-dev` (tracks `main`)
- Package wiring: `j0nix.user.shells.quickshell.packages` via shared list-merge helper.
- Font wiring: `j0nix.user.shells.fonts.packages` (Material Symbols + Nerd fonts).
- Install aggregator: `j0nix.user.software.packages` (through `shells/common/default.nix`).

## Runtime Assumptions
- Requires shell input to expose either:
  - `homeManagerModules.default`, or
  - `packages.<system>.with-cli` / `packages.<system>.default`
- Startup/stop entrypoints are `caelestia-start` and `caelestia-stop`.

## Maintenance Notes
- Update this file when the input source, major dependency contract, or startup flow changes.

## Theme Regression Analysis

### Problem Statement

The session showed a recurring mismatch:

- GTK settings and environment looked correct
- apps still came up with the wrong colours, spacing, or mixed light/dark state after login
- manually reselecting the GTK theme in `nwg-look` appeared to "fix" the issue temporarily

### What Was Ruled Out

These layers were confirmed correct during the incident:

- `~/.config/gtk-3.0/settings.ini`
- `~/.config/gtk-4.0/settings.ini`
- session env such as `GTK_THEME`
- Home Manager-managed theme package installation

That means the breakage was not primarily "theme not installed" or "wrong GTK theme name".

### Actual Root Cause

The upstream `caelestia` CLI rewrites GTK user CSS after login.

Relevant upstream behavior:

- theme application code writes both `gtk.css` and `thunar.css`
- it does this for both `gtk-3.0` and `gtk-4.0`
- the GTK writer is enabled unless the shell config explicitly disables it

Operational consequence:

- repo-managed GTK state gets overwritten after the session starts
- CSS written by Caelestia can reintroduce old colours, imports, and spacing
- `nwg-look` appears to fix the problem because it reapplies the expected widget theme after Caelestia already wrote its CSS

### Architectural Conclusion

The professional fix is not to keep stacking more GTK env overrides.

The correct ownership model is:

- Caelestia manages shell visuals
- j0nix manages GTK and Qt desktop theming

Therefore:

- Caelestia GTK theme writing should be disabled explicitly
- Caelestia Qt theme writing should also be disabled when `user/desktop/qt-theme.nix` is active
- session restore hooks are only fallback safety nets, not the primary solution

### Follow-up Rule

Whenever desktop theming regresses again, verify writer ownership before changing theme names, env vars, or CSS templates:

1. check `settings.ini`
2. check session env
3. check whether `gtk.css` is a managed file or was rewritten after login
4. check whether the shell or another post-login tool is writing toolkit config
