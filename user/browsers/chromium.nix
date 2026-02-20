{ pkgs, ... }:
{
  programs.chromium = {
    enable = true;
  };

  home.packages = [
    pkgs.chromium
  ];
}
