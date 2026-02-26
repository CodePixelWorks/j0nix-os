{ config, lib, pkgs, ... }:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  launchers = gaming.launchers or { };
  protonCfg = gaming.proton or { };
  rockstarEnabled = launchers.rockstar or false;
  heroicPkg =
    if pkgs ? heroic then
      pkgs.heroic
    else if pkgs ? heroic-games-launcher then
      pkgs.heroic-games-launcher
    else
      null;
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
    lib.optionals ((launchers.heroic or true) && heroicPkg != null) [ heroicPkg ]
    ++ lib.optionals (launchers.bottles or true) [ pkgs.bottles ]
    ++ lib.optionals (launchers.wineGui or false) [ pkgs.wineWow64Packages.waylandFull ]
    ++ lib.optionals (rockstarEnabled && (pkgs ? protontricks)) [ pkgs.protontricks ];
}
