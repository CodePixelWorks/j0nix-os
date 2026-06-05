# nix/system/dev/crw.nix
# fastCRW — self-hosted Rust-native crawler, scraper and Firecrawl-compatible API.
# https://github.com/us/crw

{ config, lib, pkgs, ... }:

let
  cfg = config.settings.dev.crw;

  crw-server = pkgs.rustPlatform.buildRustPackage rec {
    pname = "crw-server";
    version = "0.12.1-unstable-2025-06-05";

    src = pkgs.fetchFromGitHub {
      owner = "us";
      repo = "crw";
      rev = "a3ab2ad1f254bdd6f24f690c89d466c3f0c3f5e9";
      sha256 = "1gmi6y55d65hnqh075m1rqr41q1l63cc7dcx58bvq96k42snvxmx";
    };

    cargoHash = "sha256-qJK0yjvlOeGvux4TxuEqZbCJJFlGIdS50vWsQSr/t6A=";

    doCheck = false;

    meta = with lib; {
      description = "Self-hosted Rust-native web crawler and scraper (Firecrawl-compatible API)";
      homepage = "https://github.com/us/crw";
      license = licenses.agpl3Only;
      mainProgram = "crw-server";
    };
  };

in
{
  options.settings.dev.crw = {
    enable = lib.mkEnableOption "fastCRW self-hosted crawler/scraper API";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3331;
      description = ''
        REST API listen port for crw-server.
        Firecrawl-compatible endpoints are served here.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to open the configured port in the firewall.
      '';
    };

    mcpEnable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to also run the crw-mcp MCP server alongside crw-server.
      '';
    };

    mcpPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = ''
        SSE port for the crw-mcp MCP server (when enabled).
      '';
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = ''
        Extra environment variables passed to the crw-server process.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port
      ++ lib.optional (cfg.mcpEnable && cfg.openFirewall) cfg.mcpPort;

    systemd.services.crw-server = {
      description = "fastCRW server — Firecrawl-compatible REST API";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${crw-server}/bin/crw-server";
        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
        StateDirectory = "crw";
        WorkingDirectory = "/var/lib/crw";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
      };

      environment = {
        CRW_PORT = toString cfg.port;
      } // cfg.extraEnv;
    };

    systemd.services.crw-mcp = lib.mkIf cfg.mcpEnable {
      description = "fastCRW MCP server";
      after = [ "network-online.target" "crw-server.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${crw-server}/bin/crw-mcp";
        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
        WorkingDirectory = "/var/lib/crw";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };

      environment = {
        CRW_MCP_PORT = toString cfg.mcpPort;
      } // cfg.extraEnv;
    };
  };
}
