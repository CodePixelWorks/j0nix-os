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
  monitorToolsCfg = hyprlandCfg.monitorTools or { };
  installNwgDisplays = monitorToolsCfg.installNwgDisplays or false;
  nwgDisplaysPackage =
    if installNwgDisplays && builtins.hasAttr "nwg-displays" pkgs then pkgs."nwg-displays" else null;
  sessionEnvModule = import ./config/session-env.nix { inherit lib settings hyprlandCfg; };
  hyprlandDebug = hyprlandCfg.debug or { };
  inherit (sessionEnvModule)
    sessionEnv
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
    headlessOutputNames
    initialOutputStates
    initialOutputStateNames
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
  hyprlandWindowRules = import ./config/window-rules.nix { inherit lib; };
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
    toggleableOutputBindLines = [ ];
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
  hyprlandStartupCommands =
    [
      (lib.getExe importSessionEnvScript)
      (lib.getExe startGraphicalSessionTargetScript)
      (lib.getExe' pkgs.awww "awww-daemon")
      (lib.getExe hyprlandStartupAppsScript)
    ]
    ++ lib.optionals (shellStartupCommand != null) [ shellStartupCommand ]
    ++ lib.optionals (dmsOverviewEnabled && dmsOverviewAutostart) [ "${homeBinDir}/wm-overview-start" ]
    ++ lib.optionals keybindDiagnosticsEnable [ (lib.getExe hyprlandKeybindDiagnosticsStartupScript) ];
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
    swwwDaemonCommand = lib.getExe' pkgs.awww "awww-daemon";
    startupAppsCommand = lib.getExe hyprlandStartupAppsScript;
    keybindDiagnosticsStartupCommand = lib.getExe hyprlandKeybindDiagnosticsStartupScript;
    managedMonitorLines = managedConfigMonitorLines;
  };
  hyprlandFragmentFiles = lib.mapAttrs' (
    path: text: lib.nameValuePair path { inherit text; }
  ) hyprlandFragments.files;
  hyprlandLuaFragments = import ./config/lua-fragments.nix {
    inherit
      lib
      settings
      hyprlandKeybinds
      sessionEnv
      useUWSM
      ;
    profileDetails = filteredProfileDetails;
    inherit hyprlandWindowRules;
    startupCommands = hyprlandStartupCommands;
    managedMonitorLines = managedConfigMonitorLines;
  };
  hyprlandLuaFragmentFiles = lib.mapAttrs' (
    path: text: lib.nameValuePair path { inherit text; }
  ) hyprlandLuaFragments.files;
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
      awww
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

  xdg.configFile =
    hyprlandFragmentFiles
    // hyprlandLuaFragmentFiles
    // lib.optionalAttrs useUWSM {
      "uwsm/env".text = uwsmEnvText;
    }
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
      assertion = lib.all (name: name != "") initialOutputStateNames;
      message = "settings.hyprland.initialOutputStates entries must have a non-empty name.";
    }
    {
      assertion =
        (builtins.length initialOutputStateNames) == (builtins.length (lib.unique initialOutputStateNames));
      message = "settings.hyprland.initialOutputStates names must be unique.";
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
