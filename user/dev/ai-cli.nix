{ inputs, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  enabled = (dev.enable or true) && (ai.enable or true);
  installScope = ai.installScope or "system"; # "system" | "user"
  preferredTerminal = settings.preferredTerminal or "kitty";
  codex = import ../../system/dev/codex.nix { inherit inputs lib pkgs settings; };
  codexEnabled = codex.enabled;
  opencodeEnabled = ai.opencode or true;
  claudeCodeEnabled = ai.claudeCode or true;
  geminiEnabled = ai.gemini or true;
  opencodePackage = if builtins.hasAttr "opencode" pkgs then pkgs.opencode else null;
  claudeCodePackage = if builtins.hasAttr "claude-code" pkgs then pkgs."claude-code" else null;
  codexMcpNixosSync = pkgs.writeShellApplication {
    name = "codex-mcp-nixos-sync";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      mode="sync"
      if [ "''${1:-}" = "--remove" ]; then
        mode="remove"
      elif [ -n "''${1:-}" ] && [ "''${1:-}" != "sync" ]; then
        echo "Usage: codex-mcp-nixos-sync [--remove]" >&2
        exit 2
      fi

      config_file="$HOME/.codex/config.toml"
      mkdir -p "$(dirname "$config_file")"

      MCP_MODE="$mode" MCP_CONFIG_FILE="$config_file" ${pkgs.python3}/bin/python <<'PY'
from pathlib import Path
import os
import re

path = Path(os.environ["MCP_CONFIG_FILE"])
mode = os.environ["MCP_MODE"]
block = '[mcp_servers.nixos]\ncommand = "mcp-nixos"\n'
pattern = re.compile(r'(?ms)^\[mcp_servers\.nixos\]\n.*?(?=^\[|\Z)')

text = path.read_text(encoding="utf-8") if path.exists() else ""

if mode == "remove":
    updated = pattern.sub("", text, count=1)
    updated = re.sub(r"\n{3,}", "\n\n", updated).lstrip("\n")
else:
    replacement = block + "\n"
    if pattern.search(text):
        updated = pattern.sub(replacement, text, count=1)
    else:
        suffix = ""
        if text and not text.endswith("\n"):
            suffix += "\n"
        if text and not text.endswith("\n\n"):
            suffix += "\n"
        updated = f"{text}{suffix}{block}"

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
    ++ lib.optionals (installScope == "user" && codexEnabled && codex.mcpNixosEnable && codex.mcpNixosPackage != null) [ codex.mcpNixosPackage ]
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

  home.activation.codexMcpNixosSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${codexMcpNixosSync}/bin/codex-mcp-nixos-sync ${lib.optionalString (!codex.mcpNixosEnable) "--remove"}
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
