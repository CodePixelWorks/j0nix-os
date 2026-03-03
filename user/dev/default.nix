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
  sshEnabled = sshCfg.enable or true;
  sshAddKeysToAgent = sshCfg.addKeysToAgent or "yes";
  userSecretsCfg = ((settings.secrets or { }).users or { }).${settings.username} or { };
  deployedSshKeys = userSecretsCfg.sshKeys or { };
  deployedIdentityPathFor = secretName:
    let
      matches =
        lib.filterAttrs
          (name: spec:
            (spec.secretName or name) == secretName)
          deployedSshKeys;
    in
    if matches == { } then
      null
    else
      let
        keyName = builtins.head (builtins.attrNames matches);
        spec = matches.${keyName};
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
      host = profile.host or name;
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

  mkSshMatchBlock = name: profile:
    let
      host = profile.host or name;
      sshProfile = profile.ssh or { };
      resolvedIdentityFile =
        if sshProfile ? identitySecretName then
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
    in
    {
      name = name;
      value =
        {
          host = sshProfile.match or host;
          hostname = host;
          user = sshProfile.user or "git";
          identitiesOnly = sshProfile.identitiesOnly or false;
        }
        // lib.optionalAttrs (resolvedIdentityFile != null) {
          identityFile = resolvedIdentityFile;
        };
    };
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

    programs.ssh = lib.mkIf sshEnabled {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks =
        (builtins.listToAttrs (lib.mapAttrsToList mkSshMatchBlock gitHostProfiles))
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

    j0nix.user.software.packages = with pkgs; [
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
    ];
  };
}
