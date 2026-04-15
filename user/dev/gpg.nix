{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  dev = settings.dev or { };
  gpgCfg = dev.gpg or { };
  gpgEnabled = gpgCfg.enable or false;
  gpgKeys = gpgCfg.keys or { };
  gitSigningCfg = gpgCfg.gitSigning or { };
  sshAgentCfg = gpgCfg.sshAgent or { };
  sshAgentEnabled = sshAgentCfg.enable or false;

  mkGpgSigningFile =
    keyName: keySpec:
    let
      emails = keySpec.emails or [ ];
      keyPath = keySpec.key;
    in
    lib.map (email: {
      name = "git/gpg/${email}.inc";
      value = {
        text = ''
          [user]
            signingkey = ${keyPath}
        '';
      };
    }) emails;

  mkGpgSigningInclude =
    keyName: keySpec:
    let
      emails = keySpec.emails or [ ];
    in
    lib.map (email: {
      condition = "hasconfig:user.email:${email}";
      path = "~/.config/git/gpg/${email}.inc";
    }) emails;
in
{
  imports = [ ];

  config = lib.mkIf gpgEnabled {
    programs.gpg = {
      enable = true;
      settings = lib.mkIf (gpgKeys != { }) {
        use-agent = true;
      };
    };

    xdg.configFile = lib.mkIf (gpgKeys != { }) (
      builtins.listToAttrs (lib.concatLists (lib.mapAttrsToList mkGpgSigningFile gpgKeys))
    );

    programs.git = lib.mkIf gitSigningCfg.enable {
      signing = {
        signByDefault = gitSigningCfg.signByDefault or true;
      };
      includes = lib.flatten (lib.mapAttrsToList mkGpgSigningInclude gpgKeys);
    };

    home.sessionVariables = lib.mkIf sshAgentEnabled {
      GPG_AGENT_SSH = "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh";
    };

    j0nix.user.software.packages = [ pkgs.gnupg ];
  };
}
