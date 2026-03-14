{ lib, pkgs, settings, ... }:
let
  hyprlandCfg = settings.hyprland or { };
  sessionEnvCfg = hyprlandCfg.sessionEnv or { };
  caelestiaThemeCfg = ((settings.programs or { }).caelestia or { }).theme or { };
  platformTheme = sessionEnvCfg.qtPlatformTheme or null;
  hasValue = value: value != null && value != "";
  resolvedPlatformTheme =
    if platformTheme == "qtengine" then "hyprqt6engine" else platformTheme;
  qtScheme = caelestiaThemeCfg.scheme or (settings.theme or "catppuccin");
  qtFlavour = caelestiaThemeCfg.flavour or "mocha";
  qtMode = settings.colorSchemePreference or (caelestiaThemeCfg.mode or "dark");
  useDarklyStyle =
    resolvedPlatformTheme == "hyprqt6engine"
    && qtScheme == "catppuccin"
    && qtFlavour == "mocha";

  qtThemePackage =
    if resolvedPlatformTheme == null then
      null
    else if resolvedPlatformTheme == "hyprqt6engine" then
      if pkgs ? hyprqt6engine then pkgs.hyprqt6engine else null
    else if resolvedPlatformTheme == "qt6ct" then
      if pkgs ? qt6ct then pkgs.qt6ct else null
    else if resolvedPlatformTheme == "qt5ct" then
      if pkgs ? qt5ct then pkgs.qt5ct else null
    else
      null;
  qtStyleOverride =
    if useDarklyStyle && qtMode == "dark" then
      "Darkly"
    else if resolvedPlatformTheme == "hyprqt6engine" then
      "Fusion"
    else
      null;
  qtExtraPackages = lib.optionals useDarklyStyle [ pkgs.darkly-qt6 ];
in
{
  j0nix.user.software.packages =
    lib.optional (qtThemePackage != null) qtThemePackage
    ++ qtExtraPackages;

  home.sessionVariables = lib.optionalAttrs (hasValue resolvedPlatformTheme) {
    QT_QPA_PLATFORMTHEME = resolvedPlatformTheme;
  } // lib.optionalAttrs (hasValue qtStyleOverride) {
    QT_STYLE_OVERRIDE = qtStyleOverride;
  };

  xdg.configFile."hypr/hyprqt6engine.conf" = lib.mkIf (resolvedPlatformTheme == "hyprqt6engine") {
    text = ''
      theme {
        icon_theme=${settings.iconTheme.name or ""}
        style=${if qtStyleOverride != null then qtStyleOverride else "Fusion"}
      }
    '';
  };

  assertions = [
    {
      assertion = platformTheme == null || builtins.elem platformTheme [ "hyprqt6engine" "qtengine" "qt6ct" "qt5ct" ];
      message = "settings.hyprland.sessionEnv.qtPlatformTheme must be one of: hyprqt6engine, qtengine, qt6ct, qt5ct, null.";
    }
    {
      assertion = !hasValue resolvedPlatformTheme || qtThemePackage != null;
      message = "The configured settings.hyprland.sessionEnv.qtPlatformTheme package is not available in the current nixpkgs set.";
    }
  ];
}
