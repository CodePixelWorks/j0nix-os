{
  inputs,
  lib,
  pkgs,
  utils,
  settings,
  ...
}:
let
  dev = settings.dev or { };
  enabled = dev.enable or true;
  mkcertCfg = dev.mkcert or { };
  mkcertDefaultEnable = mkcertCfg.enable or false;
  firefoxEnterpriseRoots = mkcertCfg.firefoxEnterpriseRoots or true;
  userOverrides = settings.userSettings or { };
  allUsers = builtins.attrNames userOverrides;
  mkcertUsers = lib.filter (
    name:
    let
      userMkcert = ((((userOverrides.${name} or { }).dev or { }).mkcert or { }));
    in
    userMkcert.enable or mkcertDefaultEnable
  ) allUsers;
  mkcertEnabled = mkcertUsers != [ ];
  dockerCfg = dev.docker or { };
  dockerDataRoot = dockerCfg.dataRoot or null;
  systemMounts = (settings.storage or { }).systemMounts or [ ];
  isPathUnderMount = mountPoint: dataRoot:
    let
      mp = lib.removeSuffix "/" mountPoint;
      dr = lib.removeSuffix "/" dataRoot;
    in
      dr == mp || lib.hasPrefix "${mp}/" dr;
  parentMount = lib.findFirst (m: (m.enable or true) && isPathUnderMount m.mountPoint dockerDataRoot) null systemMounts;
  parentMountUnit =
    if parentMount != null && (parentMount.automount or false) then
      "${utils.escapeSystemdPath (lib.removeSuffix "/" parentMount.mountPoint)}.mount"
    else
      null;
  dockerAddressPools = dockerCfg.addressPools or [ ];
  dockerDnsServers = (settings.profileDetails or { }).dockerDnsServers or [ ];
  dockerUsers = lib.filter (
    name: ((((userOverrides.${name} or { }).dev or { }).docker or { }).enable or false)
  ) allUsers;
  dockerEnabled = dockerUsers != [ ];
  virtualisationCfg = dev.virtualisation or { };
  virtualisationDefaultEnable = virtualisationCfg.enable or false;
  virtualisationUsers = lib.filter (
    name:
    let
      userVirtualisation = ((((userOverrides.${name} or { }).dev or { }).virtualisation or { }));
    in
    userVirtualisation.enable or virtualisationDefaultEnable
  ) allUsers;
  virtualisationEnabled = virtualisationUsers != [ ];
  ai = dev.ai or { };
  aiUsers = lib.filter (
    name: ((((userOverrides.${name} or { }).dev or { }).ai or { }).enable or false)
  ) allUsers;
  aiEnabled = aiUsers != [ ];
  aiInstallScope = ai.installScope or "system"; # "system" | "user"
  codex = import ./codex.nix {
    inherit
      inputs
      lib
      pkgs
      settings
      ;
  };
  codexEnabled = codex.enabled;
  ncpEnabled = ai.ncp or true;
  ncpPackage = pkgs.writeShellApplication {
    name = "ncp";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      exec ${pkgs.nodejs}/bin/npx --yes @portel/ncp "$@"
    '';
  };
  kiloCodeEnabled = ai.kiloCode or true;
  kiloCodePackage = pkgs.writeShellApplication {
    name = "kilocode";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      exec ${pkgs.nodejs}/bin/npx --yes @kilocode/cli@alpha "$@"
    '';
  };
  opencodeEnabled = ai.opencode or true;
  opencodePackage = if builtins.hasAttr "opencode" pkgs then pkgs.opencode else null;
  claudeCodeEnabled = ai.claudeCode or true;
  claudeCodePackage = if builtins.hasAttr "claude-code" pkgs then pkgs."claude-code" else null;
  sshUsers = lib.filter (
    name: ((((userOverrides.${name} or { }).dev or { }).ssh or { }).enable or false)
  ) allUsers;
  sshEnabled = sshUsers != [ ];
  sshUsersNeedingKeyring = lib.filter (
    name:
    let
      sshCfg = (((userOverrides.${name} or { }).dev or { }).ssh or { });
      agent = sshCfg.agent or { };
      provider = agent.provider or "openssh";
      keyring = sshCfg.keyring or { };
    in
    (keyring.enable or false)
    || builtins.elem provider [
      "gnome-keyring"
      "auto"
    ]
  ) sshUsers;
  sshAgentProviders = lib.unique (
    map (
      name:
      let
        sshCfg = (((userOverrides.${name} or { }).dev or { }).ssh or { });
        agent = sshCfg.agent or { };
      in
      agent.provider or "openssh"
    ) sshUsers
  );
  sshAgentProvider = if sshAgentProviders == [ ] then "openssh" else builtins.head sshAgentProviders;
  sshAgent = {
    provider = sshAgentProvider;
  };
  sshAgentEnable = sshAgent.enable or true;
  keyringEnable = sshUsersNeedingKeyring != [ ];
  antigravityEnabled = ai.antigravity or (ai.gemini or true);
  hermesEnabled = ai.hermes or true;
  hermesPackage = pkgs.hermes-agent-with-firecrawl or null;
  antigravityInstaller = pkgs.writeShellApplication {
    name = "antigravity-install";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
    ];
    text = ''
      target_dir="''${ANTIGRAVITY_INSTALL_DIR:-''${XDG_BIN_HOME:-$HOME/.local/bin}}"
      tmp_dir="$(mktemp -d)"
      trap 'rm -rf "$tmp_dir"' EXIT

      install_script="$tmp_dir/install.sh"
      curl -fsSL -o "$install_script" https://antigravity.google/cli/install.sh

      if [ "$#" -eq 0 ]; then
        set -- --dir "$target_dir"
      fi

      exec bash "$install_script" "$@"
    '';
  };
  antigravityLauncher = pkgs.writeShellApplication {
    name = "antigravity-launcher";
    runtimeInputs = [ antigravityInstaller ];
    text = ''
      target_dir="''${ANTIGRAVITY_INSTALL_DIR:-''${XDG_BIN_HOME:-$HOME/.local/bin}}"
      binary_path="$target_dir/agy"

      if ! command -v agy >/dev/null 2>&1 && [ ! -x "$binary_path" ]; then
        antigravity-install
      fi

      if command -v agy >/dev/null 2>&1; then
        exec agy "$@"
      elif [ -x "$binary_path" ]; then
        exec "$binary_path" "$@"
      else
        echo "Antigravity CLI not found after installation"
        exit 1
      fi
    '';
  };
in
{
  imports = [
    ./nix-ld.nix
    ./qdrant.nix
    ./crw.nix
    ./ai-image-stack.nix
  ];

  config = lib.mkIf enabled {
    virtualisation.docker = lib.mkIf dockerEnabled {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = dockerCfg.autoPrune or true;
      daemon.settings = {
        features.buildkit = true;
        experimental = false;
      }
      // lib.optionalAttrs (dockerAddressPools != [ ]) {
        default-address-pools = dockerAddressPools;
      }
      // lib.optionalAttrs (dockerDnsServers != [ ]) {
        dns = dockerDnsServers;
      }
      // lib.optionalAttrs (dockerDataRoot != null) {
        data-root = dockerDataRoot;
      };
    };

    systemd.services.docker = lib.mkIf (dockerEnabled && dockerDataRoot != null) {
      after = lib.optional (parentMountUnit != null) parentMountUnit;
      requires = lib.optional (parentMountUnit != null) parentMountUnit;
      serviceConfig.ExecStartPre = [
        (pkgs.writeShellScript "docker-data-root-check" ''
          parent=$(dirname "${dockerDataRoot}")
          if [ ! -d "$parent" ]; then
            echo "ERROR: Docker data-root parent $parent is not available. External drive not mounted?"
            exit 1
          fi
          ${pkgs.coreutils}/bin/mkdir -p "${dockerDataRoot}"
        '')
      ];
    };

    j0nix.desktop.virtualisation.libvirtd.enable = lib.mkIf virtualisationEnabled (lib.mkForce true);

    j0nix.software.systemPackages =
      lib.optionals dockerEnabled (
        with pkgs;
        [
          docker-compose
          dive
          lazydocker
        ]
      )
      ++ lib.optionals keyringEnable [
        pkgs.seahorse
      ]
      ++ lib.optionals (
        aiEnabled && aiInstallScope == "system" && codexEnabled && codex.cliPackage != null
      ) [ codex.cliPackage ]
      ++ lib.optionals (aiEnabled && aiInstallScope == "system" && codexEnabled) (
        map (server: server.package) (builtins.attrValues codex.mcpServers)
      )
      ++ lib.optionals (
        aiEnabled && aiInstallScope == "system" && codexEnabled && codex.mcpLspEnable
      ) codex.mcpLspRuntimePackages
      ++ lib.optionals (aiEnabled && aiInstallScope == "system" && ncpEnabled) [ ncpPackage ]
      ++ lib.optionals (aiEnabled && aiInstallScope == "system" && kiloCodeEnabled) [ kiloCodePackage ]
      ++ lib.optionals (
        aiEnabled && aiInstallScope == "system" && opencodeEnabled && opencodePackage != null
      ) [ opencodePackage ]
      ++ lib.optionals (
        aiEnabled && aiInstallScope == "system" && claudeCodeEnabled && claudeCodePackage != null
      ) [ claudeCodePackage ]
      ++ lib.optionals (aiEnabled && aiInstallScope == "system" && antigravityEnabled) [
        antigravityInstaller
        antigravityLauncher
      ]
      ++ lib.optionals (
        aiEnabled && aiInstallScope == "system" && hermesEnabled && hermesPackage != null
      ) [ hermesPackage ]
      ++ lib.optionals (aiEnabled && aiInstallScope == "system") [ pkgs.bubblewrap ];

    programs.ssh.startAgent = sshEnabled && sshAgentEnable && sshAgentProvider == "openssh";

    systemd.user.services.j0nix-openssh-agent =
      lib.mkIf (sshEnabled && sshAgentEnable && sshAgentProvider == "auto")
        {
          description = "j0nix OpenSSH Agent for console sessions";
          wantedBy = [ "default.target" ];
          unitConfig.ConditionUser = "!@system";
          serviceConfig = {
            ExecStartPre = "${pkgs.coreutils}/bin/rm -f %t/ssh-agent";
            ExecStart = "${pkgs.openssh}/bin/ssh-agent -a %t/ssh-agent";
            StandardOutput = "null";
            Type = "forking";
            Restart = "on-failure";
            SuccessExitStatus = "0 2";
          };
        };

    services.gnome.gcr-ssh-agent.enable = lib.mkForce (
      sshEnabled
      && sshAgentEnable
      && builtins.elem sshAgentProvider [
        "gnome-keyring"
        "auto"
      ]
    );

    services.gnome.gnome-keyring.enable =
      keyringEnable
      || (
        sshEnabled
        && sshAgentEnable
        && builtins.elem sshAgentProvider [
          "gnome-keyring"
          "auto"
        ]
      );

    programs.firefox.policies = lib.mkIf (mkcertEnabled && firefoxEnterpriseRoots) {
      Certificates = {
        ImportEnterpriseRoots = true;
      };
    };

    assertions = [
      {
        assertion = builtins.isBool mkcertDefaultEnable;
        message = "settings.dev.mkcert.enable must be a boolean";
      }
      {
        assertion = builtins.isBool firefoxEnterpriseRoots;
        message = "settings.dev.mkcert.firefoxEnterpriseRoots must be a boolean";
      }
      {
        assertion = codex.validProvider;
        message = codex.providerMessage;
      }
      {
        assertion = (!codexEnabled) || codex.provider != "compat" || codex.compatAvailable;
        message = codex.compatMessage;
      }
      {
        assertion = (!codex.mcpNixosEnable) || codex.mcpNixosPackage != null;
        message = "settings.dev.ai.codex.mcp.nixos=true but pkgs.mcp-nixos is unavailable";
      }
      {
        assertion = (!codex.mcpGithubEnable) || codex.mcpGithubPackage != null;
        message = "settings.dev.ai.codex.mcp.github=true but pkgs.github-mcp-server is unavailable";
      }
      {
        assertion = (!codex.mcpHyprlandEnable) || codex.mcpHyprlandPackage != null;
        message = "settings.dev.ai.codex.mcp.hyprland=true but the hyprmcp wrapper package is unavailable";
      }
      {
        assertion = (!codex.mcpLspEnable) || codex.mcpLspPackage != null;
        message = "settings.dev.ai.codex.mcp.lsp.enable=true but pkgs.mcp-language-server-j0nix is unavailable";
      }
      {
        assertion = codex.validMcpLspLanguages;
        message = "settings.dev.ai.codex.mcp.lsp.languages contains unsupported values. Supported languages: ${lib.concatStringsSep ", " codex.supportedMcpLspLanguages}";
      }
      {
        assertion = (!opencodeEnabled) || opencodePackage != null;
        message = "settings.dev.ai.opencode=true but pkgs.opencode is unavailable";
      }
      {
        assertion = (!claudeCodeEnabled) || claudeCodePackage != null;
        message = "settings.dev.ai.claudeCode=true but pkgs.\"claude-code\" is unavailable";
      }
      {
        assertion = builtins.elem aiInstallScope [
          "system"
          "user"
        ];
        message = "settings.dev.ai.installScope must be one of: system, user";
      }
      {
        assertion = builtins.elem sshAgentProvider [
          "openssh"
          "gnome-keyring"
          "auto"
          "none"
        ];
        message = "settings.userSettings.<name>.dev.ssh.agent.provider must be one of: openssh, gnome-keyring, auto, none";
      }
      {
        assertion = builtins.length sshAgentProviders <= 1;
        message = "All enabled settings.userSettings.<name>.dev.ssh.agent.provider values must agree. Mixed SSH agent providers are not supported.";
      }
      {
        assertion = (!hermesEnabled) || hermesPackage != null;
        message = "settings.dev.ai.hermes=true but inputs.hermes-agent package is unavailable for this system";
      }
      {
        assertion = builtins.isList dockerAddressPools;
        message = "settings.dev.docker.addressPools must be a list of { base, size } entries.";
      }
      {
        assertion = builtins.isList dockerDnsServers && lib.all builtins.isString dockerDnsServers;
        message = "settings.profileDetails.dockerDnsServers must be a list of DNS server address strings.";
      }
      {
        assertion = lib.all (
          pool:
          builtins.isAttrs pool
          && (pool ? base)
          && (pool ? size)
          && builtins.isString pool.base
          && builtins.isInt pool.size
        ) dockerAddressPools;
        message = "Each settings.dev.docker.addressPools entry must be an attrset with string `base` and int `size`.";
      }
      {
        assertion = builtins.isBool (virtualisationCfg.enable or false);
        message = "settings.dev.virtualisation.enable must be a boolean";
      }
      {
        assertion = builtins.isBool (virtualisationCfg.vagrant or true);
        message = "settings.dev.virtualisation.vagrant must be a boolean";
      }
      {
        assertion = builtins.isBool (virtualisationCfg.qemu or true);
        message = "settings.dev.virtualisation.qemu must be a boolean";
      }
    ];
  };
}
