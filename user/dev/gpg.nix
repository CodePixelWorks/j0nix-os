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
  pinentryWrapper = pkgs.writeShellScript "gpg-pinentry" ''
    set -eu

    if [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; then
      exec ${pkgs.pinentry-gnome3}/bin/pinentry-gnome3 "$@"
    fi

    exec ${pkgs.pinentry-gnome3}/bin/pinentry-tty "$@"
  '';

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

  defaultKeyName = sshAgentCfg.keyName or (lib.head (builtins.attrNames gpgKeys));
  defaultKey = if defaultKeyName != null then gpgKeys.${defaultKeyName}.key or null else null;
in
{
  imports = [ ];

  config = lib.mkIf gpgEnabled {
    programs.gpg = {
      enable = true;
      settings = lib.mkIf (gpgKeys != { }) {
        use-agent = true;
        default-key = defaultKey;
        keyserver = "hkps://keys.openpgp.org";
        personal-cipher-preferences = [
          "AES256"
          "AES192"
          "AES128"
        ];
        personal-digest-preferences = [
          "SHA512"
          "SHA384"
          "SHA256"
        ];
        default-preference-list = [
          "SHA512"
          "AES256"
          "AES192"
          "AES128"
        ];
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
      # SSH_AUTH_SOCK is handled by dev/ssh module
    };

    home.file.".gnupg/gpg-agent.conf".text = ''
      ${lib.optionalString sshAgentEnabled "enable-ssh-support"}
      pinentry-program ${pinentryWrapper}
      default-cache-ttl 600
      max-cache-ttl 7200
    '';

    j0nix.user.software.packages = [
      pkgs.gnupg
      pkgs.pinentry-gnome3
    ];
  };
}
