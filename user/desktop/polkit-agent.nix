{ lib, pkgs, ... }:
{
  j0nix.user.software.packages = [ pkgs.hyprpolkitagent ];

  systemd.user.services.polkit-authentication-agent = {
    Unit = {
      Description = "Desktop polkit authentication agent";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = lib.getExe pkgs.hyprpolkitagent;
      Restart = "on-failure";
      RestartSec = 1;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
