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
  hyprlandDebug = hyprlandCfg.debug or { };
  headlessOutputs = hyprlandCfg.headlessOutputs or [ ];
  headlessOutputsWithBindings = map
    (output:
      if output ? bindIndex then
        output // { bindKey = if output.bindIndex == 10 then "0" else toString output.bindIndex; }
      else
        output)
    headlessOutputs;
  headlessOutputNames = map (output: output.name or "") headlessOutputs;
  headlessOutputsJson = pkgs.writeText "hyprland-headless-outputs.json" (builtins.toJSON headlessOutputs);
  outputBindings = hyprlandCfg.outputBindings or [ ];
  outputBindingsWithKeys = map
    (binding:
      binding // { bindKey = if binding.bindIndex == 10 then "0" else toString binding.bindIndex; })
    outputBindings;
  outputBindingNames = map (binding: binding.name or "") outputBindingsWithKeys;
  outputBindingIndices = map (binding: binding.bindIndex) outputBindingsWithKeys;
  outputBindingsJson = pkgs.writeText "hyprland-output-bindings.json" (builtins.toJSON outputBindingsWithKeys);
  toggleableOutputs = hyprlandCfg.toggleableOutputs or [ ];
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
  monitorToolsCfg = hyprlandCfg.monitorTools or { };
  installHyprdynamicmonitors = monitorToolsCfg.installHyprdynamicmonitors or true;
  installNwgDisplays = monitorToolsCfg.installNwgDisplays or true;
  defaultMonitorTool = monitorToolsCfg.default or "hyprdynamicmonitors";
  monitorToolsAutoStart = monitorToolsCfg.autoStart or true;
  hyprdynamicmonitorsServiceEnabled =
    installHyprdynamicmonitors
    && monitorToolsAutoStart
    && toggleableOutputs == [ ];
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
  keepassToggleBind = keepassWorkspaceCfg.toggleBind or "$mainMod CTRL, p";
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
  shellGeneratedConfigDir = "${config.home.homeDirectory}/.config/hypr/shells/${selectedShell}/generated";
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
        XDG_CURRENT_DESKTOP \
        XDG_RUNTIME_DIR \
        XDG_SESSION_DESKTOP \
        XDG_SESSION_TYPE \
        HYPRLAND_INSTANCE_SIGNATURE >/dev/null 2>&1 || true
      ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
        DISPLAY \
        WAYLAND_DISPLAY \
        XDG_CURRENT_DESKTOP \
        XDG_RUNTIME_DIR \
        XDG_SESSION_DESKTOP \
        XDG_SESSION_TYPE \
        HYPRLAND_INSTANCE_SIGNATURE >/dev/null 2>&1 || true
    fi
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
  toggleableOutputsDefaultsScript = pkgs.writeShellScriptBin "wm-monitor-apply-defaults" ''
    set -eu

    hyprctl_bin="${hyprctlExec}"
    jq_bin="${pkgs.jq}/bin/jq"
    outputs_json=${lib.escapeShellArg toggleableOutputsJson}

    [ -x "$hyprctl_bin" ] || exit 0
    [ -x "$jq_bin" ] || exit 0

    "$jq_bin" -c '.[]' "$outputs_json" | while IFS= read -r output; do
      name="$(printf '%s' "$output" | "$jq_bin" -r '.name // empty')"
      enabled_by_default="$(printf '%s' "$output" | "$jq_bin" -r 'if (.enabledByDefault // true) then "1" else "0" end')"
      mode="$(printf '%s' "$output" | "$jq_bin" -r '.mode // "preferred"')"
      position="$(printf '%s' "$output" | "$jq_bin" -r '.position // "auto"')"
      scale="$(printf '%s' "$output" | "$jq_bin" -r '(.scale // 1) | tostring')"

      [ -n "$name" ] || continue

      if [ "$enabled_by_default" = "1" ]; then
        "$hyprctl_bin" keyword monitor "$name,$mode,$position,$scale" >/dev/null 2>&1 || true
      else
        "$hyprctl_bin" keyword monitor "$name,disable" >/dev/null 2>&1 || true
      fi
    done
  '';
  monitorStateScript = pkgs.writeShellScriptBin "wm-monitor" ''
    set -eu

    hyprctl_bin="${hyprctlExec}"
    jq_bin="${pkgs.jq}/bin/jq"
    outputs_json=${lib.escapeShellArg toggleableOutputsJson}
    bindings_json=${lib.escapeShellArg outputBindingsJson}
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

    usage() {
      echo "usage: wm-monitor <on|off|toggle|restore|status|workspace-to|focused-workspaces-to|list|config> [output-name]" >&2
      exit 2
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

    require_output_name() {
      [ -n "$output_name" ] || usage
    }

    get_output_field() {
      local output_json="$1"
      local query="$2"
      printf '%s' "$output_json" | "$jq_bin" -r "$query"
    }

    output_is_active() {
      local name="$1"
      "$hyprctl_bin" -j monitors | "$jq_bin" -e --arg name "$name" '.[] | select(.name == $name and (.disabled // false) == false)' >/dev/null 2>&1
    }

    save_output_state() {
      local name="$1"
      local prefix="$2"

      "$hyprctl_bin" -j workspaces \
        | "$jq_bin" -r --arg output "$name" '.[] | select(.monitor == $output and (.id // -1) > 0 and (.name // "") != "") | [.name, .monitor] | @tsv' >"$prefix.workspaces.tmp"
      mv -f "$prefix.workspaces.tmp" "$prefix.workspaces"
      "$hyprctl_bin" -j monitors \
        | "$jq_bin" -r --arg output "$name" '.[] | select(.name == $output) | .activeWorkspace.name // empty' >"$prefix.active-workspace"
      "$hyprctl_bin" -j monitors \
        | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty' >"$prefix.focused-monitor"
    }

    move_workspace() {
      local workspace_name="$1"
      local target_monitor="$2"
      [ -n "$workspace_name" ] || return 0
      [ -n "$target_monitor" ] || return 0
      "$hyprctl_bin" dispatch moveworkspacetomonitor "$workspace_name" "$target_monitor" >/dev/null 2>&1 || true
    }

    get_monitor_active_workspace() {
      local name="$1"
      "$hyprctl_bin" -j monitors | "$jq_bin" -r --arg name "$name" '.[] | select(.name == $name) | .activeWorkspace.name // empty'
    }

    get_focused_monitor() {
      "$hyprctl_bin" -j monitors | "$jq_bin" -r '.[] | select(.focused == true) | .name // empty'
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

    disable_output() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local handoff_enabled target_monitor output_mode output_position output_scale

      handoff_enabled="$(get_output_field "$output_json" 'if (.workspaceHandoff.enable // false) then "1" else "0" end')"
      target_monitor="$(get_output_field "$output_json" '.workspaceHandoff.targetMonitor // ""')"
      output_mode="$(get_output_field "$output_json" '.mode // "preferred"')"
      output_position="$(get_output_field "$output_json" '.position // "auto"')"
      output_scale="$(get_output_field "$output_json" '(.scale // 1) | tostring')"

      printf '%s\n' "$output_mode" >"$prefix.mode"
      printf '%s\n' "$output_position" >"$prefix.position"
      printf '%s\n' "$output_scale" >"$prefix.scale"
      printf '%s\n' "$target_monitor" >"$prefix.target-monitor"

      if output_is_active "$name"; then
        save_output_state "$name" "$prefix"

        if [ "$handoff_enabled" = "1" ] && [ -n "$target_monitor" ]; then
          move_monitor_workspaces_to_target "$name" "$target_monitor"
        fi
      fi

      "$hyprctl_bin" keyword monitor "$name,disable" >/dev/null 2>&1 || true
    }

    enable_output() {
      local output_json="$1"
      local name="$2"
      local prefix="$3"
      local output_mode output_position output_scale focus_on_enable focused_monitor active_workspace

      output_mode="$(get_output_field "$output_json" '.mode // "preferred"')"
      output_position="$(get_output_field "$output_json" '.position // "auto"')"
      output_scale="$(get_output_field "$output_json" '(.scale // 1) | tostring')"
      focus_on_enable="$(get_output_field "$output_json" 'if (.focusOnEnable // false) then "1" else "0" end')"

      "$hyprctl_bin" keyword monitor "$name,$output_mode,$output_position,$output_scale" >/dev/null 2>&1 || true

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

    run_config_tool() {
      case ${lib.escapeShellArg defaultMonitorTool} in
        hyprdynamicmonitors)
          exec ${lib.getExe pkgs.hyprdynamicmonitors}
          ;;
        nwg-displays)
          exec ${lib.getExe pkgs.nwg-displays}
          ;;
        *)
          echo "Unknown settings.hyprland.monitorTools.default: ${defaultMonitorTool}" >&2
          exit 1
          ;;
      esac
    }

    case "$command" in
      config)
        exec ${homeBinDir}/wm-monitor-config
        ;;
      list)
        monitor_list
        exit 0
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
        ;;
      off)
        disable_output "$output_json" "$output_name" "$prefix"
        ;;
      toggle)
        if output_is_active "$output_name"; then
          disable_output "$output_json" "$output_name" "$prefix"
        else
          enable_output "$output_json" "$output_name" "$prefix"
        fi
        ;;
      restore)
        restore_output_state "$output_json" "$output_name" "$prefix"
        ;;
      status)
        monitor_status "$output_json" "$output_name" "$prefix"
        ;;
      workspace-to)
        move_active_workspace_to_output "$output_name"
        ;;
      focused-workspaces-to)
        move_monitor_workspaces_to_target "$(get_focused_monitor)" "$output_name"
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
  monitorConfigScript = pkgs.writeShellScriptBin "wm-monitor-config" ''
    case ${lib.escapeShellArg defaultMonitorTool} in
      hyprdynamicmonitors)
        exec ${lib.getExe pkgs.hyprdynamicmonitors} tui "$@"
        ;;
      nwg-displays)
        exec ${lib.getExe pkgs.nwg-displays} "$@"
        ;;
      *)
        echo "Unknown settings.hyprland.monitorTools.default: ${defaultMonitorTool}" >&2
        exit 1
        ;;
    esac
  '';
  monitorConfigTuiScript = pkgs.writeShellScriptBin "wm-monitor-config-tui" ''
    exec ${lib.getExe pkgs.hyprdynamicmonitors} tui "$@"
  '';
  monitorConfigGuiScript = pkgs.writeShellScriptBin "wm-monitor-config-gui" ''
    exec ${lib.getExe pkgs.nwg-displays} "$@"
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
  hyprlandFragments = import ./config/fragments.nix {
    inherit
      lib
      settings
      profileDetails
      isCaelestiaShell
      isDmsShell
      hyprDmsDir
      hyprlandWindowRules
      hyprlandKeybinds
      shellStartupCommand
      dmsOverviewEnabled
      dmsOverviewAutostart
      homeBinDir
      keybindDiagnosticsEnable
      ;
    mainConfigDir = mainHyprConfigDir;
    shellConfigDir = shellGeneratedConfigDir;
    sessionEnvImportCommand = lib.getExe importSessionEnvScript;
    startGraphicalSessionTargetCommand = lib.getExe startGraphicalSessionTargetScript;
    swwwDaemonCommand = lib.getExe' pkgs.swww "swww-daemon";
    toggleableOutputsDefaultsCommand = lib.optionalString (toggleableOutputs != [ ]) (lib.getExe toggleableOutputsDefaultsScript);
    startupAppsCommand = lib.getExe hyprlandStartupAppsScript;
    keybindDiagnosticsStartupCommand = lib.getExe hyprlandKeybindDiagnosticsStartupScript;
  };
  hyprlandFragmentFiles =
    lib.mapAttrs'
      (path: text: lib.nameValuePair path { inherit text; })
      hyprlandFragments.files;
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
  ++ lib.optionals (toggleableOutputs != [ ]) [
    toggleableOutputsDefaultsScript
    monitorStateScript
    monitorOnScript
    monitorOffScript
    monitorToggleScript
    monitorRestoreScript
    monitorStatusScript
    monitorWorkspaceToScript
    monitorFocusedWorkspacesToScript
    monitorListScript
    monitorConfigScript
    monitorConfigTuiScript
    monitorConfigGuiScript
  ]
  ++ lib.optionals installHyprdynamicmonitors [ pkgs.hyprdynamicmonitors ]
  ++ lib.optionals installNwgDisplays [ pkgs.nwg-displays ]
  ++ lib.optionals hasHyprKcsPackage [ hyprKcsPackage ]
  ++ lib.optional (installRawQuickshell && (pkgs ? quickshell)) pkgs.quickshell
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

  home.activation.hyprlandHeadlessOutputsReload = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    ${lib.optionalString (headlessOutputs != [ ]) ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    if [ -S "$runtime_dir/bus" ]; then
      ${pkgs.systemd}/bin/systemctl --user daemon-reload >/dev/null 2>&1 || true
      ${pkgs.systemd}/bin/systemctl --user restart hyprland-headless-outputs.service >/dev/null 2>&1 || true
    fi
    ''}
  '';

  home.activation.hyprdynamicmonitorsSync = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    if [ -S "$runtime_dir/bus" ]; then
      ${pkgs.systemd}/bin/systemctl --user daemon-reload >/dev/null 2>&1 || true
      if [ "${if hyprdynamicmonitorsServiceEnabled then "1" else "0"}" = "1" ]; then
        ${pkgs.systemd}/bin/systemctl --user start hyprdynamicmonitors.service >/dev/null 2>&1 || true
      else
        ${pkgs.systemd}/bin/systemctl --user stop hyprdynamicmonitors.service >/dev/null 2>&1 || true
      fi
    fi
  '';

  xdg.configFile =
    hyprlandFragmentFiles
    // {
      "hypr/hyprland.conf".force = true;
    };

  systemd.user.services.hyprland-headless-outputs = lib.mkIf (headlessOutputs != [ ]) {
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

  systemd.user.services.hyprdynamicmonitors = lib.mkIf hyprdynamicmonitorsServiceEnabled {
    Unit = {
      Description = "Hyprland dynamic monitor profile daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
      ConditionPathExists = "%h/.config/hyprdynamicmonitors/config.toml";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStartPre = "${lib.getExe pkgs.hyprdynamicmonitors} prepare";
      ExecStart = "${lib.getExe pkgs.hyprdynamicmonitors} run";
      Restart = "on-failure";
      RestartSec = 2;
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
      assertion = builtins.elem defaultMonitorTool [ "hyprdynamicmonitors" "nwg-displays" ];
      message = "settings.hyprland.monitorTools.default must be one of: hyprdynamicmonitors, nwg-displays.";
    }
    {
      assertion = builtins.isBool monitorToolsAutoStart;
      message = "settings.hyprland.monitorTools.autoStart must be a boolean.";
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
  ];
}
