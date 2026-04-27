{ lib, pkgs, settings, ... }:
let
  users = builtins.attrValues (settings.userSettings or { });
  userFusionEnabled = lib.any
    (user: (((user.programs or { }).autodeskFusion or { }).enable or false))
    users;
  globalFusionEnabled = (((settings.programs or { }).autodeskFusion or { }).enable or false);
  enabled = globalFusionEnabled || userFusionEnabled;
in
{
  config = lib.mkIf enabled {
    j0nix.software.systemPackages = [
      pkgs.autodesk-fusion-linux
      pkgs.cabextract
      pkgs.p7zip
      pkgs.winetricks
      (pkgs.wineWow64Packages.stagingFull or pkgs.wineWow64Packages.staging)
      pkgs.xdg-utils
      pkgs.desktop-file-utils
    ];
  };
}
