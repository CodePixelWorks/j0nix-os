{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    blender
    krita
    inkscape
    gimp
  ];
}
