# libfaketime Game Time Hack

Pattern for building per-process time manipulation tools using `libfaketime`
via `LD_PRELOAD`. Works for native Linux binaries AND Proton/Wine games
(Wine's `GetSystemTime()` → Linux `clock_gettime()` → libfaketime intercepts).
System clock is untouched.

## Technique

```bash
LD_PRELOAD=/path/to/libfaketime.so.1 FAKETIME="+4h" <command>
```

- `FAKETIME="+4h"` — offset from real time (advances with real clock)
- `FAKETIME="@2026-01-15 14:30:00"` — absolute static time (frozen)
- `FAKETIME_NO_CACHE=1` — disable caching for monotonic results
- Offset format: `+N[s|m|h|d|y]`, e.g. `+2h30m`, `-30m`, `+1d`

## Steam Launch Options Usage

For No Man's Sky (or any Steam game that checks system time):

```
game-time-fake --offset +4h %command%
```

Or via env var:

```
GAME_TIME_OFFSET=+4h game-time-fake %command%
```

To revert: simply launch without the wrapper.

## Wrapper Script Pattern (NixOS/Home Manager)

Three scripts bundled as `pkgs.writeShellScriptBin`:

1. `game-time-fake` — relative offset wrapper
2. `game-time-fake-at` — absolute time wrapper  
3. `game-time-now` — shows what fake time would be

Settings contract under `j0nix.desktop.gaming.timeHack`:

```nix
timeHack = {
  enable = true;
  defaultOffset = "+4h";
};
```

## ⚠️ Critical Pitfall: NixOS → Home Manager Config Propagation

When a settings block (e.g. `j0nix.desktop.gaming.timeHack`) is set in a
NixOS profile module (`profiles/desktop/modules/gaming.nix`) but the
consuming module runs in Home Manager context (`nix/user/gaming/tools.nix`),
the Home Manager module may see `{}` (empty) for the nested attrset.

**Symptom:** `nix flake check --no-build` passes, but the tools are never
installed. `config.j0nix.desktop.gaming.timeHack.enable` evaluates to `true`
in NixOS context but the Home Manager module's `timeHackEnabled` is `false`.

**Root cause:** The `j0nix.desktop.gaming` option is defined as a free-form
`types.attrs` in the system gaming module. While the top-level attrs are
propagated to Home Manager, nested sub-attrs added to the profile module
may not propagate depending on how the flake's `extraSpecialArgs` and
shared module imports are wired.

**Debugging steps:**

```bash
# Check if the setting reaches Home Manager
nix eval .#nixosConfigurations.<host>.config.home-manager.users.<user> \
  --apply 'xs: xs.j0nix.desktop.gaming.timeHack or {}'

# If empty, the propagation chain is broken. Check:
# 1. flake.nix extraSpecialArgs for settings passing
# 2. Whether the gaming module's option definition uses the right type
# 3. Whether the profile module sets the attr at the right level
```

**Workaround:** Pass the settings explicitly via `extraSpecialArgs` or use
the `settings` special arg (which is the merged settings.nix) rather than
relying on NixOS module option propagation.

## Verification

```bash
# Check tools are installed
which game-time-fake game-time-now

# Test fake time
game-time-fake --show date
# Should show time +4h ahead

# Test in Steam
# Right-click game → Properties → Launch Options:
# game-time-fake --offset +4h %command%
```
