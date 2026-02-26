{ settings, ... }:
let
  network = settings.network or { };
  tailscaleCfg = network.tailscale or { };
in
{
  j0nix.desktop.network = {
    hostName = settings.hostname;
    networkmanager.enable = true;
    tailscale = {
      enable = tailscaleCfg.enable or false;
      installCli = true;
    };
  };
}
