{ lib, ... }:
let
  polkitRules = import ../../../system/lib/polkit-rules.nix { inherit lib; };
in
{
  services.gvfs.enable = true;
  services.udisks2.enable = true;

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
      lazyUnmountOnShutdown = true;
    }
  ];

  j0nix.desktop.security.polkit.extraConfigSnippets =
    [ polkitRules.mkUdisksWheelMountRule ];
}
