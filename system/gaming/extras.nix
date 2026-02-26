{ config, lib, pkgs, ... }:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  protonCfg = gaming.proton or { };
  extraCfg = gaming.extras or { };
in
lib.mkIf enabled {
  environment.systemPackages =
    lib.optionals (protonCfg.updater or true) [
      pkgs.protonup-qt
    ]
    ++ lib.optionals (extraCfg.umuLauncher or true) [
      pkgs.umu-launcher
    ]
    ++ lib.optionals (extraCfg.nethack or false) [
      pkgs.nethack
    ];
}
