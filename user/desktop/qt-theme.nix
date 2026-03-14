{ lib, pkgs, settings, ... }:
let
  hyprlandCfg = settings.hyprland or { };
  sessionEnvCfg = hyprlandCfg.sessionEnv or { };
  platformTheme = sessionEnvCfg.qtPlatformTheme or null;
  hasValue = value: value != null && value != "";

  qtThemePackage =
    if platformTheme == null then
      null
    else if platformTheme == "qtengine" then
      if pkgs ? qtengine then pkgs.qtengine else null
    else if platformTheme == "qt6ct" then
      if pkgs ? qt6ct then pkgs.qt6ct else null
    else if platformTheme == "qt5ct" then
      if pkgs ? qt5ct then pkgs.qt5ct else null
    else
      null;
in
{
  j0nix.user.software.packages = lib.optional (qtThemePackage != null) qtThemePackage;

  home.sessionVariables = lib.optionalAttrs (hasValue platformTheme) {
    QT_QPA_PLATFORMTHEME = platformTheme;
  };

  assertions = [
    {
      assertion = platformTheme == null || builtins.elem platformTheme [ "qtengine" "qt6ct" "qt5ct" ];
      message = "settings.hyprland.sessionEnv.qtPlatformTheme must be one of: qtengine, qt6ct, qt5ct, null.";
    }
    {
      assertion = !hasValue platformTheme || qtThemePackage != null;
      message = "The configured settings.hyprland.sessionEnv.qtPlatformTheme package is not available in the current nixpkgs set.";
    }
  ];
}
