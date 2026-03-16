{ lib, pkgs, settings, ... }:
let
  userSettings = builtins.attrValues (settings.userSettings or { });
  windowsAppsEnable =
    lib.any
      (userCfg:
        lib.elem "fusion360-proton" ((((userCfg.programs or { }).windowsApps or { }).packages or [ ])))
      userSettings;
  fusionEnable =
    lib.any (userCfg: (((userCfg.programs or { }).fusion360 or { }).enable or false)) userSettings;
  enabled = windowsAppsEnable || fusionEnable;
in
{
  config = lib.mkIf enabled {
    j0nix.software.systemPackages = with pkgs; [
      gawk
      mokutil
    ];

    hardware.spacenavd.enable = true;
  };
}
