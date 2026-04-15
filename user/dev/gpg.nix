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

  mkGitSigningEmail =
    keyName: keySpec:
    let
      emails = keySpec.emails or [ ];
      signByDefault = keySpec.signByDefault or false;
    in
    lib.map (email: {
      inherit email;
      signByDefault = signByDefault;
      key = keySpec.key;
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

    programs.git.signing = lib.mkIf gitSigningCfg.enable {
      signByDefault = gitSigningCfg.signByDefault or true;
    };

    programs.git.settings = lib.mkIf (gpgKeys != { }) (
      let
        signingByEmail = lib.concatLists (lib.mapAttrsToList mkGitSigningEmail gpgKeys);
      in
      lib.foldl' (
        acc: entry:
        acc
        // {
          user = acc.user or { } // {
            signingkey = if entry.signByDefault then entry.key else acc.user.signingkey or null;
          };
        }
      ) { } signingByEmail
    );

    home.sessionVariables = lib.mkIf sshAgentEnabled {
      GPG_AGENT_SSH = "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh";
    };

    j0nix.user.software.packages = [ pkgs.gnupg ];
  };
}
