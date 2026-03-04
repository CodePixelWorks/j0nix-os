{ config, lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).element or { };
  enabled = cfg.enable or false;
  configFileSecretName = cfg.configFileSecretName or null;
  configPayload =
    let
      raw = cfg.config or { };
    in
    if builtins.isAttrs raw then raw else { };
  hasConfigPayload = configPayload != { };
  configText = cfg.configText or null;
  secretConfigPath =
    if configFileSecretName != null && lib.hasAttrByPath [ configFileSecretName ] (config.sops.secrets or { }) then
      config.sops.secrets.${configFileSecretName}.path
    else if configFileSecretName != null && lib.hasAttrByPath [ configFileSecretName ] (config.sops.templates or { }) then
      config.sops.templates.${configFileSecretName}.path
    else
      null;
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ pkgs.element-desktop ];

  xdg.configFile =
    lib.mkMerge [
      (lib.mkIf (secretConfigPath != null) {
        "Element/config.json".source = secretConfigPath;
      })
      (lib.mkIf (secretConfigPath == null && hasConfigPayload) {
        "Element/config.json".text = builtins.toJSON configPayload;
      })
      (lib.mkIf (secretConfigPath == null && !hasConfigPayload && configText != null) {
        "Element/config.json".text = configText;
      })
    ];

  assertions = [
    {
      assertion = configFileSecretName == null || secretConfigPath != null;
      message = "settings.userSettings.<name>.programs.element.configFileSecretName must reference an existing per-user secret or rendered secret template.";
    }
    {
      assertion = !(hasConfigPayload && configText != null);
      message = "settings.userSettings.<name>.programs.element may define at most one of: config, configText.";
    }
  ];
}
