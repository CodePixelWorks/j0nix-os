{ config, lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).keepassxc or { };
  hyprlandCfg = settings.hyprland or { };
  minimizerCfg = hyprlandCfg.minimizer or { };
  minimizerEnabled = minimizerCfg.enable or false;
  minimizerVariant = minimizerCfg.variant or "denis";
  minimizerPackage =
    if minimizerVariant == "0rteip" then
      if pkgs ? "hyprland-minimizer-orteip" then pkgs."hyprland-minimizer-orteip" else null
    else if pkgs ? "hyprland-minimizer" then
      pkgs."hyprland-minimizer"
    else
      null;
  minimizerDefaultCommand =
    if minimizerPackage != null then
      lib.getExe minimizerPackage
    else if minimizerVariant == "0rteip" then
      "hyprland-minimizer"
    else
      "hyprland-minimizer";
  minimizerCommand = minimizerCfg.command or minimizerDefaultCommand;
  minimizerOrteipCfg = minimizerCfg.orteip or { };
  minimizerOrteipAppId = minimizerOrteipCfg.appId or "keepassxc";
  enabled = cfg.enable or false;
  autoStart = cfg.autoStart or false;
  startMinimized = cfg.startMinimized or true;
  effectiveStartMinimized = startMinimized && !minimizerEnabled;
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
    if [ "${if minimizerEnabled then "1" else "0"}" = "1" ]; then
      (
        for _ in $(seq 1 50); do
          if ${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -e '.[] | select(.class=="KeePassXC")' >/dev/null 2>&1; then
            if [ "${minimizerVariant}" = "0rteip" ]; then
              ${minimizerCommand} ${minimizerOrteipAppId} >/dev/null 2>&1 || true
            else
              ${pkgs.hyprland}/bin/hyprctl dispatch focuswindow "class:^(KeePassXC)$" >/dev/null 2>&1 || true
              ${minimizerCommand} >/dev/null 2>&1 || true
            fi
            exit 0
          fi
          sleep 0.2
        done
      ) &
    fi
    exec ${lib.escapeShellArg "${pkgs.keepassxc}/bin/keepassxc"} \
      ${lib.optionalString effectiveStartMinimized "--minimized"} \
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
