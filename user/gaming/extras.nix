{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  extra = gaming.extras or { };
in
lib.mkIf enabled {
  home.packages =
    lib.optionals (extra.openSourceGames or false) [
      pkgs.superTuxKart
      pkgs.superTux
      pkgs.zeroad
      pkgs.wesnoth
      pkgs.xonotic
      pkgs.luanti
      pkgs.airshipper
      pkgs.pioneer
    ]
    ++ lib.optionals (extra.nethack or false) [ pkgs.nethack ];

  home.file.".nethackrc" = lib.mkIf (extra.nethack or false) {
    text = ''
      OPTIONS=windowtype:curses
      OPTIONS=popup_dialog
      OPTIONS=splash_screen
      OPTIONS=guicolor
      OPTIONS=perm_invent
    '';
  };
}
