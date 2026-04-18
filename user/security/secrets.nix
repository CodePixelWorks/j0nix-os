{ config, lib, osConfig ? null, pkgs, settings, ... }:
let
  enableSops = settings.enableSops or false;
  cfg = settings.secrets or { };
  userCfg = cfg.user or { };
  userAgeCfg = userCfg.age or { };
  rawFiles = userCfg.files or { };
  rawSshKeys = userCfg.sshKeys or { };
  rawGpgKeys = userCfg.gpgKeys or { };
  files = if builtins.isAttrs rawFiles then rawFiles else { };
  sshKeys = if builtins.isAttrs rawSshKeys then rawSshKeys else { };
  gpgKeys = if builtins.isAttrs rawGpgKeys then rawGpgKeys else { };
  plainFiles = lib.filterAttrs (_: spec: !(spec ? fields)) files;
  structuredFiles = lib.filterAttrs (_: spec: spec ? fields) files;
  defaultSopsFile = userCfg.defaultSopsFile or (cfg.defaultUserSopsFile or null);
  defaultSopsFormat = userCfg.defaultSopsFormat or (cfg.defaultSopsFormat or "yaml");
  inheritedSystemAgeKeyFile =
    if osConfig != null && osConfig ? sops && osConfig.sops ? age then
      osConfig.sops.age.keyFile or null
    else
      null;
  resolvedAgeKeyFile =
    if userAgeCfg ? keyFile && userAgeCfg.keyFile != null then
      userAgeCfg.keyFile
    else if inheritedSystemAgeKeyFile != null then
      inheritedSystemAgeKeyFile
    else
      ((cfg.age or { }).keyFile or null);
  exportedAgeKeyFile =
    if userAgeCfg ? keyFile && userAgeCfg.keyFile != null then
      userAgeCfg.keyFile
    else
      null;
  useInheritedSystemKey = inheritedSystemAgeKeyFile != null && resolvedAgeKeyFile == inheritedSystemAgeKeyFile;
  mkSecretValue = name: spec:
    let
      effectiveSopsFile =
        if spec ? sopsFile then
          spec.sopsFile
        else
          defaultSopsFile;
    in
    {
      key = spec.key or name;
      format = spec.format or defaultSopsFormat;
      sopsFile = effectiveSopsFile;
    }
    // lib.optionalAttrs (spec ? mode) {
      mode = spec.mode;
    }
    // lib.optionalAttrs (spec ? path) {
      path = spec.path;
    };
  fileSecrets = builtins.mapAttrs mkSecretValue plainFiles;
  structuredFileFieldSecrets =
    lib.foldl'
      (acc: name:
        let
          spec = structuredFiles.${name};
          fieldSpecs = if builtins.isAttrs spec.fields then spec.fields else { };
          fieldSecrets =
            lib.mapAttrs'
              (fieldName: fieldKey:
                lib.nameValuePair "${name}__${fieldName}" (
                  mkSecretValue "${name}__${fieldName}" {
                    key = fieldKey;
                    format = spec.format or defaultSopsFormat;
                    sopsFile = if spec ? sopsFile then spec.sopsFile else defaultSopsFile;
                  }
                  // lib.optionalAttrs (spec ? mode) {
                    mode = spec.mode;
                  }
                ))
              fieldSpecs;
        in
        acc // fieldSecrets)
      { }
      (builtins.attrNames structuredFiles);
  structuredFileTemplates =
    builtins.mapAttrs
      (name: spec:
        let
          fieldSpecs = if builtins.isAttrs spec.fields then spec.fields else { };
          content =
            lib.concatStringsSep "\n"
              (map
                (fieldName:
                  let
                    placeholderName = "${name}__${fieldName}";
                  in
                  "${fieldName}: ${builtins.getAttr placeholderName config.sops.placeholder}")
                (builtins.attrNames fieldSpecs));
        in
        {
          inherit content;
        }
        // lib.optionalAttrs (spec ? mode) {
          mode = spec.mode;
        }
        // lib.optionalAttrs (spec ? path) {
          path = spec.path;
        })
      structuredFiles;
  sshKeySecrets = builtins.mapAttrs
    (name: spec:
      mkSecretValue name {
        key = spec.key or name;
      }
      // lib.optionalAttrs (spec ? mode) {
        mode = spec.mode;
      }
      // lib.optionalAttrs (spec ? path) {
        path = spec.path;
      })
    sshKeys;
  sshKeyPassphraseSecrets =
    lib.mapAttrs'
      (name: spec:
        let
          passphraseKey = spec.passphraseKey or null;
        in
        lib.nameValuePair "${name}-passphrase" (
          mkSecretValue "${name}-passphrase" {
            key = passphraseKey;
            format = spec.passphraseFormat or defaultSopsFormat;
            sopsFile = spec.passphraseSopsFile or (spec.sopsFile or defaultSopsFile);
            mode = spec.passphraseMode or "0400";
          }
        ))
      (lib.filterAttrs (_: spec: (spec.passphraseKey or null) != null) sshKeys);
  gpgKeySecrets = builtins.mapAttrs
    (name: spec:
      mkSecretValue name {
        key = spec.key or name;
      }
      // lib.optionalAttrs (spec ? mode) {
        mode = spec.mode;
      }
      // lib.optionalAttrs (spec ? path) {
        path = spec.path;
      })
    gpgKeys;
  allManagedSecretNames = (builtins.attrNames files) ++ (builtins.attrNames sshKeys) ++ (builtins.attrNames gpgKeys);
  overlappingSecretNames =
    builtins.filter
      (name:
        builtins.length (builtins.filter (candidate: candidate == name) allManagedSecretNames) > 1)
      (lib.unique allManagedSecretNames);
  missingSopsFileFiles =
    builtins.filter
      (name:
        let
          spec = files.${name};
        in
        (if spec ? sopsFile then spec.sopsFile else defaultSopsFile) == null)
      (builtins.attrNames files);
  missingSopsFileSshKeys =
    builtins.filter
      (name:
        let
          spec = sshKeys.${name};
        in
        (if spec ? sopsFile then spec.sopsFile else defaultSopsFile) == null)
      (builtins.attrNames sshKeys);
  missingSopsFileGpgKeys =
    builtins.filter
      (name:
        let
          spec = gpgKeys.${name};
        in
        (if spec ? sopsFile then spec.sopsFile else defaultSopsFile) == null)
      (builtins.attrNames gpgKeys);
  missingSopsFileSshKeyPassphrases =
    builtins.filter
      (name:
        let
          spec = sshKeys.${name};
        in
        (spec.passphraseKey or null) != null
        && (if spec ? passphraseSopsFile then spec.passphraseSopsFile else if spec ? sopsFile then spec.sopsFile else defaultSopsFile) == null)
      (builtins.attrNames sshKeys);
  referencedFileSopsFiles =
    map
      (name:
        let
          spec = files.${name};
        in
        if spec ? sopsFile then spec.sopsFile else defaultSopsFile)
      (builtins.attrNames files);
  referencedSshSopsFiles =
    map
      (name:
        let
          spec = sshKeys.${name};
        in
        if spec ? sopsFile then spec.sopsFile else defaultSopsFile)
      (builtins.attrNames sshKeys);
  referencedSshPassphraseSopsFiles =
    map
      (name:
        let
          spec = sshKeys.${name};
        in
        if spec ? passphraseSopsFile then spec.passphraseSopsFile else if spec ? sopsFile then spec.sopsFile else defaultSopsFile)
      (builtins.attrNames (lib.filterAttrs (_: spec: (spec.passphraseKey or null) != null) sshKeys));
  referencedGpgSopsFiles =
    map
      (name:
        let
          spec = gpgKeys.${name};
        in
        if spec ? sopsFile then spec.sopsFile else defaultSopsFile)
      (builtins.attrNames gpgKeys);
  referencedSopsFiles =
    lib.unique (
      builtins.filter
        (path: path != null)
        (referencedFileSopsFiles ++ referencedSshSopsFiles ++ referencedSshPassphraseSopsFiles ++ referencedGpgSopsFiles)
    );
  missingSopsFilesOnDisk =
    builtins.filter
      (path: !(builtins.pathExists (toString path)))
      referencedSopsFiles;
  validSshKeyNames = builtins.attrNames sshKeys;
  deploySshKey = name:
    let
      spec = sshKeys.${name};
      targetName = spec.targetName or name;
      privatePath = "${config.home.homeDirectory}/.ssh/${targetName}";
      publicPath = "${privatePath}.pub";
      publicKeyText = spec.publicKey or null;
      publicKeyFile = spec.publicKeyFile or null;
      renderPublicKey =
        if publicKeyText != null then
          ''
            cat > "$tmp_pub" <<'EOF'
            ${publicKeyText}
            EOF
          ''
        else if publicKeyFile != null then
          ''
            cat ${lib.escapeShellArg (toString publicKeyFile)} > "$tmp_pub"
          ''
        else
          ''
            if ! ${pkgs.openssh}/bin/ssh-keygen -y -f ${lib.escapeShellArg config.sops.secrets.${name}.path} > "$tmp_pub"; then
              echo "warning: could not derive public key for ${targetName}; keeping existing ${publicPath} if present" >&2
              rm -f "$tmp_pub"
              tmp_pub=""
            fi
          '';
    in
    ''
      ln -sfn ${lib.escapeShellArg config.sops.secrets.${name}.path} ${lib.escapeShellArg privatePath}
      tmp_pub="$(mktemp)"
      ${renderPublicKey}
      if [ -n "$tmp_pub" ] && [ -f "$tmp_pub" ]; then
        mv "$tmp_pub" ${lib.escapeShellArg publicPath}
        chmod 644 ${lib.escapeShellArg publicPath}
      fi
    '';
  sshDeploymentScript =
    lib.concatStringsSep "\n" (
      [
        "mkdir -p \"$HOME/.ssh\""
        "chmod 700 \"$HOME/.ssh\""
      ]
      ++ map deploySshKey validSshKeyNames
    );
in
lib.mkIf enableSops {
  home.sessionVariables = lib.optionalAttrs (exportedAgeKeyFile != null) {
    SOPS_AGE_KEY_FILE = exportedAgeKeyFile;
  };

  sops = ({
    defaultSopsFormat = defaultSopsFormat;
    age =
      {
        keyFile = resolvedAgeKeyFile;
      }
      // lib.optionalAttrs useInheritedSystemKey {
        generateKey = false;
      };
    secrets =
      lib.recursiveUpdate
        (lib.recursiveUpdate
          (lib.recursiveUpdate (lib.recursiveUpdate fileSecrets structuredFileFieldSecrets) sshKeySecrets)
          sshKeyPassphraseSecrets)
        gpgKeySecrets;
    templates = structuredFileTemplates;
  } // lib.optionalAttrs (defaultSopsFile != null) {
    defaultSopsFile = defaultSopsFile;
  });

  home.activation.deploySecretBackedSshKeys =
    lib.hm.dag.entryAfter [ "writeBoundary" ]
      (if validSshKeyNames != [ ] then sshDeploymentScript else ":");

  assertions = [
    {
      assertion = builtins.isAttrs rawFiles;
      message = "settings.userSettings.<name>.secrets.files must be an attrset of secret definitions";
    }
    {
      assertion =
        lib.all
          (name:
            let
              spec = files.${name};
            in
            !(spec ? fields) || builtins.isAttrs spec.fields)
          (builtins.attrNames files);
      message = "Each settings.userSettings.<name>.secrets.files.<name>.fields value must be an attrset when used.";
    }
    {
      assertion = builtins.isAttrs rawSshKeys;
      message = "settings.userSettings.<name>.secrets.sshKeys must be an attrset of deployable SSH key definitions";
    }
    {
      assertion = builtins.isAttrs rawGpgKeys;
      message = "settings.userSettings.<name>.secrets.gpgKeys must be an attrset of deployable GPG key definitions";
    }
    {
      assertion = overlappingSecretNames == [ ];
      message = "settings.userSettings.<name>.secrets.files, settings.userSettings.<name>.secrets.sshKeys, and settings.userSettings.<name>.secrets.gpgKeys must not reuse the same attr name.";
    }
    {
      assertion = missingSopsFileFiles == [ ];
      message = "Each settings.userSettings.<name>.secrets.files entry requires either its own sopsFile or settings.userSettings.<name>.secrets.defaultSopsFile/settings.secrets.defaultUserSopsFile.";
    }
    {
      assertion = missingSopsFileSshKeys == [ ];
      message = "Each settings.userSettings.<name>.secrets.sshKeys entry requires either its own sopsFile or settings.userSettings.<name>.secrets.defaultSopsFile/settings.secrets.defaultUserSopsFile.";
    }
    {
      assertion = missingSopsFileGpgKeys == [ ];
      message = "Each settings.userSettings.<name>.secrets.gpgKeys entry requires either its own sopsFile or settings.userSettings.<name>.secrets.defaultSopsFile/settings.secrets.defaultUserSopsFile.";
    }
    {
      assertion = missingSopsFileSshKeyPassphrases == [ ];
      message = "Each settings.userSettings.<name>.secrets.sshKeys.<name>.passphraseKey requires either passphraseSopsFile, sopsFile, or settings.userSettings.<name>.secrets.defaultSopsFile/settings.secrets.defaultUserSopsFile.";
    }
    {
      assertion =
        lib.all
          (name:
            let
              spec = sshKeys.${name};
            in
            !((spec ? publicKey) && (spec ? publicKeyFile)))
          (builtins.attrNames sshKeys);
      message = "Each settings.userSettings.<name>.secrets.sshKeys entry may define at most one of: publicKey, publicKeyFile.";
    }
    {
      assertion = (files == { } && sshKeys == { } && gpgKeys == { }) || resolvedAgeKeyFile != null;
      message = "User sops secrets for ${settings.username} require a key source. Under NixOS, Home Manager should inherit osConfig.sops.age.keyFile; for standalone Home Manager set settings.userSettings.<name>.secrets.age.keyFile or settings.secrets.age.keyFile.";
    }
    {
      assertion = missingSopsFilesOnDisk == [ ];
      message =
        "Referenced user sopsFile path(s) for ${settings.username} do not exist: "
        + lib.concatStringsSep ", " (map toString missingSopsFilesOnDisk);
    }
  ];
}
