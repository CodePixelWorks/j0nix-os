{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    onlyoffice-desktopeditors
    thunderbird
  ];
}
