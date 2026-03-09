{ config, lib, pkgs, settings, ... }:
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
  remoteWorkspaceSwitchBinds = map (pair: "CTRL ALT, ${pair.key}, workspace, ${pair.workspace}") workspaceKeyPairs;
  remoteWorkspaceMoveBinds = map (pair: "CTRL SHIFT ALT, ${pair.key}, movetoworkspace, ${pair.workspace}") workspaceKeyPairs;
  hyprlandCfg = settings.hyprland or { };
  hyprlandDebug = hyprlandCfg.debug or { };
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
  keepassCfg = ((settings.programs or { }).keepassxc or { });
  keepassEnabled = keepassCfg.enable or false;
  keepassWorkspaceCfg = keepassCfg.workspace or { };
  keepassWorkspaceEnable = keepassWorkspaceCfg.enable or true;
  keepassToggleBind = keepassWorkspaceCfg.toggleBind or "$mainMod CTRL, p";
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
      workspaceSwitchBinds
      workspaceMoveBinds
      remoteWorkspaceSwitchBinds
      remoteWorkspaceMoveBinds;
  };
  installRawQuickshell = hyprlandDebug.installRawQuickshell or false;
  shellStartupCommand =
    if selectedShell == "none" then
      null
    else
      appExec "${homeBinDir}/wm-shell-start";
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
    startGraphicalSessionTargetCommand = lib.getExe startGraphicalSessionTargetScript;
    swwwDaemonCommand = lib.getExe' pkgs.swww "swww-daemon";
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

  xdg.configFile =
    hyprlandFragmentFiles
    // {
      "hypr/hyprland.conf".force = true;
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
  ];
}
