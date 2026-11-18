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

  # CLI wrapper: ts-mux <name> <up|status|down|...> [args...]
  # Auto-completes the per-instance socket + login-server.
  tsMuxCli = pkgs.writeShellApplication {
    name = "ts-mux";
    runtimeInputs = [ config.services.tailscale.package pkgs.coreutils ];
    text = ''
      set -eu
      if [ $# -lt 2 ]; then
        echo "usage: ts-mux <network> <up|status|down|logout|ping|ssh ...>" >&2
        echo "networks: ${lib.concatStringsSep " " (lib.attrNames cfg)}" >&2
        exit 1
      fi
      name="$1"; shift
      case "$name" in
        ${lib.concatStringsSep "|" (lib.attrNames cfg)}) ;;
        *) echo "unknown network: $name" >&2; exit 1 ;;
      esac
      case "$1" in
        up)
          shift
          sock="/run/tailscale-mux-$name/tailscaled.sock"
          if ! tailscale --socket="$sock" status --peers=false >/dev/null 2>&1; then
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
      ts-mux networks (userspace tailscaled, SOCKS5 app access):

      ${lib.concatStringsSep "\n      " (
        lib.mapAttrsToList (
          n: c: "${n}:  SOCKS5 127.0.0.1:${toString c.socksPort}  HTTP 127.0.0.1:${
            toString c.httpPort
          }  control=${c.loginServer or "default (login.tailscale.com)"}"
        ) cfg
      )}

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
    systemd.services = lib.mapAttrs' mkInstance cfg;
    environment.systemPackages = [
      tsMuxCli
      tsMuxInfo
    ];
  };
}
