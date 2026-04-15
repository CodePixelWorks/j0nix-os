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
  gitSigningCfg = gpgCfg.gitSigning or { };
  sshAgentCfg = gpgCfg.sshAgent or { };
  sshAgentEnabled = sshAgentCfg.enable or false;
in
{
  imports = [ ];

  config = lib.mkIf gpgEnabled {
    programs.gpg = {
      enable = true;
      settings = lib.mkIf (gitSigningCfg.key != null) {
        default-key = gitSigningCfg.key;
        use-agent = true;
      };
    };

    programs.git.signing = lib.mkIf (gitSigningCfg.key != null) {
      key = gitSigningCfg.key;
      signByDefault = gitSigningCfg.signByDefault or true;
    };

    home.sessionVariables = lib.mkIf sshAgentEnabled {
      GPG_AGENT_SSH = "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh";
    };

    j0nix.user.software.packages = [ pkgs.gnupg ];
  };
}
