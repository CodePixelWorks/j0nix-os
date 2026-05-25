{ lib, pkgs, ... }:
let
  enableUdiskieAutomount = true;
in
{
  systemd.user.services.udiskie = lib.mkIf enableUdiskieAutomount {
    Unit = {
      Description = "Udiskie automount daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.udiskie}/bin/udiskie --automount --smart-tray";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
