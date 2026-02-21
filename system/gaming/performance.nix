{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  perfCfg = gaming.performance or { };
  gamemodeRenice = perfCfg.gamemodeRenice or (-10);
in
lib.mkIf enabled {
  programs.gamemode = lib.mkIf (perfCfg.gamemode or true) {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        # Negative nice gives game processes more CPU priority.
        renice = gamemodeRenice;
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

  assertions = [
    {
      assertion = gamemodeRenice >= -20 && gamemodeRenice <= 19;
      message = "settings.gaming.performance.gamemodeRenice must be between -20 and 19";
    }
  ];
}
