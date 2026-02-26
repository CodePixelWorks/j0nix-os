{ pkgs, ... }:
let
  bambuAppImagePackage = pkgs.callPackage ../../user/programs/bambulab/appimage-package.nix { };
in
{
  j0nix.user.software.packages = [
    bambuAppImagePackage
  ];
}
