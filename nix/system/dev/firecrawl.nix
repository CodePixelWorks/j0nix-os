{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.dev or { }).firecrawl or { };
  enabled = cfg.enable or false;
  dataDir = cfg.dataDir or "/var/lib/firecrawl";
  port = cfg.port or 3002;
  redisPort = cfg.redisPort or 6379;

  baseEnv = {
    API_PORT = toString port;
    REDIS_URL = "redis://127.0.0.1:${toString redisPort}";
    OPENAI_API_KEY=cfg.openaiApiKey or "";
    LLAMAPARSE_API_KEY=cfg.llamaparseApiKey or "";
    SCRAPING_BEE_API_KEY=cfg.scrapingbeeApiKey or "";
    BULL_AUTH_KEY=cfg.bullAuthKey or "";
    ENVIRONMENT = "selfhosted";
  };
in
lib.mkIf enabled {
  # ---------------------------------------------------------------------------
  # Docker is mandatory for OCI containers
  # ---------------------------------------------------------------------------
  virtualisation.docker.enable = lib.mkForce true;

  # ---------------------------------------------------------------------------
  # Redis queue (native NixOS service)
  # ---------------------------------------------------------------------------
  services.redis.servers.firecrawl = {
    enable = true;
    bind = "127.0.0.1";
    port = redisPort;
  };

  # ---------------------------------------------------------------------------
  # OCI containers — Firecrawl self-hosted stack
  # ---------------------------------------------------------------------------
  # API, Worker and Playwright use the same upstream image.
  # Playwright exposes port 3000 on the host; API/Worker reach it via
  # 127.0.0.1 so no custom Docker network is required.
  virtualisation.oci-containers.containers = {
    firecrawl-api = {
      image = cfg.apiImage or "ghcr.io/mendableai/firecrawl";
      ports = [ "${toString port}:${toString port}" ];
      environment = baseEnv // {
        MYBROWSER = "http://127.0.0.1:3000";
        PLAYWRIGHT_MICROSERVICE_URL = "http://127.0.0.1:3000";
      } // (cfg.extraEnv or { });
      volumes = [
        "${dataDir}/api:/app/storage"
      ];
    };

    firecrawl-worker = {
      image = cfg.workerImage or cfg.apiImage or "ghcr.io/mendableai/firecrawl";
      environment = baseEnv // {
        MYBROWSER = "http://127.0.0.1:3000";
        PLAYWRIGHT_MICROSERVICE_URL = "http://127.0.0.1:3000";
        WORKER = "true";
      } // (cfg.extraEnv or { });
      volumes = [
        "${dataDir}/worker:/app/storage"
      ];
    };

    firecrawl-playwright = {
      image = cfg.playwrightImage or "mcr.microsoft.com/playwright";
      ports = [ "3000:3000" ];
      environment = {
        PORT = "3000";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root -"
    "d ${dataDir}/api 0750 root root -"
    "d ${dataDir}/worker 0750 root root -"
  ];

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------
  networking.firewall.allowedTCPPorts = lib.mkIf (cfg.openFirewall or true) [ port ];
}
