{
  baseDir,
  lib,
  profileDir,
}:
userSettings:
let
  mkEditorModule =
    editor:
    let
      localDefault = baseDir + "/nix/user/editors/${editor}/default.nix";
      localFile = baseDir + "/nix/user/editors/${editor}.nix";
    in
    if builtins.pathExists localDefault then
      localDefault
    else if builtins.pathExists localFile then
      localFile
    else
      null;

  mkBrowserModule =
    browser:
    let
      browserFile = baseDir + "/nix/user/browsers/${browser}.nix";
    in
    if builtins.pathExists browserFile then browserFile else null;

  mkWmModule =
    wm:
    let
      wmDefault = baseDir + "/nix/user/wm/${wm}/default.nix";
      wmFile = baseDir + "/nix/user/wm/${wm}.nix";
    in
    if builtins.pathExists wmDefault then
      wmDefault
    else if builtins.pathExists wmFile then
      wmFile
    else
      null;

  mkUserRoleHomeModule =
    role:
    let
      roleModule = baseDir + "/nix/roles/home/${role}.nix";
    in
    if builtins.pathExists roleModule then roleModule else null;

  mkProgramModule =
    program:
    let
      path = baseDir + "/nix/user/programs/${program}";
    in
    if builtins.pathExists path then path else null;

  shellModule = baseDir + "/nix/user/shells/${userSettings.shell}.nix";
  resolvedShellModule =
    if builtins.pathExists shellModule then shellModule else baseDir + "/nix/user/shells/zsh.nix";
  terminalMultiplexerModule = baseDir + "/nix/user/shells/multiplexer.nix";

  wmShellModule = baseDir + "/nix/user/wm/hyprland/shells/${userSettings.wmShell}";
  wmShellExists = builtins.pathExists wmShellModule;
  wmNeedsShell = builtins.elem userSettings.defaultWMS [
    "hyprland"
    "mangowc"
    "niri"
  ];
  wmShellLauncherModule = baseDir + "/nix/user/wm/shell-launcher.nix";
  wmShellCommonModule = baseDir + "/nix/user/wm/hyprland/shells/common/default.nix";

  wmModules = lib.filter (m: m != null) [ (mkWmModule userSettings.defaultWMS) ];
  editorModules = lib.filter (m: m != null) (map mkEditorModule userSettings.editors);
  browserModules = lib.filter (m: m != null) (map mkBrowserModule userSettings.browsers);
  roleNames = userSettings.roles or [ ];
  roleHomeModules = lib.filter (m: m != null) (map mkUserRoleHomeModule roleNames);
  missingRoleNames = lib.filter (role: (mkUserRoleHomeModule role) == null) roleNames;
  devModule = baseDir + "/nix/user/dev/default.nix";
  devEnabled = (userSettings.dev or { }).enable or true;
  programNames = userSettings.homePrograms or [ ];
  programModulePaths = lib.filter (m: m != null) (map mkProgramModule programNames);
  missingProgramNames = lib.filter (program: (mkProgramModule program) == null) programNames;
in
[
  (profileDir + "/home.nix")
  (baseDir + "/nix/user/software/default.nix")
  (baseDir + "/nix/user/custom/default.nix")
  (baseDir + "/nix/user/security/secrets.nix")
  resolvedShellModule
  (baseDir + "/nix/user/session-default.nix")
  terminalMultiplexerModule
  (
    { lib, ... }:
    {
      assertions = [
        {
          assertion = builtins.elem userSettings.defaultWMS [
            "hyprland"
            "gnome"
            "mangowc"
            "niri"
          ];
          message = "userSettings.<name>.defaultWMS must be one of: hyprland, gnome, mangowc, niri";
        }
        {
          assertion = !(userSettings._userOverride ? wms);
          message = "Per-user wm list is deprecated. Use userSettings.<name>.defaultWMS only.";
        }
        {
          assertion = !(userSettings._userOverride ? defaultSession);
          message = "Per-user defaultSession is deprecated. Use userSettings.<name>.defaultWMS and global settings.hyprland.useUWSM.";
        }
        {
          assertion = missingRoleNames == [ ];
          message = "Unknown user role(s) for ${userSettings.username}: ${lib.concatStringsSep ", " missingRoleNames}. Expected modules under nix/roles/home/<role>.nix";
        }
        {
          assertion = missingProgramNames == [ ];
          message = "Unknown program module(s) for ${userSettings.username}: ${lib.concatStringsSep ", " missingProgramNames}. Expected directories under nix/user/programs/";
        }
      ]
      ++ lib.optional wmNeedsShell {
        assertion = wmShellExists;
        message = "Unknown wmShell '${userSettings.wmShell}'. Valid examples: ags, caelestia-shell, dank-material-shell, noctalia-shell, none.";
      };
    }
  )
]
++ lib.optional wmNeedsShell wmShellCommonModule
++ lib.optional wmNeedsShell wmShellLauncherModule
++ wmModules
++ editorModules
++ browserModules
++ roleHomeModules
++ lib.optional (devEnabled && builtins.pathExists devModule) devModule
++ programModulePaths
++ lib.optional (wmNeedsShell && wmShellExists) wmShellModule
