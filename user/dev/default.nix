{ lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  enabled = dev.enable or true;
in
{
  imports = [
    ./ai-cli.nix
  ];

  config = lib.mkIf enabled {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    home.packages = with pkgs; [
      git
      gh
      lazygit
      just
      jq
      yq
      httpie
      hurl
      wget
      curl
      unzip
      zip
      tree
      tmux
      shellcheck
      shfmt
      nil
      nixd
      statix
      deadnix
    ];
  };
}
