{
  lib,
  pkgs,
  settings,
  ...
}:
let
  dev = settings.dev or { };
  supabaseCfg = dev.supabase or { };
  enabled = (dev.enable or true) && (supabaseCfg.enable or false);
  projectDir = supabaseCfg.projectDir or "~/supabase-project";
  port = toString (supabaseCfg.port or 8000);
  postgresPort = toString (supabaseCfg.postgresPort or 5432);
  poolerPort = toString (supabaseCfg.poolerPort or 6543);
  dashboardUsername = supabaseCfg.dashboardUsername or "supabase";
  dashboardPassword = supabaseCfg.dashboardPassword or "changeme";
  autoUpdate = supabaseCfg.autoUpdate or false;

  supabaseInit = pkgs.writeShellScriptBin "supabase-init" ''
    set -euo pipefail

    project_dir="$(${pkgs.coreutils}/bin/realpath -m ${lib.escapeShellArg projectDir})"

    if [ -f "$project_dir/docker-compose.yml" ]; then
      echo "Supabase project already exists at $project_dir"
      echo "Run 'supabase-start' to start services or delete the directory to reinitialize."
      exit 0
    fi

    echo "Initializing Supabase project at $project_dir..."
    ${pkgs.coreutils}/bin/mkdir -p "$project_dir"

    tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    echo "Cloning Supabase Docker configuration..."
    ${pkgs.git}/bin/git clone --filter=blob:none --no-checkout \
      https://github.com/supabase/supabase "$tmp_dir/supabase" >/dev/null 2>&1
    ${pkgs.git}/bin/git -C "$tmp_dir/supabase" sparse-checkout set --cone docker >/dev/null 2>&1
    ${pkgs.git}/bin/git -C "$tmp_dir/supabase" checkout master >/dev/null 2>&1

    ${pkgs.coreutils}/bin/cp -rf "$tmp_dir/supabase/docker/"* "$project_dir/"
    ${pkgs.coreutils}/bin/cp "$tmp_dir/supabase/docker/.env.example" "$project_dir/.env"

    echo "Generating secrets..."
    cd "$project_dir"
    if [ -x ./utils/generate-keys.sh ]; then
      sh ./utils/generate-keys.sh >/dev/null 2>&1 || true
    fi

    ${pkgs.gnused}/bin/sed -i \
      "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 16)|" \
      "$project_dir/.env"
    ${pkgs.gnused}/bin/sed -i \
      "s|^DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=${lib.escapeShellArg dashboardUsername}|" \
      "$project_dir/.env"
    ${pkgs.gnused}/bin/sed -i \
      "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${lib.escapeShellArg dashboardPassword}|" \
      "$project_dir/.env"
    ${pkgs.gnused}/bin/sed -i \
      "s|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://localhost:${port}|" \
      "$project_dir/.env"
    ${pkgs.gnused}/bin/sed -i \
      "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://localhost:${port}|" \
      "$project_dir/.env"

    echo "Pulling Docker images..."
    cd "$project_dir"
    ${pkgs.docker-compose}/bin/docker compose pull

    echo ""
    echo "Supabase initialized at $project_dir"
    echo "  API Gateway:  http://localhost:${port}"
    echo "  Studio:       http://localhost:${port} (login: ${dashboardUsername})"
    echo "  Postgres:     localhost:${postgresPort} (via Supavisor)"
    echo ""
    echo "Run 'supabase-start' to start all services."
    echo "IMPORTANT: Change DASHBOARD_PASSWORD in $project_dir/.env before production use."
  '';

  supabaseStart = pkgs.writeShellScriptBin "supabase-start" ''
    set -euo pipefail

    project_dir="$(${pkgs.coreutils}/bin/realpath -m ${lib.escapeShellArg projectDir})"

    if [ ! -f "$project_dir/docker-compose.yml" ]; then
      echo "No Supabase project found at $project_dir"
      echo "Run 'supabase-init' first to initialize the project."
      exit 1
    fi

    ${lib.optionalString autoUpdate ''
      echo "Pulling latest images..."
      cd "$project_dir"
      ${pkgs.docker-compose}/bin/docker compose pull
    ''}

    echo "Starting Supabase services..."
    cd "$project_dir"
    ${pkgs.docker-compose}/bin/docker compose up -d

    echo "Waiting for services to become healthy..."
    sleep 3
    ${pkgs.docker-compose}/bin/docker compose ps

    echo ""
    echo "Supabase is running:"
    echo "  Studio: http://localhost:${port}"
  '';

  supabaseStop = pkgs.writeShellScriptBin "supabase-stop" ''
    set -euo pipefail

    project_dir="$(${pkgs.coreutils}/bin/realpath -m ${lib.escapeShellArg projectDir})"

    if [ ! -f "$project_dir/docker-compose.yml" ]; then
      echo "No Supabase project found at $project_dir"
      exit 1
    fi

    echo "Stopping Supabase services..."
    cd "$project_dir"
    ${pkgs.docker-compose}/bin/docker compose down

    echo "Supabase stopped."
  '';

  supabaseStatus = pkgs.writeShellScriptBin "supabase-status" ''
    set -euo pipefail

    project_dir="$(${pkgs.coreutils}/bin/realpath -m ${lib.escapeShellArg projectDir})"

    if [ ! -f "$project_dir/docker-compose.yml" ]; then
      echo "No Supabase project found at $project_dir"
      echo "Run 'supabase-init' first."
      exit 1
    fi

    cd "$project_dir"
    ${pkgs.docker-compose}/bin/docker compose ps
  '';

  supabaseLogs = pkgs.writeShellScriptBin "supabase-logs" ''
    set -euo pipefail

    project_dir="$(${pkgs.coreutils}/bin/realpath -m ${lib.escapeShellArg projectDir})"

    if [ ! -f "$project_dir/docker-compose.yml" ]; then
      echo "No Supabase project found at $project_dir"
      exit 1
    fi

    cd "$project_dir"
    exec ${pkgs.docker-compose}/bin/docker compose logs -f "$@"
  '';
in
{
  config = lib.mkIf enabled {
    j0nix.software.systemPackages = [
      supabaseInit
      supabaseStart
      supabaseStop
      supabaseStatus
      supabaseLogs
    ];

    assertions = [
      {
        assertion = builtins.isString (supabaseCfg.projectDir or "~/supabase-project");
        message = "settings.dev.supabase.projectDir must be a string path.";
      }
      {
        assertion = builtins.isInt (supabaseCfg.port or 8000);
        message = "settings.dev.supabase.port must be an integer.";
      }
      {
        assertion = !enabled || (supabaseCfg.dashboardPassword or "changeme") != "changeme";
        message = "settings.dev.supabase.dashboardPassword must be changed from the default 'changeme'.";
      }
    ];
  };
}
