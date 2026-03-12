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
- On NVIDIA systems, the Sunshine user service exports both the selected `hardware.nvidia.package` library directories and `/run/opengl-driver/lib` plus the DRI driver paths so NVENC/VAAPI can resolve the host driver codecs under NixOS.
- `j0nix.desktop.gaming.streaming.sunshine.virtualDisplay` integrates with `settings.hyprland.headlessOutputs` and publishes a dedicated Moonlight app entry (for example `Adaptive Display`). `virtualDisplay.capture = "auto"` leaves Sunshine's capture selection unset so Sunshine can choose the least-broken Linux path for the current driver stack; explicit values such as `wlr`, `kms`, `x11`, or `nvfbc` are still supported when you want to pin a backend.
- In the Hyprland virtual-display path, `capture = "auto"` is still treated as a Wayland/non-privileged launch for the service wrapper. That keeps Sunshine off the `cap_sys_admin` wrapper, which otherwise breaks NVIDIA userspace codec loading on this setup.
- `Adaptive Display` additionally uses Sunshine `prep-cmd` hooks to retune the Hyprland headless output to `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, and `SUNSHINE_CLIENT_FPS`, save the current workspace-to-monitor and focused-monitor state, move the current workspaces onto that headless output, temporarily disable the configured physical Hyprland monitors so the headless output behaves like the primary display for the stream, then restore the monitor layout, the focused monitor, and the saved workspace mapping afterwards. To avoid Hyprland overlap warnings during the switch, the hook keeps the headless output parked at its off-screen staging position until the physical monitors are disabled, then moves it to `0x0` for the active stream. That keeps the normal `Desktop` app on the hardware-accelerated physical monitor path while `Adaptive Display` becomes the separate software/headless path.
- The Sunshine user service also runs the same headless-undo helper in `preStart` and `postStop`, so a `nixos-rebuild switch`, service restart, or crash does not leave the Hyprland workspaces and monitor layout stuck in the headless-stream state.
- Declaring a custom Sunshine app list replaces the upstream defaults, so the module now restores the standard `Desktop` entry and, when Steam is enabled, `Steam Big Picture`, then appends `Adaptive Display`.
- The current Sunshine build in nixpkgs ignores top-level `fps` and `resolutions` keys, so the wrapper intentionally does not emit them into `sunshine.conf`.
- In headless wlroots mode the module intentionally skips the privileged `cap_sys_admin` wrapper, because wlroots capture does not need it and the wrapper interferes with NVIDIA/CUDA userspace library resolution.

## Steam Optional Launch Wrappers

From `user/gaming/tools.nix`, these helpers are available for per-game Steam launch options:

- `game-session %command%`
- `game-session-gamemode %command%`
- `game-session-mangohud %command%`
