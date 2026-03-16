{ inputs, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  enabled = dev.enable or true;
  userOverrides = settings.userSettings or { };
  allUsers = builtins.attrNames userOverrides;
  dockerCfg = dev.docker or { };
  dockerAddressPools = dockerCfg.addressPools or [ ];
  dockerUsers =
    lib.filter
      (name: ((((userOverrides.${name} or { }).dev or { }).docker or { }).enable or false))
      allUsers;
  dockerEnabled = dockerUsers != [ ];
  ai = dev.ai or { };
  aiUsers =
    lib.filter
      (name: ((((userOverrides.${name} or { }).dev or { }).ai or { }).enable or false))
      allUsers;
  aiEnabled = aiUsers != [ ];
  aiInstallScope = ai.installScope or "system"; # "system" | "user"
  codex = import ./codex.nix { inherit inputs lib pkgs settings; };
  codexEnabled = codex.enabled;
  sshUsers =
    lib.filter
      (name: ((((userOverrides.${name} or { }).dev or { }).ssh or { }).enable or false))
      allUsers;
  sshEnabled = sshUsers != [ ];
  sshUsersNeedingKeyring =
    lib.filter
      (name:
        let
          sshCfg = (((userOverrides.${name} or { }).dev or { }).ssh or { });
          agent = sshCfg.agent or { };
          provider = agent.provider or "openssh";
          keyring = sshCfg.keyring or { };
        in
        (keyring.enable or false) || provider == "gnome-keyring")
      sshUsers;
  sshAgentProviders = lib.unique (map
    (name:
      let
        sshCfg = (((userOverrides.${name} or { }).dev or { }).ssh or { });
        agent = sshCfg.agent or { };
      in
      agent.provider or "openssh")
    sshUsers);
  sshAgentProvider =
    if sshAgentProviders == [ ] then
      "openssh"
    else
      builtins.head sshAgentProviders;
  sshAgent = { provider = sshAgentProvider; };
  sshAgentEnable = sshAgent.enable or true;
  keyringEnable = sshUsersNeedingKeyring != [ ];
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
{
  imports = [
    ./nix-ld.nix
  ];

  config = lib.mkIf enabled {
  virtualisation.docker = lib.mkIf dockerEnabled {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = dockerCfg.autoPrune or true;
    daemon.settings = {
      features.buildkit = true;
      experimental = false;
    } // lib.optionalAttrs (dockerAddressPools != [ ]) {
      default-address-pools = dockerAddressPools;
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
    ++ lib.optionals (aiEnabled && aiInstallScope == "system" && codexEnabled && codex.mcpNixosEnable) [ pkgs.mcp-nixos ]
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
      assertion = (!codex.mcpNixosEnable) || (pkgs ? mcp-nixos);
      message = "settings.dev.ai.codex.mcp.nixos=true but pkgs.mcp-nixos is unavailable";
    }
    {
      assertion = builtins.elem aiInstallScope [ "system" "user" ];
      message = "settings.dev.ai.installScope must be one of: system, user";
    }
    {
      assertion = builtins.elem sshAgentProvider [ "openssh" "gnome-keyring" "none" ];
      message = "settings.userSettings.<name>.dev.ssh.agent.provider must be one of: openssh, gnome-keyring, none";
    }
    {
      assertion = builtins.length sshAgentProviders <= 1;
      message = "All enabled settings.userSettings.<name>.dev.ssh.agent.provider values must agree. Mixed SSH agent providers are not supported.";
    }
    {
      assertion = (!aiEnabled) || (!geminiEnabled) || hasGeminiPackage;
      message = "settings.dev.ai.gemini=true but pkgs.gemini-cli is unavailable";
    }
    {
      assertion = builtins.isList dockerAddressPools;
      message = "settings.dev.docker.addressPools must be a list of { base, size } entries.";
    }
    {
      assertion = lib.all
        (pool:
          builtins.isAttrs pool
          && (pool ? base)
          && (pool ? size)
          && builtins.isString pool.base
          && builtins.isInt pool.size)
        dockerAddressPools;
      message = "Each settings.dev.docker.addressPools entry must be an attrset with string `base` and int `size`.";
    }
  ];
  };
}
