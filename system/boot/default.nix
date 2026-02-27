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

    splash = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Plymouth graphical boot splash.";
      };
      theme = lib.mkOption {
        type = lib.types.str;
        default = "bgrt";
        description = "Plymouth theme name.";
      };
      themePackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Additional plymouth theme packages to install for custom splash themes.";
      };
      quietBoot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Reduce boot verbosity when splash is enabled.";
      };
      highResolution = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Request highest available firmware console resolution for a sharper splash.";
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
    boot.loader.systemd-boot.consoleMode =
      lib.mkIf (cfg.splash.enable && cfg.splash.highResolution) "max";

    boot.resumeDevice = lib.mkIf (cfg.resumeDevice != null) cfg.resumeDevice;

    swapDevices = lib.mkIf cfg.swapfile.enable [
      {
        device = cfg.swapfile.path;
        size = cfg.swapfile.sizeMiB;
      }
    ];

    boot.plymouth = lib.mkIf cfg.splash.enable {
      enable = true;
      theme = cfg.splash.theme;
      themePackages = cfg.splash.themePackages;
    };

    boot.consoleLogLevel = lib.mkIf (cfg.splash.enable && cfg.splash.quietBoot) 3;
    boot.initrd.verbose = lib.mkIf (cfg.splash.enable && cfg.splash.quietBoot) false;
    boot.kernelParams = lib.mkAfter (
      lib.optionals (cfg.splash.enable && cfg.splash.quietBoot) [
        "quiet"
        "splash"
        "loglevel=3"
        "rd.udev.log_level=3"
        "udev.log_priority=3"
        "systemd.show_status=false"
        "vt.global_cursor_default=0"
      ]
    );

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
