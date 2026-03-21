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

- `steam-session-run`: core Steam launch wrapper with explicit `--gamescope`, `--x11`, `--wayland`, `--hdr`, `--gamemode`, `--mangoapp`, `--grab-cursor`, `--no-grab-cursor`, `--host-fullscreen`, and `--launcher-skip`
- `steam-session-run` writes debug logs to `~/.local/state/j0nix/gaming/steam-session-run.log`
- In nested Gamescope mode the default host window is now borderless and sized to the focused monitor. Use `--host-fullscreen` only when you explicitly want the old fullscreen host window behavior.
- In nested Gamescope mode forced cursor grab is enabled by default. Use `--no-grab-cursor` when a game needs the old cursor behavior.
- Default recommendation: do not put Gamescope in the normal Steam launch path unless you specifically need it. Use:
  - `steam-session-run --gamemode %command%`
  - `steam-session-run --wayland --gamemode %command%`
- Gamescope is treated as a special-case wrapper layer because the visible top-level window becomes the Gamescope client rather than the game's direct Xwayland window.
- `steam-session-gamescope`
- `steam-session-gamescope-wayland`
- `steam-session-gamescope-hdr`
- `steam-session-gamescope-hdr-wayland`
- `game-session-gamemode`
- `game-session-mangohud`
- `game-session-gamescope`
- `game-session-gamescope-wayland`
- `game-session-gamescope-hdr`
- `game-session-gamescope-hdr-wayland`
- `game-session-cyberpunk` (adds `--launcher-skip`)
- `game-session-cyberpunk-gamescope`
- `game-session-cyberpunk-gamescope-wayland`
- `game-session-cyberpunk-hdr` (HDR + `--launcher-skip`)
- `game-session-cyberpunk-hdr-wayland` (HDR + Wayland + `--launcher-skip`)
- `game-ready-check`

## Heroic

- Enabled by `j0nix.desktop.gaming.launchers.heroic = true`
- Package fallback is handled for `heroic` / `heroic-games-launcher`

## Proton-CachyOS

- Provider toggle: `j0nix.desktop.gaming.proton.provider = "cachyos"`
- Install/update tool: `proton-cachyos-install`
- Ensure tool exists: `proton-cachyos-ensure`
- Non-Steam with UMU + Proton-CachyOS: `game-session-umu-cachyos <game-exe-or-command>`
