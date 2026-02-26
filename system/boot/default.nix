{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.boot;
in
{
  options.j0nix.desktop.boot = {
    tmp = {
      useTmpfs = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      tmpfsSize = lib.mkOption {
        type = lib.types.str;
        default = "30%";
      };
    };

    loader = {
      systemdBoot = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        configurationLimit = lib.mkOption {
          type = lib.types.int;
          default = 12;
        };
      };
      efi = {
        canTouchEfiVariables = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
      };
    };

    resumeDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    swapfile = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/swapfile";
      };
      sizeMiB = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
    };

  };

  config = {
    boot.tmp = {
      inherit (cfg.tmp) useTmpfs tmpfsSize;
    };

    boot.loader.systemd-boot = {
      inherit (cfg.loader.systemdBoot) enable configurationLimit;
    };

    boot.loader.efi.canTouchEfiVariables = cfg.loader.efi.canTouchEfiVariables;

    boot.resumeDevice = lib.mkIf (cfg.resumeDevice != null) cfg.resumeDevice;

    swapDevices = lib.mkIf cfg.swapfile.enable [
      {
        device = cfg.swapfile.path;
        size = cfg.swapfile.sizeMiB;
      }
    ];
    assertions = [
      {
        assertion = (!cfg.swapfile.enable) || (cfg.swapfile.sizeMiB > 0);
        message = "j0nix.desktop.boot.swapfile.sizeMiB must be > 0 when swapfile.enable = true";
      }
      {
        assertion = (!cfg.swapfile.enable) || lib.hasPrefix "/" cfg.swapfile.path;
        message = "j0nix.desktop.boot.swapfile.path must be absolute";
      }
    ];
  };
}
