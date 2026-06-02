{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    digikam
    rapidraw
    upscayl
  ];
}
