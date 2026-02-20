{ pkgs, lib, ... }:
let
  mkExt = set: path: lib.attrByPath path null set;
  pick = ext: lib.optional (ext != null) ext;

  marketplace = pkgs.nix-vscode-extensions.vscode-marketplace or {};
in {
  programs.vscode = {
    enable = true;
    profiles.default = {
      extensions =
        pick (mkExt pkgs.vscode-extensions [ "vscodevim" "vim" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "bbenoist" "nix" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "jnoortheen" "nix-ide" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "arrterian" "nix-env-selector" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "ms-python" "python" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "ms-python" "vscode-pylance" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "rust-lang" "rust-analyzer" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "golang" "go" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "redhat" "vscode-yaml" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "ms-azuretools" "vscode-docker" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "ms-vscode-remote" "remote-ssh" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "ms-vscode-remote" "remote-containers" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "ms-vscode" "cpptools-extension-pack" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "tamasfe" "even-better-toml" ])
        ++ pick (mkExt pkgs.vscode-extensions [ "esbenp" "prettier-vscode" ])
        ++ pick (mkExt marketplace [ "eamodio" "gitlens" ])
        ++ pick (mkExt marketplace [ "github" "copilot" ])
        ++ pick (mkExt marketplace [ "github" "copilot-chat" ]);

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
