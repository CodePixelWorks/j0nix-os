{
  lib,
  settings,
  hyprlandCfg,
}:
let
  sessionEnvCfg = hyprlandCfg.sessionEnv or { };
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
    APP2UNIT_SLICES =
      sessionEnvCfg.app2unitSlices
        or "a=app-graphical.slice b=background-graphical.slice s=session-graphical.slice";
  };
  sessionEnv =
    sessionEnvBase
    // lib.optionalAttrs ((sessionEnvCfg.qtPlatformTheme or null) != null) {
      QT_QPA_PLATFORMTHEME = sessionEnvCfg.qtPlatformTheme;
    }
    // (sessionEnvCfg.extra or { });
in
{
  inherit sessionEnvCfg sessionEnv;
  sessionEnvLines = lib.mapAttrsToList (name: value: "env = ${name},${toString value}") sessionEnv;
  importedSessionEnvNames = builtins.attrNames sessionEnv;
  importSessionEnvArgs = lib.concatStringsSep " \\\n        " (
    map lib.escapeShellArg (builtins.attrNames sessionEnv)
  );
  uwsmEnvText =
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (toString value)}") sessionEnv
    )
    + "\n";
}
