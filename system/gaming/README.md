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
