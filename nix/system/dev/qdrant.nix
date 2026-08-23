{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.dev or { }).qdrant or { };
  enabled = cfg.enable or false;
  dataDir = cfg.dataDir or "/var/lib/qdrant";
  restPort = cfg.restPort or 6333;
  grpcPort = cfg.grpcPort or 6334;
  logLevel = cfg.logLevel or "INFO";

  qdrantConfig = pkgs.writeText "qdrant-config.yaml" (
    lib.generators.toYAML { } {
      service = {
        http_port = restPort;
        grpc_port = grpcPort;
      };
      storage = {
        storage_path = "/qdrant/storage";
        snapshots_path = "/qdrant/snapshots";
      };
      log_level = logLevel;
    }
  );
in
lib.mkIf enabled {
  # Run Qdrant as Docker container (avoids Rust AVX512 build failure
  # in the nixpkgs qdrant package on this NixOS revision).
  virtualisation.docker.enable = true;

  virtualisation.oci-containers.containers.qdrant = {
    image = "qdrant/qdrant:latest";
    autoStart = true;
    ports = [
      "${toString restPort}:6333"
      "${toString grpcPort}:6334"
    ];
    volumes = [
      "${dataDir}/storage:/qdrant/storage"
      "${dataDir}/snapshots:/qdrant/snapshots"
      "${qdrantConfig}:/qdrant/config/config.yaml:ro"
    ];
  };

  # Firewall
  networking.firewall.allowedTCPPorts = lib.mkIf (cfg.openFirewall or true) [
    restPort
    grpcPort
  ];

  assertions = [
    {
      assertion = !(cfg.openFirewall or true) || cfg.restPort != cfg.grpcPort;
      message = "settings.dev.qdrant.restPort and grpcPort must differ";
    }
  ];
}
