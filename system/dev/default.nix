{ inputs, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  enabled = dev.enable or true;
  userOverrides = settings.userSettings or { };
  dockerCfg = dev.docker or { };
  dockerUsers =
    lib.filter
      (name: ((((userOverrides.${name} or { }).dev or { }).docker or { }).enable or false))
      (builtins.attrNames userOverrides);
  dockerEnabled = dockerUsers != [ ];
  ai = dev.ai or { };
  aiUsers =
    lib.filter
      (name: ((((userOverrides.${name} or { }).dev or { }).ai or { }).enable or false))
      (builtins.attrNames userOverrides);
  aiEnabled = aiUsers != [ ];
  aiInstallScope = ai.installScope or "system"; # "system" | "user"
  codex = import ./codex.nix { inherit inputs lib pkgs settings; };
  codexEnabled = codex.enabled;
  sshCfg = dev.ssh or { };
  sshEnabled = sshCfg.enable or true;
  sshAgent = sshCfg.agent or { };
  sshAgentEnable = sshAgent.enable or true;
  sshAgentProvider = sshAgent.provider or "openssh"; # "openssh" | "gnome-keyring" | "none"
  keyring = sshCfg.keyring or { };
  keyringEnable = keyring.enable or false;
  geminiEnabled = ai.gemini or true;
  hasGeminiPackage = pkgs ? gemini-cli;
  geminiLauncher = pkgs.writeShellScriptBin "gemini-launcher" ''
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
  '';
in
lib.mkIf enabled {
  virtualisation.docker = lib.mkIf dockerEnabled {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = dockerCfg.autoPrune or true;
    daemon.settings = {
      features.buildkit = true;
      experimental = false;
    };
  };

  j0nix.software.systemPackages =
    lib.optionals dockerEnabled (with pkgs; [
      docker-compose
      dive
      lazydocker
    ]) ++ lib.optionals keyringEnable [
    pkgs.seahorse
  ] ++ lib.optionals (aiEnabled && aiInstallScope == "system" && codexEnabled && codex.cliPackage != null) [ codex.cliPackage ]
    ++ lib.optionals (aiEnabled && aiInstallScope == "system" && geminiEnabled && hasGeminiPackage) [
      pkgs.gemini-cli
      geminiLauncher
    ];

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
      assertion = builtins.elem aiInstallScope [ "system" "user" ];
      message = "settings.dev.ai.installScope must be one of: system, user";
    }
    {
      assertion = builtins.elem sshAgentProvider [ "openssh" "gnome-keyring" "none" ];
      message = "settings.dev.ssh.agent.provider must be one of: openssh, gnome-keyring, none";
    }
    {
      assertion = (sshAgentProvider != "gnome-keyring") || keyringEnable;
      message = "settings.dev.ssh.agent.provider=gnome-keyring requires settings.dev.ssh.keyring.enable=true";
    }
    {
      assertion = (!aiEnabled) || (!geminiEnabled) || hasGeminiPackage;
      message = "settings.dev.ai.gemini=true but pkgs.gemini-cli is unavailable";
    }
  ];
}
