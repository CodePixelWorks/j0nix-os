{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).betterdiscord or { };
  enabled = cfg.enable or true;
  installDiscord = cfg.installDiscord or true;
in
lib.mkIf enabled {
  home.packages =
    [ pkgs.betterdiscordctl ]
    ++ lib.optionals installDiscord [ pkgs.discord ];
}
