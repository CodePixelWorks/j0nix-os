{ inputs, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  enabled = (dev.enable or true) && (ai.enable or true);
  installScope = ai.installScope or "system"; # "system" | "user"
  preferredTerminal = settings.preferredTerminal or "kitty";
  codex = import ../../system/dev/codex.nix { inherit inputs lib pkgs settings; };
  codexEnabled = codex.enabled;
  ncpEnabled = ai.ncp or true;
  opencodeEnabled = ai.opencode or true;
  claudeCodeEnabled = ai.claudeCode or true;
  geminiEnabled = ai.gemini or true;
  ncpPackage = pkgs.writeShellApplication {
    name = "ncp";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      exec ${pkgs.nodejs}/bin/npx --yes @portel/ncp "$@"
    '';
  };
  opencodePackage = if builtins.hasAttr "opencode" pkgs then pkgs.opencode else null;
  claudeCodePackage = if builtins.hasAttr "claude-code" pkgs then pkgs."claude-code" else null;
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

      MCP_MODE="$mode" MCP_CONFIG_FILE="$config_file" MCP_SERVERS_JSON='${builtins.toJSON codex.mcpServers}' MCP_MANAGED_NAMES_JSON='${builtins.toJSON codex.mcpManagedServerNames}' ${pkgs.python3}/bin/python <<'PY'
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

updated = re.sub(r"\n{3,}", "\n\n", updated).lstrip("\n")

if updated != text:
    path.write_text(updated, encoding="utf-8")
PY
    '';
  };

  hasGeminiPackage = pkgs ? gemini-cli;
in
lib.mkIf enabled {
  j0nix.user.software.packages =
    lib.optionals (installScope == "user" && codexEnabled && codex.cliPackage != null) [ codex.cliPackage ]
    ++ lib.optionals (installScope == "user" && codexEnabled) (map (server: server.package) (builtins.attrValues codex.mcpServers))
    ++ lib.optionals (installScope == "user" && codexEnabled && codex.mcpLspEnable) codex.mcpLspRuntimePackages
    ++ lib.optionals (installScope == "user" && ncpEnabled) [ ncpPackage ]
    ++ lib.optionals (installScope == "user" && opencodeEnabled && opencodePackage != null) [ opencodePackage ]
    ++ lib.optionals (installScope == "user" && claudeCodeEnabled && claudeCodePackage != null) [ claudeCodePackage ]
    ++ lib.optionals (installScope == "user" && geminiEnabled && hasGeminiPackage) [ pkgs.gemini-cli ]
    ++ lib.optionals (installScope == "user" && geminiEnabled) [
      (pkgs.writeShellScriptBin "gemini-launcher" ''
        KEY_FILE="$HOME/.gem.key"

        if [ -f "$KEY_FILE" ]; then
          export GEMINI_API_KEY="$(tr -d '\n' < "$KEY_FILE")"
        fi

        if command -v gemini >/dev/null 2>&1; then
          exec gemini
        else
          echo "gemini CLI not found in PATH"
          exit 1
        fi
      '')
    ];

  home.activation.codexMcpSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${codexMcpSync}/bin/codex-mcp-sync
  '';

  xdg.desktopEntries.gemini-cli = lib.mkIf (geminiEnabled && (ai.geminiDesktopEntry or true)) {
    name = "Gemini CLI";
    genericName = "AI Assistant Terminal";
    comment = "Launch Gemini CLI in terminal";
    exec = "${preferredTerminal} -e gemini-launcher";
    # Use an absolute store path to avoid launcher/theme lookup misses in shell UIs.
    icon = "${../../icons/gemini-cli/gemini-cli.svg}";
    terminal = false;
    type = "Application";
    categories = [ "Development" "Utility" ];
  };

  xdg.dataFile."icons/hicolor/scalable/apps/gemini-cli.svg" = lib.mkIf (geminiEnabled && (ai.geminiDesktopEntry or true)) {
    source = ../../icons/gemini-cli/gemini-cli.svg;
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
      assertion = (!geminiEnabled) || hasGeminiPackage;
      message = "settings.dev.ai.gemini=true but pkgs.gemini-cli is unavailable";
    }
    {
      assertion = builtins.elem installScope [ "system" "user" ];
      message = "settings.dev.ai.installScope must be one of: system, user";
    }
  ];
}
