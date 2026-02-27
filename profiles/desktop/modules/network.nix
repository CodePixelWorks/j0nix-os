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
    wifi = {
      powersave = network.wifi.powersave or false;
      backend = network.wifi.backend or null;
      secretsAgent = network.wifi.secretsAgent or "nm-applet";
    };
    tailscale = {
      enable = tailscaleCfg.enable or false;
      installCli = true;
    };
  };
}
