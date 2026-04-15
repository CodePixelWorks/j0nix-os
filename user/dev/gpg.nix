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
  userSecretsCfg = ((settings.secrets or { }).user or { });
  gpgKeysSecretName = gpgCfg.keysSecretName or "gpg/keys";
  gpgPassphraseSecretName = gpgCfg.passphraseSecretName or "gpg/master-passphrase";
  keepassCfg = (settings.programs or { }).keepassxc or { };
  keepassEnabled = keepassCfg.enable or false;
  keepassAutoUnlock = keepassCfg.autoUnlock or { };
  keyringEntry = keepassAutoUnlock.keyringEntry or null;
  passwordSecretName = keepassAutoUnlock.sopsPasswordSecret or null;
  gpgHasPassphrase = gpgCfg.keyPhraseSecretName != null;
in
{
  imports = [ ];

  config = lib.mkIf gpgEnabled {
    programs.gnupg = {
      enable = true;
      dirmngr.enable = true;
      settings = {
        default-key = sshAgentCfg.defaultKey or gpgCfg.defaultKey or null;
        default-recipient-self = false;
        encrypt-to = sshAgentCfg.defaultKey or gpgCfg.defaultKey or null;
        use-agent = true;
        agent-program = "${pkgs.gnupg}/bin/gpg-agent";
        pinentry-program = "${pkgs.pinentry-gnome3}/bin/pinentry-gnome3";
        log-file = "socket://${config.home.homeDirectory}/.gnupg/log";
        additional-locked-memory = false;
        s2k-count = 65536;
        chmod = "0600";
      };
      scdaemonSettings = {
        disable-ccid = true;
      };
    };

    programs.git.signing = lib.mkIf (gitSigningCfg.enable or true) {
      enable = true;
      key = gitSigningCfg.key or null;
      signByDefault = gitSigningCfg.signByDefault or true;
    };

    programs.ssh = {
      enable = sshAgentEnabled;
      enableDefaultConfig = false;
      finalConfig = lib.mkIf sshAgentEnabled {
        identityagent = "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh";
      };
    };

    j0nix.user.software.packages = [
      pkgs.gnupg
    ]
    ++ lib.optionals sshAgentEnabled [ pkgs.pinentry-gnome3 ];

    home.activation.gpgSshAgentReady = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      GNUPGHOME="${config.home.homeDirectory}/.gnupg"
      export GNUPGHOME
      if [ ! -S "''${GNUPGHOME}/S.gpg-agent.ssh" ]; then
        mkdir -p "''${GNUPGHOME}"
        chmod 700 "''${GNUPGHOME}"
        if [ -f "''${GNUPGHOME}/gpg-agent.conf" ]; then
          ${pkgs.gnupg}/bin/gpg-agent --homedir "''${GNUPGHOME}" --daemon 2>/dev/null || true
        fi
      fi
    '';

    home.sessionVariables = lib.mkIf sshAgentEnabled {
      SSH_AUTH_SOCK = "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh";
      GPG_AGENT_SSH = "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh";
    };

    systemd.user.services.gpg-agent = lib.mkIf sshAgentEnabled {
      Unit = {
        Description = "GPG Agent for SSH and GPG operations";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "forking";
        ExecStart = "${pkgs.gnupg}/bin/gpg-agent --homedir ${config.home.homeDirectory}/.gnupg --daemon";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-abort";
        RestartSec = 1;
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    assertions = [
      {
        assertion = !(sshAgentEnabled && sshAgentCfg.defaultKey == null) || gpgCfg.defaultKey != null;
        message = "GPG SSH agent requires a default key to be set via settings.dev.gpg.defaultKey or settings.dev.gpg.sshAgent.defaultKey";
      }
    ];
  };
}
