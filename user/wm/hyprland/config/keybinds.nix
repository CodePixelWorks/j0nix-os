{
  lib,
  settings,
  homeBinDir,
  isCaelestiaShell,
  hyprctlExec,
  appExec,
  launcherAppExec,
  preferredTerminalCmd,
  preferredFileManager,
  layoutToggleBind,
  dmsOverviewEnabled,
  overviewToggleBind,
  keybindDiagnosticsEnable,
  keepassEnabled,
  keepassWorkspaceEnable,
  keepassToggleBind,
  minimizerEnabled,
  minimizerToggleBind,
  minimizerRestoreBind,
  minimizerMenuBind,
  minimizerToggleCommand,
  minimizerRestoreCommand,
  minimizerMenuCommand,
  keybindHelpCommand,
  toggleableOutputBindLines,
  workspaceSwitchBinds,
  workspaceMoveBinds,
}:
let
  # ---------------------------------------------------------------------------
  # Core keybinds (navigation, window management, media, etc)
  # ---------------------------------------------------------------------------
  coreBindsModule = import ./keybinds/core.nix {
    inherit lib homeBinDir appExec preferredTerminalCmd keybindHelpCommand;
    inherit layoutToggleBind overviewToggleBind dmsOverviewEnabled;
    inherit keepassEnabled keepassWorkspaceEnable keepassToggleBind;
    inherit minimizerEnabled minimizerToggleBind minimizerRestoreBind minimizerMenuBind;
    inherit minimizerToggleCommand minimizerRestoreCommand minimizerMenuCommand;
    inherit keybindDiagnosticsEnable toggleableOutputBindLines;
    inherit workspaceSwitchBinds workspaceMoveBinds;
  };

  baseHyprKeybinds = {
    bind  = coreBindsModule.baseBind;
    binde = coreBindsModule.baseBinde;
    bindm = coreBindsModule.baseBindm;
    bindl = coreBindsModule.baseBindl;
    bindle = coreBindsModule.baseBindle;
  };

  coreBinds = coreBindsModule.coreBinds;

  # ---------------------------------------------------------------------------
  # Shell-specific keybinds
  # ---------------------------------------------------------------------------
  shellBindsModule = import ./keybinds/shells.nix {
    inherit launcherAppExec settings preferredFileManager;
  };

  shellHyprKeybinds =
    if isCaelestiaShell then
      shellBindsModule.caelestia
    else
      {
        extraConfig = "";
      };

  # ---------------------------------------------------------------------------
  # Merge base + shell binds per type
  # ---------------------------------------------------------------------------
  mergedBindList = key: (baseHyprKeybinds.${key} or [ ]) ++ (shellHyprKeybinds.${key} or [ ]);

  renderBindLines =
    key: entries: lib.concatStringsSep "\n" (map (entry: "${key} = ${entry}") entries);

  # ---------------------------------------------------------------------------
  # Bind type metadata (for documentation/analysis, not rendering)
  # ---------------------------------------------------------------------------
  bindFlagsByType = {
    bind  = { };
    bindi = { ignore_mods = true; };
    bindin = { ignore_mods = true; non_consuming = true; };
    binde = { repeating = true; };
    bindl = { locked = true; };
    bindle = { locked = true; repeating = true; };
    bindr = { release = true; };
    bindm = { mouse = true; };
  };

  hasValue = value: value != null && value != "";
  trim = lib.strings.trim;

  parseBindEntry =
    bindType: entry:
    let
      parts = map trim (lib.splitString "," entry);
      partCount = builtins.length parts;
      mods = if partCount > 0 then builtins.elemAt parts 0 else "";
      key = if partCount > 1 then builtins.elemAt parts 1 else "";
      dispatcher = if partCount > 2 then builtins.elemAt parts 2 else "";
      argument =
        if partCount > 3 then
          lib.concatStringsSep ", " (lib.drop 3 parts)
        else if partCount == 3 then
          null
        else
          null;
    in
    {
      type = bindType;
      inherit mods key dispatcher argument;
      flags = bindFlagsByType.${bindType} or { };
      raw = entry;
    };

  parseBindList = bindType: entries: map (parseBindEntry bindType) entries;

  # ---------------------------------------------------------------------------
  # Effective bind lists (what gets rendered to Hyprland config)
  # ---------------------------------------------------------------------------
  effectiveBindLists = {
    bind  = coreBinds ++ workspaceSwitchBinds ++ workspaceMoveBinds ++ mergedBindList "bind";
    bindi = mergedBindList "bindi";
    bindin = mergedBindList "bindin";
    binde = mergedBindList "binde";
    bindl = mergedBindList "bindl";
    bindle = mergedBindList "bindle";
    bindr = mergedBindList "bindr";
    bindm = mergedBindList "bindm";
  };

  # ---------------------------------------------------------------------------
  # Structured binds (attrsets for introspection/documentation)
  # ---------------------------------------------------------------------------
  structuredBindLists = lib.mapAttrs parseBindList effectiveBindLists;
  structuredBinds = lib.concatLists (lib.attrValues structuredBindLists);
  structuredLuaGlobalBinds = if isCaelestiaShell then [ ] else structuredBinds;
  structuredLuaShellBinds =
    if isCaelestiaShell then structuredBinds else [ ];

  # ---------------------------------------------------------------------------
  # Caelestia submap config
  # ---------------------------------------------------------------------------
  caelestiaSubmapConfig =
    if isCaelestiaShell then
      let
        launcherLines = [
          "bindi = Super, Super_L, global, caelestia:launcher"
          "bindin = Super, catchall, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:272, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:273, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:274, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:275, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:276, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:277, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse_up, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse_down, global, caelestia:launcherInterrupt"
        ];
        renderedLists = lib.concatStringsSep "\n" (
          lib.filter (s: s != "") [
            (renderBindLines "bind"  effectiveBindLists.bind)
            (renderBindLines "bindi" effectiveBindLists.bindi)
            (renderBindLines "binde" effectiveBindLists.binde)
            (renderBindLines "bindl" effectiveBindLists.bindl)
            (renderBindLines "bindle" effectiveBindLists.bindle)
            (renderBindLines "bindr" effectiveBindLists.bindr)
            (renderBindLines "bindm" effectiveBindLists.bindm)
          ]
        );
      in
      ''
        exec = ${hyprctlExec} dispatch submap global
        submap = global
        ${lib.concatStringsSep "\n" launcherLines}
        ${renderedLists}
        submap = reset
      ''
    else
      "";
in
{
  inherit
    shellHyprKeybinds
    effectiveBindLists
    structuredBindLists
    structuredBinds
    structuredLuaGlobalBinds
    structuredLuaShellBinds
    caelestiaSubmapConfig
    ;
}
