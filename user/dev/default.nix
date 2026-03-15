{ config, lib, pkgs, settings, ... }:
let
  dev = settings.dev or { };
  enabled = dev.enable or true;
  gitCfg = dev.git or { };
  gitEnabled = gitCfg.enable or true;
  gitUserName = gitCfg.userName or (settings.name or settings.username);
  gitUserEmail = gitCfg.userEmail or (settings.email or "${settings.username}@localhost");
  gitDefaultBranch = gitCfg.defaultBranch or "main";
  gitHostProfiles = gitCfg.hostProfiles or { };

  sshCfg = dev.ssh or { };
  sshHosts = sshCfg.hosts or { };
  sshEnabled = sshCfg.enable or true;
  sshAddKeysToAgent = sshCfg.addKeysToAgent or "yes";
  sshAgentCfg = sshCfg.agent or { };
  sshAgentProvider = sshAgentCfg.provider or "openssh";
  keyringCfg = sshCfg.keyring or { };
  keyringEnabled = keyringCfg.enable or false;
  userSecretsCfg = ((settings.secrets or { }).user or { });
  deployedSshKeys = userSecretsCfg.sshKeys or { };
  sshKeysWithPassphrases =
    lib.filterAttrs (_: spec: (spec.passphraseKey or null) != null) deployedSshKeys;
  supportedSshProfileKeys = [
    "match"
    "port"
    "forwardAgent"
    "forwardX11"
    "forwardX11Trusted"
    "identityAgent"
    "serverAliveInterval"
    "serverAliveCountMax"
    "sendEnv"
    "setEnv"
    "compression"
    "checkHostIP"
    "proxyCommand"
    "proxyJump"
    "addKeysToAgent"
    "hashKnownHosts"
    "userKnownHostsFile"
    "controlMaster"
    "controlPath"
    "controlPersist"
    "certificateFile"
    "addressFamily"
    "kexAlgorithms"
    "localForwards"
    "remoteForwards"
    "dynamicForwards"
  ];
  deployedIdentityPathFor = keyName:
    if !(builtins.hasAttr keyName deployedSshKeys) then
      null
    else
      let
        spec = deployedSshKeys.${keyName};
        targetName = spec.targetName or keyName;
      in
      "~/.ssh/${targetName}";

  mkGitHostInclude = name: profile:
    let
      profileUserName = profile.userName or gitUserName;
      profileUserEmail = profile.userEmail or gitUserEmail;
    in
    {
      name = "git/hosts/${name}.inc";
      value.text = ''
        [user]
          name = ${profileUserName}
          email = ${profileUserEmail}
      '';
    };

  mkGitIncludes = name: profile:
    let
      sshHost = sshHosts.${name} or { };
      host = profile.host or (sshHost.host or name);
      includePath = "~/.config/git/hosts/${name}.inc";
    in
    [
      {
        condition = "hasconfig:remote.*.url:git@${host}:**";
        path = includePath;
      }
      {
        condition = "hasconfig:remote.*.url:https://${host}/**";
        path = includePath;
      }
    ];

  mkSshMatchBlocks = name: sshProfile:
    let
      host = sshProfile.host or name;
      aliases = sshProfile.aliases or [ ];
      resolvedIdentityFile =
        if sshProfile ? identityKey then
          let
            deployedPath = deployedIdentityPathFor sshProfile.identityKey;
          in
          if deployedPath != null then
            deployedPath
          else if lib.hasAttrByPath [ sshProfile.identityKey ] (config.sops.secrets or { }) then
            lib.getAttrFromPath [ sshProfile.identityKey "path" ] config.sops.secrets
          else
            (sshProfile.identityFile or null)
        else if sshProfile ? identitySecretName then
          let
            deployedPath = deployedIdentityPathFor sshProfile.identitySecretName;
          in
          if deployedPath != null then
            deployedPath
          else if lib.hasAttrByPath [ sshProfile.identitySecretName ] (config.sops.secrets or { }) then
            lib.getAttrFromPath [ sshProfile.identitySecretName "path" ] config.sops.secrets
          else
            (sshProfile.identityFile or null)
        else
          (sshProfile.identityFile or null);
      commonValue =
        {
          hostname = host;
          user = sshProfile.user or "git";
          identitiesOnly = sshProfile.identitiesOnly or false;
          extraOptions = sshProfile.options or { };
        }
        // lib.optionalAttrs (resolvedIdentityFile != null) {
          identityFile = resolvedIdentityFile;
        }
        // lib.optionalAttrs (sshProfile ? match) {
          match = sshProfile.match;
        }
        // lib.filterAttrs (key: _: builtins.elem key supportedSshProfileKeys) sshProfile;
      mkBlock = attrName: {
        name = attrName;
        value = commonValue;
      };
    in
    [
      (mkBlock name)
    ] ++ map mkBlock aliases;
  loadSecretBackedSshKeysScript =
    let
      loadKey = name: spec:
        let
          targetName = spec.targetName or name;
          privatePath = "${config.home.homeDirectory}/.ssh/${targetName}";
          passphraseSecretName = "${name}-passphrase";
          passphrasePath = config.sops.secrets.${passphraseSecretName}.path;
        in
        ''
          if [ -f ${lib.escapeShellArg privatePath} ] && [ -f ${lib.escapeShellArg passphrasePath} ]; then
            passphrase="$(cat ${lib.escapeShellArg passphrasePath})"
            if ${pkgs.openssh}/bin/ssh-keygen -y -P "$passphrase" -f ${lib.escapeShellArg privatePath} > /dev/null 2>&1; then
              askpass="$(mktemp)"
              printf '%s\n' '#!/bin/sh' 'exec cat ${lib.escapeShellArg passphrasePath}' > "$askpass"
              chmod 700 "$askpass"
              load_attempt=0
              loaded=0
              while [ "$load_attempt" -lt 5 ]; do
                if DISPLAY="''${DISPLAY:-:0}" SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force \
                  setsid -w ${pkgs.openssh}/bin/ssh-add ${lib.escapeShellArg privatePath} < /dev/null > /dev/null 2>&1; then
                  loaded=1
                  break
                fi
                load_attempt=$((load_attempt + 1))
                sleep 1
              done
              if [ "$loaded" -ne 1 ]; then
                echo "warning: failed to load ${targetName} into the SSH agent" >&2
              fi
              rm -f "$askpass"
            else
              echo "warning: passphrase secret does not unlock ${targetName}; skipping automatic SSH agent load" >&2
            fi
          fi
        '';
    in
    pkgs.writeShellScriptBin "ssh-load-secret-keys" ''
      set -eu
      agent_socket="''${SSH_AUTH_SOCK:-''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh}"
      wait_attempt=0
      while [ "$wait_attempt" -lt 20 ] && [ ! -S "$agent_socket" ]; do
        wait_attempt=$((wait_attempt + 1))
        sleep 1
      done
      if [ ! -S "$agent_socket" ]; then
        echo "warning: SSH agent socket $agent_socket was not ready; skipping declarative SSH key load" >&2
        exit 0
      fi
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList loadKey sshKeysWithPassphrases)}
    '';
  guiSshAskpass = "${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass";
  sshAddGuiScript = pkgs.writeShellScriptBin "ssh-add-gui" ''
    set -eu
    exec env SSH_ASKPASS='${guiSshAskpass}' SSH_ASKPASS_REQUIRE=force \
      ${pkgs.util-linux}/bin/setsid -w ${pkgs.openssh}/bin/ssh-add "$@" < /dev/null
  '';
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

    programs.git = lib.mkIf gitEnabled {
      enable = true;
      settings = {
        user = {
          name = gitUserName;
          email = gitUserEmail;
        };
        init.defaultBranch = gitDefaultBranch;
        pull.rebase = false;
      };
      includes = lib.flatten (lib.mapAttrsToList mkGitIncludes gitHostProfiles);
    };

    xdg.configFile = lib.mkIf gitEnabled (builtins.listToAttrs (lib.mapAttrsToList mkGitHostInclude gitHostProfiles));

    home.sessionVariables =
      lib.optionalAttrs (sshEnabled && sshAgentProvider == "gnome-keyring") {
        SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";
      };

    programs.ssh = lib.mkIf sshEnabled {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks =
        (builtins.listToAttrs (lib.concatLists (lib.mapAttrsToList mkSshMatchBlocks sshHosts)))
        // {
          "*" = {
            forwardAgent = false;
            addKeysToAgent = if sshAddKeysToAgent != null then sshAddKeysToAgent else "no";
            compression = false;
            serverAliveInterval = 0;
            serverAliveCountMax = 3;
            hashKnownHosts = false;
            userKnownHostsFile = "~/.ssh/known_hosts";
            controlMaster = "no";
            controlPath = "~/.ssh/master-%r@%n:%p";
            controlPersist = "no";
          };
        };
    };

    j0nix.user.software.packages =
      (with pkgs; [
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
        openssl
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
        openssh-askpass
      ])
      ++ lib.optionals (sshEnabled && sshAgentProvider == "gnome-keyring") [ sshAddGuiScript ]
      ++ lib.optionals (sshEnabled && sshAgentProvider == "gnome-keyring" && sshKeysWithPassphrases != { }) [
        loadSecretBackedSshKeysScript
      ];

    systemd.user.services.ssh-secret-keys-load = lib.mkIf (sshEnabled && sshAgentProvider == "gnome-keyring" && sshKeysWithPassphrases != { }) {
      Unit = {
        Description = "Load declarative secret-backed SSH keys into the SSH agent";
        After = [ "graphical-session.target" "gcr-ssh-agent.service" ];
        PartOf = [ "graphical-session.target" ];
        Wants = [ "gcr-ssh-agent.service" ];
      };
      Service = {
        Type = "oneshot";
        Environment = [ "SSH_AUTH_SOCK=%t/gcr/ssh" ];
        ExecStart = "${lib.getExe loadSecretBackedSshKeysScript}";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    assertions = [
      {
        assertion = (sshKeysWithPassphrases == { }) || sshAgentProvider == "gnome-keyring";
        message = "settings.userSettings.<name>.secrets.sshKeys.<name>.passphraseKey requires settings.userSettings.<name>.dev.ssh.agent.provider = gnome-keyring for automatic keyring loading.";
      }
    ];
  };
}
