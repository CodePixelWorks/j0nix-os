{ config, lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).keepassxc or { };
  enabled = cfg.enable or false;
  autoStart = cfg.autoStart or false;
  startMinimized = cfg.startMinimized or true;
  databasePath = cfg.databasePath or null;
  keyFileSecretName = cfg.keyFileSecretName or null;
  keyFileTargetName = cfg.keyFileTargetName or "startup.key";
  keyFileSecretPath =
    if keyFileSecretName != null && lib.hasAttrByPath [ keyFileSecretName ] (config.sops.secrets or { }) then
      config.sops.secrets.${keyFileSecretName}.path
    else if keyFileSecretName != null && lib.hasAttrByPath [ keyFileSecretName ] (config.sops.templates or { }) then
      config.sops.templates.${keyFileSecretName}.path
    else
      null;
  keyFilePath = "${config.xdg.configHome}/keepassxc/keys/${keyFileTargetName}";
  startupScript = pkgs.writeShellScriptBin "keepassxc-startup" ''
    set -eu
    exec ${lib.escapeShellArg "${pkgs.keepassxc}/bin/keepassxc"} \
      ${lib.optionalString startMinimized "--minimized"} \
      ${lib.optionalString (keyFileSecretPath != null) "--keyfile ${lib.escapeShellArg keyFilePath}"} \
      ${lib.optionalString (databasePath != null) (lib.escapeShellArg databasePath)}
  '';
in
lib.mkIf enabled {
  j0nix.user.software.packages = [
    pkgs.keepassxc
    startupScript
  ];

  xdg.configFile = lib.mkMerge [
    (lib.mkIf (keyFileSecretPath != null) {
      "keepassxc/keys/${keyFileTargetName}".source = keyFileSecretPath;
    })
    (lib.mkIf autoStart {
      "autostart/keepassxc.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=KeePassXC
        Exec=${config.home.profileDirectory}/bin/keepassxc-startup
        Terminal=false
        X-GNOME-Autostart-enabled=true
      '';
    })
  ];

  assertions = [
    {
      assertion = keyFileSecretName == null || keyFileSecretPath != null;
      message = "settings.userSettings.<name>.programs.keepassxc.keyFileSecretName must reference an existing per-user secret or template.";
    }
    {
      assertion = databasePath == null || builtins.isString databasePath;
      message = "settings.userSettings.<name>.programs.keepassxc.databasePath must be a string path or null.";
    }
  ];
}
