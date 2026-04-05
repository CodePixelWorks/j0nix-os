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
- `j0nix.desktop.gaming.proton.ntsync.enable = true` loads the `ntsync` kernel module and exports `PROTON_USE_NTSYNC=1` with fsync disabled for Steam/Proton launches.

## Sunshine Note

- `j0nix.desktop.gaming.streaming.sunshine.capSysAdmin = true` enables KMS/DRM capture for lower-latency Sunshine capture paths.
- `j0nix.desktop.gaming.streaming.sunshine.performance.mode = "aggressive"` applies a higher-priority Sunshine user service profile (`Nice` + I/O priority) without depending on fragile per-user realtime scheduler permissions.
- `j0nix.desktop.gaming.streaming.sunshine.performance.network` appends Sunshine-specific UDP/socket sysctls via the central collector. `aggressive` increases default socket buffers plus the softirq receive budget; `balanced` keeps milder values.
- When Sunshine is enabled, the active desktop users are also granted `render` and `input` group access unless explicitly disabled in `j0nix.desktop.gaming.streaming.sunshine.performance.*`.
- On NVIDIA systems, the Sunshine user service exports both the selected `hardware.nvidia.package` library directories and `/run/opengl-driver/lib` plus the DRI driver paths so NVENC/VAAPI can resolve the host driver codecs under NixOS.
- `settings.sunshine.displayTarget` is the user-facing selector for the dedicated Sunshine stream output. It supports `backend = "hyprland-headless"` for the existing virtual display path or `backend = "physical-output"` for a real connector such as a dummy plug on `DP-2`.
- The old `j0nix.desktop.gaming.streaming.sunshine.virtualDisplay` block still works as a legacy fallback, but `settings.sunshine.displayTarget` overrides it.
- Both Sunshine display-target backends must be disabled by default in `settings.hyprland.initialOutputStates`. Sunshine `prep-cmd` activates the selected target only for the lifetime of the stream, and `undo` / `postStop` disable it again.
- On this NVIDIA setup, the module uses `pkgs.sunshine.override { cudaSupport = true; }` so the nixpkgs package enables CUDA support and adds the driver runtime path needed for NVENC libraries such as `libnvidia-encode.so.1`.
- For the physical-output dummy-plug path, `capture = "wlr"` is the stable default. `kms` can expose more direct capture paths, but on this host it can produce a black desktop even when NVENC itself is working.
- When Sunshine capture is left at `auto` on Hyprland, the module now resolves that to `wlr` so Wayland streaming stays on the wlroots capture path instead of drifting back to KMS.
- `Adaptive Display` uses Sunshine `prep-cmd` hooks to retune the selected stream target to `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, and `SUNSHINE_CLIENT_FPS`, save the current workspace-to-monitor and focused-monitor state, move the current workspaces onto that target, temporarily disable the other configured physical monitors so the stream target behaves like the primary display for the stream, then restore the monitor layout, the focused monitor, and the saved workspace mapping afterwards. To avoid Hyprland overlap warnings during the switch, the hook keeps the target parked at its off-screen staging position until the physical monitors are disabled, then moves it to `0x0` for the active stream. The same hook triggers a detached WM shell restart on both the prep and undo paths so Quickshell-based shells recalculate their layer geometry after the monitor/workspace handoff.
- `settings.sunshine.disableLockScreenDuringStream = true` makes the Sunshine prep hook drop a small runtime marker and stop any running `hyprlock` instance; the shared `wm-lock-screen` helper then becomes a no-op for the duration of the stream and is restored automatically in the undo path.
- The Sunshine user service also runs the same display-target undo helper in `preStart` and `postStop`, so a `nixos-rebuild switch`, service restart, or crash does not leave the Hyprland workspaces and monitor layout stuck in the stream-target state.
- Declaring a custom Sunshine app list replaces the upstream defaults, so the module now restores the standard `Desktop` entry and, when Steam is enabled, `Steam Big Picture`, then appends `Adaptive Display`.
- The current Sunshine build in nixpkgs ignores top-level `fps` and `resolutions` keys, so the wrapper intentionally does not emit them into `sunshine.conf`. The adaptive-display prep hook still uses those lists as an allowlist for stream modes, and falls back to the configured default monitor mode when a client requests an unsupported resolution or refresh rate.
- In wlroots/Wayland capture mode the module still skips the privileged `cap_sys_admin` wrapper because that capture path does not need it.

## Steam Optional Launch Wrappers

From `user/gaming/tools.nix`, these helpers are available for per-game Steam launch options:

- `game-session %command%`
- `game-session-gamemode %command%`
- `game-session-mangohud %command%`
