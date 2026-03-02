{ config, lib, osConfig ? null, settings, ... }:
let
  enableSops = settings.enableSops or false;
  cfg = settings.secrets or { };
  usersCfg = cfg.users or { };
  userCfg = usersCfg.${settings.username} or { };
  userAgeCfg = userCfg.age or { };
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

  assertions = [
    {
      assertion = builtins.isAttrs rawItems;
      message = "settings.secrets.users.${settings.username}.items must be an attrset of secret definitions";
    }
    {
      assertion = missingSopsFileSecrets == [ ];
      message = "Each settings.secrets.users.${settings.username}.items entry requires either its own sopsFile or settings.secrets.users.${settings.username}.defaultSopsFile/settings.secrets.defaultUserSopsFile.";
    }
    {
      assertion = items == { } || resolvedAgeKeyFile != null;
      message = "User sops secrets for ${settings.username} require a key source. Under NixOS, Home Manager should inherit osConfig.sops.age.keyFile; for standalone Home Manager set settings.secrets.users.${settings.username}.age.keyFile or settings.secrets.age.keyFile.";
    }
  ];
}
