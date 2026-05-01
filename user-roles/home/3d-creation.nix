{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    blender
    inkscape
    gimp
  ];
}
