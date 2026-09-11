{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    signal-desktop
    telegram-desktop
  ];
}
