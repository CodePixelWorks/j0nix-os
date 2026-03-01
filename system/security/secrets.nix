{ lib, settings, ... }:
let
  enableSops = settings.enableSops or false;
  cfg = settings.secrets or { };
  defaultSopsFile = cfg.defaultSopsFile or null;
  defaultSopsFormat = cfg.defaultSopsFormat or "yaml";
  ageCfg = cfg.age or { };
  rawSystemSecrets = cfg.system or { };
  systemSecrets = if builtins.isAttrs rawSystemSecrets then rawSystemSecrets else { };
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
          path = spec.path or "/run/secrets/${name}";
          owner = spec.owner or "root";
          group = spec.group or "root";
          mode = spec.mode or "0400";
          format = spec.format or defaultSopsFormat;
          sopsFile = effectiveSopsFile;
        }
        // lib.optionalAttrs (spec ? neededForUsers) {
          neededForUsers = spec.neededForUsers;
        }
        // lib.optionalAttrs (spec ? restartUnits) {
          restartUnits = spec.restartUnits;
        }
        // lib.optionalAttrs (spec ? reloadUnits) {
          reloadUnits = spec.reloadUnits;
        };
    };
  missingSopsFileSecrets =
    builtins.filter
      (name:
        let
          spec = systemSecrets.${name};
        in
        (if spec ? sopsFile then spec.sopsFile else defaultSopsFile) == null)
      (builtins.attrNames systemSecrets);
in
lib.mkIf enableSops {
  sops = ({
    defaultSopsFormat = defaultSopsFormat;
    age = {
      generateKey = ageCfg.generateKey or true;
      keyFile = ageCfg.keyFile or "/var/lib/sops-nix/key.txt";
      sshKeyPaths = ageCfg.sshKeyPaths or [ ];
    };
    secrets = builtins.listToAttrs (map (name: mkSecret name systemSecrets.${name}) (builtins.attrNames systemSecrets));
  } // lib.optionalAttrs (defaultSopsFile != null) {
    defaultSopsFile = defaultSopsFile;
  });

  assertions = [
    {
      assertion = builtins.isAttrs rawSystemSecrets;
      message = "settings.secrets.system must be an attrset of secret definitions";
    }
    {
      assertion = missingSopsFileSecrets == [ ];
      message = "Each settings.secrets.system entry requires either its own sopsFile or settings.secrets.defaultSopsFile.";
    }
  ];
}
