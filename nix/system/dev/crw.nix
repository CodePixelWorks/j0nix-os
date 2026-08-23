{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.dev or { }).crw or { };
  enabled = cfg.enable or false;

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

  port = cfg.port or 3000;
  openFirewall = cfg.openFirewall or true;
  mcpEnable = cfg.mcpEnable or false;
  extraEnv = cfg.extraEnv or { };
in
lib.mkIf enabled {
  networking.firewall.allowedTCPPorts = lib.optional openFirewall port;

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
      CRW_SERVER__PORT = toString port;
    } // extraEnv;
  };

  # crw-mcp is a stdio-based MCP server — not a daemon. Expose the binary
  # so Hermes (or any MCP client) can spawn it on demand.
  environment.systemPackages = lib.optional mcpEnable crw-server;
}
