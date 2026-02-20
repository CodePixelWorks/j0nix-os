{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  launchers = gaming.launchers or { };
  protonCfg = gaming.proton or { };
in
lib.mkIf enabled {
  programs.lutris = lib.mkIf (launchers.lutris or true) {
    enable = true;
    protonPackages = lib.optionals (protonCfg.ge or true) [ pkgs.proton-ge-bin ];
    extraPackages = with pkgs; [
      mangohud
      winetricks
      gamescope
      gamemode
      umu-launcher
    ];
  };

  home.packages =
    lib.optionals (launchers.heroic or true) (
      if pkgs ? heroic then [ pkgs.heroic ] else [ ]
    )
    ++ lib.optionals (launchers.bottles or true) [ pkgs.bottles ]
    ++ lib.optionals (launchers.wineGui or false) [ pkgs.wineWowPackages.waylandFull ];
}
