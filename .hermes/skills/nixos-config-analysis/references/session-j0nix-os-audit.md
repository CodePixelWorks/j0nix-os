# Session Findings: j0nix-os NixOS Config Audit

Date: 2024-05-21
Repo: j0nix-os (NixOS gaming/dev flake)

## Finding 1: Duplicate `programs` top-level attrsets

**Location:** `settings.nix`
**Kind:** Duplicate block merge (Nix handles it, but confusing)

```nix
# Line 55
programs = {
  kitty = { ... };
};

# ... 60 lines later, Line 118
programs = {
  alacritty = { ... };
  autodeskFusion = { ... };
};
```

**Root cause:** Settings grew organically. The first block was added for kitty, the second for alacritty and later programs. Nix attrset merge makes this work, but creates confusion about where to add new entries.

**Fix:** Merge both into a single `programs` block, keeping section headers as comments.

## Finding 2: Broken feature as fallback default

**Location:** `user/wm/shell-launcher.nix:10`, `themes/catppuccin.nix:5`, `user/wm/mangowc.nix:5`
**Kind:** Default points to feature with "temporarily broken during migration" assertions

```nix
# shell-launcher.nix
selectedShell = settings.wmShell or (settings.hyprlandShell or "dank-material-shell");

# theme (used as final fallback via mk-user-settings.nix)
shell = "dank-material-shell";
```

**Assertions that fire if default is used:**
```nix
# user/wm/hyprland/default.nix
assertion = selectedShell != "dank-material-shell";
message = "dank-material-shell is temporarily marked broken during the Hyprland Lua migration.";
```

**Fix:** Change all fallback defaults to `caelestia-shell` (the currently maintained, working shell).

## Finding 3: Duplicated window rules (no-op overrides)

**Location:** `user/wm/hyprland/config/window-rules.nix`
**Kind:** Identical rules defined twice with only name suffix different

```nix
# Lines 147-157
{ name = "bambu-studio-class-no-center"; match.class = "^(BambuStudio)$"; float = true; center = false; }
{ name = "bambu-studio-title-no-center"; match.title = "^(bambu-studio)$"; float = true; center = false; }

# Lines 203-213 — exact duplicates
{ name = "bambu-studio-class-no-center-override"; match.class = "^(BambuStudio)$"; float = true; center = false; }
{ name = "bambu-studio-title-no-center-override"; match.title = "^(bambu-studio)$"; float = true; center = false; }
```

The second pair used "-override" suffix suggesting they were meant to override something, but the match/effect pairs are identical. Hyprland processes rules top-to-bottom, so later identical rules are pure no-ops.

**Fix:** Remove the duplicate pair.

## Search Methods That Surfaced These

The duplicate `programs` was found by:
```bash
grep -n "^  programs = {$" settings.nix
# => two matches at different offsets
```

The broken default was found by:
```bash
grep -rn 'or "dank-material-shell"' --include="*.nix" .
grep -rn '"dank-material-shell"' --include="*.nix" themes/
```

The duplicate rules were found by:
```bash
grep -n "bambu-studio" user/wm/hyprland/config/window-rules.nix
# => 4 matches in close proximity, 2 with same body
```

## Validation Pattern Used

After each fix:
```bash
nix flake check --no-build 2>&1 | head -20
```

Commit immediately per scope with Conventional Commits:
```
refactor(settings): merge duplicate top-level programs blocks
fix(shell-default): change default wmShell fallback from broken dank-material-shell to caelestia-shell
fix(hyprland): remove duplicate bambu-studio window rules
```
