{ config, lib, osConfig ? null, pkgs, settings, ... }:
let
  enableSops = settings.enableSops or false;
  cfg = settings.secrets or { };
  userCfg = cfg.user or { };
  userAgeCfg = userCfg.age or { };
  rawSshKeys = userCfg.sshKeys or { };
  sshKeys = if builtins.isAttrs rawSshKeys then rawSshKeys else { };
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
  useInheritedSystemKey = inheritedSystemAgeKeyFile != null && resolvedAgeKeyFile == inheritedSystemAgeKeyFile;
  rawItems = userCfg.items or { };
  items = if builtins.isAttrs rawItems then rawItems else { };
  mkSecret = name: spec:
    let
      effectiveSopsFile =
        if spec ? sopsFile then
          spec.sopsFile
        else
          defaultSopsFile;
    in
    {
      inherit name;
      value =
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
    };
  missingSopsFileSecrets =
    builtins.filter
      (name:
        let
          spec = items.${name};
        in
        (if spec ? sopsFile then spec.sopsFile else defaultSopsFile) == null)
      (builtins.attrNames items);
  missingSshKeySecrets =
    builtins.filter
      (name:
        let
          spec = sshKeys.${name};
          secretName = spec.secretName or name;
        in
        !(lib.hasAttrByPath [ secretName ] items))
      (builtins.attrNames sshKeys);
  validSshKeyNames = builtins.filter (name: !(builtins.elem name missingSshKeySecrets)) (builtins.attrNames sshKeys);
  deploySshKey = name:
    let
      spec = sshKeys.${name};
      secretName = spec.secretName or name;
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
            if ! ${pkgs.openssh}/bin/ssh-keygen -y -f ${lib.escapeShellArg config.sops.secrets.${secretName}.path} > "$tmp_pub"; then
              echo "warning: could not derive public key for ${targetName}; keeping existing ${publicPath} if present" >&2
              rm -f "$tmp_pub"
              tmp_pub=""
            fi
          '';
    in
    ''
      ln -sfn ${lib.escapeShellArg config.sops.secrets.${secretName}.path} ${lib.escapeShellArg privatePath}
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
  sops = ({
    defaultSopsFormat = defaultSopsFormat;
    age =
      {
        keyFile = resolvedAgeKeyFile;
      }
      // lib.optionalAttrs useInheritedSystemKey {
        generateKey = false;
      };
    secrets = builtins.listToAttrs (map (name: mkSecret name items.${name}) (builtins.attrNames items));
  } // lib.optionalAttrs (defaultSopsFile != null) {
    defaultSopsFile = defaultSopsFile;
  });

  home.activation.deploySecretBackedSshKeys =
    lib.hm.dag.entryAfter [ "writeBoundary" ]
      (if validSshKeyNames != [ ] then sshDeploymentScript else ":");

  assertions = [
    {
      assertion = builtins.isAttrs rawItems;
      message = "settings.userSettings.<name>.secrets.items must be an attrset of secret definitions";
    }
    {
      assertion = builtins.isAttrs rawSshKeys;
      message = "settings.userSettings.<name>.secrets.sshKeys must be an attrset of deployable SSH key definitions";
    }
    {
      assertion = missingSopsFileSecrets == [ ];
      message = "Each settings.userSettings.<name>.secrets.items entry requires either its own sopsFile or settings.userSettings.<name>.secrets.defaultSopsFile/settings.secrets.defaultUserSopsFile.";
    }
    {
      assertion = missingSshKeySecrets == [ ];
      message = "Each settings.userSettings.<name>.secrets.sshKeys entry must reference an existing items secret via secretName (or matching attr name).";
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
      assertion = items == { } || resolvedAgeKeyFile != null;
      message = "User sops secrets for ${settings.username} require a key source. Under NixOS, Home Manager should inherit osConfig.sops.age.keyFile; for standalone Home Manager set settings.userSettings.<name>.secrets.age.keyFile or settings.secrets.age.keyFile.";
    }
  ];
}
