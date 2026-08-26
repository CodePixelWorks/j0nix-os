{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  defaultCfg = ((settings.programs or { }).penguinBurner or { });
  userOverrides = settings.userSettings or { };
  allUsers = builtins.attrNames userOverrides;
  userCfgFor =
    username:
    lib.recursiveUpdate defaultCfg (
      (((userOverrides.${username} or { }).programs or { }).penguinBurner or { })
    );
  enabledUsers = lib.filter (username: (userCfgFor username).enable or false) allUsers;
  enabled = enabledUsers != [ ];
  serviceUser = if enabled then builtins.head enabledUsers else null;
  cfg = if serviceUser == null then defaultCfg else userCfgFor serviceUser;
  daemonEnabled = enabled && ((cfg.daemon or { }).enable or true);
  package = pkgs.callPackage ./penguin-burner-package.nix { };
  python = pkgs.python3;
  pythonEnv = python.withPackages (_: [ package ]);
  programFile = "${package}/${python.sitePackages}/penguin_burner.py";
  daemonBinary = "${package}/${python.sitePackages}/runtime/daemon_bin/penguin-burnerd";
  daemonLauncher = pkgs.writeShellScript "penguin-burnerd-launch" ''
    set -eu

    service_uid="$(${pkgs.coreutils}/bin/id -u ${lib.escapeShellArg serviceUser})"
    service_gid="$(${pkgs.coreutils}/bin/id -g ${lib.escapeShellArg serviceUser})"

    export PENGUIN_BURNER_DAEMON_ALLOWED_UID="$service_uid"
    export PENGUIN_BURNER_Q2RTX_UID="$service_uid"
    export PENGUIN_BURNER_Q2RTX_GID="$service_gid"

    exec ${daemonBinary} --socket /run/penguin-burnerd.sock
  '';
in
lib.mkIf enabled {
  j0nix.software.systemPackages = [ package ];

  systemd.services.penguin-burnerd = lib.mkIf daemonEnabled {
    description = "PenguinBurner hardware daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    path = [ pkgs.procps ];
    environment = {
      SUDO_USER = serviceUser;
      PENGUIN_BURNER_HOME = "/home/${serviceUser}";
      PENGUIN_BURNER_Q2RTX_USER = serviceUser;
      PENGUIN_BURNER_DAEMON_PROGRAM_FILE = programFile;
      PENGUIN_BURNER_DAEMON_PYTHON = "${pythonEnv}/bin/python3";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };
    serviceConfig = {
      Type = "notify";
      WorkingDirectory = "/";
      WatchdogSec = 30;
      ExecStart = daemonLauncher;
      Restart = "on-failure";
      RestartSec = 2;
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "penguin-burnerd";
    };
  };

  assertions = [
    {
      assertion = builtins.length enabledUsers <= 1;
      message = "At most one user may enable userSettings.<name>.programs.penguinBurner because the root daemon accepts one desktop UID.";
    }
    {
      assertion = config.j0nix.desktop.drivers.nvidia.enable;
      message = "PenguinBurner requires j0nix.desktop.drivers.nvidia.enable = true.";
    }
  ];
}
