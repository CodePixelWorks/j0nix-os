{ config, lib, ... }:
let
  modprobe = import ../lib/modprobe.nix { inherit lib; };
  cfg = config.j0nix.desktop.support.drivers;
  it87Cfg = cfg.it87;
  hasIt87KernelPackage = config.boot.kernelPackages ? it87;
  it87ModprobeOpts =
    lib.optionalAttrs (it87Cfg.forceId != null) { force_id = it87Cfg.forceId; }
    // lib.optionalAttrs it87Cfg.ignoreResourceConflict { ignore_resource_conflict = 1; };
  usbCfg = cfg.usb;
  usbKeepAwakeCfg = usbCfg.keepAwake;
  usbKeepAwakeDeviceIds = usbKeepAwakeCfg.devices or [ ];
  mkUsbKeepAwakeRule = id:
    let
      parts = lib.splitString ":" id;
      vendor = builtins.elemAt parts 0;
      product = builtins.elemAt parts 1;
    in
    ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${vendor}", ATTR{idProduct}=="${product}", TEST=="power/control", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${vendor}", ATTR{idProduct}=="${product}", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
    '';
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

    usb = {
      keepAwake = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable USB autosuspend for selected USB devices via udev rules.";
        };

        devices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "05e3:0610" "046d:c539" ];
          description = "List of USB device IDs (vendor:product) that should keep power/control=on.";
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (it87Cfg.enable && hasIt87KernelPackage) {
      boot.extraModulePackages = [ config.boot.kernelPackages.it87 ];
      # Explicitly request the out-of-tree module via the central kernel module collector.
      j0nix.desktop.kernel.modules = [ "it87" ];
    })

    (lib.mkIf (it87Cfg.enable && it87ModprobeOpts != { }) {
      boot.extraModprobeConfig = lib.mkAfter (modprobe.fromAttrset { it87 = it87ModprobeOpts; });
    })

    (lib.mkIf (usbKeepAwakeCfg.enable && usbKeepAwakeDeviceIds != [ ]) {
      services.udev.extraRules = lib.mkAfter (lib.concatStringsSep "\n" (map mkUsbKeepAwakeRule usbKeepAwakeDeviceIds));
    })

    {
      assertions = [
        {
          assertion = !(it87Cfg.enable && !hasIt87KernelPackage);
          message = "j0nix.desktop.support.drivers.it87.enable requires `boot.kernelPackages.it87` in the selected kernel package set.";
        }
        {
          assertion = lib.all (id: builtins.match "^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}$" id != null) usbKeepAwakeDeviceIds;
          message = "j0nix.desktop.support.drivers.usb.keepAwake.devices must contain vendor:product IDs like 05e3:0610";
        }
      ];
    }
  ];
}
