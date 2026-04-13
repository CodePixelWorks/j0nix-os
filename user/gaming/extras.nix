{
  config,
  lib,
  pkgs,
  ...
}:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  extra = gaming.extras or { };
  asfEnabled = extra.archisteamfarm or true;
in
lib.mkIf enabled {
  j0nix.user.software.packages =
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
    ++ lib.optionals (extra.nethack or false) [ pkgs.nethack ]
    ++ lib.optionals asfEnabled [ pkgs.ArchiSteamFarm ];

  home.file.".nethackrc" = lib.mkIf (extra.nethack or false) {
    text = ''
      OPTIONS=windowtype:curses
      OPTIONS=popup_dialog
      OPTIONS=splash_screen
      OPTIONS=guicolor
      OPTIONS=perm_invent
    '';
  };

  xdg.desktopEntries.archisteamfarm = lib.mkIf asfEnabled {
    name = "ArchiSteamFarm";
    exec = "${lib.getExe pkgs.ArchiSteamFarm} --path ${config.home.homeDirectory}/.config/archisteamfarm";
    comment = "Steam card idling bot";
    categories = [
      "Game"
      "Utility"
    ];
    icon = "steam";
  };
}
