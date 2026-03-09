{ pkgs, settings, ... }:
{
  j0nix.desktop.fonts.packages = [
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    settings.themeDetails.fontPkg
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
  ];
}
