{ config, lib, pkgs, settings, inputs, ... }:
let
  profileDetails = settings.profileDetails or { hyprlandMonitors = [ ]; };
  selectedShell = settings.wmShell or (settings.hyprlandShell or "dank-material-shell");
  isCaelestiaShell = selectedShell == "caelestia-shell";
  isDmsShell = selectedShell == "dank-material-shell";
  dmsSettings = settings.dms or { };
  dmsWorkspaceSettings = dmsSettings.workspaces or { };
  hyprDmsDir = "${config.home.homeDirectory}/.config/hypr/dms";
  useUWSM = (settings.hyprland or { }).useUWSM or true;
  appExecBackend = (settings.hyprland or { }).appExecBackend or "auto";
  launcherPolicy = import ../../../system/lib/app-exec-policy.nix { inherit lib pkgs useUWSM appExecBackend; };
  app2unitExec = launcherPolicy.app2unitExe;
  uwsmExec = launcherPolicy.uwsmExe;
  hyprctlExec = lib.getExe' pkgs.hyprland "hyprctl";
  homeBinDir = "${config.home.profileDirectory}/bin";
  appExec = launcherPolicy.mkExec;
  launcherAppExec = appExec;
  preferredTerminal = settings.preferredTerminal or "kitty";
  preferredTerminalCmd =
    if builtins.elem preferredTerminal [ "gnome-console" "gnome console" ] then "kgx" else preferredTerminal;
  workspaceCountRaw = dmsWorkspaceSettings.count or 10;
  workspaceCount = lib.min 10 (lib.max 1 workspaceCountRaw);
  workspaceKeyPairs = builtins.genList
    (i:
      let
        ws = i + 1;
      in
      {
        workspace = toString ws;
        key = if ws == 10 then "0" else toString ws;
      })
    workspaceCount;
  workspaceSwitchBinds = map (pair: "$mainMod, ${pair.key}, workspace, ${pair.workspace}") workspaceKeyPairs;
  workspaceMoveBinds = map (pair: "$mainMod SHIFT, ${pair.key}, movetoworkspace, ${pair.workspace}") workspaceKeyPairs;
  hyprlandCfg = settings.hyprland or { };
  sunshineDisplayTargetBackend = (((settings.sunshine or { }).displayTarget or { }).backend or "hyprland-headless");
  sunshineUsesPhysicalOutput = sunshineDisplayTargetBackend == "physical-output";
  sunshineUsesHeadlessOutput = sunshineDisplayTargetBackend == "hyprland-headless";
  profileHeadlessOutput = profileDetails.hyprlandSunshineHeadlessOutput or null;
  profilePhysicalOutput = profileDetails.hyprlandSunshinePhysicalOutput or null;
  profileOutputBindingsBase = profileDetails.hyprlandOutputBindingsBase or [ ];
  profileInitialOutputStatesBase = profileDetails.hyprlandInitialOutputStatesBase or [ ];
  profileToggleableOutputsBase = profileDetails.hyprlandToggleableOutputsBase or [ ];
  monitorToolsCfg = hyprlandCfg.monitorTools or { };
  installNwgDisplays = monitorToolsCfg.installNwgDisplays or false;
  nwgDisplaysPackage =
    if installNwgDisplays && builtins.hasAttr "nwg-displays" pkgs then
      pkgs."nwg-displays"
    else
      null;
  sessionEnvCfg = hyprlandCfg.sessionEnv or { };
  hyprlandDebug = hyprlandCfg.debug or { };
  sessionEnvBase = {
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    GDK_BACKEND = "wayland,x11";
    QT_QPA_PLATFORM = "wayland;xcb";
    SDL_VIDEODRIVER = "wayland,x11,windows";
    CLUTTER_BACKEND = "wayland";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_DESKTOP = "Hyprland";
    COLORSCHEME_PREFERENCE = settings.colorSchemePreference or "dark";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    APP2UNIT_SLICES = sessionEnvCfg.app2unitSlices or "a=app-graphical.slice b=background-graphical.slice s=session-graphical.slice";
  };
  sessionEnv =
    sessionEnvBase
    // lib.optionalAttrs ((sessionEnvCfg.qtPlatformTheme or null) != null) {
      QT_QPA_PLATFORMTHEME = sessionEnvCfg.qtPlatformTheme;
    }
    // (sessionEnvCfg.extra or { });
  sessionEnvLines = lib.mapAttrsToList (name: value: "env = ${name},${toString value}") sessionEnv;
  importedSessionEnvNames = builtins.attrNames sessionEnv;
  importSessionEnvArgs = lib.concatStringsSep " \\\n        " (map lib.escapeShellArg importedSessionEnvNames);
  uwsmEnvText = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (toString value)}") sessionEnv) + "\n";
  headlessOutputs =
    if hyprlandCfg ? headlessOutputs then
      hyprlandCfg.headlessOutputs
    else if sunshineUsesHeadlessOutput && profileHeadlessOutput != null then
      [ profileHeadlessOutput ]
    else
      [ ];
  headlessOutputIsEnabledByDefault =
    name:
      let
        matchingState = lib.findFirst (state: (state.name or "") == name) null (hyprlandCfg.initialOutputStates or [ ]);
      in
        if matchingState != null then
          matchingState.enabledByDefault or true
        else
          true;
  headlessOutputsWithBindings = map
    (output:
      if output ? bindIndex then
        output // { bindKey = if output.bindIndex == 10 then "0" else toString output.bindIndex; }
      else
        output)
    headlessOutputs;
  headlessOutputNames = map (output: output.name or "") headlessOutputs;
  headlessOutputsAutoEnsure = builtins.any (output: headlessOutputIsEnabledByDefault (output.name or "")) headlessOutputs;
  headlessOutputsJson = pkgs.writeText "hyprland-headless-outputs.json" (builtins.toJSON headlessOutputs);
  outputBindings =
    if hyprlandCfg ? outputBindings then
      hyprlandCfg.outputBindings
    else
      profileOutputBindingsBase
      ++ lib.optionals (sunshineUsesPhysicalOutput && profilePhysicalOutput != null) [
        {
          name = profilePhysicalOutput.name;
          description = profilePhysicalOutput.description or "";
          bindIndex = profilePhysicalOutput.bindIndex;
        }
      ]
      ++ lib.optionals (sunshineUsesHeadlessOutput && profileHeadlessOutput != null) [
        {
          name = profileHeadlessOutput.name;
          description = profileHeadlessOutput.description or "";
          bindIndex = profileHeadlessOutput.bindIndex;
        }
      ];
  outputBindingsWithKeys = map
    (binding:
      binding // { bindKey = if binding.bindIndex == 10 then "0" else toString binding.bindIndex; })
    outputBindings;
  outputBindingNames = map (binding: binding.name or "") outputBindingsWithKeys;
  outputBindingIndices = map (binding: binding.bindIndex) outputBindingsWithKeys;
  outputBindingsJson = pkgs.writeText "hyprland-output-bindings.json" (builtins.toJSON outputBindingsWithKeys);
  initialOutputStates =
    let configured =
      if hyprlandCfg ? initialOutputStates then
        hyprlandCfg.initialOutputStates
      else
        profileInitialOutputStatesBase
        ++ lib.optionals (sunshineUsesHeadlessOutput && profileHeadlessOutput != null) [
          {
            name = profileHeadlessOutput.name;
            enabledByDefault = false;
            mode = profileHeadlessOutput.mode or "2880x1800@60";
            position = profileHeadlessOutput.position or "10000x10000";
            scale = profileHeadlessOutput.scale or 1;
          }
        ];
    in
      if configured != [ ] then
        configured
      else
        map
          (output: {
            name = output.name or "";
            enabledByDefault = output.enabledByDefault or true;
            mode = output.mode or "preferred";
            position = output.position or "auto";
            scale = output.scale or 1;
          })
          toggleableOutputs;
  initialOutputStateNames = map (output: output.name or "") initialOutputStates;
  toggleableOutputs =
    if hyprlandCfg ? toggleableOutputs then
      hyprlandCfg.toggleableOutputs
    else
      profileToggleableOutputsBase
      ++ lib.optionals (sunshineUsesPhysicalOutput && profilePhysicalOutput != null) [ profilePhysicalOutput ];
  toggleableOutputsWithBindings =
    builtins.genList
      (idx:
        let
          output = builtins.elemAt toggleableOutputs idx;
          bindIndex = output.bindIndex or (idx + 1);
        in
        output
        // {
          inherit bindIndex;
          bindKey = if bindIndex == 10 then "0" else toString bindIndex;
        })
      (builtins.length toggleableOutputs);
  toggleableOutputNames = map (output: output.name or "") toggleableOutputsWithBindings;
  managedOutputsWithBindings = toggleableOutputsWithBindings ++ (builtins.filter (output: output ? bindIndex) headlessOutputsWithBindings);
  managedOutputBindIndices = map (output: output.bindIndex) managedOutputsWithBindings;
  toggleableOutputsJson = pkgs.writeText "hyprland-toggleable-outputs.json" (builtins.toJSON managedOutputsWithBindings);
  keybindDiagnosticsCfg = hyprlandDebug.keybindDiagnostics or { };
  keybindDiagnosticsEnable = keybindDiagnosticsCfg.enable or false;
  keybindDiagnosticsDelaySeconds = keybindDiagnosticsCfg.delaySeconds or 8;
  keybindDiagnosticsLogDir = keybindDiagnosticsCfg.logDir or "\${XDG_STATE_HOME:-$HOME/.local/state}/hyprland/diagnostics";
  keybindDiagnosticsProbeScript = pkgs.writeShellScriptBin "wm-hypr-keybind-probe" ''
    set -eu
    label="''${1:-unknown}"
    log_dir="${keybindDiagnosticsLogDir}"
    mkdir -p "$log_dir"
    log_file="$log_dir/keybind-probe.log"
    printf '%s label=%s uid=%s wayland=%s hypr=%s\n' \
      "$(${pkgs.coreutils}/bin/date --iso-8601=seconds)" \
      "$label" \
      "$(${pkgs.coreutils}/bin/id -u)" \
      "''${WAYLAND_DISPLAY:-}" \
      "''${HYPRLAND_INSTANCE_SIGNATURE:-}" >>"$log_file"
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "Hyprland keybind probe" "$label" >/dev/null 2>&1 || true
    fi
  '';
  keybindDiagnosticsScript = pkgs.writeShellScriptBin "wm-hypr-keybind-dump" ''
    set -eu

    phase="''${1:-manual}"
    case "$phase" in
      --phase=*) phase="''${phase#--phase=}" ;;
    esac

    log_dir="${keybindDiagnosticsLogDir}"
    mkdir -p "$log_dir"

    ts="$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
    out_file="$log_dir/keybinds-$ts-$phase.log"

    run_hyprctl() {
      label="$1"
      shift
      echo
      echo "## $label"
      if command -v hyprctl >/dev/null 2>&1; then
        hyprctl "$@" 2>&1 || true
      else
        echo "hyprctl not found in PATH"
      fi
    }

    run_cmd() {
      label="$1"
      shift
      echo
      echo "## $label"
      "$@" 2>&1 || true
    }

    {
      echo "# Hyprland keybind diagnostics"
      echo "timestamp=$(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
      echo "phase=$phase"
      echo "pid=$$"
      echo "user=''${USER:-unknown}"
      echo "uid=$(${pkgs.coreutils}/bin/id -u)"
      echo "session_type=''${XDG_SESSION_TYPE:-}"
      echo "session_class=''${XDG_SESSION_CLASS:-}"
      echo "desktop=''${XDG_CURRENT_DESKTOP:-}"
      echo "wayland_display=''${WAYLAND_DISPLAY:-}"
      echo "hypr_instance=''${HYPRLAND_INSTANCE_SIGNATURE:-}"
      echo "xdg_runtime_dir=''${XDG_RUNTIME_DIR:-}"
      echo "path=$PATH"

      run_hyprctl "version" version
      run_hyprctl "instances" instances
      run_hyprctl "activeworkspace" activeworkspace
      run_hyprctl "configerrors" configerrors
      run_hyprctl "globalshortcuts" globalshortcuts
      run_hyprctl "binds" binds
      run_hyprctl "devices" devices
      run_hyprctl "layers" layers
      run_cmd "app2unit probe" ${app2unitExec} -- true
      run_cmd "uwsm app probe" ${uwsmExec} app -- true
    } >"$out_file"

    echo "$out_file"
  '';
  minimizerCfg = hyprlandCfg.minimizer or { };
  minimizerEnabled = minimizerCfg.enable or false;
  minimizerVariant = minimizerCfg.variant or "denis";
  minimizerIsDenis = minimizerVariant == "denis";
  minimizerIsOrteip = minimizerVariant == "0rteip";
  minimizerPackage =
    if minimizerIsOrteip then
      if pkgs ? "hyprland-minimizer-orteip" then pkgs."hyprland-minimizer-orteip" else null
    else if pkgs ? "hyprland-minimizer" then
      pkgs."hyprland-minimizer"
    else
      null;
  minimizerDefaultCommand =
    if minimizerPackage != null then
      lib.getExe minimizerPackage
    else if minimizerIsOrteip then
      "hyprland-minimizer"
    else
      "hyprland-minimizer";
  minimizerCommand = minimizerCfg.command or minimizerDefaultCommand;
  minimizerOrteipCfg = minimizerCfg.orteip or { };
  minimizerOrteipAppId = minimizerOrteipCfg.appId or "keepassxc";
  minimizerBinds = minimizerCfg.binds or { };
  minimizerToggleBind = minimizerBinds.toggle or "$mainMod CTRL, m";
  minimizerRestoreBind = minimizerBinds.restore or "$mainMod CTRL SHIFT, m";
  minimizerMenuBind = minimizerBinds.menu or "$mainMod CTRL, c";
  minimizerToggleCommand =
    if minimizerIsOrteip then "${minimizerCommand} ${minimizerOrteipAppId}" else minimizerCommand;
  minimizerRestoreCommand =
    if minimizerIsDenis then "${minimizerCommand} --restore-last" else minimizerToggleCommand;
  minimizerMenuCommand =
    if minimizerIsDenis then "${minimizerCommand} --menu" else minimizerToggleCommand;
  hasHyprKcsPackage =
    (inputs ? hyprkcs)
    && (inputs.hyprkcs ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.hyprkcs.packages)
    && (inputs.hyprkcs.packages.${pkgs.stdenv.hostPlatform.system} ? default);
  hyprKcsPackage =
    if hasHyprKcsPackage then
      inputs.hyprkcs.packages.${pkgs.stdenv.hostPlatform.system}.default
    else
      null;
  keybindHelpCommand =
    if hasHyprKcsPackage then
      appExec (lib.getExe' hyprKcsPackage "hyprkcs")
    else
      "false";
  keepassCfg = ((settings.programs or { }).keepassxc or { });
  keepassEnabled = keepassCfg.enable or false;
  keepassWorkspaceCfg = keepassCfg.workspace or { };
  keepassWorkspaceEnable = keepassWorkspaceCfg.enable or true;
  keepassToggleBind = keepassWorkspaceCfg.toggleBind or "$mainMod SHIFT, p";
  toggleableOutputBindLines =
    lib.concatMap
      (output:
        let
          binds = output.binds or { };
          bindKey = output.bindKey or "";
          outputNameArg = lib.escapeShellArg output.name;
          hasBind = bind: bind != null && bind != "";
          mkBind = bind: command:
            lib.optional (hasBind bind) "${bind}, exec, ${command}";
        in
        [
          "$mainMod CTRL, ${bindKey}, exec, ${homeBinDir}/wm-monitor-toggle ${outputNameArg}"
          "$mainMod CTRL SHIFT, ${bindKey}, exec, ${homeBinDir}/wm-monitor-restore ${outputNameArg}"
        ]
        ++ (mkBind (binds.toggle or null) "${homeBinDir}/wm-monitor-toggle ${outputNameArg}")
        ++ (mkBind (binds.on or null) "${homeBinDir}/wm-monitor-on ${outputNameArg}")
        ++ (mkBind (binds.off or null) "${homeBinDir}/wm-monitor-off ${outputNameArg}")
        ++ (mkBind (binds.restore or null) "${homeBinDir}/wm-monitor-restore ${outputNameArg}"))
      managedOutputsWithBindings;
  workspaceOutputBindLines =
    lib.concatMap
      (output:
        let
          bindKey = output.bindKey or "";
          outputNameArg = lib.escapeShellArg output.name;
        in
        [
          "$mainMod ALT, ${bindKey}, exec, ${homeBinDir}/wm-monitor-workspace-to ${outputNameArg}"
          "$mainMod CTRL ALT, ${bindKey}, exec, ${homeBinDir}/wm-monitor-focused-workspaces-to ${outputNameArg}"
        ])
      outputBindingsWithKeys;
  preferredFileManager = settings.preferredFileManager or "nautilus";
  layoutToggleBind = hyprlandCfg.layoutToggleBind or "$mainMod SHIFT, SPACE";
  overviewToggleBind = hyprlandCfg.overviewToggleBind or "$mainMod, TAB";
  dmsOverviewSettings = dmsSettings.overview or { };
  dmsOverviewEnabled = dmsOverviewSettings.enable or false;
  dmsOverviewAutostart = dmsOverviewSettings.autostart or false;
  userHyprShellOverridesDir = "${config.home.homeDirectory}/.config/hypr/shell-overrides/${selectedShell}";
  userHyprConfigPath = "${userHyprShellOverridesDir}/user-overrides.conf";
  mainHyprConfigDir = "${config.home.homeDirectory}/.config/hypr/conf.d";
  hyprlandRuntimeMonitorConfigPath = "${mainHyprConfigDir}/11-runtime-monitors.conf";
  shellGeneratedConfigDir = "${config.home.homeDirectory}/.config/hypr/shells/${selectedShell}/generated";
  initialOutputStatesJson = pkgs.writeText "hyprland-initial-output-states.json" (builtins.toJSON initialOutputStates);
  hyprlandWindowRules = import ./config/window-rules.nix;
  hyprlandKeybinds = import ./config/keybinds.nix {
    inherit
      lib
      settings
      isCaelestiaShell
      hyprctlExec
      appExec
      launcherAppExec
      preferredTerminalCmd
      preferredFileManager
      layoutToggleBind
      dmsOverviewEnabled
      overviewToggleBind
      keybindDiagnosticsEnable
      keepassEnabled
      keepassWorkspaceEnable
      keepassToggleBind
      minimizerEnabled
      minimizerToggleBind
      minimizerRestoreBind
      minimizerMenuBind
      minimizerToggleCommand
      minimizerRestoreCommand
      minimizerMenuCommand
      keybindHelpCommand
      workspaceSwitchBinds
      workspaceMoveBinds;
      toggleableOutputBindLines = toggleableOutputBindLines ++ workspaceOutputBindLines;
  };
  installRawQuickshell = hyprlandDebug.installRawQuickshell or false;
  shellStartupCommand =
    if selectedShell == "none" then
      null
    else
      appExec "${homeBinDir}/wm-shell-start";
  importSessionEnvScript = pkgs.writeShellScriptBin "wm-import-session-env" ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    if [ -S "$runtime_dir/bus" ]; then
      ${pkgs.systemd}/bin/systemctl --user import-environment \
        DISPLAY \
        WAYLAND_DISPLAY \
        XDG_RUNTIME_DIR \
        HYPRLAND_INSTANCE_SIGNATURE \
        ${importSessionEnvArgs} >/dev/null 2>&1 || true
      ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
        DISPLAY \
        WAYLAND_DISPLAY \
        XDG_RUNTIME_DIR \
        HYPRLAND_INSTANCE_SIGNATURE \
      ${importSessionEnvArgs} >/dev/null 2>&1 || true
    fi
  '';
  runtimeMonitorResetScript = pkgs.writeShellScriptBin "wm-monitor-reset-runtime" ''
    set -eu
    exec ${lib.getExe monitorStateScript} sync-defaults
  '';
  headlessOutputsEnsureScript = pkgs.writeShellScriptBin "wm-headless-output-ensure" ''
    set -eu

    hyprctl_bin="${hyprctlExec}"
    jq_bin="${pkgs.jq}/bin/jq"
    outputs_json=${lib.escapeShellArg headlessOutputsJson}

    [ -x "$hyprctl_bin" ] || exit 0

    ensure_output() {
      name="$1"
      mode="$2"
      position="$3"
      scale="$4"

      if ! "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
        "$hyprctl_bin" output create headless "$name" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
          if "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
      fi

      "$hyprctl_bin" keyword monitor "$name,$mode,$position,$scale" >/dev/null 2>&1 || true
    }

    "$jq_bin" -c '.[]' "$outputs_json" | while IFS= read -r output; do
      name="$(printf '%s' "$output" | "$jq_bin" -r '.name')"
      mode="$(printf '%s' "$output" | "$jq_bin" -r '.mode // "preferred"')"
      position="$(printf '%s' "$output" | "$jq_bin" -r '.position // "10000x10000"')"
      scale="$(printf '%s' "$output" | "$jq_bin" -r '(.scale // 1) | tostring')"
      [ -n "$name" ] || continue
      ensure_output "$name" "$mode" "$position" "$scale"
    done
  '';
  headlessOutputsRemoveScript = pkgs.writeShellScriptBin "wm-headless-output-remove" ''
    set -eu

    hyprctl_bin="${hyprctlExec}"
    jq_bin="${pkgs.jq}/bin/jq"
    outputs_json=${lib.escapeShellArg headlessOutputsJson}

    [ -x "$hyprctl_bin" ] || exit 0

    "$jq_bin" -r '.[].name // empty' "$outputs_json" | while IFS= read -r name; do
      [ -n "$name" ] || continue
      "$hyprctl_bin" output remove "$name" >/dev/null 2>&1 || true
    done
  '';
  monitorStateScript = pkgs.writeShellScriptBin "wm-monitor" ''
    set -eu

    hyprctl_bin="${hyprctlExec}"
    jq_bin="${pkgs.jq}/bin/jq"
    flock_bin="${pkgs.util-linux}/bin/flock"
    outputs_json=${lib.escapeShellArg toggleableOutputsJson}
    initial_states_json=${lib.escapeShellArg initialOutputStatesJson}
    bindings_json=${lib.escapeShellArg outputBindingsJson}
    headless_outputs_json=${lib.escapeShellArg headlessOutputsJson}
    runtime_config_path=${lib.escapeShellArg hyprlandRuntimeMonitorConfigPath}
    runtime_dir="''${XDG_RUNTIME_DIR:-}"
    if [ -n "$runtime_dir" ] && [ -d "$runtime_dir" ] && [ -w "$runtime_dir" ]; then
      state_dir="$runtime_dir/hyprland-monitor-state"
    else
      state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
      state_dir="$state_home/hyprland-monitor-state"
    fi
    command="''${1:-}"
    output_name="''${2:-}"

    [ -x "$hyprctl_bin" ] || exit 0
    [ -x "$jq_bin" ] || exit 0
    mkdir -p "$state_dir"
    lock_file="$state_dir/runtime-monitors.lock"

    usage() {
      echo "usage: wm-monitor <on|off|toggle|restore|status|workspace-to|focused-workspaces-to|list|discover|enable-discovered|suggest|prompt-new|sync-live|sync-defaults|watch> [output-name]" >&2
      exit 2
    }

    acquire_runtime_lock() {
      exec 8>"$lock_file"
      "$flock_bin" -x 8
    }

    release_runtime_lock() {
      "$flock_bin" -u 8 >/dev/null 2>&1 || true
      exec 8>&-
    }

    with_runtime_lock() {
      local rc
      acquire_runtime_lock
      set +e
      "$@"
      rc=$?
      set -e
      release_runtime_lock
      return "$rc"
    }

    sanitize_name() {
      printf '%s' "$1" | tr -c '[:alnum:]._-' '_'
    }

    state_prefix() {
      printf '%s/%s' "$state_dir" "$(sanitize_name "$1")"
    }

    load_output_config() {
      local name="$1"
      "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name)' "$outputs_json"
    }

    load_output_binding() {
      local name="$1"
      "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name)' "$bindings_json"
    }

    output_is_headless() {
      local name="$1"
      "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' "$headless_outputs_json" >/dev/null 2>&1
    }

    output_is_known() {
      local name="$1"
      "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' "$bindings_json" >/dev/null 2>&1
    }

    require_output_name() {
      [ -n "$output_name" ] || usage
    }

    get_output_field() {
      local output_json="$1"
      local query="$2"
      printf '%s' "$output_json" | "$jq_bin" -r "$query"
    }

    write_runtime_header() {
      echo "# ------------------------------------------------------------------"
      echo "# Runtime Monitor Overrides"
      echo "# ------------------------------------------------------------------"
      echo "# Managed by wm-monitor. This file intentionally persists the current"
      echo "# toggleable output state across Hyprland reloads."
    }

    output_is_active() {
      local name="$1"
      "$hyprctl_bin" -j monitors | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name and (.disabled // false) == false)' >/dev/null 2>&1
    }

    list_unknown_active_monitors() {
      "$hyprctl_bin" -j monitors all \
        | "$jq_bin" -c --argfile bindings "$bindings_json" '
            .[]
            | select((.disabled // false) == false and (.name // "") != "")
            | select(([$bindings[]?.name] | index(.name)) == null)
          '
    }

    get_live_monitor_json() {
      local name="$1"
      "$hyprctl_bin" -j monitors all | "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name and (.disabled // false) == false)'
    }

    monitor_spec_from_declared_output() {
      local output_json="$1"
      local name mode position scale

      name="$(printf '%s' "$output_json" | "$jq_bin" -r '.name // empty')"
      mode="$(printf '%s' "$output_json" | "$jq_bin" -r '.mode // "preferred"')"
      position="$(printf '%s' "$output_json" | "$jq_bin" -r '.position // "auto"')"
      scale="$(printf '%s' "$output_json" | "$jq_bin" -r '(.scale // 1) | tostring')"
      [ -n "$name" ] || return 1
      printf '%s,%s,%s,%s\n' "$name" "$mode" "$position" "$scale"
    }

    monitor_spec_from_live_or_declared_output() {
      local output_json="$1"
      local name monitor_json mode position scale

      name="$(printf '%s' "$output_json" | "$jq_bin" -r '.name // empty')"
      [ -n "$name" ] || return 1
      monitor_json="$(get_live_monitor_json "$name" 2>/dev/null || true)"

      if [ -n "$monitor_json" ]; then
        mode="$(printf '%s' "$monitor_json" | "$jq_bin" -r '"\(.width)x\(.height)@\((.refreshRate // 60) | tostring)"')"
        position="$(printf '%s' "$monitor_json" | "$jq_bin" -r '"\((.x // 0) | floor)x\((.y // 0) | floor)"')"
        scale="$(printf '%s' "$monitor_json" | "$jq_bin" -r '(.scale // 1) | tostring')"
        printf '%s,%s,%s,%s\n' "$name" "$mode" "$position" "$scale"
      else
        monitor_spec_from_declared_output "$output_json"
      fi
    }

    save_output_runtime_spec() {
      local output_json="$1"
      local prefix="$2"
      local current_spec _name output_mode output_position output_scale

      current_spec="$(monitor_spec_from_live_or_declared_output "$output_json")" || return 0
      IFS=, read -r _name output_mode output_position output_scale <<EOF
$current_spec
EOF
      printf '%s\n' "$output_mode" >"$prefix.mode"
      printf '%s\n' "$output_position" >"$prefix.position"
      printf '%s\n' "$output_scale" >"$prefix.scale"
    }

    read_saved_or_declared_output_field() {
      local prefix="$1"
      local file_suffix="$2"
      local output_json="$3"
      local query="$4"
      local file_path="$prefix.$file_suffix"

      if [ -f "$file_path" ]; then
        cat "$file_path" 2>/dev/null || true
      else
        get_output_field "$output_json" "$query"
      fi
    }

    sync_default_monitor_overrides_locked() {
      local tmp_file output name enabled monitor_line

      mkdir -p "$(dirname "$runtime_config_path")"
      tmp_file="$(mktemp "$(dirname "$runtime_config_path")/.11-runtime-monitors.conf.XXXXXX")"
      {
        write_runtime_header
        "$jq_bin" -c '.[]' "$initial_states_json" | while IFS= read -r output; do
          name="$(printf '%s' "$output" | "$jq_bin" -r '.name // empty')"
          [ -n "$name" ] || continue
          enabled="$(printf '%s' "$output" | "$jq_bin" -r 'if (.enabledByDefault // true) then "1" else "0" end')"

          if [ "$enabled" = "1" ]; then
            monitor_line="$(monitor_spec_from_declared_output "$output")"
          else
            monitor_line="$name,disable"
          fi

          printf 'monitor = %s\n' "$monitor_line"
        done
      } >"$tmp_file"
      mv -f "$tmp_file" "$runtime_config_path"

      if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        "$jq_bin" -c '.[]' "$initial_states_json" | while IFS= read -r output; do
          name="$(printf '%s' "$output" | "$jq_bin" -r '.name // empty')"
          enabled="$(printf '%s' "$output" | "$jq_bin" -r 'if (.enabledByDefault // true) then "1" else "0" end')"
          monitor_line="$(monitor_spec_from_declared_output "$output")"
          [ -n "$name" ] || continue

          if [ "$enabled" = "1" ] && output_is_headless "$name"; then
            ensure_headless_output "$name"
          fi

          if [ "$enabled" = "1" ]; then
            "$hyprctl_bin" keyword monitor "$monitor_line" >/dev/null 2>&1 || true
          else
            "$hyprctl_bin" keyword monitor "$name,disable" >/dev/null 2>&1 || true
          fi
        done
      fi
    }

    sync_default_monitor_overrides() {
      with_runtime_lock sync_default_monitor_overrides_locked
    }

    describe_monitor_json() {
      local monitor_json="$1"
      printf '%s' "$monitor_json" \
        | "$jq_bin" -r '
            if (.description // "") != "" then
              .description
            else
              ([.make // "", .model // ""] | map(select(. != "")) | join(" "))
            end
          '
    }

    parse_mode_dimensions() {
      local mode="$1"
      printf '%s\n' "$mode" | sed -n 's/^\([0-9]\+\)x\([0-9]\+\)@.*$/\1 \2/p'
    }

    compute_unknown_monitor_position() {
      local width="$1"
      local height="$2"
      local left_x bottom_y pos_x pos_y

      read -r left_x bottom_y <<EOF
$("$hyprctl_bin" -j monitors | "$jq_bin" -r '
  [ .[] | select((.disabled // false) == false) | {
      x: (.x // 0),
      y: (.y // 0),
      width: (.width // 0),
      height: (.height // 0),
      scale: (.scale // 1)
    } ] as $monitors
  | if ($monitors | length) == 0 then
      "-1 0"
    else
      [
        ($monitors | map(.x) | min),
        ($monitors | map(.y + ((.height / .scale) | floor)) | max)
      ]
      | @tsv
    end
')
EOF

      [ -n "''${left_x:-}" ] || left_x=0
      [ -n "''${bottom_y:-}" ] || bottom_y=0
      pos_x=$((left_x - width))
      pos_y=$((bottom_y - height))
      printf '%sx%s\n' "$pos_x" "$pos_y"
    }

    get_unknown_monitor_json() {
      local name="$1"
      "$hyprctl_bin" -j monitors all | "$jq_bin" -ce --arg name "$name" '.[] | select(.name == $name)'
    }

    unknown_monitor_mode() {
      local monitor_json="$1"
      printf '%s' "$monitor_json" | "$jq_bin" -r '
        if (.disabled // false) == false and (.width // 0) > 0 and (.height // 0) > 0 then
          "\(.width)x\(.height)@\((.refreshRate // 60) | tostring)"
        else
          (.availableModes[0] // "1920x1080@60.00Hz")
        end
      ' | sed 's/Hz$//'
    }

    unknown_monitor_scale() {
      printf '1\n'
    }

    unknown_monitor_position() {
      local monitor_json="$1"
      local mode width height dims

      mode="$(unknown_monitor_mode "$monitor_json")"
      dims="$(parse_mode_dimensions "$mode" || true)"
      width="$(printf '%s' "$dims" | awk '{print $1}')"
      height="$(printf '%s' "$dims" | awk '{print $2}')"

      if [ -z "''${width:-}" ] || [ -z "''${height:-}" ]; then
        printf '%s\n' "-1920x0"
        return 0
      fi

      compute_unknown_monitor_position "$width" "$height"
    }

    list_unknown_monitors() {
      "$hyprctl_bin" -j monitors all \
        | "$jq_bin" -r --argfile bindings "$bindings_json" '
            .[] as $monitor
            | select(($monitor.name // "") != "")
            | select(([$bindings[]?.name] | index($monitor.name)) == null)
            | [
                $monitor.name,
                (if ($monitor.disabled // false) then "disabled" else "active" end),
                (if ($monitor.description // "") != "" then $monitor.description else ([$monitor.make // "", $monitor.model // ""] | map(select(. != "")) | join(" ")) end),
                (
                  if ($monitor.disabled // false) == false and ($monitor.width // 0) > 0 and ($monitor.height // 0) > 0 then
                    "\($monitor.width)x\($monitor.height)@\(($monitor.refreshRate // 60) | tostring)"
                  else
                    ($monitor.availableModes[0] // "1920x1080@60.00Hz")
                  end
                ),
                ""
              ]
            | @tsv
          ' \
        | while IFS=$'\t' read -r name state description mode _; do
            [ -n "$name" ] || continue
            position="$(unknown_monitor_position "$(get_unknown_monitor_json "$name")")"
            printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$state" "$description" "$(printf '%s' "$mode" | sed 's/Hz$//')" "$position"
          done
    }

    enable_unknown_monitor() {
      local name="$1"
      local monitor_json mode position scale

      monitor_json="$(get_unknown_monitor_json "$name")" || {
        echo "Unknown monitor: $name" >&2
        exit 1
      }

      if output_is_known "$name"; then
        echo "Monitor $name is already managed. Use wm-monitor on/off/toggle instead." >&2
        exit 1
      fi

      mode="$(unknown_monitor_mode "$monitor_json")"
      position="$(unknown_monitor_position "$monitor_json")"
      scale="$(unknown_monitor_scale)"

      "$hyprctl_bin" keyword monitor "$name,$mode,$position,$scale" >/dev/null 2>&1 || true
      wait_for_output_state "$name" active
      printf '%s enabled temporarily at %s with %s scale %s\n' "$name" "$position" "$mode" "$scale"
    }

    suggest_unknown_monitor_config() {
      local name="$1"
      local monitor_json description mode position

      monitor_json="$(get_unknown_monitor_json "$name")" || {
        echo "Unknown monitor: $name" >&2
        exit 1
      }

      description="$(describe_monitor_json "$monitor_json")"
      mode="$(unknown_monitor_mode "$monitor_json")"
      position="$(unknown_monitor_position "$monitor_json")"

      cat <<EOF
# Suggested settings.nix snippet for $name
# Description: $description

{
  name = "$name";
  enabledByDefault = false;
  mode = "$mode";
  position = "$position";
  scale = 1;
}
EOF
    }

    prompt_new_monitor_dialog() {
      local mode unknown_lines unknown_signature signature_file yad_bin nwg_displays_bin wl_copy_bin
      local selected_name action_rc snippet_file

      mode="''${1:-interactive}"
      signature_file="$state_dir/new-monitor-dialog.signature"
      yad_bin="$(command -v yad || true)"
      nwg_displays_bin="$(command -v nwg-displays || true)"
      wl_copy_bin="$(command -v wl-copy || true)"

      unknown_lines="$(list_unknown_monitors || true)"
      if [ -z "$unknown_lines" ]; then
        rm -f "$signature_file"
        return 0
      fi

      unknown_signature="$(
        printf '%s\n' "$unknown_lines" \
          | cut -f1 \
          | sort \
          | tr '\n' ',' \
          | sed 's/,$//'
      )"

      if [ "$mode" = "--auto" ]; then
        if [ -f "$signature_file" ] && [ "$(cat "$signature_file" 2>/dev/null || true)" = "$unknown_signature" ]; then
          return 0
        fi
        printf '%s\n' "$unknown_signature" >"$signature_file"
      fi

      if [ -z "$yad_bin" ]; then
        if [ "$mode" != "--auto" ]; then
          printf '%s\n' "$unknown_lines"
        fi
        return 0
      fi

      if selected_name="$(
        printf '%s\n' "$unknown_lines" | "$yad_bin" \
          --list \
          --title="New Monitor Detected" \
          --text="Select how to handle the newly detected monitor." \
          --column="Name" \
          --column="State" \
          --column="Description" \
          --column="Suggested Mode" \
          --column="Suggested Position" \
          --separator=$'\t' \
          --print-column=1 \
          --button="Enable Temporarily:0" \
          --button="Show Suggested Nix Snippet:2" \
          --button="Open nwg-displays:3" \
          --button="Cancel:1"
      )"; then
        action_rc=0
      else
        action_rc=$?
      fi

      [ -n "$selected_name" ] || return 0

      case "$action_rc" in
        0)
          enable_unknown_monitor "$selected_name"
          sync_runtime_monitor_overrides
          ;;
        2)
          snippet_file="$(mktemp)"
          suggest_unknown_monitor_config "$selected_name" >"$snippet_file"
          if [ -n "$wl_copy_bin" ]; then
            "$wl_copy_bin" <"$snippet_file" >/dev/null 2>&1 || true
          fi
          "$yad_bin" --text-info --title="Suggested Nix Snippet" --filename="$snippet_file" --width=760 --height=420
          rm -f "$snippet_file"
          ;;
        3)
          if [ -n "$nwg_displays_bin" ]; then
            "$nwg_displays_bin" >/dev/null 2>&1 &
          fi
          ;;
      esac
    }

    wait_for_output_state() {
      local name="$1"
      local desired_state="$2"

      for _ in $(seq 1 50); do
        if [ "$desired_state" = "active" ]; then
          output_is_active "$name" && return 0
        else
          output_is_active "$name" || return 0
        fi
        sleep 0.1
      done

      return 0
    }

    save_output_state() {
      local name="$1"
      local prefix="$2"
      local output_json="$3"

      "$hyprctl_bin" -j workspaces \
        | "$jq_bin" -r --arg output "$name" '.[] | select(.monitor == $output and (.id // -1) > 0 and (.name // "") != "") | [.name, .monitor] | @tsv' >"$prefix.workspaces.tmp"
      mv -f "$prefix.workspaces.tmp" "$prefix.workspaces"
      "$hyprctl_bin" -j monitors \
        | "$jq_bin" -r --arg output "$name" '.[] | select(.name == $output) | .activeWorkspace.name // empty' >"$prefix.active-workspace"
      "$hyprctl_bin" -j monitors \
        | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty' >"$prefix.focused-monitor"
      save_output_runtime_spec "$output_json" "$prefix"
    }

    move_workspace() {
      local workspace_name="$1"
      local target_monitor="$2"
      [ -n "$workspace_name" ] || return 0
      [ -n "$target_monitor" ] || return 0
      "$hyprctl_bin" dispatch moveworkspacetomonitor "$workspace_name $target_monitor" >/dev/null 2>&1 || true
    }

    get_monitor_active_workspace() {
      local name="$1"
      "$hyprctl_bin" -j monitors | "$jq_bin" -r --arg name "$name" '.[] | select(.name == $name) | .activeWorkspace.name // empty'
    }

    get_focused_monitor() {
      "$hyprctl_bin" -j monitors | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty'
    }

    pick_handoff_monitor() {
      local source_monitor="$1"
      local preferred_monitor="$2"

      if [ -n "$preferred_monitor" ] && [ "$preferred_monitor" != "$source_monitor" ] && output_is_active "$preferred_monitor"; then
        printf '%s\n' "$preferred_monitor"
        return 0
      fi

      "$hyprctl_bin" -j monitors         | "$jq_bin" -r --arg source "$source_monitor" '.[] | select((.disabled // false) == false and (.name // "") != "" and .name != $source) | .name'         | head -n 1
    }

    focus_monitor() {
      local name="$1"
      [ -n "$name" ] || return 0
      "$hyprctl_bin" dispatch focusmonitor "$name" >/dev/null 2>&1 || true
    }

    activate_workspace_on_monitor() {
      local monitor_name="$1"
      local workspace_name="$2"

      [ -n "$monitor_name" ] || return 0
      [ -n "$workspace_name" ] || return 0

      focus_monitor "$monitor_name"
      "$hyprctl_bin" dispatch workspace "$workspace_name" >/dev/null 2>&1 || true
    }

    move_monitor_workspaces_to_target() {
      local source_monitor="$1"
      local target_monitor="$2"
      local active_workspace=""

      [ -n "$source_monitor" ] || return 0
      [ -n "$target_monitor" ] || return 0
      [ "$source_monitor" = "$target_monitor" ] && return 0

      active_workspace="$(get_monitor_active_workspace "$source_monitor")"

      while IFS= read -r workspace_name; do
        [ -n "$workspace_name" ] || continue
        [ "$workspace_name" = "$active_workspace" ] && continue
        move_workspace "$workspace_name" "$target_monitor"
      done < <(
        "$hyprctl_bin" -j workspaces \
          | "$jq_bin" -r --arg output "$source_monitor" '.[] | select(.monitor == $output and (.id // -1) > 0 and (.name // "") != "") | .name'
      )

      if [ -n "$active_workspace" ]; then
        move_workspace "$active_workspace" "$target_monitor"
        activate_workspace_on_monitor "$target_monitor" "$active_workspace"
      else
        focus_monitor "$target_monitor"
      fi
    }

    move_active_workspace_to_output() {
      local target_monitor="$1"
      local workspace_name

      workspace_name="$("$hyprctl_bin" -j activeworkspace | "$jq_bin" -r '.name // empty')"
      [ -n "$workspace_name" ] || return 0
      move_workspace "$workspace_name" "$target_monitor"
      activate_workspace_on_monitor "$target_monitor" "$workspace_name"
    }

    move_other_monitors_workspaces_to_target() {
      local target_monitor="$1"

      [ -n "$target_monitor" ] || return 0

      "$hyprctl_bin" -j monitors         | "$jq_bin" -r --arg target "$target_monitor" '.[] | select((.disabled // false) == false and (.name // "") != "" and .name != $target) | .name'         | while IFS= read -r source_monitor; do
            [ -n "$source_monitor" ] || continue
            move_monitor_workspaces_to_target "$source_monitor" "$target_monitor"
          done

      focus_monitor "$target_monitor"
    }

    ensure_output_ready_for_workspace_move() {
      local target_monitor="$1"
      local output_json prefix

      [ -n "$target_monitor" ] || return 0
      output_json="$(load_output_config "$target_monitor" 2>/dev/null || true)"
      [ -n "$output_json" ] || return 0

      if ! output_is_active "$target_monitor"; then
        prefix="$(state_prefix "$target_monitor")"
        enable_output "$output_json" "$target_monitor" "$prefix"
        sync_runtime_monitor_overrides
      fi
    }

    disable_output() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local handoff_enabled target_monitor

      handoff_enabled="$(get_output_field "$output_json" 'if (.workspaceHandoff.enable // false) then "1" else "0" end')"
      target_monitor="$(get_output_field "$output_json" '.workspaceHandoff.targetMonitor // ""')"
      target_monitor="$(pick_handoff_monitor "$name" "$target_monitor")"
      printf '%s\n' "$target_monitor" >"$prefix.target-monitor"

      if output_is_active "$name"; then
        save_output_state "$name" "$prefix" "$output_json"

        if [ "$handoff_enabled" = "1" ] && [ -n "$target_monitor" ]; then
          move_monitor_workspaces_to_target "$name" "$target_monitor"
        fi
      fi

      "$hyprctl_bin" keyword monitor "$name,disable" >/dev/null 2>&1 || true
      wait_for_output_state "$name" inactive
    }

    enable_output() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local output_mode output_position output_scale focus_on_enable focused_monitor active_workspace

      output_mode="$(read_saved_or_declared_output_field "$prefix" mode "$output_json" '.mode // "preferred"')"
      output_position="$(read_saved_or_declared_output_field "$prefix" position "$output_json" '.position // "auto"')"
      output_scale="$(read_saved_or_declared_output_field "$prefix" scale "$output_json" '(.scale // 1) | tostring')"
      focus_on_enable="$(get_output_field "$output_json" 'if (.focusOnEnable // false) then "1" else "0" end')"

       if output_is_headless "$name" && ! "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
        "$hyprctl_bin" output create headless "$name" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
          if "$hyprctl_bin" -j monitors all | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
      fi

      "$hyprctl_bin" keyword monitor "$name,$output_mode,$output_position,$output_scale" >/dev/null 2>&1 || true
      wait_for_output_state "$name" active

      if [ -f "$prefix.workspaces" ]; then
        active_workspace="$(cat "$prefix.active-workspace" 2>/dev/null || true)"
        while IFS=$'\t' read -r workspace_name _; do
          [ -n "$workspace_name" ] || continue
          [ "$workspace_name" = "$active_workspace" ] && continue
          move_workspace "$workspace_name" "$name"
        done <"$prefix.workspaces"

        if [ -n "$active_workspace" ]; then
          move_workspace "$active_workspace" "$name"
          activate_workspace_on_monitor "$name" "$active_workspace"
        else
          focus_monitor "$name"
        fi
      fi

      focused_monitor="$(cat "$prefix.focused-monitor" 2>/dev/null || true)"
      if [ "$focus_on_enable" = "1" ] || [ "$focused_monitor" = "$name" ]; then
        focus_monitor "$name"
      elif [ -n "$focused_monitor" ]; then
        focus_monitor "$focused_monitor"
      fi
    }

    restore_output_state() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"

      enable_output "$output_json" "$name" "$prefix"
      rm -f "$prefix.workspaces" "$prefix.active-workspace" "$prefix.focused-monitor" "$prefix.mode" "$prefix.position" "$prefix.scale" "$prefix.target-monitor"
    }

    monitor_status() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local active state

      if output_is_active "$name"; then
        active="active"
      else
        active="disabled"
      fi

      if [ -f "$prefix.workspaces" ]; then
        state="saved-state"
      else
        state="no-saved-state"
      fi

      echo "$name $active $state"
    }

    monitor_list() {
      "$jq_bin" -r '.[] | [.bindIndex, .name, (.description // "")] | @tsv' "$bindings_json" \
        | while IFS=$'\t' read -r bind_index name description; do
            [ -n "$name" ] || continue
            if output_is_active "$name"; then
              active="active"
            else
              active="disabled"
            fi
            printf '%s\t%s\t%s\t%s\n' "$bind_index" "$name" "$description" "$active"
          done
    }

    sync_runtime_monitor_overrides_locked() {
      local tmp_file monitor_line output name unknown_monitor_json unknown_name unknown_spec

      mkdir -p "$(dirname "$runtime_config_path")"
      tmp_file="$(mktemp "$(dirname "$runtime_config_path")/.11-runtime-monitors.conf.XXXXXX")"
      {
        write_runtime_header
        "$jq_bin" -c '.[]' "$outputs_json" | while IFS= read -r output; do
          name="$(printf '%s' "$output" | "$jq_bin" -r '.name // empty')"
          [ -n "$name" ] || continue

          if output_is_active "$name"; then
            monitor_line="$(monitor_spec_from_live_or_declared_output "$output")"
          else
            monitor_line="''${name},disable"
          fi

          printf 'monitor = %s\n' "$monitor_line"
        done

        list_unknown_active_monitors | while IFS= read -r unknown_monitor_json; do
          unknown_name="$(printf '%s' "$unknown_monitor_json" | "$jq_bin" -r '.name // empty')"
          [ -n "$unknown_name" ] || continue
          unknown_spec="$(printf '%s' "$unknown_monitor_json" | "$jq_bin" -r '"\(.name),\(.width)x\(.height)@\((.refreshRate // 60) | tostring),\((.x // 0) | floor)x\((.y // 0) | floor),\((.scale // 1) | tostring)"')"
          printf 'monitor = %s\n' "$unknown_spec"
        done
      } >"$tmp_file"
      mv -f "$tmp_file" "$runtime_config_path"
    }

    sync_runtime_monitor_overrides() {
      with_runtime_lock sync_runtime_monitor_overrides_locked
    }

    watch_monitor_events() {
      while :; do
        sync_runtime_monitor_overrides || true
        prompt_new_monitor_dialog --auto || true
        sleep 2
      done
    }

    case "$command" in
      list)
        monitor_list
        exit 0
        ;;
      sync-live)
        sync_runtime_monitor_overrides
        exit 0
        ;;
      sync-defaults)
        sync_default_monitor_overrides
        exit 0
        ;;
      watch)
        watch_monitor_events
        exit 0
        ;;
      prompt-new)
        prompt_new_monitor_dialog "$output_name"
        exit 0
        ;;
      discover)
        list_unknown_monitors
        exit 0
        ;;
      enable-discovered|suggest)
        require_output_name
        ;;
      on|off|toggle|restore|status)
        require_output_name
        output_json="$(load_output_config "$output_name")" || {
          echo "Unknown managed output: $output_name" >&2
          exit 1
        }
        prefix="$(state_prefix "$output_name")"
        ;;
      workspace-to|focused-workspaces-to)
        require_output_name
        if [ -s "$bindings_json" ]; then
          load_output_binding "$output_name" >/dev/null 2>&1 || {
            echo "Unknown output binding: $output_name" >&2
            exit 1
          }
        fi
        ;;
      *)
        usage
        ;;
    esac

    case "$command" in
      on)
        enable_output "$output_json" "$output_name" "$prefix"
        sync_runtime_monitor_overrides
        ;;
      off)
        disable_output "$output_json" "$output_name" "$prefix"
        sync_runtime_monitor_overrides
        ;;
      toggle)
        if output_is_active "$output_name"; then
          disable_output "$output_json" "$output_name" "$prefix"
        else
          enable_output "$output_json" "$output_name" "$prefix"
        fi
        sync_runtime_monitor_overrides
        ;;
      restore)
        restore_output_state "$output_json" "$output_name" "$prefix"
        sync_runtime_monitor_overrides
        ;;
      status)
        monitor_status "$output_json" "$output_name" "$prefix"
        ;;
      discover)
        list_unknown_monitors
        ;;
      enable-discovered)
        enable_unknown_monitor "$output_name"
        ;;
      suggest)
        suggest_unknown_monitor_config "$output_name"
        ;;
      prompt-new)
        prompt_new_monitor_dialog "$output_name"
        ;;
      workspace-to)
        ensure_output_ready_for_workspace_move "$output_name"
        move_active_workspace_to_output "$output_name"
        ;;
      focused-workspaces-to)
        ensure_output_ready_for_workspace_move "$output_name"
        move_other_monitors_workspaces_to_target "$output_name"
        ;;
    esac
  '';
  monitorOnScript = pkgs.writeShellScriptBin "wm-monitor-on" ''exec ${lib.getExe monitorStateScript} on "$@"'';
  monitorOffScript = pkgs.writeShellScriptBin "wm-monitor-off" ''exec ${lib.getExe monitorStateScript} off "$@"'';
  monitorToggleScript = pkgs.writeShellScriptBin "wm-monitor-toggle" ''exec ${lib.getExe monitorStateScript} toggle "$@"'';
  monitorRestoreScript = pkgs.writeShellScriptBin "wm-monitor-restore" ''exec ${lib.getExe monitorStateScript} restore "$@"'';
  monitorStatusScript = pkgs.writeShellScriptBin "wm-monitor-status" ''exec ${lib.getExe monitorStateScript} status "$@"'';
  monitorWorkspaceToScript = pkgs.writeShellScriptBin "wm-monitor-workspace-to" ''exec ${lib.getExe monitorStateScript} workspace-to "$@"'';
  monitorFocusedWorkspacesToScript = pkgs.writeShellScriptBin "wm-monitor-focused-workspaces-to" ''exec ${lib.getExe monitorStateScript} focused-workspaces-to "$@"'';
  monitorListScript = pkgs.writeShellScriptBin "wm-monitor-list" ''exec ${lib.getExe monitorStateScript} list "$@"'';
  monitorDiscoverScript = pkgs.writeShellScriptBin "wm-monitor-discover" ''exec ${lib.getExe monitorStateScript} discover "$@"'';
  monitorSuggestScript = pkgs.writeShellScriptBin "wm-monitor-suggest" ''exec ${lib.getExe monitorStateScript} suggest "$@"'';
  monitorNewDialogScript = pkgs.writeShellScriptBin "wm-monitor-new-dialog" ''exec ${lib.getExe monitorStateScript} prompt-new "$@"'';
  monitorDebugScript = pkgs.writeShellScriptBin "wm-monitor-debug" ''
    set -eu

    echo "== Hyprland monitors (all) =="
    ${hyprctlExec} -j monitors all || true
    echo
    echo "== Startup monitor defaults =="
    cat ${lib.escapeShellArg "${config.home.homeDirectory}/.config/hypr/conf.d/10-monitors.conf"} || true
    echo
    echo "== Runtime monitor overrides =="
    cat ${lib.escapeShellArg hyprlandRuntimeMonitorConfigPath} || true
  '';
  startGraphicalSessionTargetScript = pkgs.writeShellScriptBin "wm-start-graphical-session-target" ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    if [ -S "$runtime_dir/bus" ]; then
      ${pkgs.systemd}/bin/systemctl --user start graphical-session.target >/dev/null 2>&1 || true
    fi
  '';
  hyprlandStartupAppsScript = pkgs.writeShellScriptBin "wm-hypr-startup-apps" ''
    hyprctl_bin="${hyprctlExec}"
    [ -x "$hyprctl_bin" ] || exit 0

    launch_on_workspace() {
      workspace="$1"
      command="$2"
      "$hyprctl_bin" dispatch exec "[workspace $workspace silent] $command" >/dev/null 2>&1 || true
    }

    if ! ${pkgs.procps}/bin/pgrep -x firefox >/dev/null 2>&1; then
      launch_on_workspace 2 '${launcherAppExec "firefox"}'
    fi

    if ! ${pkgs.procps}/bin/pgrep -x btop >/dev/null 2>&1; then
      launch_on_workspace 3 '${launcherAppExec "${preferredTerminalCmd} btop"}'
    fi
  '';
  hyprlandKeybindDiagnosticsStartupScript = pkgs.writeShellScriptBin "wm-hypr-keybind-diagnostics-startup" ''
    ${homeBinDir}/wm-hypr-keybind-dump --phase=login-initial
    sleep ${toString keybindDiagnosticsDelaySeconds}
    ${homeBinDir}/wm-hypr-keybind-dump --phase=login-delayed
  '';
  managedStaticMonitorNames = lib.unique (toggleableOutputNames ++ headlessOutputNames);
  initialOutputStateToMonitorLine =
    output:
      let
        name = output.name or "";
        enabledByDefault = output.enabledByDefault or true;
        mode = output.mode or "preferred";
        position = output.position or "auto";
        scale = toString (output.scale or 1);
      in
        if enabledByDefault then
          "${name},${mode},${position},${scale}"
        else
          "${name},disable";
  managedConfigMonitorNames =
    map (output: output.name or "") (builtins.filter (output: !(builtins.elem (output.name or "") headlessOutputNames)) initialOutputStates);
  managedConfigMonitorLines =
    map initialOutputStateToMonitorLine
      (builtins.filter (output: !(builtins.elem (output.name or "") headlessOutputNames)) initialOutputStates);
  monitorNameFromLine =
    line:
      let
        match = builtins.match "[[:space:]]*([^,[:space:]]+)[[:space:]]*,.*" line;
      in
        if match == null then line else builtins.elemAt match 0;
  filteredProfileDetails = profileDetails // {
    hyprlandMonitors =
      builtins.filter
        (line: !(builtins.elem (monitorNameFromLine line) managedConfigMonitorNames))
        (profileDetails.hyprlandMonitors or [ ]);
  };
  hyprlandFragments = import ./config/fragments.nix {
    inherit
      lib
      settings
      ;
    profileDetails = filteredProfileDetails;
    inherit
      isCaelestiaShell
      isDmsShell
      hyprDmsDir
      hyprlandWindowRules
      hyprlandKeybinds
      shellStartupCommand
      dmsOverviewEnabled
      dmsOverviewAutostart
      homeBinDir
      sessionEnvLines
      keybindDiagnosticsEnable
      ;
    mainConfigDir = mainHyprConfigDir;
    shellConfigDir = shellGeneratedConfigDir;
    sessionEnvImportCommand = lib.getExe importSessionEnvScript;
    startGraphicalSessionTargetCommand = lib.getExe startGraphicalSessionTargetScript;
    swwwDaemonCommand = lib.getExe' pkgs.swww "swww-daemon";
    startupAppsCommand = lib.getExe hyprlandStartupAppsScript;
    keybindDiagnosticsStartupCommand = lib.getExe hyprlandKeybindDiagnosticsStartupScript;
    runtimeMonitorResetCommand = lib.getExe runtimeMonitorResetScript;
    managedMonitorLines = managedConfigMonitorLines;
  };
  hyprlandFragmentFiles =
    lib.mapAttrs'
      (path: text: lib.nameValuePair path { inherit text; })
      hyprlandFragments.files;
  hyprlandMutableConfigPaths = [
    "hypr/conf.d/11-runtime-monitors.conf"
  ];
  hyprlandMainConfig = ''
    # ------------------------------------------------------------------
    # j0nix Hyprland main config
    # ------------------------------------------------------------------
    # This file is intentionally thin:
    # - ordered includes from ~/.config/hypr/conf.d
    # - shell-scoped generated include
    # - shell-scoped user override include (loaded last)

    ${lib.concatStringsSep "\n" (map (path: "source = ${path}") hyprlandFragments.includePaths)}

    # User-local shell override (persistent, sourced last on purpose).
    source = ${userHyprConfigPath}
  '';
in {
  j0nix.user.software.packages = with pkgs; [
    swww
    wayvnc
    wl-clipboard
    grim
    slurp
    swappy
    playerctl
  ]
  ++ lib.optionals keybindDiagnosticsEnable [
    keybindDiagnosticsScript
    keybindDiagnosticsProbeScript
  ]
  ++ lib.optionals (headlessOutputs != [ ]) [
    headlessOutputsEnsureScript
    headlessOutputsRemoveScript
  ]
  ++ lib.optionals (initialOutputStates != [ ]) [
    monitorStateScript
    monitorOnScript
    monitorOffScript
    monitorToggleScript
    monitorRestoreScript
    monitorStatusScript
    monitorWorkspaceToScript
    monitorFocusedWorkspacesToScript
    monitorListScript
    monitorDiscoverScript
    monitorSuggestScript
    monitorNewDialogScript
    monitorDebugScript
  ]
  ++ lib.optionals hasHyprKcsPackage [ hyprKcsPackage ]
  ++ lib.optional (installRawQuickshell && (pkgs ? quickshell)) pkgs.quickshell
  ++ lib.optional (nwgDisplaysPackage != null) nwgDisplaysPackage
  ++ lib.optionals (minimizerEnabled && minimizerPackage != null) [ minimizerPackage ];

  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false;
    extraConfig = hyprlandMainConfig;
    settings = { };

  };

  home.activation.hyprlandUserOverridesInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg_dir="$HOME/.config/hypr/shell-overrides/${selectedShell}"
    cfg_file="$cfg_dir/user-overrides.conf"
    legacy_cfg_file="$HOME/.config/hypr/user-overrides.conf"

    if [ -L "$cfg_file" ]; then
      $DRY_RUN_CMD rm -f "$cfg_file"
    fi

    $DRY_RUN_CMD mkdir -p "$cfg_dir"

    if [ ! -e "$cfg_file" ]; then
      if [ -f "$legacy_cfg_file" ] && [ ! -L "$legacy_cfg_file" ]; then
        # Migrate existing shared override file to the new shell-scoped location.
        $DRY_RUN_CMD cp "$legacy_cfg_file" "$cfg_file"
      else
        $DRY_RUN_CMD cat >"$cfg_file" <<'EOF'
# Local Hyprland overrides for this user.
# Sourced last from the generated Hyprland config.
# This file is shell-scoped:
#   ~/.config/hypr/shell-overrides/${selectedShell}/user-overrides.conf
#
# Examples:
# bind = SUPER, F2, exec, kitty
# windowrule = float 1, match:class ^(pavucontrol)$
# monitor = ,preferred,auto,1
EOF
      fi
      $DRY_RUN_CMD chmod 0644 "$cfg_file"
    fi
  '';

  home.activation.hyprlandRuntimeMonitorOverridesInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg_dir="$HOME/.config/hypr/conf.d"
    cfg_file="$cfg_dir/11-runtime-monitors.conf"

    if [ -L "$cfg_file" ]; then
      $DRY_RUN_CMD rm -f "$cfg_file"
    fi

    $DRY_RUN_CMD mkdir -p "$cfg_dir"
    $DRY_RUN_CMD ${lib.getExe runtimeMonitorResetScript}
    $DRY_RUN_CMD chmod 0644 "$cfg_file"
  '';

  home.activation.hyprlandHeadlessOutputsReload = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    if [ -S "$runtime_dir/bus" ]; then
      ${lib.optionalString headlessOutputsAutoEnsure ''
      ${pkgs.systemd}/bin/systemctl --user daemon-reload >/dev/null 2>&1 || true
      ${pkgs.systemd}/bin/systemctl --user restart hyprland-headless-outputs.service >/dev/null 2>&1 || true
      ''}
      ${pkgs.systemd}/bin/systemctl --user daemon-reload >/dev/null 2>&1 || true
      ${pkgs.systemd}/bin/systemctl --user restart hyprland-runtime-monitor-defaults.service >/dev/null 2>&1 || true
    fi
  '';

  xdg.configFile =
    builtins.removeAttrs hyprlandFragmentFiles hyprlandMutableConfigPaths
    // lib.optionalAttrs useUWSM {
      "uwsm/env".text = uwsmEnvText;
    }
    // {
      "hypr/hyprland.conf".force = true;
    };

  systemd.user.services.hyprland-headless-outputs = lib.mkIf headlessOutputsAutoEnsure {
    Unit = {
      Description = "Ensure Hyprland headless outputs";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe headlessOutputsEnsureScript;
      ExecStop = lib.getExe headlessOutputsRemoveScript;
    };
  };

  systemd.user.services.hyprland-runtime-monitor-defaults = lib.mkIf (initialOutputStates != [ ]) {
    Unit = {
      Description = "Manage Hyprland runtime monitor overrides";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      Restart = "always";
      RestartSec = 1;
      ExecStartPre = "${lib.getExe monitorStateScript} sync-defaults";
      ExecStart = "${lib.getExe monitorStateScript} watch";
      ExecStopPost = "${lib.getExe monitorStateScript} sync-defaults";
    };
  };

  assertions = [
    {
      assertion = !(installRawQuickshell && isDmsShell);
      message = "settings.hyprland.debug.installRawQuickshell conflicts with hyprlandShell=dank-material-shell (quickshell package collision).";
    }
    {
      assertion = workspaceCountRaw >= 1 && workspaceCountRaw <= 10;
      message = "settings.dms.workspaces.count must be between 1 and 10";
    }
    {
      assertion = builtins.elem appExecBackend [ "auto" "app2unit" "uwsm" ];
      message = "settings.hyprland.appExecBackend must be one of: auto, app2unit, uwsm";
    }
    {
      assertion = builtins.isAttrs (sessionEnvCfg.extra or { });
      message = "settings.hyprland.sessionEnv.extra must be an attribute set of environment variables.";
    }
    {
      assertion = (sessionEnvCfg.qtPlatformTheme or null) == null || builtins.isString sessionEnvCfg.qtPlatformTheme;
      message = "settings.hyprland.sessionEnv.qtPlatformTheme must be a string or null.";
    }
    {
      assertion = !minimizerEnabled || minimizerCommand != "";
      message = "settings.hyprland.minimizer.command must not be empty when minimizer is enabled.";
    }
    {
      assertion = builtins.elem minimizerVariant [ "denis" "0rteip" ];
      message = "settings.hyprland.minimizer.variant must be one of: denis, 0rteip";
    }
    {
      assertion = !minimizerEnabled || minimizerOrteipAppId != "";
      message = "settings.hyprland.minimizer.orteip.appId must not be empty when minimizer is enabled.";
    }
    {
      assertion = keybindDiagnosticsDelaySeconds >= 0;
      message = "settings.hyprland.debug.keybindDiagnostics.delaySeconds must be >= 0.";
    }
    {
      assertion = lib.all (name: name != "") headlessOutputNames;
      message = "settings.hyprland.headlessOutputs entries must have a non-empty name.";
    }
    {
      assertion = (builtins.length headlessOutputNames) == (builtins.length (lib.unique headlessOutputNames));
      message = "settings.hyprland.headlessOutputs names must be unique.";
    }
    {
      assertion = lib.all (name: name != "") outputBindingNames;
      message = "settings.hyprland.outputBindings entries must have a non-empty name.";
    }
    {
      assertion = lib.all (name: name != "") initialOutputStateNames;
      message = "settings.hyprland.initialOutputStates entries must have a non-empty name.";
    }
    {
      assertion = (builtins.length initialOutputStateNames) == (builtins.length (lib.unique initialOutputStateNames));
      message = "settings.hyprland.initialOutputStates names must be unique.";
    }
    {
      assertion = (builtins.length outputBindingNames) == (builtins.length (lib.unique outputBindingNames));
      message = "settings.hyprland.outputBindings names must be unique.";
    }
    {
      assertion = lib.all (index: index >= 1 && index <= 10) outputBindingIndices;
      message = "settings.hyprland.outputBindings bindIndex values must be between 1 and 10.";
    }
    {
      assertion = (builtins.length outputBindingIndices) == (builtins.length (lib.unique outputBindingIndices));
      message = "settings.hyprland.outputBindings bindIndex values must be unique.";
    }
    {
      assertion = lib.all (name: name != "") toggleableOutputNames;
      message = "settings.hyprland.toggleableOutputs entries must have a non-empty name.";
    }
    {
      assertion = (builtins.length toggleableOutputNames) == (builtins.length (lib.unique toggleableOutputNames));
      message = "settings.hyprland.toggleableOutputs names must be unique.";
    }
    {
      assertion = lib.all (index: index >= 1 && index <= 10) managedOutputBindIndices;
      message = "Managed output bindIndex values must be between 1 and 10.";
    }
    {
      assertion = (builtins.length managedOutputBindIndices) == (builtins.length (lib.unique managedOutputBindIndices));
      message = "Managed output bindIndex values must be unique.";
    }
    {
      assertion = lib.all
        (output: !(output.workspaceHandoff.enable or false) || ((output.workspaceHandoff.targetMonitor or "") != ""))
        toggleableOutputs;
      message = "settings.hyprland.toggleableOutputs.<name>.workspaceHandoff.targetMonitor must be set when workspaceHandoff.enable is true.";
    }
    {
      assertion = hasHyprKcsPackage;
      message = "Hyprland keybind help requires inputs.hyprkcs.packages.<system>.default to be available.";
    }
    {
      assertion = !installNwgDisplays || nwgDisplaysPackage != null;
      message = "settings.hyprland.monitorTools.installNwgDisplays is enabled, but pkgs.\"nwg-displays\" is not available in the active nixpkgs.";
    }
  ];
}
