{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).betterdiscord or { };
  enabled = cfg.enable or false;
  installDiscord = cfg.installDiscord or true;
in
lib.mkIf enabled {
  j0nix.user.software.packages =
    [ pkgs.betterdiscordctl ]
    ++ lib.optionals installDiscord [ pkgs.discord ];
}
