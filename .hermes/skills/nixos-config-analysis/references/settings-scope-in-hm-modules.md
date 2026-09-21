# Settings Scope Path in Home Manager Modules

**Problem**: In `j0nix-os` Home Manager modules, the `settings` argument is already the **per-user merged settings object** produced by `mkUserSettings`. Using a path like `settings.userSettings.<name>.programs.foo` (or worse, hardcoding a username) is wrong — it double-traverses a tree that was already resolved.

## What `settings` IS in each context

| Context | `settings` meaning | Correct path to read |
|---|---|---|
| `flake.nix` top-level | The raw `settings.nix` attrset | `settings.userSettings.jonas.programs.foo` |
| System modules (NixOS) | The raw `settings.nix` attrset | `settings.userSettings.*` (with per-user iteration) |
| **Home Manager modules** (user/*) | The merged per-user settings from `mkUserSettings username` | `settings.programs.foo` |

This is because in `flake.nix`:

```nix
userSettings = host.mkUserSettings username;
```

And `mkUserSettings` returns:

```nix
baseSettings
  // userOverrideAttrs  # dotfilesDir, shell, defaultWMS, etc.
  # Then it merges nested attrsets at top level:
  // { programs = lib.recursiveUpdate (baseSettings.programs or {}) userProgramOverride; }
  // { dev = lib.recursiveUpdate (baseSettings.dev or {}) userDevOverride; }
  // etc.
```

So `settings` in HM land already has `settings.programs.streambert.enable = false` inherited from base or overridden by the user.

## Anti-Pattern (WRONG)

```nix
# user/programs/streambert/default.nix  -- WRONG
{
  lib, pkgs, settings, ...
}:
let
  # WRONG: double-traversing, and hardcodes "jonas"!
  cfg = lib.attrByPath [ "userSettings" "jonas" "programs" "streambert" ] { } settings;
in
lib.mkIf (cfg.enable or false) {
  j0nix.user.software.packages = [ pkgs.streambert ];
}
```

This fails because:
1. `settings.userSettings` does not exist — `mkUserSettings` already resolved the user
2. Hardcoding "jonas" breaks for any other user (multi-user broken)

## Correct Pattern

The simplest defensive pattern (used by most existing modules):

```nix
# user/programs/streambert/default.nix
{
  lib, pkgs, settings, ...
}:
let
  cfg = (settings.programs or { }).streambert or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ pkgs.streambert ];
}
```

This is the same pattern used by every other program module in the repo:
- `user/programs/betterdiscord/default.nix`: `cfg = (settings.programs or { }).betterdiscord or { };`
- `user/programs/keepassxc/default.nix`: `cfg = (settings.programs or { }).keepassxc or { };`

### Alternative: explicit attrByPath (preferred when enforcing a contract)

When the base `settings.nix` already declares the default structure, use `lib.attrByPath` with an explicit default instead of the defensive `or`-cascade. This makes the lookup location explicit and provides a clean default if the declaration is ever removed:

```nix
let
  cfg = lib.attrByPath [ "programs" "streambert" ] { enable = false; } settings;
in
lib.mkIf cfg.enable {
  j0nix.user.software.packages = [ pkgs.streambert ];
}
```

**When to use which:**
- **Defensive `or`-chain**: Use when the module must tolerate an undeclared structure (e.g., third-party modules, optional feature branches). Keeps working even if `settings.nix` doesn't mention the program.
- **Explicit `attrByPath`**: Use when the base `settings.nix` already declares the program with `enable = false;` as part of the documented contract. The default `{ enable = false; }` clearly signals "this should exist, fall back to disabled."

**Critical**: Either pattern requires the base `settings.nix` to declare the default when the program is part of the repo's feature set:

```nix
# settings.nix — base defaults (NOT inside userSettings!)
programs = {
  streambert = {
    enable = false;
  };
  # ... other programs
};
```

Without this base default, `settings.programs.streambert` in HM modules would be `null` or trigger an attribute missing error, depending on the access pattern.

## When each path is right

```nix
# Inside a Home Manager module (correct):
settings.programs.streambert.enable        # user-merged value
settings.wmShell                              # user-merged value
settings.dev.git.name                         # user-merged value

# Inside flake.nix or system modules (correct):
settings.userSettings.jonas.programs.streambert.enable   # raw per-user override
settings.userSettings.jonas.wmShell                      # raw per-user override
```

## How to verify

If unsure what `settings` contains in a given module, check the call site:

```bash
# In flake.nix, search for mkHomeModules or home-manager.users:
grep -n "mkHomeModules\|home-manager.users" flake.nix
grep -n "mkUserSettings" system/lib/settings/mk-user-settings.nix
```

The `settings` argument passed to Home Manager modules is produced by `mkUserSettings`, not by importing `settings.nix` directly.

## Detection

Search for hardcoded usernames or double-traversed `userSettings` in `user/` modules:

```bash
grep -rn "userSettings\." user/ --include="*.nix"
grep -rn '\"jonas\"\|\"alice\"\|\"bob\"' user/ --include="*.nix"
```

Any match in `user/*` is likely a bug. The only valid place for `userSettings` reference (with a username) is in system modules or `flake.nix`.
