{ ... }:
{
  imports = [
    ./identity.nix
    ./environment.nix
    ./polkit-agent.nix
    ./qt-theme.nix
    ./theme.nix
    ./xdg.nix
    ./udiskie.nix
  ];
}
