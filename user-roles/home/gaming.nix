{ lib, pkgs, settings, ... }:
let
  gamingCfg = settings.gaming or { };
in
{
  # Keep the gaming role lean by making the optional FOSS game bundle explicit.
  j0nix.user.software.packages = with pkgs; [
    nethack
  ] ++ lib.optionals (gamingCfg.openSourceGames or false) [
    supertuxkart
    supertux
    zeroad
    wesnoth
    xonotic
    luanti
    airshipper
    pioneer
  ];

  # Add nethack configuration file
  home.file.".nethackrc" = {
    text = ''
      OPTIONS=windowtype:curses
      OPTIONS=popup_dialog
      OPTIONS=splash_screen
      OPTIONS=guicolor
      OPTIONS=perm_invent
    '';
  };
}
