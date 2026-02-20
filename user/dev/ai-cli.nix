{ inputs, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  ai = dev.ai or { };
  enabled = (dev.enable or true) && (ai.enable or true);

  codexEnabled = ai.codex or true;
  geminiEnabled = ai.gemini or true;

  hasCodexPackage =
    (inputs ? codex-cli-nix)
    && (inputs.codex-cli-nix ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.codex-cli-nix.packages)
    && (inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system} ? default);

  hasGeminiPackage = pkgs ? gemini-cli;
in
lib.mkIf enabled {
  home.packages =
    lib.optionals (codexEnabled && hasCodexPackage) [ inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default ]
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
    exec = "kitty -e gemini-launcher";
    terminal = false;
    type = "Application";
    categories = [ "Development" "Utility" ];
  };

  assertions = [
    {
      assertion = (!codexEnabled) || hasCodexPackage;
      message = "settings.dev.ai.codex=true but codex-cli-nix package is unavailable";
    }
    {
      assertion = (!geminiEnabled) || hasGeminiPackage;
      message = "settings.dev.ai.gemini=true but pkgs.gemini-cli is unavailable";
    }
  ];
}
