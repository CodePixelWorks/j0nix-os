{ inputs, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  enabled = dev.enable or true;
  dockerCfg = dev.docker or { };
  ai = dev.ai or { };
  codexEnabled = (ai.enable or true) && (ai.codex or true);
in
lib.mkIf enabled {
  virtualisation.docker = lib.mkIf (dockerCfg.enable or true) {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = dockerCfg.autoPrune or true;
    daemon.settings = {
      features.buildkit = true;
      experimental = false;
    };
  };

  environment.systemPackages = with pkgs; [
    docker-compose
    dive
    lazydocker
  ] ++ lib.optionals codexEnabled [
    inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
