# User Gaming Modules

Per-user gaming launchers and helper tools.

## Files

- `default.nix`: user gaming entrypoint
- `launchers.nix`: Lutris/Heroic/Bottles/Rockstar related launchers
- `tools.nix`: utility tools
- `extras.nix`: optional extras

## Control

Managed by `j0nix.desktop.gaming.*` (typically set in `profiles/desktop/modules/gaming.nix`).

## Rockstar (Steam Non-Steam)

- Toggle with `j0nix.desktop.gaming.launchers.rockstar`
- Helper command: `rockstar-steam-setup`
- Lutris fallback helper: `rockstar-lutris-setup`

## Steam Helpers

- `game-session-gamemode`
- `game-session-mangohud`
- `game-session-gamescope-hdr`
- `game-session-cyberpunk` (adds `--launcher-skip`)
- `game-session-cyberpunk-hdr` (HDR + `--launcher-skip`)
- `game-ready-check`

## Heroic

- Enabled by `j0nix.desktop.gaming.launchers.heroic = true`
- Package fallback is handled for `heroic` / `heroic-games-launcher`

## Proton-CachyOS

- Provider toggle: `j0nix.desktop.gaming.proton.provider = "cachyos"`
- Install/update tool: `proton-cachyos-install`
- Ensure tool exists: `proton-cachyos-ensure`
- Non-Steam with UMU + Proton-CachyOS: `game-session-umu-cachyos <game-exe-or-command>`
