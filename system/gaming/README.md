# System Gaming Modules

System-level gaming stack controlled by `j0nix.desktop.gaming.*` (typically set in `profiles/desktop/modules/gaming.nix`).

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

- `j0nix.desktop.gaming.performance.gamemodeRenice` controls gamemode CPU priority (`-20..19`, default `-10`).
- `j0nix.desktop.gaming.performance.autoPerformanceMode` switches power profile to `performance` while gamemode sessions are active.
- `j0nix.desktop.gaming.performance.gamescopeHdr` enables HDR wrapper tooling for gamescope launch.

## Steam Note

- `j0nix.desktop.gaming.steam.steamRun` installs `steam-run`.
- `j0nix.desktop.gaming.proton.provider` selects preferred compat provider (`cachyos` or `ge`).

## Sunshine Note

- `j0nix.desktop.gaming.streaming.sunshine.capSysAdmin = true` enables KMS/DRM capture for lower-latency Sunshine capture paths.
- `j0nix.desktop.gaming.streaming.sunshine.performance.mode = "aggressive"` applies a higher-priority Sunshine user service profile (`Nice` + I/O priority) without depending on fragile per-user realtime scheduler permissions.
- `j0nix.desktop.gaming.streaming.sunshine.performance.network` appends Sunshine-specific UDP/socket sysctls via the central collector. `aggressive` increases default socket buffers plus the softirq receive budget; `balanced` keeps milder values.
- When Sunshine is enabled, the active desktop users are also granted `render` and `input` group access unless explicitly disabled in `j0nix.desktop.gaming.streaming.sunshine.performance.*`.
- On NVIDIA systems, the Sunshine user service exports `/run/opengl-driver/lib` and the DRI driver paths explicitly so NVENC/VAAPI can resolve the host driver codecs under NixOS.
- `j0nix.desktop.gaming.streaming.sunshine.virtualDisplay` integrates with `settings.hyprland.headlessOutputs`, switches Sunshine to wlroots capture (`capture = wlr`), and publishes a dedicated Moonlight app entry for the headless output (for example `Mac Display`).

## Steam Optional Launch Wrappers

From `user/gaming/tools.nix`, these helpers are available for per-game Steam launch options:

- `game-session %command%`
- `game-session-gamemode %command%`
- `game-session-mangohud %command%`
