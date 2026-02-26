{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.boot;
  modprobe = import ../lib/modprobe.nix { inherit lib; };
  hasModprobeOptions = cfg.modprobeOptions != { };
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

    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    modprobeOptions = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.oneOf [
        lib.types.bool
        lib.types.int
        lib.types.float
        lib.types.str
      ]));
      default = { };
      description = "Kernel module options grouped by module name.";
    };

    appimageBinfmt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
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

    boot.kernelModules = lib.mkAfter cfg.kernelModules;

    boot.extraModprobeConfig = lib.mkIf hasModprobeOptions (lib.mkAfter (modprobe.fromAttrset cfg.modprobeOptions));

    boot.binfmt.registrations.appimage = lib.mkIf cfg.appimageBinfmt.enable {
      wrapInterpreterInShell = false;
      interpreter = "${pkgs.appimage-run}/bin/appimage-run";
      recognitionType = "magic";
      offset = 0;
      mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
      magicOrExtension = ''\x7fELF....AI\x02'';
    };

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
