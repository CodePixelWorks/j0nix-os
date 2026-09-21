# Role-Scoped Program Module Imports

In modular NixOS configurations, program modules should not be imported
unconditionally for all users. Instead, each role should `import` only the
program modules that are relevant to its workload.

## Problem with Global Program Imports

The naive approach puts every program module into a global `imports` list:

```nix
# nix/user/programs/default.nix  ❌ anti-pattern
{
  imports = [
    ./davinci-resolve
    ./bambulab
    ./autodesk-fusion
    ./betterdiscord
    # ... 20 more
  ];
}
```

This means every user evaluates every program module, even if they never
use the tool. It bloats evaluation time and creates unnecessary assertions
and defaults for users who do not have the role that needs the program.

## Preferred Pattern: Role-Scoped Imports + Global Defaults

Program modules live under `nix/user/programs/<name>/` and can be attached
to roles **or** provided globally with per-user override.

### Role-scoped imports (unchanged)

Roles import only the program modules they need:

```nix
# nix/roles/home/video-editing.nix
{ pkgs, ... }:
{
  imports = [ ../../user/programs/davinci-resolve ];

  j0nix.user.software.packages = with pkgs; [
    gpu-screen-recorder
    shotcut
    ffmpeg-full
  ];
}
```

### Global defaults with selective override

A `defaultHomePrograms` list in `settings.nix` defines which program modules
every user gets by default. A user can override this completely with
`homePrograms` inside their `userSettings` block.

```nix
# settings.nix
{
  defaultHomePrograms = [
    "alacritty" "keepassxc" "kitty"
    "autodesk-fusion" "balena-etcher" "bambulab"
    # ... role-agnostic programs
  ];

  userSettings.jonas = {
    homePrograms = [ "kitty" "keepassxc" ];   # replaces defaultHomePrograms
    roles = [ "developer" "video-editing" ];    # davinci-resolve comes from role
  };
}
```

### Wiring in mkHomeModules

The `mkHomeModules` builder resolves program modules dynamically:

```nix
# nix/system/lib/home/mk-home-modules.nix
mkProgramModule = name:
  let path = "${baseDir}/programs/${name}";
  in if builtins.pathExists (path + "/default.nix") then path else null;

programModules = lib.filter (m: m != null) (
  map mkProgramModule (userSettings.homePrograms or defaultHomePrograms)
);

# Assertion: fail fast with a clear message if a program name has no module
missingProgramNames = lib.filter (name:
  !builtins.pathExists ("${baseDir}/programs/${name}/default.nix")
) (userSettings.homePrograms or defaultHomePrograms);
```

**Fallback behavior**: If neither `homePrograms` nor `defaultHomePrograms` is
set, the builder falls back to importing `nix/user/programs/default.nix`
(the old all-programs import) for backward compatibility.

### Program module contract

Program modules remain self-contained with their own `enable` toggle:

```nix
# nix/user/programs/davinci-resolve/default.nix
{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).davinciResolve or { };
  enabled = cfg.enable or true;
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ resolveFixed ];
}
```

When attached to a role, the module can default to `enable = true` because
the role is the gatekeeper. When listed in `defaultHomePrograms`, the same
module behaves as a global default.

## Decision Matrix: Where to Place a Program Module

| Situation | Where to register | Why |
|---|---|---|
| Needed by almost every user | `defaultHomePrograms` in `settings.nix` | Global default, still overridable per user |
| Needed only by one role | Role `imports` | Clean separation, no global bloat |
| Needed by some users but not all | `defaultHomePrograms` + let specific users override `homePrograms` | Declarative opt-out |
| Only available as Flatpak | Program module + `services.flatpak.packages` | Keeps Flatpak wiring in one place |

## Advantages

- **Faster evaluation**: Users without the `video-editing` role never evaluate
  the DaVinci Resolve wrapper or its assertions.
- **Cleaner defaults**: Program modules can default to `enable = true` since
  the role is the gatekeeper, not the global toggle.
- **Role = bundle of concern**: A role file becomes a complete manifest of
  packages, program modules, and config for that workload.
- **Easier removal**: Dropping a role from a user's `roles` list immediately
  removes all associated packages and program state.
- **Explicit global list**: `defaultHomePrograms` makes the global baseline
  visible and auditable in one place.
- **Per-user override**: Power users can trim their personal set without
  affecting the global default.
