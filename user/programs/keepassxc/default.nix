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

  xdg.configFile = lib.mkIf (keyFileSecretPath != null) {
    "keepassxc/keys/${keyFileTargetName}".source = keyFileSecretPath;
  };

  systemd.user.services.keepassxc-startup = lib.mkIf autoStart {
    Unit = {
      Description = "KeePassXC startup database launcher";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${config.home.profileDirectory}/bin/keepassxc-startup";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

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
