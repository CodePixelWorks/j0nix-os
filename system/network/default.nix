{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.network;
  wifiManagerDesktopEntry = pkgs.makeDesktopItem {
    name = "j0nix-wifi-manager";
    desktopName = "Wi-Fi Manager";
    genericName = "Network Connections";
    comment = "Manage Wi-Fi and Ethernet connections";
    exec = "nm-connection-editor";
    icon = "network-wireless";
    categories = [ "Network" "Settings" ];
    terminal = false;
  };
in
{
  options.j0nix.desktop.network = {
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "nixos";
    };

    networkmanager.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    wifiManagerGui.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install NetworkManager GUI tools (nm-applet / nm-connection-editor).";
    };

    wifiManagerGui.desktopEntry.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install a visible Wi-Fi Manager launcher entry with icon.";
    };

    wifi = {
      powersave = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Wi-Fi power saving (can reduce throughput/latency).";
      };

      backend = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "iwd" "wpa_supplicant" ]);
        default = null;
        description = "Override NetworkManager Wi-Fi backend (iwd or wpa_supplicant).";
      };

      scanRandMacAddress = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Randomize MAC address during scans (can delay association on some APs).";
      };

      secretsAgent = lib.mkOption {
        type = lib.types.enum [ "nm-applet" "none" ];
        default = "nm-applet";
        description = "Secrets agent to supply Wi-Fi credentials to NetworkManager.";
      };
    };

    tailscale = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      installCli = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };

    resolver = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the local development DNS resolver.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Loopback address where the local resolver listens.";
      };

      wildcardAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Target IP returned for wildcard development domains.";
      };

      upstreamServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "1.1.1.1"
          "1.0.0.1"
        ];
        description = "Upstream DNS servers used for non-local lookups.";
      };

      wildcardDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domain suffixes resolved via wildcard records, for example `test` or `dev.local`.";
      };

      records = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Exact host-to-IP mappings served by the local resolver.";
      };
    };
  };

  config =
    let
      resolverHasEntries = cfg.resolver.wildcardDomains != [ ] || cfg.resolver.records != { };
      resolverEnabled = cfg.resolver.enable || resolverHasEntries;
      resolverAddressRecords =
        (map (domain: "/.${domain}/${cfg.resolver.wildcardAddress}") cfg.resolver.wildcardDomains)
        ++ (lib.mapAttrsToList (host: ip: "/${host}/${ip}") cfg.resolver.records);
    in
    {
    networking.hostName = cfg.hostName;
    networking.networkmanager.enable = cfg.networkmanager.enable;
    networking.networkmanager.dns = lib.mkIf resolverEnabled "systemd-resolved";
    services.tailscale.enable = cfg.tailscale.enable;
    services.resolved.enable = resolverEnabled;
    services.resolved.extraConfig = lib.mkIf resolverEnabled ''
      DNS=${cfg.resolver.listenAddress}
      Domains=~.
    '';

    services.dnsmasq = lib.mkIf resolverEnabled {
      enable = true;
      settings = {
        domain-needed = true;
        bogus-priv = true;
        no-resolv = true;
        bind-interfaces = true;
        "listen-address" = cfg.resolver.listenAddress;
        server = cfg.resolver.upstreamServers;
        address = resolverAddressRecords;
      };
    };

    networking.networkmanager.wifi = {
      powersave = cfg.wifi.powersave;
      backend = lib.mkIf (cfg.wifi.backend != null) cfg.wifi.backend;
      scanRandMacAddress = cfg.wifi.scanRandMacAddress;
    };

    programs.nm-applet.enable =
      cfg.networkmanager.enable && cfg.wifi.secretsAgent == "nm-applet";

    j0nix.software.systemPackages =
      lib.optionals cfg.networkmanager.enable [
        pkgs.networkmanager
      ]
      ++ lib.optionals (cfg.networkmanager.enable && cfg.wifiManagerGui.enable) [
        pkgs.networkmanagerapplet
      ]
      ++ lib.optionals (cfg.networkmanager.enable && cfg.wifiManagerGui.enable && cfg.wifiManagerGui.desktopEntry.enable) [
        wifiManagerDesktopEntry
      ]
      ++ lib.optionals (cfg.tailscale.enable && cfg.tailscale.installCli) [
        pkgs.tailscale
      ];

    assertions = [
      {
        assertion = !resolverEnabled || cfg.resolver.upstreamServers != [ ];
        message = "j0nix.desktop.network.resolver.upstreamServers must not be empty when the local resolver is enabled.";
      }
    ];
  };
}
