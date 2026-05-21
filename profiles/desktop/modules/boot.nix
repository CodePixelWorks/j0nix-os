{ lib, pkgs, settings, ... }:
let
  bootCfg = settings.boot or { };
  splashCfg = bootCfg.splash or { };
  splashEnabled = splashCfg.enable or false;
  hasAdiPlymouthThemes = pkgs ? adi1090x-plymouth-themes;
in
{
  j0nix.desktop.boot.splash.themePackages =
    lib.optionals (splashEnabled && hasAdiPlymouthThemes) [ pkgs.adi1090x-plymouth-themes ];
}
