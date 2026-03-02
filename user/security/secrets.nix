{ config, lib, settings, ... }:
let
  enableSops = settings.enableSops or false;
  cfg = settings.secrets or { };
  usersCfg = cfg.users or { };
  userCfg = usersCfg.${settings.username} or { };
  defaultSopsFile = userCfg.defaultSopsFile or (cfg.defaultUserSopsFile or null);
  defaultSopsFormat = userCfg.defaultSopsFormat or (cfg.defaultSopsFormat or "yaml");
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
  ];
}
