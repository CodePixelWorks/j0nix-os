{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    mangohud
    goverlay
    protontricks
    lutris
    heroic
  ];
}
