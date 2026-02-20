{ pkgs, lib, settings, ... }:
let
  mkExt = set: path: lib.attrByPath path null set;
  pick = ext: lib.optional (ext != null) ext;

  marketplace = pkgs.nix-vscode-extensions.vscode-marketplace or {};

  vscodeCfg = settings.vscode or { };
  extensionCfg = vscodeCfg.extensions or { };
  openVSXIds = extensionCfg.openVSX or [ ];
  marketplaceIds = extensionCfg.marketplace or [ ];

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
        ++ resolveExts marketplace marketplaceIds;

      userSettings = {
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
    };
  };
}
