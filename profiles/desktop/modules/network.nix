{ settings, ... }:
let
  network = settings.network or { };
  tailscaleCfg = network.tailscale or { };
in
{
  j0nix.desktop.network = {
    hostName = settings.hostname;
    networkmanager.enable = true;
    wifiManagerGui = {
      enable = network.wifiManagerGui.enable or true;
      desktopEntry.enable = network.wifiManagerGui.desktopEntry.enable or true;
    };
    tailscale = {
      enable = tailscaleCfg.enable or false;
      installCli = true;
    };
  };
}
