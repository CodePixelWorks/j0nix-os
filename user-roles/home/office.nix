{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    libreoffice
    thunderbird
    evince
  ];
}
