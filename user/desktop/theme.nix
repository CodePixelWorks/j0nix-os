{ lib, pkgs, settings, ... }:
let
  iconThemeCfg = settings.iconTheme or { };
  iconThemeEnabled = iconThemeCfg.enable or true;
  iconThemeName = iconThemeCfg.name or "Papirus-Dark";
  iconThemePackageKey = iconThemeCfg.package or "papirus";
  iconThemePackage =
    if iconThemePackageKey == "papirus" then
      pkgs.papirus-icon-theme
    else if iconThemePackageKey == "colloid" then
      if pkgs ? "colloid-icon-theme" then
        pkgs."colloid-icon-theme"
      else
        null
    else if iconThemePackageKey == "adwaita" then
      pkgs.adwaita-icon-theme
    else if iconThemePackageKey == "breeze" then
      if (pkgs ? kdePackages) && (pkgs.kdePackages ? breeze-icons) then
        pkgs.kdePackages.breeze-icons
      else if pkgs ? breeze-icons then
        pkgs.breeze-icons
      else
        null
    else
      null;
in
{
  home.sessionVariables = lib.optionalAttrs iconThemeEnabled {
    XDG_ICON_THEME = iconThemeName;
    GTK_ICON_THEME = iconThemeName;
    QT_ICON_THEME_NAME = iconThemeName;
  };

  gtk = lib.mkIf (iconThemeEnabled && iconThemePackage != null) {
    enable = true;
    iconTheme = {
      name = iconThemeName;
      package = iconThemePackage;
    };
  };

  dconf.settings = lib.mkIf iconThemeEnabled {
    "org/gnome/desktop/interface" = {
      icon-theme = iconThemeName;
      font-name = "Cantarell 11";
      document-font-name = "Cantarell 11";
      monospace-font-name = "JetBrainsMono Nerd Font 11";
    };
  };

  assertions = [
    {
      assertion = (!iconThemeEnabled) || (iconThemePackage != null);
      message = "settings.iconTheme.package must be one of: colloid, papirus, adwaita, breeze";
    }
  ];
}
