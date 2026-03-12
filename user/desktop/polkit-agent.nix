{ lib, pkgs, ... }:
{
  j0nix.user.software.packages = [ pkgs.lxqt.lxqt-policykit ];

  systemd.user.services.polkit-authentication-agent = {
    Unit = {
      Description = "Desktop polkit authentication agent";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = lib.getExe pkgs.lxqt.lxqt-policykit;
      Restart = "on-failure";
      RestartSec = 1;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
