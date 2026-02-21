{ lib, pkgs, settings, ... }:
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
        // lib.optionalAttrs (sshProfile ? identityFile) {
          identityFile = sshProfile.identityFile;
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
      matchBlocks =
        (builtins.listToAttrs (lib.mapAttrsToList mkSshMatchBlock gitHostProfiles))
        // lib.optionalAttrs (sshAddKeysToAgent != null) {
          "*" = {
            addKeysToAgent = sshAddKeysToAgent;
          };
        };
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
