{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  perfCfg = gaming.performance or { };
in
lib.mkIf enabled {
  programs.gamemode = lib.mkIf (perfCfg.gamemode or true) {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 20;
      };
    };
  };

  environment.systemPackages =
    lib.optionals (perfCfg.gamescope or true) [
      pkgs.gamescope
    ]
    ++ lib.optionals (perfCfg.mangohud or true) [
      (pkgs.mangohud.override { lowerBitnessSupport = true; })
    ];
}
