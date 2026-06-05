{
  lib,
  pkgs,
  utils,
  settings,
  ...
}:
let
  cfg = (settings.dev or { }).qdrant or { };
  enabled = cfg.enable or false;
  dataDir = cfg.dataDir or "/var/lib/qdrant";
  restPort = cfg.restPort or 6333;
  grpcPort = cfg.grpcPort or 6334;
  configFile = pkgs.writeText "qdrant-config.yaml" (lib.generators.toYAML { } {
    service = {
      http_port = restPort;
      grpc_port = grpcPort;
    };
    storage = {
      storage_path = "${dataDir}/storage";
      snapshots_path = "${dataDir}/snapshots";
    };
    log_level = cfg.logLevel or "INFO";
  });
in
lib.mkIf enabled {
  # ---------------------------------------------------------------------------
  # System packages
  # ---------------------------------------------------------------------------
  environment.systemPackages = [ pkgs.qdrant ];

  # ---------------------------------------------------------------------------
  # User and data directories
  # ---------------------------------------------------------------------------
  users.users.qdrant = {
    isSystemUser = true;
    group = "qdrant";
    home = dataDir;
    createHome = true;
  };
  users.groups.qdrant = { };

  # ---------------------------------------------------------------------------
  # Systemd service
  # ---------------------------------------------------------------------------
  systemd.services.qdrant = {
    description = "Qdrant vector search engine";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "qdrant";
      Group = "qdrant";
      ExecStart = "${pkgs.qdrant}/bin/qdrant --config-path ${configFile}";
      Restart = "on-failure";
      RestartSec = 5;

      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ dataDir ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      PrivateTmp = true;
    };
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------
  networking.firewall.allowedTCPPorts = lib.mkIf (cfg.openFirewall or true) [
    restPort
    grpcPort
  ];
}
