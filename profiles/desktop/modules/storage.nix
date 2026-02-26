{ lib, settings, ... }:
let
  storage = settings.storage or { };
  autoMountWindows = storage.autoMountWindows or true;
  noPasswordMounts = storage.noPasswordMounts or true;
in
{
  services.gvfs.enable = true;
  services.udisks2.enable = autoMountWindows;
  services.dbus.implementation = "broker";

  j0nix.desktop.storage.mounts = [
    {
      name = "games";
      enable = true;
      mountPoint = "/mnt/Games";
      device = "/dev/disk/by-uuid/6A68028468024F6F";
      fsType = "ntfs3";
      options = [
        "rw"
        "uid=1000"
        "gid=100"
        "umask=0022"
        "nofail"
      ];
      gvfsShow = true;
      gvfsName = "GAMES";
      automount = false;
      idleTimeout = "5min";
      preventRemount = true;
      forceDirtyNtfsMount = false;
    }
  ];

  security.polkit.enable = true;
  security.polkit.extraConfig = lib.mkIf noPasswordMounts ''
    polkit.addRule(function(action, subject) {
      var allowed = [
        "org.freedesktop.udisks2.filesystem-mount",
        "org.freedesktop.udisks2.filesystem-mount-system",
        "org.freedesktop.udisks2.filesystem-mount-other-seat",
        "org.freedesktop.udisks2.filesystem-unmount-others",
        "org.freedesktop.udisks2.encrypted-unlock",
        "org.freedesktop.udisks2.eject-media"
      ];

      if (allowed.indexOf(action.id) >= 0 && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  assertions = [
    {
      assertion = builtins.isBool autoMountWindows && builtins.isBool noPasswordMounts;
      message = "settings.storage.autoMountWindows and settings.storage.noPasswordMounts must be booleans";
    }
  ];
}
