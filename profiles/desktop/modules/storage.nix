{ lib, settings, utils, ... }:
let
  storage = settings.storage or { };
  gamesDisk = storage.gamesDisk or { };
  gamesDiskEnabled = gamesDisk.enable or false;
  gamesDiskMountPoint = gamesDisk.mountPoint or "/mnt/Games";
  gamesDiskUuid = gamesDisk.uuid or "";
  gamesDiskFsType = gamesDisk.fsType or "ntfs3";
  gamesDiskGvfsShow = gamesDisk.gvfsShow or true;
  gamesDiskGvfsName = gamesDisk.gvfsName or "GAMES";
  gamesDiskOnDemandAutomount = gamesDisk.onDemandAutomount or false;
  gamesDiskIdleTimeout = gamesDisk.idleTimeout or "5min";
  gamesDiskForceDirtyNtfsMount = gamesDisk.forceDirtyNtfsMount or false;

  mkMountRebuildGuards = import ../../../system/lib/mount-rebuild-guards.nix { inherit lib utils; };

  # Profile-local source of truth for additional managed data mounts.
  managedExtraMounts =
    lib.optionals gamesDiskEnabled [
      {
        mountPoint = gamesDiskMountPoint;
        automount = gamesDiskOnDemandAutomount;
        preventRemount = true;
      }
    ];
in
{
  fileSystems = lib.optionalAttrs gamesDiskEnabled {
    "${gamesDiskMountPoint}" = {
      device = "/dev/disk/by-uuid/${gamesDiskUuid}";
      fsType = gamesDiskFsType;
      options = [
        "rw"
        "uid=1000"
        "gid=100"
        "umask=0022"
        "nofail"
      ]
      ++ lib.optionals gamesDiskGvfsShow [
        "x-gvfs-show"
        "x-gvfs-name=${gamesDiskGvfsName}"
      ]
      ++ lib.optionals gamesDiskOnDemandAutomount [
        "x-systemd.automount"
        "x-systemd.idle-timeout=${gamesDiskIdleTimeout}"
      ]
      ++ lib.optionals gamesDiskForceDirtyNtfsMount [
        # Emergency-only workaround for NTFS dirty volumes. Prefer running chkdsk on Windows.
        "force"
      ];
    };
  };

  # Prevent rebuild reconfiguration from stopping/restarting selected data-disk mount units while in use.
  # The source-of-truth mount list lives in this module (`managedExtraMounts`); guard logic is shared in a helper lib.
  systemd.units = mkMountRebuildGuards managedExtraMounts;

  assertions = [
    {
      assertion = (!gamesDiskEnabled) || (gamesDiskUuid != "");
      message = "settings.storage.gamesDisk.uuid must be set when gamesDisk.enable = true";
    }
    {
      assertion = (!gamesDiskEnabled) || lib.hasPrefix "/" gamesDiskMountPoint;
      message = "settings.storage.gamesDisk.mountPoint must be an absolute path";
    }
    {
      assertion = (!gamesDiskEnabled) || (!gamesDiskGvfsShow) || (gamesDiskGvfsName != "");
      message = "settings.storage.gamesDisk.gvfsName must not be empty when gvfsShow = true";
    }
    {
      assertion = (!gamesDiskForceDirtyNtfsMount) || builtins.elem gamesDiskFsType [ "ntfs3" "ntfs" ];
      message = "settings.storage.gamesDisk.forceDirtyNtfsMount is only valid for NTFS filesystems";
    }
  ];
}
