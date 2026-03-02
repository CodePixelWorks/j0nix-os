{ pkgs, ... }:
{
  programs.qutebrowser.enable = true;
  j0nix.user.software.packages = [ pkgs.qutebrowser ];
}
