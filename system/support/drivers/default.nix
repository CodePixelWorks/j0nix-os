{ config, lib, ... }:
let
  modprobe = import ../../lib/modprobe.nix { inherit lib; };
  cfg = config.j0nix.desktop.support.drivers;
  it87Cfg = cfg.it87;
  hasIt87KernelPackage = config.boot.kernelPackages ? it87;
  it87ModprobeOpts =
    lib.optionalAttrs (it87Cfg.forceId != null) { force_id = it87Cfg.forceId; }
    // lib.optionalAttrs it87Cfg.ignoreResourceConflict { ignore_resource_conflict = 1; };
in
{
  options.j0nix.desktop.support.drivers = {
    it87 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the out-of-tree it87 hwmon kernel module package for IT87xx Super-I/O fan/temperature chips.";
      };

      ignoreResourceConflict = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set it87.ignore_resource_conflict=1 (commonly needed on desktop boards).";
      };

      forceId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional it87.force_id module parameter (e.g. \"0x8718\") for unsupported chip detection.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (it87Cfg.enable && hasIt87KernelPackage) {
      boot.extraModulePackages = [ config.boot.kernelPackages.it87 ];
    })

    (lib.mkIf (it87Cfg.enable && it87ModprobeOpts != { }) {
      boot.extraModprobeConfig = lib.mkAfter (modprobe.fromAttrset { it87 = it87ModprobeOpts; });
    })

    {
      assertions = [
        {
          assertion = !(it87Cfg.enable && !hasIt87KernelPackage);
          message = "j0nix.desktop.support.drivers.it87.enable requires `boot.kernelPackages.it87` in the selected kernel package set.";
        }
      ];
    }
  ];
}
