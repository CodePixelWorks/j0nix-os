{ config, lib, pkgs, settings, ... }:
let
  gaming = config.j0nix.desktop.gaming or { };
  gamingEnabled = gaming.enable or true;
  drivers = config.j0nix.desktop.drivers or { };
  nvidia = drivers.nvidia or { };
  sunshineUseNvidia = nvidia.enable or false;
  streaming = gaming.streaming or { };
  sunshine = streaming.sunshine or { };
  sunshineEnabled = sunshine.enable or false;
  steam = gaming.steam or { };
  steamEnabled = steam.enable or false;
  sunshineOpenFirewall = sunshine.openFirewall or true;
  sunshineCapSysAdmin = sunshine.capSysAdmin or true;
  sunshineAutoStart = sunshine.autoStart or true;
  sunshinePerf = sunshine.performance or { };
  sunshinePerfMode = sunshinePerf.mode or "aggressive";
  sunshineAddRenderGroup = sunshinePerf.addRenderGroup or true;
  sunshineAddInputGroup = sunshinePerf.addInputGroup or true;
  sunshineNetworkPerf = sunshinePerf.network or { };
  sunshineNetworkPerfEnable = sunshineNetworkPerf.enable or true;
  sunshineNetworkPerfMode = sunshineNetworkPerf.mode or sunshinePerfMode;
  sunshineExtraGroups =
    lib.unique (
      lib.optionals sunshineAddRenderGroup [ "render" ]
      ++ lib.optionals sunshineAddInputGroup [ "input" ]
    );
  sunshineVirtualDisplay = sunshine.virtualDisplay or { };
  sunshineVirtualDisplayEnabled = sunshineVirtualDisplay.enable or false;
  sunshineVirtualOutputName = sunshineVirtualDisplay.outputName or null;
  sunshineVirtualAppName = sunshineVirtualDisplay.appName or "Adaptive Display";
  sunshineVirtualAppIcon = "${../../icons/sunshine/adaptive-display.svg}";
  sunshineVirtualCaptureRaw = sunshineVirtualDisplay.capture or "auto";
  sunshineVirtualCaptureAuto = builtins.elem sunshineVirtualCaptureRaw [ null "" "auto" ];
  sunshineVirtualCapture = if sunshineVirtualCaptureAuto then null else sunshineVirtualCaptureRaw;
  sunshineUsesWaylandCapture =
    sunshineVirtualDisplayEnabled
    && (
      sunshineVirtualCapture == null
      || builtins.elem sunshineVirtualCapture [ "wlr" "wl" "wayland" ]
    );
  sunshineNeedsPrivilegedWrapper = sunshineCapSysAdmin && !sunshineUsesWaylandCapture;
  sunshineVirtualResolutions = sunshineVirtualDisplay.resolutions or [
    "2880x1800"
    "2560x1600"
    "1920x1200"
    "1920x1080"
    "1600x900"
    "1280x720"
  ];
  sunshineVirtualFps = sunshineVirtualDisplay.fps or [
    60
    90
    120
  ];
  sunshineNvidiaPackageLibDirs =
    lib.optionals sunshineUseNvidia [
      "${config.hardware.nvidia.package}/lib"
      "${config.hardware.nvidia.package}/lib64"
    ];
  configuredHeadlessOutputs = (settings.hyprland or { }).headlessOutputs or [ ];
  configuredHeadlessOutputMap = lib.listToAttrs (map (output: lib.nameValuePair output.name output) configuredHeadlessOutputs);
  configuredPhysicalMonitors = ((settings.profileDetails or { hyprlandMonitors = [ ]; }).hyprlandMonitors or [ ]);
  configuredPhysicalMonitorNames = map (spec: builtins.head (lib.splitString "," spec)) configuredPhysicalMonitors;
  sunshineVirtualOutputConfig =
    if sunshineVirtualDisplayEnabled && sunshineVirtualOutputName != null && builtins.hasAttr sunshineVirtualOutputName configuredHeadlessOutputMap then
      configuredHeadlessOutputMap.${sunshineVirtualOutputName}
    else
      null;
  defaultHeadlessMode =
    if sunshineVirtualOutputConfig != null then
      sunshineVirtualOutputConfig.mode or "2880x1800@60"
    else
      "2880x1800@60";
  defaultHeadlessPosition =
    if sunshineVirtualOutputConfig != null then
      sunshineVirtualOutputConfig.position or "10000x10000"
    else
      "10000x10000";
  defaultHeadlessScale =
    toString (
      if sunshineVirtualOutputConfig != null then
        sunshineVirtualOutputConfig.scale or 1
      else
        1
    );
  settingsFormat = pkgs.formats.keyValue { };
  sunshineServicePriorityConfig =
    if sunshinePerfMode == "aggressive" then
      {
        Nice = -20;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 0;
      }
    else
      {
        Nice = -10;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 0;
      };
  sunshineNetworkSysctlFragment =
    if sunshineNetworkPerfMode == "aggressive" then
      {
        # Sunshine/Moonlight use bursty UDP traffic. Slightly larger default socket
        # buffers and a wider softirq receive budget reduce drops/jitter during
        # high-bitrate 120 Hz LAN sessions without pushing to pathological values.
        "net.core.rmem_default" = 524288;
        "net.core.wmem_default" = 524288;
        "net.ipv4.udp_rmem_min" = 262144;
        "net.ipv4.udp_wmem_min" = 262144;
        "net.core.netdev_budget" = 600;
        "net.core.netdev_budget_usecs" = 8000;
      }
    else
      {
        "net.core.rmem_default" = 262144;
        "net.core.wmem_default" = 262144;
        "net.ipv4.udp_rmem_min" = 131072;
        "net.ipv4.udp_wmem_min" = 131072;
        "net.core.netdev_budget" = 400;
        "net.core.netdev_budget_usecs" = 4000;
      };
  sunshineDynamicConfigFile =
    settingsFormat.generate "sunshine-j0nix-base.conf" (builtins.removeAttrs config.services.sunshine.settings [
      "output_name"
      "resolutions"
      "fps"
    ]);
  sunshineGraphicsLibraryDirs =
    lib.unique (
      sunshineNvidiaPackageLibDirs
      ++ [ "/run/opengl-driver/lib" ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ "/run/opengl-driver-32/lib" ]
    );
  sunshineDriDriverDirs = map (dir: "${dir}/dri") sunshineGraphicsLibraryDirs;
  sunshineNvidiaEnvironment = {
    # Sunshine's FFmpeg/NVENC path resolves vendor codecs at runtime. On NixOS,
    # those driver libraries live under /run/opengl-driver, so expose them
    # explicitly to the user service instead of relying on login-shell state.
    LD_LIBRARY_PATH = lib.concatStringsSep ":" sunshineGraphicsLibraryDirs;
    LIBGL_DRIVERS_PATH = lib.concatStringsSep ":" sunshineDriDriverDirs;
    LIBVA_DRIVERS_PATH = lib.concatStringsSep ":" sunshineDriDriverDirs;
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
  };
  sunshineExecutable =
    if sunshineNeedsPrivilegedWrapper then
      "${config.security.wrapperDir}/sunshine"
    else
      lib.getExe config.services.sunshine.package;
  sunshineHeadlessPrepScript = pkgs.writeShellScriptBin "sunshine-headless-prep" ''
    set -eu

    hyprctl_bin="${lib.getExe' pkgs.hyprland "hyprctl"}"
    jq_bin="${pkgs.jq}/bin/jq"
    coreutils_bin="${pkgs.coreutils}/bin"
    headless_name=${lib.escapeShellArg (if sunshineVirtualOutputName != null then sunshineVirtualOutputName else "")}
    default_mode=${lib.escapeShellArg defaultHeadlessMode}
    staging_position=${lib.escapeShellArg defaultHeadlessPosition}
    stream_position='0x0'
    headless_scale=${lib.escapeShellArg defaultHeadlessScale}
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$("$coreutils_bin"/id -u)}"
    state_dir="$runtime_dir/sunshine-j0nix"
    workspace_state="$state_dir/headless-workspaces.tsv"
    active_state="$state_dir/headless-active-workspace"
    focused_monitor_state="$state_dir/headless-focused-monitor"

    if [ -z "$headless_name" ] || [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ ! -x "$hyprctl_bin" ] || [ ! -x "$jq_bin" ]; then
      exit 0
    fi

    width="''${SUNSHINE_CLIENT_WIDTH:-}"
    height="''${SUNSHINE_CLIENT_HEIGHT:-}"
    fps="''${SUNSHINE_CLIENT_FPS:-}"

    if [ -n "$width" ] && [ -n "$height" ]; then
      mode="''${width}x''${height}@''${fps:-60}"
    else
      mode="$default_mode"
    fi

    "$hyprctl_bin" keyword monitor "$headless_name,$mode,$staging_position,$headless_scale" >/dev/null 2>&1 || true
    "$coreutils_bin"/mkdir -p "$state_dir"
    "$hyprctl_bin" -j workspaces | "$jq_bin" -r '.[] | select((.name // "") != "" and (.monitor // "") != "") | [.name, .monitor] | @tsv' > "$workspace_state.tmp"
    "$coreutils_bin"/mv "$workspace_state.tmp" "$workspace_state"
    "$hyprctl_bin" -j activeworkspace | "$jq_bin" -r '.name // empty' > "$active_state"
    "$hyprctl_bin" -j monitors | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty' > "$focused_monitor_state"

    move_workspace_to_headless() {
      local workspace_name="$1"
      [ -n "$workspace_name" ] || return 0
      "$hyprctl_bin" dispatch moveworkspacetomonitor "$workspace_name" "$headless_name" >/dev/null 2>&1 || true
    }

    active_workspace=""
    if [ -f "$active_state" ]; then
      IFS= read -r active_workspace < "$active_state" || true
    fi

    if [ -f "$workspace_state" ]; then
      while IFS=$'\t' read -r workspace_name monitor_name; do
        [ -n "$workspace_name" ] || continue
        [ "$workspace_name" = "$active_workspace" ] && continue
        [ "$monitor_name" = "$headless_name" ] && continue
        move_workspace_to_headless "$workspace_name"
      done < "$workspace_state"
    fi

    if [ -n "$active_workspace" ]; then
      move_workspace_to_headless "$active_workspace"
    fi

    ${lib.concatStringsSep "\n    " (map (name: "\"$hyprctl_bin\" keyword monitor ${lib.escapeShellArg "${name},disable"} >/dev/null 2>&1 || true") configuredPhysicalMonitorNames)}
    "$hyprctl_bin" keyword monitor "$headless_name,$mode,$stream_position,$headless_scale" >/dev/null 2>&1 || true
    "$hyprctl_bin" dispatch focusmonitor "$headless_name" >/dev/null 2>&1 || true
    if command -v wm-shell-restart-detached >/dev/null 2>&1; then
      wm-shell-restart-detached >/dev/null 2>&1 || true
    fi
  '';
  sunshineHeadlessUndoScript = pkgs.writeShellScriptBin "sunshine-headless-undo" ''
    set -eu

    hyprctl_bin="${lib.getExe' pkgs.hyprland "hyprctl"}"
    coreutils_bin="${pkgs.coreutils}/bin"
    headless_name=${lib.escapeShellArg (if sunshineVirtualOutputName != null then sunshineVirtualOutputName else "")}
    default_mode=${lib.escapeShellArg defaultHeadlessMode}
    headless_position=${lib.escapeShellArg defaultHeadlessPosition}
    headless_scale=${lib.escapeShellArg defaultHeadlessScale}
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$("$coreutils_bin"/id -u)}"
    state_dir="$runtime_dir/sunshine-j0nix"
    workspace_state="$state_dir/headless-workspaces.tsv"
    active_state="$state_dir/headless-active-workspace"
    focused_monitor_state="$state_dir/headless-focused-monitor"

    if [ -z "$headless_name" ] || [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ ! -x "$hyprctl_bin" ]; then
      exit 0
    fi

    ${lib.concatStringsSep "\n    " (map (spec: "\"$hyprctl_bin\" keyword monitor ${lib.escapeShellArg spec} >/dev/null 2>&1 || true") configuredPhysicalMonitors)}

    active_workspace=""
    if [ -f "$active_state" ]; then
      IFS= read -r active_workspace < "$active_state" || true
    fi
    focused_monitor=""
    if [ -f "$focused_monitor_state" ]; then
      IFS= read -r focused_monitor < "$focused_monitor_state" || true
    fi

    restore_workspace_monitor() {
      local workspace_name="$1"
      local monitor_name="$2"
      [ -n "$workspace_name" ] || return 0
      [ -n "$monitor_name" ] || return 0
      "$hyprctl_bin" dispatch moveworkspacetomonitor "$workspace_name" "$monitor_name" >/dev/null 2>&1 || true
    }

    if [ -f "$workspace_state" ]; then
      while IFS=$'\t' read -r workspace_name monitor_name; do
        [ -n "$workspace_name" ] || continue
        [ "$workspace_name" = "$active_workspace" ] && continue
        restore_workspace_monitor "$workspace_name" "$monitor_name"
      done < "$workspace_state"

      if [ -n "$active_workspace" ]; then
        while IFS=$'\t' read -r workspace_name monitor_name; do
          [ "$workspace_name" = "$active_workspace" ] || continue
          restore_workspace_monitor "$workspace_name" "$monitor_name"
          break
        done < "$workspace_state"
      fi
    fi

    "$hyprctl_bin" keyword monitor "$headless_name,$default_mode,$headless_position,$headless_scale" >/dev/null 2>&1 || true
    if [ -n "$focused_monitor" ]; then
      "$hyprctl_bin" dispatch focusmonitor "$focused_monitor" >/dev/null 2>&1 || true
    fi
    if command -v wm-shell-restart-detached >/dev/null 2>&1; then
      wm-shell-restart-detached >/dev/null 2>&1 || true
    fi
    "$coreutils_bin"/rm -f "$workspace_state" "$active_state" "$focused_monitor_state"
  '';
  sunshineHeadlessPrepCommand = lib.getExe sunshineHeadlessPrepScript;
  sunshineHeadlessUndoCommand = lib.getExe sunshineHeadlessUndoScript;
  sunshineLaunchWrapper = pkgs.writeShellScript "sunshine-j0nix-launch" ''
    set -eu

    hyprctl_bin="${lib.getExe' pkgs.hyprland "hyprctl"}"
    jq_bin="${pkgs.jq}/bin/jq"
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    tmp_config="$runtime_dir/sunshine-j0nix.conf"
    base_config=${lib.escapeShellArg sunshineDynamicConfigFile}
    rm -f "$tmp_config"
    ${pkgs.coreutils}/bin/install -m 600 "$base_config" "$tmp_config"

    ${lib.optionalString sunshineVirtualDisplayEnabled ''
      headless_name=${lib.escapeShellArg (if sunshineVirtualOutputName != null then sunshineVirtualOutputName else "")}
      headless_mode=${lib.escapeShellArg defaultHeadlessMode}
      headless_position=${lib.escapeShellArg defaultHeadlessPosition}
      headless_scale=${lib.escapeShellArg defaultHeadlessScale}

      if [ -n "$headless_name" ] && [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -x "$hyprctl_bin" ]; then
        if ! "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$headless_name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
          "$hyprctl_bin" output create headless "$headless_name" >/dev/null 2>&1 || true
          for _ in $(seq 1 50); do
            if "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$headless_name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
              break
            fi
            sleep 0.1
          done
        fi

        "$hyprctl_bin" keyword monitor "$headless_name,$headless_mode,$headless_position,$headless_scale" >/dev/null 2>&1 || true
      fi
    ''}

    exec ${sunshineExecutable} "$tmp_config"
  '';
  sunshineBaseApps =
    [
      {
        name = "Desktop";
        "image-path" = "desktop.png";
      }
    ]
    ++ lib.optionals steamEnabled [
      {
        name = "Steam Big Picture";
        detached = [ "setsid steam steam://open/bigpicture" ];
        "prep-cmd" = [
          {
            do = "";
            undo = "setsid steam steam://close/bigpicture";
          }
        ];
        "image-path" = "steam.png";
      }
    ];
in
lib.mkIf (gamingEnabled && sunshineEnabled) {
  services.sunshine = {
    enable = true;
    openFirewall = sunshineOpenFirewall;
    capSysAdmin = sunshineNeedsPrivilegedWrapper;
    autoStart = sunshineAutoStart;
    settings = lib.optionalAttrs sunshineVirtualDisplayEnabled (
      lib.optionalAttrs (sunshineVirtualCapture != null) {
        capture = sunshineVirtualCapture;
      }
    );
  };

  services.sunshine.applications.env.PATH = lib.mkDefault "$(PATH):$(HOME)/.local/bin";

  services.sunshine.applications.apps =
    lib.mkAfter (
      sunshineBaseApps
      ++ lib.optionals sunshineVirtualDisplayEnabled [
        {
          name = sunshineVirtualAppName;
          "auto-detach" = true;
          "image-path" = sunshineVirtualAppIcon;
          "working-dir" = "/tmp";
          "prep-cmd" = [
            {
              do = sunshineHeadlessPrepCommand;
              undo = sunshineHeadlessUndoCommand;
            }
          ];
        }
      ]
    );

  # Sunshine benefits from direct render-node access and reliable virtual input
  # permissions for low-latency capture and controller/keyboard injection.
  j0nix.desktop.accounts.additionalExtraGroups = lib.mkAfter sunshineExtraGroups;

  # Route Sunshine-specific network tuning through the shared sysctl collector so
  # it composes cleanly with the generic network-performance and gaming roles.
  j0nix.desktop.sysctl.extraFragments =
    lib.mkAfter (lib.optional sunshineNetworkPerfEnable sunshineNetworkSysctlFragment);

  # Apply a dedicated service-priority profile on top of the upstream user unit.
  # This mirrors the useful part of common Sunshine tuning gists without forcing
  # an extreme RT priority that can starve a daily-driver desktop.
  systemd.user.services.sunshine.environment = lib.mkIf sunshineUseNvidia sunshineNvidiaEnvironment;
  systemd.user.services.sunshine.preStart = lib.mkIf sunshineVirtualDisplayEnabled ''
    ${sunshineHeadlessUndoCommand} >/dev/null 2>&1 || true
  '';
  systemd.user.services.sunshine.postStop = lib.mkIf sunshineVirtualDisplayEnabled ''
    ${sunshineHeadlessUndoCommand} >/dev/null 2>&1 || true
  '';

  systemd.user.services.sunshine.serviceConfig = sunshineServicePriorityConfig // {
    ExecStart = lib.mkForce "${sunshineLaunchWrapper}";
  };

  assertions = [
    {
      assertion = builtins.isBool sunshineOpenFirewall;
      message = "j0nix.desktop.gaming.streaming.sunshine.openFirewall must be a boolean";
    }
    {
      assertion = builtins.isBool sunshineCapSysAdmin;
      message = "j0nix.desktop.gaming.streaming.sunshine.capSysAdmin must be a boolean";
    }
    {
      assertion = builtins.isBool sunshineAutoStart;
      message = "j0nix.desktop.gaming.streaming.sunshine.autoStart must be a boolean";
    }
    {
      assertion = builtins.elem sunshinePerfMode [ "balanced" "aggressive" ];
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.mode must be one of: balanced, aggressive";
    }
    {
      assertion = builtins.isBool sunshineAddRenderGroup;
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.addRenderGroup must be a boolean";
    }
    {
      assertion = builtins.isBool sunshineAddInputGroup;
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.addInputGroup must be a boolean";
    }
    {
      assertion = builtins.isBool sunshineNetworkPerfEnable;
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.network.enable must be a boolean";
    }
    {
      assertion = builtins.elem sunshineNetworkPerfMode [ "balanced" "aggressive" ];
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.network.mode must be one of: balanced, aggressive";
    }
    {
      assertion = !sunshineVirtualDisplayEnabled || sunshineVirtualCaptureAuto || builtins.elem sunshineVirtualCapture [ "wlr" "wl" "wayland" "kms" "x11" "nvfbc" ];
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.capture must be auto, empty, or one of: wlr, wl, wayland, kms, x11, nvfbc";
    }
    {
      assertion = !sunshineVirtualDisplayEnabled || builtins.all (mode: builtins.match "^[0-9]+x[0-9]+$" mode != null) sunshineVirtualResolutions;
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.resolutions must contain WIDTHxHEIGHT strings such as 2880x1800";
    }
    {
      assertion = !sunshineVirtualDisplayEnabled || builtins.all (fps: fps > 0) sunshineVirtualFps;
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.fps must contain positive integers";
    }
    {
      assertion = !sunshineVirtualDisplayEnabled || sunshineVirtualOutputName != null;
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.outputName must be set when virtualDisplay is enabled.";
    }
    {
      assertion = !sunshineVirtualDisplayEnabled || sunshineVirtualAppName != "";
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.appName must not be empty when virtualDisplay is enabled.";
    }
    {
      assertion = !sunshineVirtualDisplayEnabled || sunshineVirtualOutputConfig != null;
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.outputName must reference a configured settings.hyprland.headlessOutputs entry.";
    }
  ];
}
