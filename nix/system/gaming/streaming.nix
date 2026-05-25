{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  monitorLib = import ../lib/monitor.nix { inherit lib; };
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
  sunshineExtraGroups = lib.unique (
    lib.optionals sunshineAddRenderGroup [ "render" ] ++ lib.optionals sunshineAddInputGroup [ "input" ]
  );
  sunshineDisplayTargetSettings = ((settings.sunshine or { }).displayTarget or { });
  sunshineVirtualDisplay = sunshine.virtualDisplay or { };
  sunshineDisableLockScreenDuringStream = (
    (settings.sunshine or { }).disableLockScreenDuringStream or true
  );
  sunshineDisplayTargetEnabled =
    sunshineDisplayTargetSettings.enable or (sunshineVirtualDisplay.enable or false);
  sunshineDisplayTargetBackend = sunshineDisplayTargetSettings.backend or "hyprland-headless";
  sunshineDisplayTargetOutputName =
    sunshineDisplayTargetSettings.outputName or (sunshineVirtualDisplay.outputName or null);
  sunshineDisplayTargetAppName =
    sunshineDisplayTargetSettings.appName or (sunshineVirtualDisplay.appName or "Adaptive Display");
  sunshineDisplayTargetAppIcon = "${../../../icons/sunshine/adaptive-display.svg}";
  hyprlandEnabled = config.programs.hyprland.enable or false;
  sunshineDisplayTargetCaptureRaw =
    sunshineDisplayTargetSettings.capture or (sunshineVirtualDisplay.capture or "auto");
  sunshineDisplayTargetCaptureAuto = builtins.elem sunshineDisplayTargetCaptureRaw [
    null
    ""
    "auto"
  ];
  sunshineDisplayTargetCapture =
    if sunshineDisplayTargetCaptureAuto then
      if hyprlandEnabled then "wlr" else null
    else
      sunshineDisplayTargetCaptureRaw;
  sunshineDisplayTargetIsHeadless = sunshineDisplayTargetBackend == "hyprland-headless";
  sunshineDisplayTargetIsPhysical = sunshineDisplayTargetBackend == "physical-output";
  profileDetails = settings.profileDetails or { };
  profileHeadlessOutput = profileDetails.hyprlandSunshineHeadlessOutput or null;
  profileInitialOutputStatesBase = profileDetails.hyprlandInitialOutputStatesBase or [ ];
  sunshineUsesWaylandCapture =
    sunshineDisplayTargetEnabled
    && (
      if sunshineDisplayTargetIsHeadless then
        (
          sunshineDisplayTargetCapture == null
          || builtins.elem sunshineDisplayTargetCapture [
            "wlr"
            "wl"
            "wayland"
          ]
        )
      else
        builtins.elem sunshineDisplayTargetCapture [
          "wlr"
          "wl"
          "wayland"
        ]
    );
  # KMS capture requires privileged wrapper for DRM device access
  sunshineNeedsPrivilegedWrapper =
    sunshineCapSysAdmin && (!sunshineUsesWaylandCapture || sunshineDisplayTargetCapture == "kms");
  sunshineDisplayTargetResolutions =
    sunshineDisplayTargetSettings.resolutions or (sunshineVirtualDisplay.resolutions or [
      "2880x1800"
      "2560x1600"
      "1920x1200"
      "1920x1080"
      "1600x900"
      "1280x720"
    ]
    );
  sunshineDisplayTargetFps =
    sunshineDisplayTargetSettings.fps or (sunshineVirtualDisplay.fps or [
      60
      90
      120
    ]
    );
  sunshineNvidiaPackageLibDirs = lib.optionals sunshineUseNvidia [
    "${config.hardware.nvidia.package}/lib"
    "${config.hardware.nvidia.package}/lib64"
  ];
  configuredHeadlessOutputs =
    if ((settings.hyprland or { }) ? headlessOutputs) then
      (settings.hyprland or { }).headlessOutputs
    else if sunshineDisplayTargetIsHeadless && profileHeadlessOutput != null then
      [ profileHeadlessOutput ]
    else
      [ ];
  configuredHeadlessOutputMap = lib.listToAttrs (
    map (output: lib.nameValuePair output.name output) configuredHeadlessOutputs
  );
  configuredInitialOutputStates =
    if ((settings.hyprland or { }) ? initialOutputStates) then
      (settings.hyprland or { }).initialOutputStates
    else
      profileInitialOutputStatesBase
      ++ lib.optionals (sunshineDisplayTargetIsHeadless && profileHeadlessOutput != null) [
        {
          name = profileHeadlessOutput.name;
          enabledByDefault = false;
          mode = profileHeadlessOutput.mode or "2880x1800@60";
          position = profileHeadlessOutput.position or "10000x10000";
          scale = profileHeadlessOutput.scale or 1;
        }
      ];
  configuredInitialOutputStateMap = lib.listToAttrs (
    map (output: lib.nameValuePair output.name output) configuredInitialOutputStates
  );
  configuredHeadlessOutputNames = map (output: output.name or "") configuredHeadlessOutputs;
  configuredPhysicalOutputStates = builtins.filter (
    output: !(builtins.elem (output.name or "") configuredHeadlessOutputNames)
  ) configuredInitialOutputStates;
  configuredPhysicalOutputIndexMap = lib.listToAttrs (
    lib.imap0 (idx: output: lib.nameValuePair (output.name or "") idx) configuredPhysicalOutputStates
  );
  initialOutputStateToMonitorSpec =
    output:
    let
      name = output.name or "";
      enabledByDefault = output.enabledByDefault or true;
      mode = output.mode or "preferred";
      position = output.position or "auto";
      scale = toString (output.scale or 1);
    in
    if enabledByDefault then "${name},${mode},${position},${scale}" else "${name},disable";
  sunshineDisplayTargetConfig =
    if !sunshineDisplayTargetEnabled || sunshineDisplayTargetOutputName == null then
      null
    else if
      sunshineDisplayTargetIsHeadless
      && builtins.hasAttr sunshineDisplayTargetOutputName configuredHeadlessOutputMap
    then
      configuredHeadlessOutputMap.${sunshineDisplayTargetOutputName}
    else if
      sunshineDisplayTargetIsPhysical
      && builtins.hasAttr sunshineDisplayTargetOutputName configuredInitialOutputStateMap
    then
      configuredInitialOutputStateMap.${sunshineDisplayTargetOutputName}
    else
      null;
  sunshineDisplayTargetInitialState =
    if
      sunshineDisplayTargetEnabled
      && sunshineDisplayTargetOutputName != null
      && builtins.hasAttr sunshineDisplayTargetOutputName configuredInitialOutputStateMap
    then
      configuredInitialOutputStateMap.${sunshineDisplayTargetOutputName}
    else
      null;
  sunshineDisplayTargetDefaultSpec =
    if sunshineDisplayTargetInitialState != null then
      initialOutputStateToMonitorSpec sunshineDisplayTargetInitialState
    else
      "";
  sunshineDisplayTargetDisableOtherMonitorNames = map (output: output.name or "") (
    builtins.filter (
      output:
      let
        name = output.name or "";
      in
      name != "" && name != sunshineDisplayTargetOutputName
    ) configuredPhysicalOutputStates
  );
  defaultTargetMode =
    if sunshineDisplayTargetConfig != null then
      sunshineDisplayTargetConfig.mode or "2880x1800@60"
    else
      "2880x1800@60";
  defaultTargetPosition =
    if sunshineDisplayTargetConfig != null then
      sunshineDisplayTargetConfig.position or "10000x10000"
    else
      "10000x10000";
  sunshineKmsOutputIndex =
    if
      sunshineDisplayTargetEnabled
      && sunshineDisplayTargetIsPhysical
      && sunshineDisplayTargetCapture == "kms"
      && sunshineDisplayTargetOutputName != null
      && builtins.hasAttr sunshineDisplayTargetOutputName configuredPhysicalOutputIndexMap
    then
      configuredPhysicalOutputIndexMap.${sunshineDisplayTargetOutputName}
    else
      null;
  defaultTargetScale = toString (
    if sunshineDisplayTargetConfig != null then sunshineDisplayTargetConfig.scale or 1 else 1
  );
  allowedTargetResolutions = lib.concatStringsSep " " (map monitorLib.renderResolution sunshineDisplayTargetResolutions);
  allowedTargetFps = lib.concatStringsSep " " (map toString sunshineDisplayTargetFps);
  settingsFormat = pkgs.formats.keyValue { };
  sunshineServicePriorityConfig =
    if sunshinePerfMode == "aggressive" then
      {
        Nice = -20;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 0;
        CPUWeight = 10000;
        IOWeight = 1000;
      }
    else
      {
        Nice = -10;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 0;
        CPUWeight = 500;
        IOWeight = 500;
      };
  sunshineNetworkSysctlFragment =
    if sunshineNetworkPerfMode == "aggressive" then
      {
        # Sunshine/Moonlight use bursty UDP traffic. Larger socket buffers
        # and wider softirq budget reduce drops/jitter during high-bitrate
        # 120 Hz LAN sessions.
        # Additional fixes for slow connection warnings:
        # - Increase connection tracking for UDP
        # - Optimize UDP fragment handling
        # - Increase network device tx queue
        "net.core.optmem_max" = 1048576;
        "net.core.rmem_default" = 1048576;
        "net.core.wmem_default" = 1048576;
        "net.core.rmem_max" = 16777216;
        "net.core.wmem_max" = 16777216;
        "net.ipv4.udp_rmem_min" = 524288;
        "net.ipv4.udp_wmem_min" = 524288;
        "net.ipv4.udp_mem" = "65536 131072 262144";
        "net.ipv4.tcp_rmem" = "131072 1048576 16777216";
        "net.ipv4.tcp_wmem" = "131072 1048576 16777216";
        "net.ipv4.tcp_window_scaling" = 1;
        "net.ipv4.tcp_timestamps" = 1;
        "net.ipv4.tcp_sack" = 1;
        "net.core.netdev_budget" = 800;
        "net.core.netdev_budget_usecs" = 12000;
        "net.core.netdev_max_backlog" = 5000;
        "net.ipv4.neigh.default.gc_thresh1" = 4096;
        "net.ipv4.neigh.default.gc_thresh2" = 6144;
        "net.ipv4.neigh.default.gc_thresh3" = 8192;
      }
    else
      {
        "net.core.optmem_max" = 524288;
        "net.core.rmem_default" = 262144;
        "net.core.wmem_default" = 262144;
        "net.ipv4.udp_rmem_min" = 131072;
        "net.ipv4.udp_wmem_min" = 131072;
        "net.ipv4.udp_mem" = "32768 65536 131072";
        "net.core.netdev_budget" = 400;
        "net.core.netdev_budget_usecs" = 4000;
      };
  # Network interface metric for LAN prioritization
  # This script detects wired vs wireless interfaces and sets metrics accordingly
  # to prefer LAN over WiFi for streaming.
  sunshineNetworkInterfaceScript = pkgs.writeShellScriptBin "sunshine-network-pref" ''
    set -eu

    # Find all network interfaces and determine wired vs wireless
    wired_iface=""
    wireless_iface=""

    for iface in /sys/class/net/*; do
      iface_name=$(basename "$iface")
      
      # Skip loopback and virtual interfaces
      if [ "$iface_name" = "lo" ] || [ "$iface_name" = "docker"* ] || [ "$iface_name" = "br-"* ] || [ "$iface_name" = "veth"* ]; then
        continue
      fi

      # Check if interface is up
      if ! ip link show "$iface_name" 2>/dev/null | grep -q "state UP"; then
        continue
      fi

      # Check for wireless by checking for wireless kernel interfaces
      if [ -d "/sys/class/net/$iface_name/wireless" ]; then
        if [ -z "$wireless_iface" ]; then
          wireless_iface="$iface_name"
        fi
      else
        # Assume wired
        if [ -z "$wired_iface" ]; then
          wired_iface="$iface_name"
        fi
      fi
    done

    # Set metric: wired (100) should have lower metric than wireless (600)
    set_metric() {
      local iface="$1"
      local metric="$2"
      if [ -n "$iface" ] && [ -d "/sys/class/net/$iface" ]; then
        ip route replace default dev "$iface" metric "$metric" 2>/dev/null || true
      fi
    }

    # Prefer wired over wireless
    if [ -n "$wired_iface" ]; then
      set_metric "$wired_iface" 100
    fi
    if [ -n "$wireless_iface" ]; then
      set_metric "$wireless_iface" 600
    fi
  '';

  sunshineDynamicConfigFile = settingsFormat.generate "sunshine-j0nix-base.conf" (
    builtins.removeAttrs config.services.sunshine.settings [
      "output_name"
      "resolutions"
      "fps"
    ]
  );
  sunshineGraphicsLibraryDirs = lib.unique (
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
    EGL_PLATFORM = "drm";
    # Explicitly enable NVENC hardware encoding
    CUDA_VISIBLE_DEVICES = "0";
  };
  sunshineStreamingAppEnvironment = {
    PATH = "$(PATH):$(HOME)/.local/bin";
    # For Sunshine-launched apps, prefer immediate presentation over host-side
    # vblank/VRR synchronization so the encoder is not stalled behind another
    # sync layer before frames even reach the stream.
    __GL_SYNC_TO_VBLANK = "0";
    __GL_GSYNC_ALLOWED = "0";
    __GL_VRR_ALLOWED = "0";
    vblank_mode = "0";
  };
  sunshineExecutable =
    if sunshineNeedsPrivilegedWrapper then
      "${config.security.wrapperDir}/sunshine"
    else
      lib.getExe config.services.sunshine.package;
  sunshineDisplayPrepScript = pkgs.writeShellScriptBin "sunshine-display-prep" ''
    set -eu

    hyprctl_bin="${lib.getExe' pkgs.hyprland "hyprctl"}"
    jq_bin="${pkgs.jq}/bin/jq"
    coreutils_bin="${pkgs.coreutils}/bin"
    target_backend=${lib.escapeShellArg sunshineDisplayTargetBackend}
    target_name=${
      lib.escapeShellArg (
        if sunshineDisplayTargetOutputName != null then sunshineDisplayTargetOutputName else ""
      )
    }
    default_mode=${lib.escapeShellArg defaultTargetMode}
    staging_position=${lib.escapeShellArg defaultTargetPosition}
    stream_position=${
      lib.escapeShellArg (if sunshineDisplayTargetIsHeadless then "0x0" else defaultTargetPosition)
    }
    target_scale=${lib.escapeShellArg defaultTargetScale}
    allowed_resolutions=${lib.escapeShellArg allowedTargetResolutions}
    allowed_fps=${lib.escapeShellArg allowedTargetFps}
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$("$coreutils_bin"/id -u)}"
    state_dir="$runtime_dir/sunshine-j0nix"
    workspace_state="$state_dir/headless-workspaces.tsv"
    active_state="$state_dir/headless-active-workspace"
    focused_monitor_state="$state_dir/headless-focused-monitor"
    lockscreen_disable_marker="$state_dir/disable-lock-screen"

    if [ -z "$target_name" ] || [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ ! -x "$hyprctl_bin" ] || [ ! -x "$jq_bin" ]; then
      exit 0
    fi

    lua_string() {
      "$jq_bin" -Rn -r --arg value "$1" '$value | @json'
    }

    render_monitor_enabled() {
      local name="$1"
      local mode="$2"
      local position="$3"
      local scale="$4"
      printf 'hl.monitor({ output = %s, disabled = false, mode = %s, position = %s, scale = %s })\n' \
        "$(lua_string "$name")" \
        "$(lua_string "$mode")" \
        "$(lua_string "$position")" \
        "$(lua_string "$scale")"
    }

    render_monitor_disabled() {
      local name="$1"
      printf 'hl.monitor({ output = %s, disabled = true })\n' "$(lua_string "$name")"
    }

    apply_monitor_enabled() {
      "$hyprctl_bin" eval "$(render_monitor_enabled "$1" "$2" "$3" "$4")" >/dev/null 2>&1 || true
    }

    apply_monitor_disabled() {
      "$hyprctl_bin" eval "$(render_monitor_disabled "$1")" >/dev/null 2>&1 || true
    }

    width="''${SUNSHINE_CLIENT_WIDTH:-}"
    height="''${SUNSHINE_CLIENT_HEIGHT:-}"
    fps="''${SUNSHINE_CLIENT_FPS:-}"
    default_refresh="$default_mode"
    if [ "''${default_refresh#*@}" != "$default_refresh" ]; then
      default_refresh="''${default_refresh##*@}"
    else
      default_refresh=""
    fi

    mode="$default_mode"
    if [ -n "$width" ] && [ -n "$height" ]; then
      requested_resolution="''${width}x''${height}"
      resolution_allowed=0
      selected_fps=""

      if [ "$target_backend" = "physical-output" ] || [ "$target_backend" = "hyprland-headless" ]; then
        resolution_allowed=1
      fi

      for allowed_resolution in $allowed_resolutions; do
        if [ "$allowed_resolution" = "$requested_resolution" ]; then
          resolution_allowed=1
          break
        fi
      done

      if [ -n "$fps" ]; then
        for allowed_fps_value in $allowed_fps; do
          if [ "$allowed_fps_value" = "$fps" ]; then
            selected_fps="$fps"
            break
          fi
        done
      fi

      if [ "$resolution_allowed" -eq 1 ]; then
        effective_fps="$selected_fps"
        if [ -z "$effective_fps" ]; then
          effective_fps="$default_refresh"
        fi

        if [ -n "$effective_fps" ]; then
          mode="''${requested_resolution}@''${effective_fps}"
        else
          mode="$requested_resolution"
        fi
      fi
    fi

    if [ "$target_backend" = "hyprland-headless" ]; then
      if ! "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$target_name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
        "$hyprctl_bin" output create headless "$target_name" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
          if "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$target_name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
      fi
    fi

    apply_monitor_enabled "$target_name" "$mode" "$staging_position" "$target_scale"
    "$coreutils_bin"/mkdir -p "$state_dir"
    ${lib.optionalString sunshineDisableLockScreenDuringStream ''
      : > "$lockscreen_disable_marker"
      ${pkgs.procps}/bin/pkill -x hyprlock >/dev/null 2>&1 || true
    ''}
    "$hyprctl_bin" -j workspaces | "$jq_bin" -r '.[] | select((.name // "") != "" and (.monitor // "") != "") | [.name, .monitor] | @tsv' > "$workspace_state.tmp"
    "$coreutils_bin"/mv "$workspace_state.tmp" "$workspace_state"
    "$hyprctl_bin" -j activeworkspace | "$jq_bin" -r '.name // empty' > "$active_state"
    "$hyprctl_bin" -j monitors | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty' > "$focused_monitor_state"

    move_workspace_to_target() {
      local workspace_name="$1"
      [ -n "$workspace_name" ] || return 0
      "$hyprctl_bin" dispatch moveworkspacetomonitor "$workspace_name $target_name" >/dev/null 2>&1 || true
    }

    active_workspace=""
    if [ -f "$active_state" ]; then
      IFS= read -r active_workspace < "$active_state" || true
    fi

    if [ -f "$workspace_state" ]; then
      while IFS=$'\t' read -r workspace_name monitor_name; do
        [ -n "$workspace_name" ] || continue
        [ "$workspace_name" = "$active_workspace" ] && continue
        [ "$monitor_name" = "$target_name" ] && continue
        move_workspace_to_target "$workspace_name"
      done < "$workspace_state"
    fi

    if [ -n "$active_workspace" ]; then
      move_workspace_to_target "$active_workspace"
    fi

    ${lib.concatStringsSep "\n    " (
      map (
        name:
        "apply_monitor_disabled ${lib.escapeShellArg name}"
      ) sunshineDisplayTargetDisableOtherMonitorNames
    )}
    apply_monitor_enabled "$target_name" "$mode" "$stream_position" "$target_scale"
    "$hyprctl_bin" dispatch focusmonitor "$target_name" >/dev/null 2>&1 || true
    if command -v wm-shell-restart-detached >/dev/null 2>&1; then
      wm-shell-restart-detached >/dev/null 2>&1 || true
    fi
  '';
  sunshineDisplayUndoScript = pkgs.writeShellScriptBin "sunshine-display-undo" ''
    set -eu

    hyprctl_bin="${lib.getExe' pkgs.hyprland "hyprctl"}"
    coreutils_bin="${pkgs.coreutils}/bin"
    target_name=${
      lib.escapeShellArg (
        if sunshineDisplayTargetOutputName != null then sunshineDisplayTargetOutputName else ""
      )
    }
    target_default_spec=${lib.escapeShellArg sunshineDisplayTargetDefaultSpec}
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$("$coreutils_bin"/id -u)}"
    state_dir="$runtime_dir/sunshine-j0nix"
    workspace_state="$state_dir/headless-workspaces.tsv"
    active_state="$state_dir/headless-active-workspace"
    focused_monitor_state="$state_dir/headless-focused-monitor"
    lockscreen_disable_marker="$state_dir/disable-lock-screen"

    if [ -z "$target_name" ] || [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ ! -x "$hyprctl_bin" ]; then
      exit 0
    fi

    lua_string() {
      ${pkgs.jq}/bin/jq -Rn -r --arg value "$1" '$value | @json'
    }

    render_monitor_enabled() {
      local name="$1"
      local mode="$2"
      local position="$3"
      local scale="$4"
      printf 'hl.monitor({ output = %s, disabled = false, mode = %s, position = %s, scale = %s })\n' \
        "$(lua_string "$name")" \
        "$(lua_string "$mode")" \
        "$(lua_string "$position")" \
        "$(lua_string "$scale")"
    }

    render_monitor_disabled() {
      local name="$1"
      printf 'hl.monitor({ output = %s, disabled = true })\n' "$(lua_string "$name")"
    }

    apply_monitor_enabled() {
      "$hyprctl_bin" eval "$(render_monitor_enabled "$1" "$2" "$3" "$4")" >/dev/null 2>&1 || true
    }

    apply_monitor_disabled() {
      "$hyprctl_bin" eval "$(render_monitor_disabled "$1")" >/dev/null 2>&1 || true
    }

    apply_monitor_spec() {
      local spec="$1"
      local name mode position scale
      IFS=, read -r name mode position scale <<EOF
$spec
EOF
      if [ "$mode" = "disable" ]; then
        apply_monitor_disabled "$name"
      else
        apply_monitor_enabled "$name" "$mode" "$position" "$scale"
      fi
    }

    ${lib.concatStringsSep "\n    " (
      map (spec: "apply_monitor_spec ${lib.escapeShellArg spec}") (
        map initialOutputStateToMonitorSpec configuredPhysicalOutputStates
      )
    )}

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
      "$hyprctl_bin" dispatch moveworkspacetomonitor "$workspace_name $monitor_name" >/dev/null 2>&1 || true
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

    if [ -n "$target_default_spec" ]; then
      apply_monitor_spec "$target_default_spec"
    else
      apply_monitor_disabled "$target_name"
    fi
    if [ -n "$focused_monitor" ]; then
      "$hyprctl_bin" dispatch focusmonitor "$focused_monitor" >/dev/null 2>&1 || true
    fi
    if command -v wm-shell-restart-detached >/dev/null 2>&1; then
      wm-shell-restart-detached >/dev/null 2>&1 || true
    fi
    "$coreutils_bin"/rm -f "$workspace_state" "$active_state" "$focused_monitor_state" "$lockscreen_disable_marker"
  '';
  sunshineDisplayPrepCommand = lib.getExe sunshineDisplayPrepScript;
  sunshineDisplayUndoCommand = lib.getExe sunshineDisplayUndoScript;
  sunshineLaunchWrapper = pkgs.writeShellScript "sunshine-j0nix-launch" ''
    set -eu

    hyprctl_bin="${lib.getExe' pkgs.hyprland "hyprctl"}"
    jq_bin="${pkgs.jq}/bin/jq"
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    tmp_config="$runtime_dir/sunshine-j0nix.conf"
    base_config=${lib.escapeShellArg sunshineDynamicConfigFile}
    rm -f "$tmp_config"
    ${pkgs.coreutils}/bin/install -m 600 "$base_config" "$tmp_config"

    lua_string() {
      "$jq_bin" -Rn -r --arg value "$1" '$value | @json'
    }

    render_monitor_enabled() {
      local name="$1"
      local mode="$2"
      local position="$3"
      local scale="$4"
      printf 'hl.monitor({ output = %s, disabled = false, mode = %s, position = %s, scale = %s })\n' \
        "$(lua_string "$name")" \
        "$(lua_string "$mode")" \
        "$(lua_string "$position")" \
        "$(lua_string "$scale")"
    }

    apply_monitor_enabled() {
      "$hyprctl_bin" eval "$(render_monitor_enabled "$1" "$2" "$3" "$4")" >/dev/null 2>&1 || true
    }

    ${lib.optionalString
      (sunshineDisplayTargetEnabled && sunshineDisplayTargetIsPhysical && sunshineKmsOutputIndex != null)
      ''
        target_name=${
          lib.escapeShellArg (
            if sunshineDisplayTargetOutputName != null then sunshineDisplayTargetOutputName else ""
          )
        }
        target_mode=${lib.escapeShellArg defaultTargetMode}
        target_position=${lib.escapeShellArg defaultTargetPosition}
        target_scale=${lib.escapeShellArg defaultTargetScale}

        if [ -n "$target_name" ] && [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -x "$hyprctl_bin" ]; then
          apply_monitor_enabled "$target_name" "$target_mode" "$target_position" "$target_scale"
          for _ in $(seq 1 50); do
            if "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$target_name" '.[] | select(.name == $name and (.disabled // false) == false and (.width // 0) > 0 and (.height // 0) > 0)' >/dev/null 2>&1; then
              break
            fi
            sleep 0.1
          done
        fi
      ''
    }

    ${lib.optionalString (sunshineKmsOutputIndex != null) ''
      printf 'output_name = %s\n' ${lib.escapeShellArg (toString sunshineKmsOutputIndex)} >> "$tmp_config"
    ''}

    exec ${sunshineExecutable} "$tmp_config"
  '';
  sunshineBaseApps = [
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
    package = lib.mkIf sunshineUseNvidia (
      lib.mkDefault (pkgs.sunshine.override { cudaSupport = true; })
    );
    settings =
      lib.optionalAttrs sunshineUseNvidia {
        # Enable hardware NVENC encoding
        encoder = "nvenc";
      }
      // lib.optionalAttrs sunshineDisplayTargetEnabled (
        lib.optionalAttrs (sunshineDisplayTargetCapture != null) {
          capture = sunshineDisplayTargetCapture;
        }
      );
  };

  services.sunshine.applications.env = lib.mkMerge [
    sunshineStreamingAppEnvironment
  ];

  services.sunshine.applications.apps = lib.mkAfter (
    sunshineBaseApps
    ++ lib.optionals sunshineDisplayTargetEnabled [
      {
        name = sunshineDisplayTargetAppName;
        "auto-detach" = true;
        "image-path" = sunshineDisplayTargetAppIcon;
        "working-dir" = "/tmp";
        "prep-cmd" = [
          {
            do = sunshineDisplayPrepCommand;
            undo = sunshineDisplayUndoCommand;
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
  j0nix.desktop.sysctl.extraFragments = lib.mkAfter (
    lib.optional sunshineNetworkPerfEnable sunshineNetworkSysctlFragment
  );

  # Apply NVIDIA environment variables for hardware encoding
  systemd.user.services.sunshine.environment = lib.mkIf sunshineUseNvidia sunshineNvidiaEnvironment;

  # Run display cleanup before and after streaming
  systemd.user.services.sunshine.preStart = lib.mkIf sunshineDisplayTargetEnabled ''
    ${sunshineDisplayUndoCommand} >/dev/null 2>&1 || true
  '';
  systemd.user.services.sunshine.postStop = lib.mkIf sunshineDisplayTargetEnabled ''
    ${sunshineDisplayUndoCommand} >/dev/null 2>&1 || true
  '';

  # Run network interface prioritization before Sunshine starts to prefer LAN
  systemd.user.services.sunshine.serviceConfig = sunshineServicePriorityConfig // {
    ExecStartPre = [
      # Set network interface priority for LAN preference before Sunshine starts
      "${lib.getExe sunshineNetworkInterfaceScript}"
    ];
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
      assertion = builtins.elem sunshinePerfMode [
        "balanced"
        "aggressive"
      ];
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
      assertion = builtins.elem sunshineNetworkPerfMode [
        "balanced"
        "aggressive"
      ];
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.network.mode must be one of: balanced, aggressive";
    }
    {
      assertion =
        !sunshineDisplayTargetEnabled
        || sunshineDisplayTargetCaptureAuto
        || builtins.elem sunshineDisplayTargetCapture [
          "wlr"
          "wl"
          "wayland"
          "kms"
          "x11"
          "nvfbc"
        ];
      message = "settings.sunshine.displayTarget.capture must be auto, empty, or one of: wlr, wl, wayland, kms, x11, nvfbc";
    }
    {
      assertion =
        !sunshineDisplayTargetEnabled
        || builtins.all (
          mode: builtins.match "^[0-9]+x[0-9]+$" (monitorLib.renderResolution mode) != null
        ) sunshineDisplayTargetResolutions;
      message = "settings.sunshine.displayTarget.resolutions must contain WIDTHxHEIGHT strings or attrsets";
    }
    {
      assertion = !sunshineDisplayTargetEnabled || builtins.all (fps: fps > 0) sunshineDisplayTargetFps;
      message = "settings.sunshine.displayTarget.fps must contain positive integers";
    }
    {
      assertion =
        !sunshineDisplayTargetEnabled
        || builtins.elem sunshineDisplayTargetBackend [
          "hyprland-headless"
          "physical-output"
        ];
      message = "settings.sunshine.displayTarget.backend must be one of: hyprland-headless, physical-output";
    }
    {
      assertion = !sunshineDisplayTargetEnabled || sunshineDisplayTargetOutputName != null;
      message = "settings.sunshine.displayTarget.outputName must be set when the Sunshine display target is enabled.";
    }
    {
      assertion = !sunshineDisplayTargetEnabled || sunshineDisplayTargetAppName != "";
      message = "settings.sunshine.displayTarget.appName must not be empty when the Sunshine display target is enabled.";
    }
    {
      assertion = !sunshineDisplayTargetEnabled || sunshineDisplayTargetConfig != null;
      message = "settings.sunshine.displayTarget.outputName must reference either a configured settings.hyprland.headlessOutputs entry or a settings.hyprland.initialOutputStates entry, depending on the selected backend.";
    }
    {
      assertion =
        !sunshineDisplayTargetEnabled
        || !sunshineDisplayTargetIsHeadless
        || builtins.elem sunshineDisplayTargetOutputName configuredHeadlessOutputNames;
      message = "settings.sunshine.displayTarget.outputName must reference a configured settings.hyprland.headlessOutputs entry when backend = hyprland-headless.";
    }
    {
      assertion =
        !sunshineDisplayTargetEnabled
        || !sunshineDisplayTargetIsHeadless
        || (
          sunshineDisplayTargetInitialState != null
          && ((sunshineDisplayTargetInitialState.enabledByDefault or true) == false)
        );
      message = "settings.sunshine.displayTarget.outputName must be disabled by default in settings.hyprland.initialOutputStates when backend = hyprland-headless.";
    }
    {
      assertion =
        !sunshineDisplayTargetEnabled
        || !sunshineDisplayTargetIsPhysical
        || !builtins.elem sunshineDisplayTargetOutputName configuredHeadlessOutputNames;
      message = "settings.sunshine.displayTarget.outputName must not reference a headless output when backend = physical-output.";
    }
    {
      assertion =
        !sunshineDisplayTargetEnabled
        || !sunshineDisplayTargetIsPhysical
        || (
          sunshineDisplayTargetInitialState != null
          && ((sunshineDisplayTargetInitialState.enabledByDefault or true) == false)
        );
      message = "settings.sunshine.displayTarget.outputName must be disabled by default in settings.hyprland.initialOutputStates when backend = physical-output.";
    }
  ];
}
