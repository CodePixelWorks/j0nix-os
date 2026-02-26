{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    remmina
    signal-desktop
    telegram-desktop
  ];
}
