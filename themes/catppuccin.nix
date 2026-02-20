{ pkgs, ... }:
{
  themeName = "catppuccin";
  fontPkg = pkgs.nerd-fonts.jetbrains-mono;
  shell = "dank-material-shell";
}
