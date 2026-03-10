{ config, lib, pkgs, ... }:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  launchers = gaming.launchers or { };
  protonCfg = gaming.proton or { };
  bottlesPkg = pkgs.bottles-j0nix or pkgs.bottles;
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

  j0nix.user.software.packages =
    lib.optionals ((launchers.heroic or true) && heroicPkg != null) [ heroicPkg ]
    ++ lib.optionals (launchers.bottles or true) [ bottlesPkg ]
    ++ lib.optionals (launchers.wineGui or false) [ pkgs.wineWow64Packages.waylandFull ]
    ++ lib.optionals (rockstarEnabled && (pkgs ? protontricks)) [ pkgs.protontricks ];
}
