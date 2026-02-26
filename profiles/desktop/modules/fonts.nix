{ pkgs, settings, ... }:
{
  j0nix.desktop.fonts.packages = [
    settings.themeDetails.fontPkg
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
  ];
}
