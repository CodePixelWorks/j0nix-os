{ lib, pkgs, settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "appimage";
  bambuAppImagePackage = pkgs.callPackage ../../user/programs/bambulab/appimage-package.nix { };
in
{
  j0nix.user.software.packages = lib.optionals (provider == "appimage") [
    bambuAppImagePackage
  ];
}
