{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    gws
    onlyoffice-desktopeditors
    thunderbird
  ];
}
