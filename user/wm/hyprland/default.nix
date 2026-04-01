{
  config,
  lib,
  pkgs,
  settings,
  inputs,
  ...
}:
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
  launcherPolicy = import ../../../system/lib/app-exec-policy.nix {
    inherit
      lib
      pkgs
      useUWSM
      appExecBackend
      ;
  };
  app2unitExec = launcherPolicy.app2unitExe;
  uwsmExec = launcherPolicy.uwsmExe;
  hyprctlExec = lib.getExe' pkgs.hyprland "hyprctl";
  homeBinDir = "${config.home.profileDirectory}/bin";
  appExec = launcherPolicy.mkExec;
  launcherAppExec = appExec;
  preferredTerminal = settings.preferredTerminal or "kitty";
  preferredTerminalCmd =
    if
      builtins.elem preferredTerminal [
        "gnome-console"
        "gnome console"
      ]
    then
      "kgx"
    else
      preferredTerminal;
  workspaceCountRaw = dmsWorkspaceSettings.count or 10;
  workspaceCount = lib.min 10 (lib.max 1 workspaceCountRaw);
  workspaceKeyPairs = builtins.genList (
    i:
    let
      ws = i + 1;
    in
    {
      workspace = toString ws;
      key = if ws == 10 then "0" else toString ws;
    }
  ) workspaceCount;
  workspaceSwitchBinds = map (
    pair: "$mainMod, ${pair.key}, workspace, ${pair.workspace}"
  ) workspaceKeyPairs;
  workspaceMoveBinds = map (
    pair: "$mainMod SHIFT, ${pair.key}, movetoworkspace, ${pair.workspace}"
  ) workspaceKeyPairs;
  hyprlandCfg = settings.hyprland or { };
  sunshineDisplayTargetBackend = (
    ((settings.sunshine or { }).displayTarget or { }).backend or "hyprland-headless"
  );
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
    if installNwgDisplays && builtins.hasAttr "nwg-displays" pkgs then pkgs."nwg-displays" else null;
  sessionEnv = import ./config/session-env.nix { inherit lib settings hyprlandCfg; };
  hyprlandDebug = hyprlandCfg.debug or { };
  inherit (sessionEnv)
    sessionEnvCfg
    sessionEnvLines
    importSessionEnvArgs
    uwsmEnvText
    ;

  outputs = import ./config/outputs.nix {
    inherit
      lib
      pkgs
      hyprlandCfg
      profileDetails
      ;
    inherit sunshineUsesHeadlessOutput sunshineUsesPhysicalOutput;
  };
  inherit (outputs)
    headlessOutputs
    headlessOutputsWithBindings
    headlessOutputNames
    headlessOutputsAutoEnsure
    headlessOutputsJson
    outputBindings
    outputBindingsWithKeys
    outputBindingNames
    outputBindingIndices
    outputBindingsJson
    initialOutputStates
    initialOutputStateNames
    initialOutputStatesJson
    toggleableOutputs
    toggleableOutputsWithBindings
    toggleableOutputNames
    managedOutputsWithBindings
    managedOutputBindIndices
    toggleableOutputsJson
    ;
  keybindDiag = import ./config/keybind-diagnostics.nix {
    inherit
      lib
      pkgs
      app2unitExec
      uwsmExec
      ;
    hyprlandDebug = hyprlandDebug;
  };
  inherit (keybindDiag)
    keybindDiagnosticsEnable
    keybindDiagnosticsDelaySeconds
    keybindDiagnosticsLogDir
    keybindDiagnosticsProbeScript
    keybindDiagnosticsScript
    ;

  minimizer = import ./config/minimizer.nix { inherit lib pkgs hyprlandCfg; };
  inherit (minimizer)
    minimizerEnabled
    minimizerVariant
    minimizerIsDenis
    minimizerIsOrteip
    minimizerPackage
    minimizerDefaultCommand
    minimizerCommand
    minimizerOrteipCfg
    minimizerOrteipAppId
    minimizerBinds
    minimizerToggleBind
    minimizerRestoreBind
    minimizerMenuBind
    minimizerToggleCommand
    minimizerRestoreCommand
    minimizerMenuCommand
    ;
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
    if hasHyprKcsPackage then appExec (lib.getExe' hyprKcsPackage "hyprkcs") else "false";
  keepassCfg = ((settings.programs or { }).keepassxc or { });
  keepassEnabled = keepassCfg.enable or false;
  keepassWorkspaceCfg = keepassCfg.workspace or { };
  keepassWorkspaceEnable = keepassWorkspaceCfg.enable or true;
  keepassToggleBind = keepassWorkspaceCfg.toggleBind or "$mainMod SHIFT, p";
  toggleableOutputBindLines = lib.concatMap (
    output:
    let
      binds = output.binds or { };
      bindKey = output.bindKey or "";
      outputNameArg = lib.escapeShellArg output.name;
      hasBind = bind: bind != null && bind != "";
      mkBind = bind: command: lib.optional (hasBind bind) "${bind}, exec, ${command}";
    in
    [
      "$mainMod CTRL, ${bindKey}, exec, ${homeBinDir}/wm-monitor-toggle ${outputNameArg}"
      "$mainMod CTRL SHIFT, ${bindKey}, exec, ${homeBinDir}/wm-monitor-restore ${outputNameArg}"
    ]
    ++ (mkBind (binds.toggle or null) "${homeBinDir}/wm-monitor-toggle ${outputNameArg}")
    ++ (mkBind (binds.on or null) "${homeBinDir}/wm-monitor-on ${outputNameArg}")
    ++ (mkBind (binds.off or null) "${homeBinDir}/wm-monitor-off ${outputNameArg}")
    ++ (mkBind (binds.restore or null) "${homeBinDir}/wm-monitor-restore ${outputNameArg}")
  ) managedOutputsWithBindings;
  workspaceOutputBindLines = lib.concatMap (
    output:
    let
      bindKey = output.bindKey or "";
      outputNameArg = lib.escapeShellArg output.name;
    in
    [
      "$mainMod ALT, ${bindKey}, exec, ${homeBinDir}/wm-monitor-workspace-to ${outputNameArg}"
      "$mainMod CTRL ALT, ${bindKey}, exec, ${homeBinDir}/wm-monitor-focused-workspaces-to ${outputNameArg}"
    ]
  ) outputBindingsWithKeys;
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
      workspaceMoveBinds
      ;
    toggleableOutputBindLines = toggleableOutputBindLines ++ workspaceOutputBindLines;
  };
  installRawQuickshell = hyprlandDebug.installRawQuickshell or false;
  shellStartupCommand =
    if selectedShell == "none" then null else appExec "${homeBinDir}/wm-shell-start";
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
  monitorScripts = import ./config/monitor-scripts.nix {
    inherit lib pkgs hyprctlExec;
    inherit
      toggleableOutputsJson
      initialOutputStatesJson
      outputBindingsJson
      headlessOutputsJson
      ;
    hyprlandRuntimeMonitorConfigPath = hyprlandRuntimeMonitorConfigPath;
    homeDirectory = config.home.homeDirectory;
  };
  inherit (monitorScripts)
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
    ;
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
    if enabledByDefault then "${name},${mode},${position},${scale}" else "${name},disable";
  managedConfigMonitorNames = map (output: output.name or "") (
    builtins.filter (
      output: !(builtins.elem (output.name or "") headlessOutputNames)
    ) initialOutputStates
  );
  managedConfigMonitorLines = map initialOutputStateToMonitorLine (
    builtins.filter (
      output: !(builtins.elem (output.name or "") headlessOutputNames)
    ) initialOutputStates
  );
  monitorNameFromLine =
    line:
    let
      match = builtins.match "[[:space:]]*([^,[:space:]]+)[[:space:]]*,.*" line;
    in
    if match == null then line else builtins.elemAt match 0;
  filteredProfileDetails = profileDetails // {
    hyprlandMonitors = builtins.filter (
      line: !(builtins.elem (monitorNameFromLine line) managedConfigMonitorNames)
    ) (profileDetails.hyprlandMonitors or [ ]);
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
  hyprlandFragmentFiles = lib.mapAttrs' (
    path: text: lib.nameValuePair path { inherit text; }
  ) hyprlandFragments.files;
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
in
{
  j0nix.user.software.packages =
    with pkgs;
    [
      hyprlock
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
      assertion = builtins.elem appExecBackend [
        "auto"
        "app2unit"
        "uwsm"
      ];
      message = "settings.hyprland.appExecBackend must be one of: auto, app2unit, uwsm";
    }
    {
      assertion = builtins.isAttrs (sessionEnvCfg.extra or { });
      message = "settings.hyprland.sessionEnv.extra must be an attribute set of environment variables.";
    }
    {
      assertion =
        (sessionEnvCfg.qtPlatformTheme or null) == null || builtins.isString sessionEnvCfg.qtPlatformTheme;
      message = "settings.hyprland.sessionEnv.qtPlatformTheme must be a string or null.";
    }
    {
      assertion = !minimizerEnabled || minimizerCommand != "";
      message = "settings.hyprland.minimizer.command must not be empty when minimizer is enabled.";
    }
    {
      assertion = builtins.elem minimizerVariant [
        "denis"
        "0rteip"
      ];
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
      assertion =
        (builtins.length headlessOutputNames) == (builtins.length (lib.unique headlessOutputNames));
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
      assertion =
        (builtins.length initialOutputStateNames) == (builtins.length (lib.unique initialOutputStateNames));
      message = "settings.hyprland.initialOutputStates names must be unique.";
    }
    {
      assertion =
        (builtins.length outputBindingNames) == (builtins.length (lib.unique outputBindingNames));
      message = "settings.hyprland.outputBindings names must be unique.";
    }
    {
      assertion = lib.all (index: index >= 1 && index <= 10) outputBindingIndices;
      message = "settings.hyprland.outputBindings bindIndex values must be between 1 and 10.";
    }
    {
      assertion =
        (builtins.length outputBindingIndices) == (builtins.length (lib.unique outputBindingIndices));
      message = "settings.hyprland.outputBindings bindIndex values must be unique.";
    }
    {
      assertion = lib.all (name: name != "") toggleableOutputNames;
      message = "settings.hyprland.toggleableOutputs entries must have a non-empty name.";
    }
    {
      assertion =
        (builtins.length toggleableOutputNames) == (builtins.length (lib.unique toggleableOutputNames));
      message = "settings.hyprland.toggleableOutputs names must be unique.";
    }
    {
      assertion = lib.all (index: index >= 1 && index <= 10) managedOutputBindIndices;
      message = "Managed output bindIndex values must be between 1 and 10.";
    }
    {
      assertion =
        (builtins.length managedOutputBindIndices)
        == (builtins.length (lib.unique managedOutputBindIndices));
      message = "Managed output bindIndex values must be unique.";
    }
    {
      assertion = lib.all (
        output:
        !(output.workspaceHandoff.enable or false) || ((output.workspaceHandoff.targetMonitor or "") != "")
      ) toggleableOutputs;
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
