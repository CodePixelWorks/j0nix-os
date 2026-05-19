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
      localDefault = baseDir + "/user/editors/${editor}/default.nix";
      localFile = baseDir + "/user/editors/${editor}.nix";
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
      browserFile = baseDir + "/user/browsers/${browser}.nix";
    in
    if builtins.pathExists browserFile then browserFile else null;

  mkWmModule =
    wm:
    let
      wmDefault = baseDir + "/user/wm/${wm}/default.nix";
      wmFile = baseDir + "/user/wm/${wm}.nix";
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
      roleModule = baseDir + "/user-roles/home/${role}.nix";
    in
    if builtins.pathExists roleModule then roleModule else null;

  shellModule = baseDir + "/user/shells/${userSettings.shell}.nix";
  resolvedShellModule =
    if builtins.pathExists shellModule then shellModule else baseDir + "/user/shells/zsh.nix";

  wmShellModule = baseDir + "/user/wm/hyprland/shells/${userSettings.wmShell}";
  wmShellExists = builtins.pathExists wmShellModule;
  wmNeedsShell = builtins.elem userSettings.defaultWMS [
    "hyprland"
    "mangowc"
    "niri"
  ];
  wmShellLauncherModule = baseDir + "/user/wm/shell-launcher.nix";
  wmShellCommonModule = baseDir + "/user/wm/hyprland/shells/common/default.nix";

  wmModules = lib.filter (m: m != null) [ (mkWmModule userSettings.defaultWMS) ];
  editorModules = lib.filter (m: m != null) (map mkEditorModule userSettings.editors);
  browserModules = lib.filter (m: m != null) (map mkBrowserModule userSettings.browsers);
  roleNames = userSettings.roles or [ ];
  roleHomeModules = lib.filter (m: m != null) (map mkUserRoleHomeModule roleNames);
  missingRoleNames = lib.filter (role: (mkUserRoleHomeModule role) == null) roleNames;
  devModule = baseDir + "/user/dev/default.nix";
  devEnabled = (userSettings.dev or { }).enable or true;
in
[
  (profileDir + "/home.nix")
  (baseDir + "/user/software/default.nix")
  (baseDir + "/user/custom/default.nix")
  (baseDir + "/user/security/secrets.nix")
  resolvedShellModule
  (baseDir + "/user/session-default.nix")
  (baseDir + "/user/programs/default.nix")
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
          message = "Unknown user role(s) for ${userSettings.username}: ${lib.concatStringsSep ", " missingRoleNames}. Expected modules under user-roles/home/<role>.nix";
        }
      ]
      ++ lib.optional wmNeedsShell {
        assertion = wmShellExists;
        message = "Unknown wmShell '${userSettings.wmShell}'. Valid examples: ags, caelestia-shell, noctalia-shell, none. dank-material-shell is temporarily broken during the Hyprland Lua migration.";
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
++ lib.optional (wmNeedsShell && wmShellExists) wmShellModule
