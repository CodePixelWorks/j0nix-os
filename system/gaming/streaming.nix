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
  sunshineVirtualAppName = sunshineVirtualDisplay.appName or "Mac Display";
  sunshineVirtualCapture = sunshineVirtualDisplay.capture or "wlr";
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
  sunshineVirtualResolutionsValue =
    "[${lib.concatStringsSep ", " sunshineVirtualResolutions}]";
  sunshineVirtualFpsValue =
    "[${lib.concatStringsSep ", " (map toString sunshineVirtualFps)}]";
  configuredHeadlessOutputs = (settings.hyprland or { }).headlessOutputs or [ ];
  configuredHeadlessOutputMap = lib.listToAttrs (map (output: lib.nameValuePair output.name output) configuredHeadlessOutputs);
  sunshineVirtualOutputConfig =
    if sunshineVirtualDisplayEnabled && sunshineVirtualOutputName != null && builtins.hasAttr sunshineVirtualOutputName configuredHeadlessOutputMap then
      configuredHeadlessOutputMap.${sunshineVirtualOutputName}
    else
      null;
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
    [ "/run/opengl-driver/lib" ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ "/run/opengl-driver-32/lib" ];
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
    if sunshineCapSysAdmin then
      "${config.security.wrapperDir}/sunshine"
    else
      lib.getExe config.services.sunshine.package;
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
      printf '\nresolutions = %s\n' ${lib.escapeShellArg sunshineVirtualResolutionsValue} >>"$tmp_config"
      printf 'fps = %s\n' ${lib.escapeShellArg sunshineVirtualFpsValue} >>"$tmp_config"

      headless_name=${lib.escapeShellArg (if sunshineVirtualOutputName != null then sunshineVirtualOutputName else "")}
      headless_mode=${lib.escapeShellArg (if sunshineVirtualOutputConfig != null then (sunshineVirtualOutputConfig.mode or "2880x1800@60") else "2880x1800@60")}
      headless_position=${lib.escapeShellArg (if sunshineVirtualOutputConfig != null then (sunshineVirtualOutputConfig.position or "10000x10000") else "10000x10000")}
      headless_scale=${lib.escapeShellArg (toString (if sunshineVirtualOutputConfig != null then (sunshineVirtualOutputConfig.scale or 1) else 1))}

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
in
lib.mkIf (gamingEnabled && sunshineEnabled) {
  services.sunshine = {
    enable = true;
    openFirewall = sunshineOpenFirewall;
    capSysAdmin = sunshineCapSysAdmin;
    autoStart = sunshineAutoStart;
    settings = lib.optionalAttrs sunshineVirtualDisplayEnabled {
      capture = sunshineVirtualCapture;
    };
  };

  services.sunshine.applications.apps = lib.mkAfter (lib.optionals sunshineVirtualDisplayEnabled [
    {
      name = sunshineVirtualAppName;
      output = sunshineVirtualOutputName;
      cmd = "";
      "auto-detach" = true;
    }
  ]);

  # Sunshine benefits from direct render-node access and reliable virtual input
  # permissions for low-latency capture and controller/keyboard injection.
  j0nix.desktop.accounts.baseExtraGroups = lib.mkAfter sunshineExtraGroups;

  # Route Sunshine-specific network tuning through the shared sysctl collector so
  # it composes cleanly with the generic network-performance and gaming roles.
  j0nix.desktop.sysctl.extraFragments =
    lib.mkAfter (lib.optional sunshineNetworkPerfEnable sunshineNetworkSysctlFragment);

  # Apply a dedicated service-priority profile on top of the upstream user unit.
  # This mirrors the useful part of common Sunshine tuning gists without forcing
  # an extreme RT priority that can starve a daily-driver desktop.
  systemd.user.services.sunshine.environment = lib.mkIf sunshineUseNvidia sunshineNvidiaEnvironment;

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
      assertion = !sunshineVirtualDisplayEnabled || builtins.elem sunshineVirtualCapture [ "wlr" "wl" "wayland" ];
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.capture must be one of: wlr, wl, wayland";
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
