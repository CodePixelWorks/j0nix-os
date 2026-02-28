{ inputs, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  enabled = dev.enable or true;
  dockerCfg = dev.docker or { };
  ai = dev.ai or { };
  codex = import ../lib/codex.nix { inherit inputs lib pkgs settings; };
  codexEnabled = codex.enabled;
  sshCfg = dev.ssh or { };
  sshEnabled = sshCfg.enable or true;
  sshAgent = sshCfg.agent or { };
  sshAgentEnable = sshAgent.enable or true;
  sshAgentProvider = sshAgent.provider or "openssh"; # "openssh" | "gnome-keyring" | "none"
  keyring = sshCfg.keyring or { };
  keyringEnable = keyring.enable or false;
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
  ] ++ lib.optionals keyringEnable [
    seahorse
  ] ++ lib.optionals (codexEnabled && codex.cliPackage != null) [ codex.cliPackage ];

  programs.ssh.startAgent = sshEnabled && sshAgentEnable && sshAgentProvider == "openssh";

  services.gnome.gcr-ssh-agent.enable =
    lib.mkForce (sshEnabled && sshAgentEnable && sshAgentProvider == "gnome-keyring");

  services.gnome.gnome-keyring.enable =
    keyringEnable || (sshEnabled && sshAgentEnable && sshAgentProvider == "gnome-keyring");

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
      assertion = builtins.elem sshAgentProvider [ "openssh" "gnome-keyring" "none" ];
      message = "settings.dev.ssh.agent.provider must be one of: openssh, gnome-keyring, none";
    }
    {
      assertion = (sshAgentProvider != "gnome-keyring") || keyringEnable;
      message = "settings.dev.ssh.agent.provider=gnome-keyring requires settings.dev.ssh.keyring.enable=true";
    }
  ];
}
