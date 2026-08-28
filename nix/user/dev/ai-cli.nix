{
  config,
  inputs,
  lib,
  pkgs,
  settings,
  ...
}:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  enabled = (dev.enable or true) && (ai.enable or true);
  installScope = ai.installScope or "system"; # "system" | "user"
  preferredTerminal = settings.preferredTerminal or "kitty";
  codex = import ../../system/dev/codex.nix {
    inherit
      inputs
      lib
      pkgs
      settings
      ;
  };
  codexEnabled = codex.enabled;
  ncpEnabled = ai.ncp or true;
  kiloCodeEnabled = ai.kiloCode or true;
  opencodeEnabled = ai.opencode or true;
  claudeCodeEnabled = ai.claudeCode or true;
  antigravityEnabled = ai.antigravity or (ai.gemini or true);
  antigravityDesktopEntry = ai.antigravityDesktopEntry or (ai.geminiDesktopEntry or true);
  hermesEnabled = ai.hermes or true;
  hermesMcpCfg = ai.hermesMcp or { };
  hermesGiteaCfg = hermesMcpCfg.gitea or { };
  hermesGiteaEnabled = hermesEnabled && (hermesGiteaCfg.enable or false);
  hermesDonsetchCfg = hermesMcpCfg.donsetch or { };
  hermesDonsetchEnabled = hermesEnabled && (hermesDonsetchCfg.enable or false);
  hermesDonsetchPreferred = hermesDonsetchEnabled && (hermesDonsetchCfg.preferForWeb or true);
  hermesDonsetchSupervised = hermesDonsetchCfg.supervised or true;
  hermesGiteaHost = hermesGiteaCfg.host or "https://gitea.com";
  hermesGiteaTokenSecretName = hermesGiteaCfg.tokenSecretName or "gitea-mcp-token";
  hermesGiteaTokenAvailable = lib.hasAttrByPath [ hermesGiteaTokenSecretName ] (
    config.sops.secrets or { }
  );
  hermesGiteaTokenPath =
    if hermesGiteaTokenAvailable then
      config.sops.secrets.${hermesGiteaTokenSecretName}.path
    else
      "/missing/${hermesGiteaTokenSecretName}";
  mcpRemotes = ai.mcpRemotes or { };
  hermesPackage = pkgs.hermes-agent-with-firecrawl or null;
  hermesGiteaPackage = pkgs.gitea-mcp or null;
  hermesDonsetchPackage = pkgs.donsetch or null;
  ncpPackage = pkgs.writeShellApplication {
    name = "ncp";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      exec ${pkgs.nodejs}/bin/npx --yes @portel/ncp "$@"
    '';
  };
  kiloCodePackage = pkgs.writeShellApplication {
    name = "kilocode";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      exec ${pkgs.nodejs}/bin/npx --yes @kilocode/cli@alpha "$@"
    '';
  };
  opencodePackage = if builtins.hasAttr "opencode" pkgs then pkgs.opencode else null;
  claudeCodePackage = if builtins.hasAttr "claude-code" pkgs then pkgs."claude-code" else null;
  antigravityInstaller = pkgs.writeShellApplication {
    name = "antigravity-install";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
    ];
    text = ''
      target_dir="''${ANTIGRAVITY_INSTALL_DIR:-''${XDG_BIN_HOME:-$HOME/.local/bin}}"
      tmp_dir="$(mktemp -d)"
      trap 'rm -rf "$tmp_dir"' EXIT

      install_script="$tmp_dir/install.sh"
      curl -fsSL -o "$install_script" https://antigravity.google/cli/install.sh

      if [ "$#" -eq 0 ]; then
        set -- --dir "$target_dir"
      fi

      exec bash "$install_script" "$@"
    '';
  };
  antigravityLauncher = pkgs.writeShellApplication {
    name = "antigravity-launcher";
    runtimeInputs = [ antigravityInstaller ];
    text = ''
      target_dir="''${ANTIGRAVITY_INSTALL_DIR:-''${XDG_BIN_HOME:-$HOME/.local/bin}}"
      binary_path="$target_dir/agy"

      if ! command -v agy >/dev/null 2>&1 && [ ! -x "$binary_path" ]; then
        antigravity-install
      fi

      if command -v agy >/dev/null 2>&1; then
        exec agy "$@"
      elif [ -x "$binary_path" ]; then
        exec "$binary_path" "$@"
      else
        echo "Antigravity CLI not found after installation"
        exit 1
      fi
    '';
  };
  hermesGiteaServer = {
    command = "${hermesGiteaPackage}/bin/gitea-mcp";
    args = [
      "-t"
      "stdio"
      "-H"
      hermesGiteaHost
    ];
    env.GITEA_ACCESS_TOKEN_FILE = hermesGiteaTokenPath;
  };
  hermesDonsetchServer = {
    command = "${hermesDonsetchPackage}/bin/donsetch";
    args = [ "mcp" ] ++ lib.optional hermesDonsetchSupervised "--supervised";
  };
  hermesManagedServers =
    lib.optionalAttrs hermesGiteaEnabled { gitea = hermesGiteaServer; }
    // lib.optionalAttrs hermesDonsetchEnabled { donsetch = hermesDonsetchServer; };
  hermesDonsetchPrompt = ''
    Web research policy:
    - Use the Donsetch MCP tools web_search, web_fetch, and web_crawl by default for internet search, page retrieval, and crawling.
    - Do not use CRW, Firecrawl, or Hermes' built-in web tools while Donsetch is available.
    - Fall back to another web backend only when Donsetch fails or lacks a required capability, and mention that fallback.
  '';
  hermesMcpSyncPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);
  hermesMcpSync = pkgs.writeShellApplication {
    name = "hermes-mcp-sync";
    runtimeInputs = [ hermesMcpSyncPython ];
    text = ''
      config_file="$HOME/.hermes/config.yaml"
      mkdir -p "$(dirname "$config_file")"

      HERMES_CONFIG_FILE="$config_file" \
        HERMES_MANAGED_SERVERS=${lib.escapeShellArg (builtins.toJSON hermesManagedServers)} \
        HERMES_DONSETCH_PREFERRED=${lib.escapeShellArg (if hermesDonsetchPreferred then "1" else "0")} \
        HERMES_DONSETCH_PROMPT=${lib.escapeShellArg hermesDonsetchPrompt} \
        ${hermesMcpSyncPython}/bin/python <<'PY'
      import json
      import os
      from pathlib import Path
      import tempfile
      import yaml

      path = Path(os.environ["HERMES_CONFIG_FILE"])
      if path.exists():
          config = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
          mode = path.stat().st_mode & 0o777
      else:
          config = {}
          mode = 0o600

      servers = config.setdefault("mcp_servers", {})
      desired_servers = json.loads(os.environ["HERMES_MANAGED_SERVERS"])
      changed = False
      for name, desired in desired_servers.items():
          if servers.get(name) != desired:
              servers[name] = desired
              changed = True

      marker_start = "<!-- j0nix:donsetch:start -->"
      marker_end = "<!-- j0nix:donsetch:end -->"
      if os.environ["HERMES_DONSETCH_PREFERRED"] == "1":
          agent = config.setdefault("agent", {})
          current_prompt = agent.get("system_prompt", "") or ""
          if not isinstance(current_prompt, str):
              raise TypeError("Hermes agent.system_prompt must be a string")
          start = current_prompt.find(marker_start)
          end = current_prompt.find(marker_end)
          if start != -1 and end >= start:
              current_prompt = (
                  current_prompt[:start] + current_prompt[end + len(marker_end):]
              ).strip()
          managed_prompt = (
              f"{marker_start}\n{os.environ['HERMES_DONSETCH_PROMPT'].strip()}\n{marker_end}"
          )
          updated_prompt = "\n\n".join(part for part in [current_prompt, managed_prompt] if part)
          if agent.get("system_prompt", "") != updated_prompt:
              agent["system_prompt"] = updated_prompt
              changed = True

      if not changed:
          raise SystemExit(0)

      path.parent.mkdir(parents=True, exist_ok=True)
      with tempfile.NamedTemporaryFile(
          mode="w", encoding="utf-8", dir=path.parent, delete=False
      ) as handle:
          yaml.safe_dump(config, handle, sort_keys=False, allow_unicode=True)
          temporary_path = Path(handle.name)
      temporary_path.chmod(mode)
      temporary_path.replace(path)
      PY
    '';
  };
  codexMcpSync = pkgs.writeShellApplication {
    name = "codex-mcp-sync";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
            if [ "''${1:-}" = "--remove-all" ]; then
              mode="remove-all"
            elif [ -z "''${1:-}" ] || [ "''${1:-}" = "sync" ]; then
              mode="sync"
            else
              echo "Usage: codex-mcp-sync [sync|--remove-all]" >&2
              exit 2
            fi

            config_file="$HOME/.codex/config.toml"
            mkdir -p "$(dirname "$config_file")"

            MCP_MODE="$mode" MCP_CONFIG_FILE="$config_file" MCP_SERVERS_JSON='${builtins.toJSON codex.mcpServers}' MCP_MANAGED_NAMES_JSON='${
              builtins.toJSON (codex.mcpManagedServerNames ++ builtins.attrNames mcpRemotes)
            }' MCP_REMOTES_JSON='${builtins.toJSON mcpRemotes}' ${pkgs.python3}/bin/python <<'PY'
      from pathlib import Path
      import os
      import re
      import json

      path = Path(os.environ["MCP_CONFIG_FILE"])
      mode = os.environ["MCP_MODE"]
      servers = json.loads(os.environ["MCP_SERVERS_JSON"])
      managed_names = json.loads(os.environ["MCP_MANAGED_NAMES_JSON"])

      text = path.read_text(encoding="utf-8") if path.exists() else ""

      def render_block(name, server):
          lines = [f"[mcp_servers.{name}]", f'command = "{server["command"]}"']
          return "\n".join(lines) + "\n"

      def render_remote_block(name, url):
          lines = [f"[mcp_servers.{name}]", f'url = "{url}"']
          return "\n".join(lines) + "\n"

      updated = text
      for name in managed_names:
          pattern = re.compile(rf'(?ms)^\[mcp_servers\.{re.escape(name)}\]\n.*?(?=^\[|\Z)')
          updated = pattern.sub("", updated, count=1)

      if mode != "remove-all":
          for name, server in servers.items():
              block = render_block(name, server)
              suffix = ""
              if updated and not updated.endswith("\n"):
                  suffix += "\n"
              if updated and not updated.endswith("\n\n"):
                  suffix += "\n"
              updated = f"{updated}{suffix}{block}"

          if "MCP_REMOTES_JSON" in os.environ:
              remotes = json.loads(os.environ["MCP_REMOTES_JSON"])
              for name, url in remotes.items():
                  block = render_remote_block(name, url)
                  suffix = ""
                  if updated and not updated.endswith("\n"):
                      suffix += "\n"
                  if updated and not updated.endswith("\n\n"):
                      suffix += "\n"
                  updated = f"{updated}{suffix}{block}"

      updated = re.sub(r"\n{3,}", "\n\n", updated).lstrip("\n")

      if updated != text:
          path.write_text(updated, encoding="utf-8")
      PY
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages =
    lib.optionals (installScope == "user" && codexEnabled && codex.cliPackage != null) [
      codex.cliPackage
    ]
    ++ lib.optionals (installScope == "user" && codexEnabled) (
      map (server: server.package) (builtins.attrValues codex.mcpServers)
    )
    ++ lib.optionals (
      installScope == "user" && codexEnabled && codex.mcpLspEnable
    ) codex.mcpLspRuntimePackages
    ++ lib.optionals (installScope == "user" && ncpEnabled) [ ncpPackage ]
    ++ lib.optionals (installScope == "user" && kiloCodeEnabled) [ kiloCodePackage ]
    ++ lib.optionals (installScope == "user" && opencodeEnabled && opencodePackage != null) [
      opencodePackage
    ]
    ++ lib.optionals (installScope == "user" && claudeCodeEnabled && claudeCodePackage != null) [
      claudeCodePackage
    ]
    ++ lib.optionals (installScope == "user" && antigravityEnabled) [
      antigravityInstaller
      antigravityLauncher
    ]
    ++ lib.optionals (installScope == "user" && hermesEnabled && hermesPackage != null) [
      hermesPackage
    ]
    ++ lib.optionals hermesGiteaEnabled [ hermesGiteaPackage ]
    ++ lib.optionals hermesDonsetchEnabled [ hermesDonsetchPackage ]
    ++ lib.optionals (installScope == "user") [ pkgs.bubblewrap ];

  home.activation.codexMcpSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${codexMcpSync}/bin/codex-mcp-sync
  '';

  home.activation.hermesMcpSync = lib.mkIf (hermesGiteaEnabled || hermesDonsetchEnabled) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${hermesMcpSync}/bin/hermes-mcp-sync
    ''
  );

  xdg.configFile."codex/mcp-remotes.json" = lib.mkIf (mcpRemotes != { }) {
    text = builtins.toJSON {
      inherit mcpRemotes;
    };
  };

  xdg.desktopEntries.antigravity-cli = lib.mkIf (antigravityEnabled && antigravityDesktopEntry) {
    name = "Antigravity CLI";
    genericName = "AI Assistant Terminal";
    comment = "Launch Antigravity CLI in terminal";
    exec = "${preferredTerminal} -e antigravity-launcher";
    icon = "utilities-terminal";
    terminal = false;
    type = "Application";
    categories = [
      "Development"
      "Utility"
    ];
  };

  assertions = [
    {
      assertion = codex.validProvider;
      message = codex.providerMessage;
    }
    {
      assertion = (!codexEnabled) || codex.provider != "compat" || codex.compatAvailable;
      message = codex.compatMessage;
    }
    {
      assertion = (!codex.mcpNixosEnable) || codex.mcpNixosPackage != null;
      message = "settings.dev.ai.codex.mcp.nixos=true but pkgs.mcp-nixos is unavailable";
    }
    {
      assertion = (!codex.mcpGithubEnable) || codex.mcpGithubPackage != null;
      message = "settings.dev.ai.codex.mcp.github=true but pkgs.github-mcp-server is unavailable";
    }
    {
      assertion = (!codex.mcpHyprlandEnable) || codex.mcpHyprlandPackage != null;
      message = "settings.dev.ai.codex.mcp.hyprland=true but the hyprmcp wrapper package is unavailable";
    }
    {
      assertion = (!codex.mcpLspEnable) || codex.mcpLspPackage != null;
      message = "settings.dev.ai.codex.mcp.lsp.enable=true but pkgs.mcp-language-server-j0nix is unavailable";
    }
    {
      assertion = codex.validMcpLspLanguages;
      message = "settings.dev.ai.codex.mcp.lsp.languages contains unsupported values. Supported languages: ${lib.concatStringsSep ", " codex.supportedMcpLspLanguages}";
    }
    {
      assertion = (!opencodeEnabled) || opencodePackage != null;
      message = "settings.dev.ai.opencode=true but pkgs.opencode is unavailable";
    }
    {
      assertion = (!claudeCodeEnabled) || claudeCodePackage != null;
      message = "settings.dev.ai.claudeCode=true but pkgs.\"claude-code\" is unavailable";
    }
    {
      assertion = (!hermesEnabled) || hermesPackage != null;
      message = "settings.dev.ai.hermes=true but inputs.hermes-agent package is unavailable for this system";
    }
    {
      assertion = (!hermesGiteaEnabled) || hermesGiteaPackage != null;
      message = "Hermes Gitea MCP is enabled but pkgs.gitea-mcp is unavailable";
    }
    {
      assertion = (!hermesDonsetchEnabled) || hermesDonsetchPackage != null;
      message = "Hermes Donsetch MCP is enabled but pkgs.donsetch is unavailable";
    }
    {
      assertion = (!hermesGiteaEnabled) || hermesGiteaTokenAvailable;
      message = "Hermes Gitea MCP requires the configured user SOPS secret: ${hermesGiteaTokenSecretName}";
    }
    {
      assertion = (!hermesGiteaEnabled) || lib.hasPrefix "https://" hermesGiteaHost;
      message = "settings.userSettings.<name>.dev.ai.hermesMcp.gitea.host must use HTTPS";
    }
    {
      assertion = builtins.elem installScope [
        "system"
        "user"
      ];
      message = "settings.dev.ai.installScope must be one of: system, user";
    }
  ];
}
