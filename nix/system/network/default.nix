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
  routePreferenceScript = pkgs.writeShellApplication {
    name = "j0nix-network-route-preference";
    runtimeInputs = [
      pkgs.networkmanager
      pkgs.coreutils
    ];
    text = ''
      set -eu

      ethernet_metric=${toString cfg.routing.preferWired.ethernetRouteMetric}
      wifi_metric=${toString cfg.routing.preferWired.wifiRouteMetric}
      ethernet_priority=${toString cfg.routing.preferWired.ethernetAutoconnectPriority}
      wifi_priority=${toString cfg.routing.preferWired.wifiAutoconnectPriority}

      sync_device_type() {
        local device_type="$1"
        local route_metric="$2"
        local autoconnect_priority="$3"

        nmcli -t -f DEVICE,TYPE,STATE device status | while IFS=: read -r device current_type state; do
          [ "$current_type" = "$device_type" ] || continue
          [ "$state" = "connected" ] || continue
          [ -n "$device" ] || continue

          connection="$(${pkgs.networkmanager}/bin/nmcli -g GENERAL.CONNECTION device show "$device" 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 || true)"
          [ -n "$connection" ] || continue
          [ "$connection" != "--" ] || continue

          current_ipv4_metric="$(${pkgs.networkmanager}/bin/nmcli -g ipv4.route-metric connection show "$connection" 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 || true)"
          current_ipv6_metric="$(${pkgs.networkmanager}/bin/nmcli -g ipv6.route-metric connection show "$connection" 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 || true)"
          current_priority="$(${pkgs.networkmanager}/bin/nmcli -g connection.autoconnect-priority connection show "$connection" 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 || true)"

          if [ "$current_ipv4_metric" != "$route_metric" ] || [ "$current_ipv6_metric" != "$route_metric" ] || [ "$current_priority" != "$autoconnect_priority" ]; then
            ${pkgs.networkmanager}/bin/nmcli connection modify "$connection" \
              ipv4.route-metric "$route_metric" \
              ipv6.route-metric "$route_metric" \
              connection.autoconnect-priority "$autoconnect_priority" >/dev/null 2>&1 || true
            ${pkgs.networkmanager}/bin/nmcli device reapply "$device" >/dev/null 2>&1 || true
          fi
        done
      }

      sync_device_type ethernet "$ethernet_metric" "$ethernet_priority"
      sync_device_type wifi "$wifi_metric" "$wifi_priority"
    '';
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

    routing.preferWired = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Prefer Ethernet over Wi-Fi by applying lower route metrics and higher autoconnect priority.";
      };

      ethernetRouteMetric = lib.mkOption {
        type = lib.types.ints.positive;
        default = 100;
        description = "Route metric applied to connected Ethernet NetworkManager profiles.";
      };

      wifiRouteMetric = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = "Route metric applied to connected Wi-Fi NetworkManager profiles.";
      };

      ethernetAutoconnectPriority = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Autoconnect priority applied to connected Ethernet NetworkManager profiles.";
      };

      wifiAutoconnectPriority = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Autoconnect priority applied to connected Wi-Fi NetworkManager profiles.";
      };
    };
  };

  config =
    let
      resolverHasEntries = cfg.resolver.wildcardDomains != [ ] || cfg.resolver.records != { };
      resolverEnabled = cfg.resolver.enable || resolverHasEntries;
      recordRouteDomains = builtins.filter (domain: domain != "") (
        lib.mapAttrsToList (
          host: _ip:
          let
            match = builtins.match "[^.]+\\.(.+)" host;
          in
          if match == null then "" else builtins.elemAt match 0
        ) cfg.resolver.records
      );
      resolverRouteDomains = map (domain: "~${domain}") (
        lib.unique (cfg.resolver.wildcardDomains ++ recordRouteDomains)
      );
      resolverAddressRecords =
        (map (domain: "/.${domain}/${cfg.resolver.wildcardAddress}") cfg.resolver.wildcardDomains)
        ++ (lib.mapAttrsToList (host: ip: "/${host}/${ip}") cfg.resolver.records);
    in
    {
    networking.hostName = cfg.hostName;
    networking.networkmanager.enable = cfg.networkmanager.enable;
    networking.networkmanager.dns = lib.mkIf resolverEnabled "systemd-resolved";
    networking.networkmanager.dispatcherScripts = lib.optionals (cfg.networkmanager.enable && cfg.routing.preferWired.enable) [
      {
        source = routePreferenceScript;
        type = "basic";
      }
    ];
    services.tailscale.enable = cfg.tailscale.enable;
    services.resolved.enable = resolverEnabled;
    services.resolved.settings = lib.mkIf resolverEnabled {
      Resolve = {
        DNS = [ cfg.resolver.listenAddress ];
      }
      // lib.optionalAttrs (resolverRouteDomains != [ ]) {
        Domains = resolverRouteDomains;
      };
    };

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

    systemd.services.j0nix-network-route-preference = lib.mkIf (cfg.networkmanager.enable && cfg.routing.preferWired.enable) {
      description = "Apply j0nix preferred Ethernet route metrics";
      after = [ "NetworkManager.service" ];
      wants = [ "NetworkManager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe routePreferenceScript;
      };
    };

    assertions = [
      {
        assertion = !resolverEnabled || cfg.resolver.upstreamServers != [ ];
        message = "j0nix.desktop.network.resolver.upstreamServers must not be empty when the local resolver is enabled.";
      }
    ];
  };
}
