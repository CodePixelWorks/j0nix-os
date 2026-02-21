# User Gaming Modules

Per-user gaming launchers and helper tools.

## Files

- `default.nix`: user gaming entrypoint
- `launchers.nix`: Lutris/Heroic/Bottles/Rockstar related launchers
- `tools.nix`: utility tools
- `extras.nix`: optional extras

## Control

Managed by `settings.gaming.*`.

## Rockstar (Steam Non-Steam)

- Toggle with `settings.gaming.launchers.rockstar`
- Helper command: `rockstar-steam-setup`
- Lutris fallback helper: `rockstar-lutris-setup`

## Steam Helpers

- `game-session-gamemode`
- `game-session-mangohud`
- `game-session-gamescope-hdr`

## Proton-CachyOS

- Provider toggle: `settings.gaming.proton.provider = "cachyos"`
- Install/update tool: `proton-cachyos-install`
- Ensure tool exists: `proton-cachyos-ensure`
- Non-Steam with UMU + Proton-CachyOS: `game-session-umu-cachyos <game-exe-or-command>`
