{ profileMeta, settings, ... }:
let
  network = settings.network or { };
  tailscaleCfg = network.tailscale or { };
  resolverCfg = network.resolver or { };
  routingCfg = network.routing or { };
  preferWiredCfg = routingCfg.preferWired or { };
in
{
  j0nix.desktop.network = {
    hostName = profileMeta.hostname;
    networkmanager.enable = network.networkmanager.enable or true;
    wifiManagerGui = {
      enable = network.wifiManagerGui.enable or true;
      desktopEntry.enable = network.wifiManagerGui.desktopEntry.enable or true;
    };
    wifi = {
      powersave = network.wifi.powersave or false;
      backend = network.wifi.backend or null;
      scanRandMacAddress = network.wifi.scanRandMacAddress or false;
      secretsAgent = network.wifi.secretsAgent or "nm-applet";
    };
    tailscale = {
      enable = tailscaleCfg.enable or false;
      installCli = true;
    };
    resolver = {
      enable = resolverCfg.enable or false;
      listenAddress = resolverCfg.listenAddress or "127.0.0.1";
      wildcardAddress = resolverCfg.wildcardAddress or "127.0.0.1";
      upstreamServers = resolverCfg.upstreamServers or [
        "1.1.1.1"
        "1.0.0.1"
      ];
      wildcardDomains = resolverCfg.wildcardDomains or [ ];
      records = resolverCfg.records or { };
    };
    routing.preferWired = {
      enable = preferWiredCfg.enable or true;
      ethernetRouteMetric = preferWiredCfg.ethernetRouteMetric or 100;
      wifiRouteMetric = preferWiredCfg.wifiRouteMetric or 600;
      ethernetAutoconnectPriority = preferWiredCfg.ethernetAutoconnectPriority or 100;
      wifiAutoconnectPriority = preferWiredCfg.wifiAutoconnectPriority or 10;
    };
  };
}
