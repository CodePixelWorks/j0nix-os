{ config, inputs, pkgs, lib, settings, ... }:
let
  mkExt = set: path: lib.attrByPath path null set;
  pick = ext: lib.optional (ext != null) ext;

  marketplace = pkgs.nix-vscode-extensions.vscode-marketplace or {};

  vscodeCfg = settings.vscode or { };
  extensionCfg = vscodeCfg.extensions or { };
  codex = import ../../../system/lib/codex.nix { inherit inputs lib pkgs settings; };
  openVSXIds = extensionCfg.openVSX or [ ];
  marketplaceIds = extensionCfg.marketplace or [ ];
  seededUserSettings = {
    "editor.fontLigatures" = true;
    "editor.formatOnSave" = true;
    "files.autoSave" = "onFocusChange";
    "editor.codeActionsOnSave" = {
      "source.fixAll" = "explicit";
      "source.organizeImports" = "explicit";
    };
    "terminal.integrated.defaultProfile.linux" = "zsh";
    "docker.languageserver.formatter.ignoreMultilineInstructions" = true;
    "nix.enableLanguageServer" = true;
    "nix.serverPath" = "nixd";
    "rust-analyzer.check.command" = "clippy";
    "python.analysis.typeCheckingMode" = "basic";
    "yaml.format.enable" = true;
  };

  mkExtFromId = set: extId:
    let
      parts = lib.splitString "." extId;
    in
      if builtins.length parts < 2 then
        null
      else
        mkExt set [
          (builtins.elemAt parts 0)
          (lib.concatStringsSep "." (lib.drop 1 parts))
        ];

  resolveExts = set: ids: lib.concatMap (id: pick (mkExtFromId set id)) ids;
in {
  programs.vscode = {
    enable = true;
    profiles.default = {
      extensions =
        resolveExts pkgs.vscode-extensions openVSXIds
        ++ resolveExts marketplace marketplaceIds
        ++ lib.optionals (codex.enabled && codex.vscodeEnable && codex.vscodeExtension != null) [ codex.vscodeExtension ];
    };
  };

  # Seed VSCode settings once so the file stays writable in the UI.
  home.activation.vscodeSeedUserSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for settings_file in \
      "$HOME/.config/Code/User/settings.json" \
      "$HOME/.config/VSCodium/User/settings.json" \
      "$HOME/.config/code-server/User/settings.json"
    do
      if [ -L "$settings_file" ]; then
        $DRY_RUN_CMD rm -f "$settings_file"
      fi

      if [ ! -e "$settings_file" ]; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$settings_file")"
        $DRY_RUN_CMD cat >"$settings_file" <<'EOF'
${builtins.toJSON seededUserSettings}
EOF
        $DRY_RUN_CMD chmod 644 "$settings_file"
      fi
    done
  '';

  assertions = [
    {
      assertion = (!codex.enabled) || (!codex.vscodeEnable) || codex.vscodeExtension != null;
      message = "Codex VSCode integration is enabled, but the OpenAI VSCode extension is unavailable in nix-vscode-extensions.";
    }
  ];
}
