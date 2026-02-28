{ inputs, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  enabled = (dev.enable or true) && (ai.enable or true);
  preferredTerminal = settings.preferredTerminal or "kitty";
  codex = import ../../system/lib/codex.nix { inherit inputs lib pkgs settings; };
  codexEnabled = codex.enabled;
  geminiEnabled = ai.gemini or true;

  hasGeminiPackage = pkgs ? gemini-cli;
in
lib.mkIf enabled {
  home.packages =
    lib.optionals (codexEnabled && codex.cliPackage != null) [ codex.cliPackage ]
    ++ lib.optionals (geminiEnabled && hasGeminiPackage) [ pkgs.gemini-cli ]
    ++ lib.optionals geminiEnabled [
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
      assertion = (!geminiEnabled) || hasGeminiPackage;
      message = "settings.dev.ai.gemini=true but pkgs.gemini-cli is unavailable";
    }
  ];
}
