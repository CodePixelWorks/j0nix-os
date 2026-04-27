{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  dev = settings.dev or { };
  enableSops = settings.enableSops or false;
  gpgCfg = dev.gpg or { };
  gpgEnabled = gpgCfg.enable or false;
  gpgKeys = gpgCfg.keys or { };
  userSecretsCfg = ((settings.secrets or { }).user or { });
  deployedGpgKeys = userSecretsCfg.gpgKeys or { };
  gitSigningCfg = gpgCfg.gitSigning or { };
  sshAgentCfg = gpgCfg.sshAgent or { };
  sshAgentEnabled = sshAgentCfg.enable or false;
  agentCacheTtl = gpgCfg.agentCacheTtl or 34560000;
  agentMaxCacheTtl = gpgCfg.agentMaxCacheTtl or agentCacheTtl;
  presetInterval = gpgCfg.presetInterval or "5min";
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

  managedGpgKeyNames = if enableSops then builtins.attrNames deployedGpgKeys else [ ];
  managedGpgKeysWithPassphrases = lib.filterAttrs (
    _: spec: (spec.passphraseKey or null) != null && (spec.presetPassphrase or true)
  ) deployedGpgKeys;
  hasManagedGpgPassphrases = enableSops && managedGpgKeysWithPassphrases != { };
  importManagedGpgKey =
    name:
    let
      spec = deployedGpgKeys.${name};
      secretPath = config.sops.secrets.${name}.path;
      passphrasePath =
        if spec ? passphraseKey then config.sops.secrets."${name}-passphrase".path else null;
      keyFingerprint = spec.fingerprint or ((gpgKeys.${name} or { }).key or "");
      keygrip = spec.keygrip or "";
      configuredKeygrips = spec.keygrips or (lib.optional (keygrip != "") keygrip);
      configuredKeygripLines = lib.concatMapStringsSep "\n" (
        grip: "printf '%s\\n' ${lib.escapeShellArg grip}"
      ) configuredKeygrips;
      statePath = "${config.home.homeDirectory}/.local/state/j0nix/gpg-import/${name}.sha256";
      presetPassphrase = (spec.passphraseKey or null) != null && (spec.presetPassphrase or true);
      presetScript =
        if presetPassphrase then
          ''
            if [ ! -f ${lib.escapeShellArg passphrasePath} ]; then
              echo "warning: GPG passphrase secret for managed key ${name} was not available; passphrase was not preloaded" >&2
            else
              keygrips="$(
                {
                  ${configuredKeygripLines}
                  ${pkgs.gnupg}/bin/gpg --batch --with-colons --with-keygrip --list-secret-keys ${lib.escapeShellArg keyFingerprint} \
                    | ${pkgs.gawk}/bin/awk -F: '$1 == "grp" { print $10 }'
                } | ${pkgs.gnused}/bin/sed '/^$/d' | ${pkgs.coreutils}/bin/sort -u
              )"

              if [ -z "$keygrips" ]; then
                echo "warning: could not determine GPG keygrip for managed key ${name}; passphrase was not preloaded" >&2
              else
                printf '%s\n' "$keygrips" | while IFS= read -r keygrip; do
                  ${pkgs.gnupg}/libexec/gpg-preset-passphrase --preset "$keygrip" < ${lib.escapeShellArg passphrasePath}
                done
              fi
            fi
          ''
        else
          "";
    in
    ''
      wait_attempt=0
      while [ "$wait_attempt" -lt 30 ] && [ ! -f ${lib.escapeShellArg secretPath} ]; do
        wait_attempt=$((wait_attempt + 1))
        sleep 1
      done

      if [ ! -f ${lib.escapeShellArg secretPath} ]; then
        echo "warning: GPG private key secret for managed key ${name} was not available; skipping import and preset" >&2
      else
        current_checksum="$(${pkgs.coreutils}/bin/sha256sum ${lib.escapeShellArg secretPath} | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
        previous_checksum=""
        if [ -f ${lib.escapeShellArg statePath} ]; then
          previous_checksum="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg statePath})"
        fi

        if [ "$current_checksum" != "$previous_checksum" ]; then
          echo "Importing managed GPG key: ${name}"
          ${pkgs.gnupg}/bin/gpg --batch --import ${lib.escapeShellArg secretPath}
          printf '%s\n' "$current_checksum" > ${lib.escapeShellArg statePath}
        fi

        if [ -n ${lib.escapeShellArg keyFingerprint} ]; then
          ${pkgs.gnupg}/bin/gpg --batch --with-colons --list-secret-keys ${lib.escapeShellArg keyFingerprint} > /dev/null
        fi

        ${presetScript}
      fi
    '';
  managedGpgImportScript = pkgs.writeShellScriptBin "gpg-load-secret-keys" ''
    set -eu

    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.gnupg"
    mkdir -p "$HOME/.local/state/j0nix/gpg-import"
    chmod 700 "$HOME/.local/state/j0nix/gpg-import"
    ${pkgs.gnupg}/bin/gpgconf --reload gpg-agent || true
    ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent || true

    ${lib.concatStringsSep "\n" (map importManagedGpgKey managedGpgKeyNames)}
  '';
  gitGpgProgram = pkgs.writeShellScript "git-gpg-with-managed-secrets" ''
    set -eu

    ${lib.optionalString hasManagedGpgPassphrases ''
      ${lib.getExe managedGpgImportScript} >/dev/null
    ''}

    exec ${pkgs.gnupg}/bin/gpg "$@"
  '';
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
      settings.gpg.program = "${gitGpgProgram}";
      includes = lib.flatten (lib.mapAttrsToList mkGpgSigningInclude gpgKeys);
    };

    home.sessionVariables = lib.mkIf sshAgentEnabled {
      GPG_AGENT_SSH = "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh";
      # SSH_AUTH_SOCK is handled by dev/ssh module
    };

    home.file.".gnupg/gpg-agent.conf".text = ''
      ${lib.optionalString sshAgentEnabled "enable-ssh-support"}
      ${lib.optionalString hasManagedGpgPassphrases "allow-preset-passphrase"}
      pinentry-program ${pinentryWrapper}
      default-cache-ttl ${toString agentCacheTtl}
      max-cache-ttl ${toString agentMaxCacheTtl}
    '';

    home.activation.importManagedGpgKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      if managedGpgKeyNames != [ ] then "$DRY_RUN_CMD ${lib.getExe managedGpgImportScript}" else ":"
    );

    j0nix.user.software.packages = [
      pkgs.gnupg
      pkgs.gawk
      pkgs.pinentry-gnome3
    ]
    ++ lib.optionals (managedGpgKeyNames != [ ]) [ managedGpgImportScript ];

    systemd.user.services.gpg-secret-keys-load = lib.mkIf hasManagedGpgPassphrases {
      Unit = {
        Description = "Load declarative secret-backed GPG key passphrases into gpg-agent";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "10s";
        ExecStart = "${lib.getExe managedGpgImportScript}";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    systemd.user.timers.gpg-secret-keys-load = lib.mkIf hasManagedGpgPassphrases {
      Unit = {
        Description = "Refresh declarative secret-backed GPG passphrases in gpg-agent";
      };
      Timer = {
        OnBootSec = "1min";
        OnUnitActiveSec = presetInterval;
        AccuracySec = "30s";
        Unit = "gpg-secret-keys-load.service";
        Persistent = true;
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
