{ ... }:
{
  imports = [
    ./identity.nix
    ./environment.nix
    ./polkit-agent.nix
    ./theme.nix
    ./xdg.nix
    ./udiskie.nix
  ];
}
