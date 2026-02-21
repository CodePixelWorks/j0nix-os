# System Gaming Modules

System-level gaming stack controlled by `settings.gaming.*`.

## Files

- `default.nix`: entrypoint/aggregation
- `steam.nix`: Steam and Proton base integration
- `performance.nix`: Gamescope/Gamemode/MangoHud-level toggles
- `controllers.nix`: controller support and udev behavior
- `extras.nix`: optional extras

## Scope

Use this folder for machine-wide gaming requirements.
Per-user launchers and helpers belong in `user/gaming/`.

## Performance Note

- `settings.gaming.performance.gamemodeRenice` controls gamemode CPU priority (`-20..19`, default `-10`).
- `settings.gaming.performance.gamescopeHdr` enables HDR wrapper tooling for gamescope launch.

## Steam Note

- `settings.gaming.steam.steamRun` installs `steam-run`.
- `settings.gaming.proton.provider` selects preferred compat provider (`cachyos` or `ge`).

## Steam Optional Launch Wrappers

From `user/gaming/tools.nix`, these helpers are available for per-game Steam launch options:

- `game-session %command%`
- `game-session-gamemode %command%`
- `game-session-mangohud %command%`
