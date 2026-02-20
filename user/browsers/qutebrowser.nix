{ pkgs, ... }:
{
  programs.qutebrowser.enable = true;
  home.packages = [ pkgs.qutebrowser ];
}
