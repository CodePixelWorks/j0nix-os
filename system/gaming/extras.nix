{
  config,
  lib,
  pkgs,
  ...
}:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  protonCfg = gaming.proton or { };
  extraCfg = gaming.extras or { };
  asfEnabled = extraCfg.archisteamfarm or true;
in
lib.mkIf enabled {
  j0nix.software.systemPackages =
    lib.optionals (protonCfg.updater or true) [
      pkgs.protonup-qt
    ]
    ++ lib.optionals (extraCfg.umuLauncher or true) [
      pkgs.umu-launcher
    ]
    ++ lib.optionals (extraCfg.nethack or false) [
      pkgs.nethack
    ]
    ++ lib.optionals asfEnabled [
      pkgs.archisteamfarm
    ];

  services.archisteamfarm = lib.mkIf asfEnabled {
    enable = true;
    package = pkgs.archisteamfarm;
    web-ui.enable = true;
    dataDir = "/var/lib/archisteamfarm";
  };
}
