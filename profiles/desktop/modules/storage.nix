{ config, lib, utils, ... }:
let
  cfg = config.j0nix.desktop.storage;
  mkMountRebuildGuards = import ../../../system/lib/mount-rebuild-guards.nix { inherit lib utils; };

  enabledManagedMounts = lib.filter (m: m.enable) cfg.mounts;

  mkMountOptions = m:
    m.options
    ++ lib.optionals m.gvfsShow [
      "x-gvfs-show"
      "x-gvfs-name=${m.gvfsName}"
    ]
    ++ lib.optionals m.automount [
      "x-systemd.automount"
      "x-systemd.idle-timeout=${m.idleTimeout}"
    ]
    ++ lib.optionals m.forceDirtyNtfsMount [
      # Emergency-only workaround for NTFS dirty volumes. Prefer running chkdsk on Windows.
      "force"
    ];
in
{
  options.j0nix.desktop.storage.mounts = lib.mkOption {
    default = [ ];
    description = "Declarative extra data mounts managed by the desktop profile.";
    type = lib.types.listOf (lib.types.submodule ({ ... }: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "mount";
        };
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        mountPoint = lib.mkOption {
          type = lib.types.str;
        };
        device = lib.mkOption {
          type = lib.types.str;
        };
        fsType = lib.mkOption {
          type = lib.types.str;
        };
        options = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        gvfsShow = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        gvfsName = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        automount = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        idleTimeout = lib.mkOption {
          type = lib.types.str;
          default = "5min";
        };
        preventRemount = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        forceDirtyNtfsMount = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };
    }));
  };

  config = {
    fileSystems = builtins.listToAttrs (map
      (m: {
        name = m.mountPoint;
        value = {
          inherit (m) device fsType;
          options = mkMountOptions m;
        };
      })
      enabledManagedMounts);

    # Source of truth is `j0nix.desktop.storage.mounts`; rebuild guard logic is handled by a shared helper.
    systemd.units = mkMountRebuildGuards cfg.mounts;

    assertions =
      map
        (m: {
          assertion = m.device != "";
          message = "storage mount '${m.name}' requires a non-empty device";
        })
        enabledManagedMounts
      ++ map
        (m: {
          assertion = lib.hasPrefix "/" m.mountPoint;
          message = "storage mount '${m.name}' requires an absolute mountPoint";
        })
        enabledManagedMounts
      ++ map
        (m: {
          assertion = (!m.gvfsShow) || (m.gvfsName != "");
          message = "storage mount '${m.name}' requires gvfsName when gvfsShow = true";
        })
        enabledManagedMounts
      ++ map
        (m: {
          assertion = (!m.forceDirtyNtfsMount) || builtins.elem m.fsType [ "ntfs3" "ntfs" ];
          message = "storage mount '${m.name}' uses forceDirtyNtfsMount only for NTFS filesystems";
        })
        enabledManagedMounts;
  };
}
