{ config, lib, pkgs, settings, ... }:
let
  gaming = config.j0nix.desktop.gaming or { };
  gamingEnabled = gaming.enable or true;
  streaming = gaming.streaming or { };
  sunshine = streaming.sunshine or { };
  sunshineEnabled = sunshine.enable or false;
  sunshineOpenFirewall = sunshine.openFirewall or true;
  sunshineCapSysAdmin = sunshine.capSysAdmin or true;
  sunshineAutoStart = sunshine.autoStart or true;
  sunshinePerf = sunshine.performance or { };
  sunshinePerfMode = sunshinePerf.mode or "aggressive";
  sunshineCpuRealtimePriority = sunshinePerf.cpuRealtimePriority or 20;
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
        CPUSchedulingPolicy = "rr";
        CPUSchedulingPriority = sunshineCpuRealtimePriority;
        LimitRTPRIO = "infinity";
        LimitRTTIME = "infinity";
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
    settingsFormat.generate "sunshine-j0nix-base.conf" (builtins.removeAttrs config.services.sunshine.settings [ "output_name" ]);
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
    cp "$base_config" "$tmp_config"

    ${lib.optionalString sunshineVirtualDisplayEnabled ''
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

        headless_display_id="$("$hyprctl_bin" -j monitors all | "$jq_bin" -r --arg name "$headless_name" 'to_entries | map(select(.value.name == $name)) | if length > 0 then .[0].key else empty end')"
        if [ -n "$headless_display_id" ]; then
          printf '\noutput_name = %s\n' "$headless_display_id" >>"$tmp_config"
        else
          echo "warning: could not resolve headless Hyprland output '$headless_name' for Sunshine; falling back to Sunshine default display" >&2
        fi
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
      resolutions = sunshineVirtualResolutions;
      fps = sunshineVirtualFps;
    };
  };

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
      assertion = sunshineCpuRealtimePriority >= 1 && sunshineCpuRealtimePriority <= 99;
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.cpuRealtimePriority must be between 1 and 99";
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
      assertion = !sunshineVirtualDisplayEnabled || sunshineVirtualOutputName != null;
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.outputName must be set when virtualDisplay is enabled.";
    }
    {
      assertion = !sunshineVirtualDisplayEnabled || sunshineVirtualOutputConfig != null;
      message = "j0nix.desktop.gaming.streaming.sunshine.virtualDisplay.outputName must reference a configured settings.hyprland.headlessOutputs entry.";
    }
  ];
}
