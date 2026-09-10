{ ... }:
{
  imports = [
    ./identity.nix
    ./environment.nix
    ./polkit-agent.nix
    ./theme.nix
    ./stylix-compat.nix
    ./xdg.nix
    ./udiskie.nix
  ];
}
