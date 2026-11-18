# ts-mux — multiple additional Tailscale networks on one workstation
#
# The system tailscaled (j0nix.desktop.network.tailscale) owns the kernel
# TUN device and system routes for the primary tailnet (Headscale
# ts.j0lab.xyz). A second tailscaled instance cannot take the TUN device
# or the system routing table — so every additional network runs its own
# tailscaled in USERSPACE networking mode with:
#
#   - its own state dir (identity/keys per network)
#   - its own unix socket (CLI isolation)
#   - its own DERP-listening port (0 = random, avoids the UDP 41641 clash)
#   - SOCKS5 + HTTP proxy listeners on loopback for app access
#
# Apps reach machines in network N through that instance's SOCKS5 proxy:
#   ssh -o ProxyCommand='nc -x 127.0.0.1:<socksPort> %h %p' user@host
#   (or proxychains-ng / any SOCKS-aware client)
#
# Login is interactive per network:
#   ts-mux <name> up          # prints the auth URL, browser opens
#   ts-mux <name> status
#   ts-mux <name> down
#
# Networks are declarative under j0nix.desktop.network.tailscaleMux.<name>;
# the daemon starts on boot but stays logged-out until the first `up`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.j0nix.desktop.network.tailscaleMux;
  enabled = cfg != { };

  # Root-side one-shot: sets --operator so the user's CLI can talk to the
  # daemon without sudo (chicken-and-egg: 'tailscale set --operator'
  # itself requires root when no operator exists yet).
  mkOperatorOneshot = name: c: {
    name = "tailscaled-mux-${name}-operator";
    value = {
      description = "Set operator for tailscaled mux instance '${name}'";
      after = [ "tailscaled-mux-${name}.service" ];
      requires = [ "tailscaled-mux-${name}.service" ];
      wantedBy = [ "tailscaled-mux-${name}.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.services.tailscale.package}/bin/tailscale --socket=/run/tailscale-mux-${name}/tailscaled.sock set --operator=${c.operator} ${lib.optionalString c.acceptRoutes "--accept-routes"}";
        RemainAfterExit = true;
      };
    };
  };

  # Persistent tunnel: local loopback listener bridged through the
  # instance's SOCKS5 proxy to host:remotePort. systemd keeps it alive
  # (restart on failure), so games/app clients just use localhost.
  mkTunnelService = net: c: preset: t: {
    name = "ts-tunnel-${net}-${preset}";
    value = {
      description =
        "ts-tunnel '${net}/${preset}': 127.0.0.1:${toString t.localPort} -> ${t.host}:${toString t.remotePort}";
      after = [ "tailscaled-mux-${net}.service" "tailscaled-mux-${net}-operator.service" ];
      requires = [ "tailscaled-mux-${net}.service" ];
      wantedBy = lib.optionals t.autoStart [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${tunnelRelay} ${toString c.socksPort} ${toString t.localPort} ${t.host} ${toString t.remotePort}";
        Restart = "on-failure";
        RestartSec = 3;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
      };
    };
  };

  mkInstance = name: c: {
    name = "tailscaled-mux-${name}";
    value = {
      description = "Tailscale mux instance '${name}' (userspace, extra network)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";
        StateDirectory = "tailscale-mux-${name}";
        RuntimeDirectory = "tailscale-mux-${name}";
        ExecStart = ''
          ${config.services.tailscale.package}/bin/tailscaled \
            --tun=userspace-networking \
            --statedir=/var/lib/tailscale-mux-${name} \
            --socket=/run/tailscale-mux-${name}/tailscaled.sock \
            --port=0 \
            --socks5-server=127.0.0.1:${toString c.socksPort} \
            --outbound-http-proxy-listen=127.0.0.1:${toString c.httpPort}
        '';
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
      };
    };
  };

  # TCP relay: local listener -> the instance's SOCKS5 -> host:port.
  # Pure stdlib asyncio (no dependencies) — for apps without proxy
  # support, e.g. `ts-mux official tunnel 25565 <node> 25565` and then
  # pointing the Minecraft client at localhost:25565.
  tunnelRelay = pkgs.writers.writePython3 "ts-tunnel-relay" { } ''
    ${builtins.readFile ./ts-tunnel-relay.py}
  '';

  # CLI wrapper: ts-mux <name> <up|status|down|...> [args...]
  # Auto-completes the per-instance socket + login-server.
  tsMuxCli = pkgs.writeShellApplication {
    name = "ts-mux";
    runtimeInputs = [ config.services.tailscale.package pkgs.coreutils ];
    text = ''
      set -eu
      if [ $# -lt 2 ]; then
        echo "usage: ts-mux <network> <up|login|status|down|logout|ping|ssh ...>" >&2
        echo "networks: j0lab (primary, system daemon) ${lib.concatStringsSep " " (lib.attrNames cfg)}" >&2
        exit 1
      fi
      name="$1"; shift
      case "$name" in
        ${lib.concatStringsSep "|" (lib.attrNames cfg)}) ;;
        # The primary tailnet (system tailscaled, kernel TUN) is reachable
        # through ts-mux as a read-mostly alias: status/ping/netcheck use
        # the system socket. up/down are rejected — the primary's lifecycle
        # belongs to the declarative services.tailscale config.
        j0lab)
          # Primary tailnet: the system daemon owns the TUN. Everything
          # except its lifecycle is proxied to the system CLI.
          case "$1" in
            up|down|logout)
              echo "j0lab is managed by services.tailscale — use systemctl/systemctl-rebuild" >&2
              exit 1
              ;;
          esac
          shift
          exec tailscale "$@"
          ;;
        *) echo "unknown network: $name" >&2; exit 1 ;;
      esac
      case "$1" in
        tunnels)
          # List configured presets and their service state. Read live
          # from systemd (no nix-side interpolation traps): the unit
          # description carries the mapping.
          for u in $(systemctl list-units --all "ts-tunnel-$name-*" --no-legend 2>/dev/null | awk '{print $1}'); do
            state=$(systemctl is-active "$u" 2>/dev/null || echo inactive)
            desc=$(systemctl show -p Description --value "$u" 2>/dev/null)
            printf '%-46s %-10s %s\n' "$u" "$state" "$desc"
          done
          ;;
        start|stop|restart)
          # systemd service for a configured preset: ts-mux <net> start <preset>
          preset="$2"
          svc="ts-tunnel-$name-$preset.service"
          exec systemctl "$1" "$svc"
          ;;
        tunnel)
          # ts-mux <name> tunnel <localPort> <host> <remotePort>
          # Local TCP listener -> the instance's SOCKS5 proxy ->
          # host:port. For apps without proxy support (Minecraft etc.).
          shift
          if [ $# -ne 3 ]; then
            echo "usage: ts-mux $name tunnel <localPort> <host> <remotePort>" >&2
            exit 1
          fi
          case "$name" in
            ${lib.concatStringsSep "
            " (
              lib.mapAttrsToList (
                n: c: ''${n}) socks=${toString c.socksPort} ;;''
              ) cfg
            )}
          esac
          exec ${tunnelRelay} "$socks" "$1" "$2" "$3"
          ;;
        up|login)
          shift
          sock="/run/tailscale-mux-$name/tailscaled.sock"
          # `tailscale status` exits non-zero when logged out (NeedsLogin) —
          # the JSON form exits 0 and still proves the daemon is reachable.
          if ! tailscale --socket="$sock" status --json --peers=false >/dev/null 2>&1; then
            echo "daemon tailscaled-mux-$name not running" >&2
            exit 1
          fi
          backend=$(tailscale --socket="$sock" status --json --peers=false | ${pkgs.jq}/bin/jq -r .BackendState)
          if [ "$backend" = "NeedsLogin" ] || [ "$backend" = "Stopped" ]; then
            ${
              lib.concatStringsSep "\n          " (
                lib.mapAttrsToList (
                  n: c:
                  lib.optionalString (c.loginServer != null) ''
                    if [ "$name" = "${n}" ]; then
                      exec tailscale --socket="$sock" up --login-server='${c.loginServer}' "$@"
                    fi
                  ''
                ) cfg
              )
            }
            exec tailscale --socket="$sock" up "$@"
          fi
          echo "network '$name' already up"
          ;;
        *)
          exec tailscale --socket="/run/tailscale-mux-$name/tailscaled.sock" "$@"
          ;;
      esac
    '';
  };

  # Per-network proxy port summary
  tsMuxInfo = pkgs.writeShellApplication {
    name = "ts-mux-info";
    runtimeInputs = [ pkgs.coreutils pkgs.jq ];
    text = ''
      cat <<EOF
      ts-mux networks:

      j0lab:  primary tailnet (system daemon, kernel TUN — all apps
              reach it directly, no SOCKS needed); control: ts.j0lab.xyz

      ${lib.concatStringsSep "\n      " (
        lib.mapAttrsToList (
          n: c: "${n}:  SOCKS5 127.0.0.1:${toString c.socksPort}  HTTP 127.0.0.1:${
            toString c.httpPort
          }  control=${
            if c.loginServer != null then c.loginServer else "default (login.tailscale.com)"
          }"
        ) cfg
      )}

      tunnel presets: listed live by 'ts-mux <name> tunnels' (read from
      systemd; each preset = service ts-tunnel-<name>-<preset>)

      usage:
        ts-mux <name> up              # login (interactive auth URL)
        ts-mux <name> status          # tailnet status
        ts-mux <name> down            # log out
        ssh -o ProxyCommand='nc -x 127.0.0.1:<socksPort> %h %p' user@host
      EOF
    '';
  };
in
{
  options.j0nix.desktop.network.tailscaleMux = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          loginServer = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Control server for this network (Headscale URL or null for
              Tailscale SaaS). One instance per network.
            '';
          };
          socksPort = lib.mkOption {
            type = lib.types.port;
            description = "Loopback SOCKS5 port for reaching this network's nodes.";
          };
          httpPort = lib.mkOption {
            type = lib.types.port;
            description = "Loopback HTTP proxy port for reaching this network's nodes.";
          };
          operator = lib.mkOption {
            type = lib.types.str;
            description = "User allowed to operate this instance's CLI without root.";
          };
          acceptRoutes = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Accept routes advertised by subnet routers in this network.";
          };
          tunnels = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  localPort = lib.mkOption {
                    type = lib.types.port;
                    description = "Loopback port the app connects to.";
                  };
                  host = lib.mkOption {
                    type = lib.types.str;
                    description = "Target node (MagicDNS name or tailnet IP).";
                  };
                  remotePort = lib.mkOption {
                    type = lib.types.port;
                    description = "TCP port on the target node.";
                  };
                  autoStart = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Start this tunnel on boot.";
                  };
                  description = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Human label shown by ts-mux-info.";
                  };
                };
              }
            );
            default = { };
            description = ''
              Persistent TCP tunnels through this network's SOCKS proxy,
              for apps without proxy support (Minecraft etc.). Each preset
              becomes a systemd service `ts-tunnel-<net>-<preset>`.
            '';
          };
        };
      }
    );
    default = { };
    description = ''
      Additional Tailscale networks reachable in parallel with the primary
      tailnet. Each entry runs an isolated userspace tailscaled with its own
      identity, SOCKS5/HTTP proxies, and CLI via `ts-mux <name> ...`.
      The primary tailnet (j0nix.desktop.network.tailscale) is unaffected.
    '';
  };

  config = lib.mkIf enabled {
    systemd.services =
      (lib.mapAttrs' mkInstance cfg)
      // (lib.mapAttrs' mkOperatorOneshot cfg)
      // (lib.concatMapAttrs (
        net: c: lib.mapAttrs' (preset: t: mkTunnelService net c preset t) c.tunnels or { }
      ) cfg);
    environment.systemPackages = [
      tsMuxCli
      tsMuxInfo
    ];
  };
}
