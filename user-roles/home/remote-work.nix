{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    element-desktop
    remmina
    signal-desktop
    telegram-desktop
  ];
}
