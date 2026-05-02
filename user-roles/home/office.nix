{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    libreoffice-fresh
    thunderbird
  ];
}
