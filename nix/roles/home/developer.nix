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
    gws
    google-cloud-sdk
    httpie
    playwright-driver
    crush
    zellij
  ];
}
