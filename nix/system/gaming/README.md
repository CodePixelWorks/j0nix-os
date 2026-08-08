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
Per-user launchers and helpers belong in `nix/user/gaming/`.

## Performance Note

- `j0nix.desktop.gaming.performance.gamemodeRenice` controls gamemode CPU priority (`-20..19`, default `-10`).
- `j0nix.desktop.gaming.performance.autoPerformanceMode` switches power profile to `performance` while gamemode sessions are active.
- `j0nix.desktop.gaming.performance.gamescopeHdr` enables HDR wrapper tooling for gamescope launch.

## Steam Note

- `j0nix.desktop.gaming.steam.steamRun` installs `steam-run`.
- `j0nix.desktop.gaming.proton.provider` selects preferred compat provider (`cachyos` or `ge`).
- `j0nix.desktop.gaming.proton.ntsync.enable = true` loads the `ntsync` kernel module and exports `PROTON_USE_NTSYNC=1` with fsync disabled for Steam/Proton launches.
- `j0nix.desktop.gaming.proton.updater = true` installs ProtonUp-Qt, and ProtonPlus is installed alongside it so dwproton can be managed from a GUI.

## Sunshine Note

- `j0nix.desktop.gaming.streaming.sunshine.capSysAdmin = true` enables KMS/DRM capture for lower-latency Sunshine capture paths.
- `j0nix.desktop.gaming.streaming.sunshine.performance.mode = "aggressive"` applies a higher-priority Sunshine user service profile (`Nice = -20` plus stronger CPU/I/O weights) without depending on fragile per-user realtime scheduler permissions.
- `j0nix.desktop.gaming.streaming.sunshine.performance.network` appends Sunshine-specific UDP/socket sysctls via the central collector. `aggressive` increases default socket buffers plus the softirq receive budget; `balanced` keeps milder values.
- When Sunshine is enabled, the active desktop users are also granted `render` and `input` group access unless explicitly disabled in `j0nix.desktop.gaming.streaming.sunshine.performance.*`.
- On NVIDIA systems, the Sunshine user service exports both the selected `hardware.nvidia.package` library directories and `/run/opengl-driver/lib` plus the DRI driver paths so NVENC/VAAPI can resolve the host driver codecs under NixOS.
- `settings.sunshine.displayTarget` is the user-facing selector for the dedicated Sunshine stream output. It supports `backend = "hyprland-headless"` for the existing virtual display path or `backend = "physical-output"` for a real connector such as a dummy plug on `DP-2`.
- The old `j0nix.desktop.gaming.streaming.sunshine.virtualDisplay` block still works as a legacy fallback, but `settings.sunshine.displayTarget` overrides it.
- The configured Sunshine display target stays disabled by default at Hyprland startup. Sunshine `prep-cmd` activates the selected target only for the lifetime of the stream, and `undo` / `postStop` disable it again.
- On this NVIDIA setup, the module uses `pkgs.sunshine.override { cudaSupport = true; }` so the nixpkgs package enables CUDA support and adds the driver runtime path needed for NVENC libraries such as `libnvidia-encode.so.1`.
- Sunshine Web UI credentials are managed per user under `settings.userSettings.<name>.programs.sunshine.webUi`, because the service itself runs in the user session.
- `sunshine-reset-creds --prompt` interactively sets a new Sunshine Web UI password for the configured username.
- If `passwordSecretName` points at a per-user SOPS secret such as `sunshine/web_password`, Home Manager reapplies that password automatically on each switch.
- For the physical-output dummy-plug path, this host currently opts into `capture = "kms"` to prefer the direct DRM capture path on the dedicated stream output. `wlr` remains available as the fallback when the Wayland path is the better choice for a given regression.
- When Sunshine capture is left at `auto` on Hyprland, the module now resolves that to `wlr` so Wayland streaming stays on the wlroots capture path instead of drifting back to KMS.
- Sunshine-launched apps inherit a no-vblank/no-VRR environment (`__GL_SYNC_TO_VBLANK=0`, `__GL_GSYNC_ALLOWED=0`, `__GL_VRR_ALLOWED=0`, `vblank_mode=0`) so driver-level sync does not add another pacing layer on the host. In-game VSync or other explicit frame limiters still need to be disabled separately.
- `Adaptive Display` uses Sunshine `prep-cmd` hooks through the shared `wm-monitor transaction-begin` / `transaction-end` helpers. The transaction retunes the selected stream target to `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, and `SUNSHINE_CLIENT_FPS`, records workspace and focus state, moves active workspaces to the stream target, temporarily disables the other configured physical monitors, then restores the saved monitor layout, focus, and workspace mapping afterwards. On the headless path the target is moved to `0x0` during the stream; on the physical-output path it stays on its configured position to avoid overlap. For `kms` on physical outputs, the launch wrapper also injects the matching Sunshine `output_name` display index so DRM capture stays pinned to the intended connector.
- On the physical-output + `kms` path, the launch wrapper also pre-enables the target output in its configured staging position before Sunshine starts, so the injected `output_name` monitor index actually exists during Sunshine startup.
- `settings.sunshine.disableLockScreenDuringStream = true` makes the Sunshine prep hook drop a small runtime marker and stop any running `hyprlock` instance; the shared `wm-lock-screen` helper then becomes a no-op for the duration of the stream and is restored automatically in the undo path.
- The Sunshine user service also runs the same display-target undo helper in `preStart` and `postStop`, so a `nixos-rebuild switch`, service restart, or crash does not leave the Hyprland workspaces and monitor layout stuck in the stream-target state.
- Declaring a custom Sunshine app list replaces the upstream defaults, so the module now restores the standard `Desktop` entry and, when Steam is enabled, `Steam Big Picture`, then appends `Adaptive Display`.
- The current Sunshine build in nixpkgs ignores top-level `fps` and `resolutions` keys, so the wrapper intentionally does not emit them into `sunshine.conf`. The adaptive-display prep hook still uses the declared FPS list as a known-good refresh guardrail and keeps the resolution list as a guardrail for headless targets, but for physical-output targets it now trusts the client resolution again and falls back only on the configured default refresh rate when needed.
- In wlroots/Wayland capture mode the module still skips the privileged `cap_sys_admin` wrapper because that capture path does not need it.

## Steam Optional Launch Wrappers

From `nix/user/gaming/tools.nix`, these helpers are available for per-game Steam launch options:

- `game-session %command%`
- `game-session-gamemode %command%`
- `game-session-mangohud %command%`
