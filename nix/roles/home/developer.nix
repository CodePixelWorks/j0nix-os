{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    jq
    ripgrep
    fd
    bat
    eza
    lazygit
    just
    direnv
    httpie
    zellij
  ];
}
