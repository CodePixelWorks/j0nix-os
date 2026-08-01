{ lib, pkgs, settings, ... }:
let
  cfg = (settings.stylix or { });
  enabled = cfg.enable or false;
  configuredBase16Scheme = cfg.base16Scheme or null;
  polarity = cfg.polarity or (if (settings.colorSchemePreference or "dark") == "light" then "light" else "dark");
  iconThemeCfg = settings.iconTheme or { };
  iconThemeEnabled = iconThemeCfg.enable or true;
  iconThemePackageKey = iconThemeCfg.package or "papirus";
  iconThemePackage =
    if iconThemePackageKey == "papirus" then
      pkgs.papirus-icon-theme
    else if iconThemePackageKey == "colloid" then
      if pkgs ? "colloid-icon-theme" then pkgs."colloid-icon-theme" else null
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
  stylix = lib.mkIf enabled {
    enable = true;
    autoEnable = true;
    polarity = polarity;
    base16Scheme =
      if configuredBase16Scheme != null then
        configuredBase16Scheme
      else {
        scheme = "j0nix Catppuccin Mocha";
        author = "j0nix";
        base00 = "1e1e2e";
        base01 = "181825";
        base02 = "313244";
        base03 = "45475a";
        base04 = "585b70";
        base05 = "cdd6f4";
        base06 = "f5e0dc";
        base07 = "b4befe";
        base08 = "f38ba8";
        base09 = "fab387";
        base0A = "f9e2af";
        base0B = "a6e3a1";
        base0C = "94e2d5";
        base0D = "89b4fa";
        base0E = "cba6f7";
        base0F = "f2cdcd";
      };
    fonts = {
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = 11;
        desktop = 11;
        popups = 11;
        terminal = 11;
      };
    };
    icons = lib.mkIf (iconThemeEnabled && iconThemePackage != null) {
      enable = true;
      package = iconThemePackage;
      dark = iconThemeCfg.name or "Colloid-Dark";
      light = iconThemeCfg.lightName or "Colloid-Light";
    };
    targets = {
      gtk.enable = true;
      qt = {
        enable = true;
        platform = lib.mkForce "qtct";
      };
      gnome.enable = true;
    };
  };

  assertions = [
    {
      assertion = (!enabled) || builtins.elem polarity [ "light" "dark" ];
      message = "settings.stylix.polarity must be either \"light\" or \"dark\".";
    }
    {
      assertion = (!enabled) || (!iconThemeEnabled) || (iconThemePackage != null);
      message = "settings.iconTheme.package must be one of: colloid, papirus, adwaita, breeze";
    }
  ];
}
