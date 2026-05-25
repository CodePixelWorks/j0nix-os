{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    obs-studio
  ];
}
